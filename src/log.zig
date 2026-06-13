//! zigkit-log: Lightweight structured logger.
//!
//! Supports text and JSON output formats with level filtering.
//!
//! Ownership: Logger stores a pointer to the writer. The writer must
//! outlive the Logger.

const std = @import("std");
const internal_json = @import("internal/json.zig");

/// Log severity level.
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    fatal = 5,

    pub fn string(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }

    pub fn jsonString(self: Level) []const u8 {
        return switch (self) {
            .trace => "trace",
            .debug => "debug",
            .info => "info",
            .warn => "warn",
            .err => "err",
            .fatal => "fatal",
        };
    }
};

/// Output format.
pub const Format = enum {
    text,
    json,
};

/// ANSI color mode.
pub const ColorMode = enum {
    auto,
    always,
    never,
};

/// Logger configuration.
pub const LoggerOptions = struct {
    level: Level = .info,
    format: Format = .text,
    /// Include timestamp in output.
    timestamp: bool = true,
    color: ColorMode = .never,
};

/// Structured logger. Stores a pointer to an `std.Io.Writer`.
///
/// The writer must outlive the Logger instance.
pub const Logger = struct {
    writer: *std.Io.Writer,
    options: LoggerOptions,

    /// Creates a Logger that writes to `writer`.
    pub fn init(writer: *std.Io.Writer, options: LoggerOptions) Logger {
        return .{ .writer = writer, .options = options };
    }

    /// Returns true if the given level would be output.
    pub fn enabled(self: *const Logger, level: Level) bool {
        return @intFromEnum(level) >= @intFromEnum(self.options.level);
    }

    pub fn trace(self: *Logger, message: []const u8, fields: anytype) !void {
        try self.log(.trace, message, fields);
    }
    pub fn debug(self: *Logger, message: []const u8, fields: anytype) !void {
        try self.log(.debug, message, fields);
    }
    pub fn info(self: *Logger, message: []const u8, fields: anytype) !void {
        try self.log(.info, message, fields);
    }
    pub fn warn(self: *Logger, message: []const u8, fields: anytype) !void {
        try self.log(.warn, message, fields);
    }
    pub fn err(self: *Logger, message: []const u8, fields: anytype) !void {
        try self.log(.err, message, fields);
    }
    pub fn fatal(self: *Logger, message: []const u8, fields: anytype) !void {
        try self.log(.fatal, message, fields);
    }

    fn log(self: *Logger, level: Level, message: []const u8, fields: anytype) !void {
        if (!self.enabled(level)) return;
        switch (self.options.format) {
            .text => try self.writeText(level, message, fields),
            .json => try self.writeJson(level, message, fields),
        }
        try self.writer.flush();
    }

    fn writeText(self: *Logger, level: Level, message: []const u8, fields: anytype) !void {
        // Optional timestamp
        if (self.options.timestamp) {
            const io = std.Io.Threaded.global_single_threaded.io();
            const ts = std.Io.Clock.real.now(io).toMilliseconds();
            try self.writer.print("{d} ", .{ts});
        }
        // Level
        try self.writer.writeAll(level.string());
        try self.writer.writeByte(' ');
        // Message
        try self.writer.writeAll(message);
        // Fields
        const FieldsType = @TypeOf(fields);
        if (@typeInfo(FieldsType) == .@"struct") {
            inline for (std.meta.fields(FieldsType)) |field| {
                try self.writer.writeByte(' ');
                try self.writer.writeAll(field.name);
                try self.writer.writeByte('=');
                const val = @field(fields, field.name);
                try writeTextValue(self.writer, val);
            }
        }
        try self.writer.writeByte('\n');
    }

    fn writeJson(self: *Logger, level: Level, message: []const u8, fields: anytype) !void {
        try self.writer.writeByte('{');

        // Optional timestamp
        if (self.options.timestamp) {
            const io = std.Io.Threaded.global_single_threaded.io();
            const ts = std.Io.Clock.real.now(io).toMilliseconds();
            try self.writer.print("\"time_unix_ms\":{d},", .{ts});
        }

        // Level
        try self.writer.writeAll("\"level\":");
        try internal_json.writeEscapedString(self.writer, level.jsonString());

        // Message
        try self.writer.writeByte(',');
        try self.writer.writeAll("\"message\":");
        try internal_json.writeEscapedString(self.writer, message);

        // Fields
        const FieldsType = @TypeOf(fields);
        if (@typeInfo(FieldsType) == .@"struct") {
            inline for (std.meta.fields(FieldsType)) |field| {
                try self.writer.writeByte(',');
                try internal_json.writeEscapedString(self.writer, field.name);
                try self.writer.writeByte(':');
                const val = @field(fields, field.name);
                try writeJsonValue(self.writer, val);
            }
        }

        try self.writer.writeAll("}\n");
    }
};

fn writeTextValue(writer: *std.Io.Writer, val: anytype) !void {
    const T = @TypeOf(val);
    switch (@typeInfo(T)) {
        .bool => try writer.writeAll(if (val) "true" else "false"),
        .int, .comptime_int => try writer.print("{d}", .{val}),
        .float, .comptime_float => try writer.print("{d}", .{val}),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                // []const u8 or []u8
                try writer.writeAll(val);
            } else if (ptr.size == .many and ptr.child == u8 and ptr.sentinel_ptr != null) {
                // [*:0]const u8 (null-terminated many-pointer)
                try writer.writeAll(std.mem.span(val));
            } else if (ptr.size == .one) {
                // *const [N]u8 or *const [N:0]u8 — pointer to array, coerce to slice
                const child_info = @typeInfo(ptr.child);
                if (child_info == .array and child_info.array.child == u8) {
                    try writer.writeAll(val);
                } else {
                    @compileError("unsupported field type for log: " ++ @typeName(T));
                }
            } else {
                @compileError("unsupported field type for log: " ++ @typeName(T));
            }
        },
        .array => |arr| {
            if (arr.child == u8) {
                try writer.writeAll(&val);
            } else {
                @compileError("unsupported field type for log: " ++ @typeName(T));
            }
        },
        .@"enum" => try writer.writeAll(@tagName(val)),
        .optional => {
            if (val) |v| {
                try writeTextValue(writer, v);
            } else {
                try writer.writeAll("null");
            }
        },
        else => @compileError("unsupported field type for log: " ++ @typeName(T)),
    }
}

fn writeJsonValue(writer: *std.Io.Writer, val: anytype) !void {
    const T = @TypeOf(val);
    switch (@typeInfo(T)) {
        .bool => try writer.writeAll(if (val) "true" else "false"),
        .int, .comptime_int => try writer.print("{d}", .{val}),
        .float, .comptime_float => try writer.print("{d}", .{val}),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                // []const u8 or []u8
                try internal_json.writeEscapedString(writer, val);
            } else if (ptr.size == .many and ptr.child == u8 and ptr.sentinel_ptr != null) {
                // [*:0]const u8 (null-terminated many-pointer)
                try internal_json.writeEscapedString(writer, std.mem.span(val));
            } else if (ptr.size == .one) {
                // *const [N]u8 or *const [N:0]u8 — pointer to array, coerce to slice
                const child_info = @typeInfo(ptr.child);
                if (child_info == .array and child_info.array.child == u8) {
                    try internal_json.writeEscapedString(writer, val);
                } else {
                    @compileError("unsupported field type for JSON log: " ++ @typeName(T));
                }
            } else {
                @compileError("unsupported field type for JSON log: " ++ @typeName(T));
            }
        },
        .array => |arr| {
            if (arr.child == u8) {
                try internal_json.writeEscapedString(writer, &val);
            } else {
                @compileError("unsupported field type for JSON log: " ++ @typeName(T));
            }
        },
        .@"enum" => try internal_json.writeEscapedString(writer, @tagName(val)),
        .optional => {
            if (val) |v| {
                try writeJsonValue(writer, v);
            } else {
                try writer.writeAll("null");
            }
        },
        else => @compileError("unsupported field type for JSON log: " ++ @typeName(T)),
    }
}
