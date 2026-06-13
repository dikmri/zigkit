//! zigkit-config: Configuration loader supporting ZON, JSON, env vars, and overrides.
//!
//! Priority order (highest to lowest): overrides > env > file > struct default

const std = @import("std");
const internal_string = @import("internal/string.zig");

pub const FileFormat = enum { auto, zon, json };

pub const Override = struct {
    key: []const u8,
    value: []const u8,
};

pub const LoadOptions = struct {
    file_path: ?[]const u8 = null,
    file_format: FileFormat = .auto,
    env_prefix: ?[]const u8 = null,
    overrides: []const Override = &.{},
    allow_unknown_fields: bool = false,
};

pub const ConfigError = error{
    FileNotFound,
    UnsupportedFormat,
    InvalidFormat,
    UnknownField,
    MissingRequiredField,
    InvalidValue,
    UnsupportedType,
    OutOfMemory,
};

/// Load a config struct T from file, env vars, and/or overrides.
/// Caller owns the returned value; call free() to release string memory.
pub fn load(comptime T: type, allocator: std.mem.Allocator, options: LoadOptions) !T {
    // 1. Start with struct defaults (or zero-init for fields without defaults)
    var result: T = try initDefaults(T, allocator);
    errdefer freeValue(T, allocator, result);

    // 2. Apply file values (overrides struct defaults)
    if (options.file_path) |path| {
        const fmt = if (options.file_format == .auto) detectFormat(path) else options.file_format;
        if (fmt == .auto) return ConfigError.UnsupportedFormat;
        try applyFile(T, allocator, &result, path, fmt, options.allow_unknown_fields);
    }

    // 3. Apply env vars (overrides file values)
    if (options.env_prefix) |prefix| {
        try applyEnv(T, allocator, &result, prefix);
    }

    // 4. Apply explicit overrides (highest priority)
    for (options.overrides) |ov| {
        setFieldFromString(T, allocator, &result, ov.key, ov.value) catch |err| switch (err) {
            error.UnknownField => if (!options.allow_unknown_fields) return err,
            else => return err,
        };
    }

    // 5. Validate required fields
    try validateRequired(T, result);

    return result;
}

/// Release all allocator-owned strings in a config value.
pub fn free(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    freeValue(T, allocator, value);
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: initialisation
// ─────────────────────────────────────────────────────────────────────────────

/// Build a T using only struct field defaults. Fields without defaults are zero-init.
/// All []const u8 values (including inside nested structs) are duped so we own them.
fn initDefaults(comptime T: type, allocator: std.mem.Allocator) !T {
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (field.default_value_ptr) |ptr| {
            const typed: *const field.type = @alignCast(@ptrCast(ptr));
            const val = typed.*;
            // Deep-copy so we own all memory (strings, nested structs, etc.)
            @field(result, field.name) = try deepCopyValue(field.type, allocator, val);
        } else {
            // Zero-initialise fields without defaults.
            @field(result, field.name) = zeroValue(field.type);
        }
    }
    return result;
}

/// Deep-copy a value so that all []const u8 slices are allocator-owned.
fn deepCopyValue(comptime FT: type, allocator: std.mem.Allocator, val: FT) !FT {
    return switch (@typeInfo(FT)) {
        .pointer => |p| if (p.size == .slice and p.child == u8)
            try allocator.dupe(u8, val)
        else
            val, // non-string pointers: copy as-is
        .optional => |opt| if (val) |inner|
            @as(FT, try deepCopyValue(opt.child, allocator, inner))
        else
            null,
        .@"struct" => blk: {
            var copy: FT = undefined;
            inline for (@typeInfo(FT).@"struct".fields) |f| {
                @field(copy, f.name) = try deepCopyValue(f.type, allocator, @field(val, f.name));
            }
            break :blk copy;
        },
        else => val, // scalars, enums, bools: copy directly
    };
}

/// Return the zero value for type FT.
fn zeroValue(comptime FT: type) FT {
    return switch (@typeInfo(FT)) {
        .bool => false,
        .int => 0,
        .float => 0.0,
        .pointer => |p| if (p.size == .slice) @as(FT, &.{}) else @compileError("unsupported pointer type"),
        .optional => null,
        .@"enum" => @as(FT, @enumFromInt(0)),
        .@"struct" => blk: {
            // Zero-init nested struct fields
            var s: FT = undefined;
            inline for (@typeInfo(FT).@"struct".fields) |f| {
                @field(s, f.name) = zeroValue(f.type);
            }
            break :blk s;
        },
        else => @compileError("unsupported type in zeroValue: " ++ @typeName(FT)),
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: freeing
// ─────────────────────────────────────────────────────────────────────────────

fn freeValue(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        freeField(field.type, allocator, @field(value, field.name));
    }
}

fn freeField(comptime FT: type, allocator: std.mem.Allocator, val: FT) void {
    switch (@typeInfo(FT)) {
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                allocator.free(val);
            }
        },
        .optional => |opt| {
            if (val) |inner| {
                freeField(opt.child, allocator, inner);
            }
        },
        .@"struct" => {
            freeValue(FT, allocator, val);
        },
        else => {},
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: format detection
// ─────────────────────────────────────────────────────────────────────────────

fn detectFormat(path: []const u8) FileFormat {
    if (std.mem.endsWith(u8, path, ".zon")) return .zon;
    if (std.mem.endsWith(u8, path, ".json")) return .json;
    return .auto; // unknown extension
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: file reading
// ─────────────────────────────────────────────────────────────────────────────

fn readFileZ(allocator: std.mem.Allocator, path: []const u8) ![:0]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ConfigError.FileNotFound,
        else => return err,
    };
    defer file.close(io);
    const stat = try file.stat(io);
    const buf = try allocator.allocSentinel(u8, stat.size, 0);
    errdefer allocator.free(buf);
    _ = try file.readPositionalAll(io, buf, 0);
    return buf;
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ConfigError.FileNotFound,
        else => return err,
    };
    defer file.close(io);
    const stat = try file.stat(io);
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    _ = try file.readPositionalAll(io, buf, 0);
    return buf;
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: file parsing and applying
// ─────────────────────────────────────────────────────────────────────────────

fn applyFile(
    comptime T: type,
    allocator: std.mem.Allocator,
    result: *T,
    path: []const u8,
    fmt: FileFormat,
    allow_unknown: bool,
) !void {
    switch (fmt) {
        .zon => try applyZon(T, allocator, result, path),
        .json => try applyJson(T, allocator, result, path, allow_unknown),
        .auto => return ConfigError.UnsupportedFormat,
    }
}

fn applyZon(comptime T: type, allocator: std.mem.Allocator, result: *T, path: []const u8) !void {
    const source = try readFileZ(allocator, path);
    defer allocator.free(source);

    // Parse into a fresh T; ZON handles struct defaults for missing fields.
    const parsed = std.zon.parse.fromSliceAlloc(T, allocator, source, null, .{}) catch {
        return ConfigError.InvalidFormat;
    };
    // The parsed value owns its strings (via allocator). Walk fields and transfer.
    inline for (@typeInfo(T).@"struct".fields) |field| {
        // Free the current value in result (which holds initDefaults value)
        freeField(field.type, allocator, @field(result.*, field.name));
        // Move parsed value into result; for nested structs and strings, ownership transfers.
        @field(result.*, field.name) = @field(parsed, field.name);
    }
    // Note: 'parsed' itself is now drained (fields moved); no further free needed.
}

fn applyJson(
    comptime T: type,
    allocator: std.mem.Allocator,
    result: *T,
    path: []const u8,
    allow_unknown: bool,
) !void {
    const source = try readFileAlloc(allocator, path);
    defer allocator.free(source);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch {
        return ConfigError.InvalidFormat;
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return ConfigError.InvalidFormat;

    try applyJsonObject(T, allocator, result, root.object, allow_unknown);
}

fn applyJsonObject(
    comptime T: type,
    allocator: std.mem.Allocator,
    result: *T,
    obj: std.json.ObjectMap,
    allow_unknown: bool,
) !void {
    // Check for unknown fields if requested
    if (!allow_unknown) {
        var it = obj.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            var found = false;
            inline for (@typeInfo(T).@"struct".fields) |field| {
                if (std.mem.eql(u8, field.name, key)) {
                    found = true;
                    break;
                }
            }
            if (!found) return ConfigError.UnknownField;
        }
    }

    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (obj.get(field.name)) |json_val| {
            const old = @field(result.*, field.name);
            freeField(field.type, allocator, old);
            @field(result.*, field.name) = try jsonValueToField(field.type, allocator, json_val);
        }
    }
}

fn jsonValueToField(comptime FT: type, allocator: std.mem.Allocator, val: std.json.Value) !FT {
    return switch (@typeInfo(FT)) {
        .bool => switch (val) {
            .bool => |b| b,
            else => ConfigError.InvalidValue,
        },
        .int => switch (val) {
            .integer => |i| std.math.cast(FT, i) orelse ConfigError.InvalidValue,
            else => ConfigError.InvalidValue,
        },
        .float => switch (val) {
            .float => |f| @as(FT, @floatCast(f)),
            .integer => |i| @as(FT, @floatFromInt(i)),
            else => ConfigError.InvalidValue,
        },
        .pointer => |p| if (p.size == .slice and p.child == u8) switch (val) {
            .string => |s| try allocator.dupe(u8, s),
            else => ConfigError.InvalidValue,
        } else @compileError("unsupported pointer type in JSON"),
        .optional => |opt| switch (val) {
            .null => null,
            else => @as(FT, try jsonValueToField(opt.child, allocator, val)),
        },
        .@"enum" => switch (val) {
            .string => |s| std.meta.stringToEnum(FT, s) orelse ConfigError.InvalidValue,
            else => ConfigError.InvalidValue,
        },
        .@"struct" => switch (val) {
            .object => |obj| blk: {
                var nested: FT = try initDefaults(FT, allocator);
                errdefer freeValue(FT, allocator, nested);
                try applyJsonObject(FT, allocator, &nested, obj, false);
                break :blk nested;
            },
            else => ConfigError.InvalidValue,
        },
        else => @compileError("unsupported type in JSON parsing: " ++ @typeName(FT)),
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: env var application
// ─────────────────────────────────────────────────────────────────────────────

fn applyEnv(comptime T: type, allocator: std.mem.Allocator, result: *T, prefix: []const u8) !void {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        // Skip nested struct fields — env vars can only set scalar values
        if (@typeInfo(field.type) == .@"struct") continue;

        const env_name = try internal_string.toEnvNameAlloc(allocator, prefix, field.name);
        defer allocator.free(env_name);

        // getenv requires a null-terminated string; allocate sentinel version.
        const env_name_z = try allocator.dupeZ(u8, env_name);
        defer allocator.free(env_name_z);

        const env_val_c = std.c.getenv(env_name_z.ptr);
        if (env_val_c) |cptr| {
            const raw = std.mem.sliceTo(cptr, 0);
            const old = @field(result.*, field.name);
            freeField(field.type, allocator, old);
            @field(result.*, field.name) = try parseFieldFromString(field.type, allocator, raw);
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: set field from string (for env + overrides)
// ─────────────────────────────────────────────────────────────────────────────

fn setFieldFromString(
    comptime T: type,
    allocator: std.mem.Allocator,
    result: *T,
    key: []const u8,
    value: []const u8,
) !void {
    var found = false;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, key)) {
            found = true;
            const old = @field(result.*, field.name);
            freeField(field.type, allocator, old);
            @field(result.*, field.name) = try parseFieldFromString(field.type, allocator, value);
        }
    }
    if (!found) return ConfigError.UnknownField;
}

fn parseFieldFromString(comptime FT: type, allocator: std.mem.Allocator, raw: []const u8) !FT {
    return switch (@typeInfo(FT)) {
        .bool => if (std.mem.eql(u8, raw, "true") or std.mem.eql(u8, raw, "1"))
            true
        else if (std.mem.eql(u8, raw, "false") or std.mem.eql(u8, raw, "0"))
            false
        else
            ConfigError.InvalidValue,
        .int => std.fmt.parseInt(FT, raw, 10) catch ConfigError.InvalidValue,
        .float => std.fmt.parseFloat(FT, raw) catch ConfigError.InvalidValue,
        .pointer => |p| if (p.size == .slice and p.child == u8)
            try allocator.dupe(u8, raw)
        else
            @compileError("unsupported pointer type: " ++ @typeName(FT)),
        .optional => |opt| if (raw.len == 0)
            null
        else
            @as(FT, try parseFieldFromString(opt.child, allocator, raw)),
        .@"enum" => std.meta.stringToEnum(FT, raw) orelse ConfigError.InvalidValue,
        .@"struct" => return ConfigError.UnsupportedType,
        else => @compileError("unsupported type for string parsing: " ++ @typeName(FT)),
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: validation
// ─────────────────────────────────────────────────────────────────────────────

fn validateRequired(comptime T: type, value: T) !void {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        // A field is required if it has no default and is not optional
        if (field.default_value_ptr == null and @typeInfo(field.type) != .optional) {
            // For []const u8: required means non-empty
            if (@typeInfo(field.type) == .pointer) {
                const pi = @typeInfo(field.type).pointer;
                if (pi.size == .slice and pi.child == u8) {
                    if (@field(value, field.name).len == 0) {
                        return ConfigError.MissingRequiredField;
                    }
                }
            }
            // For nested structs without defaults: recurse
            if (@typeInfo(field.type) == .@"struct") {
                try validateRequired(field.type, @field(value, field.name));
            }
        }
    }
}
