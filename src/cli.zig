//! zigkit-cli: Command-line argument parser.
//!
//! Supports long/short options, flags, typed values, positionals,
//! subcommands, help/version rendering, and detailed error reports.

const std = @import("std");

// ── Public types ──────────────────────────────────────────────────────────

/// Kind of value an option accepts.
pub const ValueKind = enum {
    bool,
    string,
    int,
    float,
    path,
};

/// Specification for a single option (flag or valued option).
pub const OptionSpec = struct {
    long: []const u8,
    short: ?u8 = null,
    value_name: ?[]const u8 = null,
    kind: ValueKind = .string,
    required: bool = false,
    multiple: bool = false,
    default: ?[]const u8 = null,
    help: []const u8 = "",
};

/// Specification for a positional argument.
pub const PositionalSpec = struct {
    name: []const u8,
    required: bool = true,
    multiple: bool = false,
    help: []const u8 = "",
};

/// Specification for a command (root or subcommand).
pub const CommandSpec = struct {
    name: []const u8,
    version: ?[]const u8 = null,
    about: []const u8 = "",
    options: []const OptionSpec = &.{},
    positionals: []const PositionalSpec = &.{},
    subcommands: []const CommandSpec = &.{},
};

/// A parsed value.
pub const Value = union(ValueKind) {
    bool: bool,
    string: []const u8,
    int: i64,
    float: f64,
    path: []const u8,
};

/// Errors during CLI parsing.
pub const CliError = error{
    UnknownOption,
    MissingOptionValue,
    MissingRequiredOption,
    InvalidOptionValue,
    UnexpectedArgument,
    UnknownCommand,
    DuplicateOption,
    HelpRequested,
    VersionRequested,
    OutOfMemory,
};

/// Detailed error report.
pub const ErrorReport = struct {
    kind: anyerror,
    message: []const u8,
    hint: ?[]const u8 = null,
    option: ?[]const u8 = null,
    command: ?[]const u8 = null,

    pub fn deinit(self: *ErrorReport, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.hint) |h| allocator.free(h);
        if (self.option) |o| allocator.free(o);
        if (self.command) |c| allocator.free(c);
        self.* = undefined;
    }
};

/// Result of a detailed parse (either ok or error).
pub const ParseDetailedResult = union(enum) {
    ok: ParseResult,
    err: ErrorReport,
};

// ── ParseResult ────────────────────────────────────────────────────────────

/// Internal storage for one named option's values.
/// In Zig 0.16, std.ArrayList is unmanaged (requires allocator for most ops).
const ParseEntry = struct {
    /// Points into the spec's `long` field — NOT owned.
    name: []const u8,
    values: std.ArrayList(Value),
};

/// Result of a successful parse.
pub const ParseResult = struct {
    allocator: std.mem.Allocator,
    /// The command name — owned.
    command: []const u8,
    /// The selected subcommand name — owned or null.
    selected_subcommand: ?[]const u8,
    /// Option entries (name is NOT owned; values ARE owned).
    entries: std.ArrayList(ParseEntry),
    /// Positional argument values — owned.
    positionals: std.ArrayList([]const u8),

    pub fn deinit(self: *ParseResult) void {
        const alloc = self.allocator;
        for (self.entries.items) |*entry| {
            for (entry.values.items) |val| {
                switch (val) {
                    .string, .path => |s| alloc.free(s),
                    else => {},
                }
            }
            entry.values.deinit(alloc);
        }
        self.entries.deinit(alloc);
        for (self.positionals.items) |p| alloc.free(p);
        self.positionals.deinit(alloc);
        alloc.free(self.command);
        if (self.selected_subcommand) |sc| alloc.free(sc);
        self.* = undefined;
    }

    fn findEntry(self: *const ParseResult, name: []const u8) ?*ParseEntry {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }

    pub fn getBool(self: *const ParseResult, name: []const u8) ?bool {
        const entry = self.findEntry(name) orelse return null;
        if (entry.values.items.len == 0) return null;
        return switch (entry.values.items[entry.values.items.len - 1]) {
            .bool => |b| b,
            else => null,
        };
    }

    pub fn getString(self: *const ParseResult, name: []const u8) ?[]const u8 {
        const entry = self.findEntry(name) orelse return null;
        if (entry.values.items.len == 0) return null;
        return switch (entry.values.items[entry.values.items.len - 1]) {
            .string, .path => |s| s,
            else => null,
        };
    }

    pub fn getInt(self: *const ParseResult, name: []const u8) ?i64 {
        const entry = self.findEntry(name) orelse return null;
        if (entry.values.items.len == 0) return null;
        return switch (entry.values.items[entry.values.items.len - 1]) {
            .int => |i| i,
            else => null,
        };
    }

    pub fn getFloat(self: *const ParseResult, name: []const u8) ?f64 {
        const entry = self.findEntry(name) orelse return null;
        if (entry.values.items.len == 0) return null;
        return switch (entry.values.items[entry.values.items.len - 1]) {
            .float => |f| f,
            else => null,
        };
    }

    pub fn getStrings(self: *const ParseResult, name: []const u8) []const Value {
        const entry = self.findEntry(name) orelse return &.{};
        return entry.values.items;
    }

    pub fn positional(self: *const ParseResult, index: usize) ?[]const u8 {
        if (index >= self.positionals.items.len) return null;
        return self.positionals.items[index];
    }
};

// ── Help/Version rendering ─────────────────────────────────────────────────

/// Renders help text. Caller owns the returned slice.
pub fn renderHelpAlloc(allocator: std.mem.Allocator, spec: CommandSpec) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);

    // Header
    if (spec.version) |ver| {
        try aw.writer.print("{s} {s}\n", .{ spec.name, ver });
    } else {
        try aw.writer.print("{s}\n", .{spec.name});
    }
    if (spec.about.len > 0) {
        try aw.writer.print("{s}\n", .{spec.about});
    }
    try aw.writer.writeByte('\n');

    // Usage line
    try aw.writer.print("USAGE:\n  {s}", .{spec.name});
    if (spec.options.len > 0) try aw.writer.writeAll(" [OPTIONS]");
    for (spec.positionals) |pos| {
        if (pos.required) {
            try aw.writer.print(" <{s}>", .{pos.name});
        } else {
            try aw.writer.print(" [{s}]", .{pos.name});
        }
    }
    if (spec.subcommands.len > 0) try aw.writer.writeAll(" <COMMAND>");
    try aw.writer.writeByte('\n');

    // Args
    if (spec.positionals.len > 0) {
        try aw.writer.writeAll("\nARGS:\n");
        for (spec.positionals) |pos| {
            try aw.writer.print("  <{s}>", .{pos.name});
            if (pos.help.len > 0) {
                try aw.writer.print("    {s}", .{pos.help});
            }
            try aw.writer.writeByte('\n');
        }
    }

    // Options
    {
        try aw.writer.writeAll("\nOPTIONS:\n");
        for (spec.options) |opt| {
            if (opt.short) |s| {
                try aw.writer.print("  -{c}, --{s}", .{ s, opt.long });
            } else {
                try aw.writer.print("      --{s}", .{opt.long});
            }
            if (opt.value_name) |vn| {
                try aw.writer.print(" <{s}>", .{vn});
            }
            if (opt.help.len > 0) {
                try aw.writer.print("    {s}", .{opt.help});
            }
            try aw.writer.writeByte('\n');
        }
        // Always add help
        try aw.writer.writeAll("  -h, --help             show help\n");
        if (spec.version != null) {
            try aw.writer.writeAll("  -V, --version          show version\n");
        }
    }

    // Subcommands
    if (spec.subcommands.len > 0) {
        try aw.writer.writeAll("\nCOMMANDS:\n");
        for (spec.subcommands) |sub| {
            try aw.writer.print("  {s}", .{sub.name});
            if (sub.about.len > 0) {
                try aw.writer.print("    {s}", .{sub.about});
            }
            try aw.writer.writeByte('\n');
        }
    }

    const content = aw.writer.buffered();
    const result = try allocator.dupe(u8, content);
    allocator.free(aw.writer.buffer);
    return result;
}

/// Renders version text. Caller owns the returned slice.
pub fn renderVersionAlloc(allocator: std.mem.Allocator, spec: CommandSpec) ![]u8 {
    if (spec.version) |ver| {
        return std.fmt.allocPrint(allocator, "{s} {s}\n", .{ spec.name, ver });
    }
    return std.fmt.allocPrint(allocator, "{s}\n", .{spec.name});
}

// ── Parse ─────────────────────────────────────────────────────────────────

/// Parses args according to spec. Returns ParseResult on success, error on failure.
/// `args` should be the argument slice WITHOUT argv[0] (the program name).
/// Caller must call result.deinit() when done.
pub fn parse(
    allocator: std.mem.Allocator,
    spec: CommandSpec,
    args: []const []const u8,
) CliError!ParseResult {
    const detail = parseDetailed(allocator, spec, args);
    return switch (detail) {
        .ok => |r| r,
        .err => |e| blk: {
            const kind = e.kind;
            var ee = e;
            ee.deinit(allocator);
            break :blk @as(CliError, @errorCast(kind));
        },
    };
}

/// Parses args and returns a detailed result (either ok or an ErrorReport).
/// Caller must call ok.deinit() or err.deinit(allocator) on the result.
pub fn parseDetailed(
    allocator: std.mem.Allocator,
    spec: CommandSpec,
    args: []const []const u8,
) ParseDetailedResult {
    const result = parseImpl(allocator, spec, args) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "parse error: {s}", .{@errorName(err)}) catch
            return .{ .err = .{ .kind = err, .message = "(OOM)" } };
        return .{ .err = .{ .kind = err, .message = msg } };
    };
    return .{ .ok = result };
}

// ── Internal Parser ────────────────────────────────────────────────────────

fn makeEmptyParseResult(allocator: std.mem.Allocator, name: []const u8) CliError!ParseResult {
    return ParseResult{
        .allocator = allocator,
        .command = allocator.dupe(u8, name) catch return CliError.OutOfMemory,
        .selected_subcommand = null,
        .entries = .empty,
        .positionals = .empty,
    };
}

fn parseImpl(
    allocator: std.mem.Allocator,
    spec: CommandSpec,
    args: []const []const u8,
) CliError!ParseResult {
    // Check for subcommand as first non-flag arg BEFORE allocating result.
    if (args.len > 0 and spec.subcommands.len > 0 and !std.mem.startsWith(u8, args[0], "-")) {
        const subcmd_name = args[0];
        for (spec.subcommands) |sub| {
            if (std.mem.eql(u8, sub.name, subcmd_name)) {
                // Recurse into subcommand, parse remaining args
                var sub_result = try parseImpl(allocator, sub, args[1..]);
                // Set selected_subcommand on the result
                sub_result.selected_subcommand = allocator.dupe(u8, subcmd_name) catch {
                    sub_result.deinit();
                    return CliError.OutOfMemory;
                };
                return sub_result;
            }
        }
        // Unknown subcommand
        return CliError.UnknownCommand;
    }

    var result = try makeEmptyParseResult(allocator, spec.name);
    errdefer result.deinit();

    var i: usize = 0;
    var positional_index: usize = 0;
    var end_of_options = false;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (end_of_options) {
            const val = allocator.dupe(u8, arg) catch return CliError.OutOfMemory;
            errdefer allocator.free(val);
            result.positionals.append(allocator, val) catch return CliError.OutOfMemory;
            positional_index += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--")) {
            end_of_options = true;
            continue;
        }

        // --help / -h
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return CliError.HelpRequested;
        }

        // --version / -V
        if (spec.version != null and (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V"))) {
            return CliError.VersionRequested;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            // Long option: --name or --name=value or --name value
            const rest = arg[2..];
            const eq_pos = std.mem.indexOfScalar(u8, rest, '=');

            var opt_name: []const u8 = undefined;
            var opt_value: ?[]const u8 = null;

            if (eq_pos) |pos| {
                opt_name = rest[0..pos];
                opt_value = rest[pos + 1 ..];
            } else {
                opt_name = rest;
            }

            const opt_spec = findOptionByLong(spec.options, opt_name) orelse {
                return CliError.UnknownOption;
            };

            if (opt_spec.kind == .bool) {
                // Bool flag doesn't take a value
                try appendEntry(&result, allocator, opt_spec.long, .{ .bool = true });
            } else {
                // Need a value
                if (opt_value == null) {
                    // Next arg must exist and must not start with '-'
                    if (i + 1 >= args.len) return CliError.MissingOptionValue;
                    if (std.mem.startsWith(u8, args[i + 1], "-")) return CliError.MissingOptionValue;
                    i += 1;
                    opt_value = args[i];
                }
                const parsed_val = try parseValue(allocator, opt_spec.kind, opt_value.?);
                try appendEntry(&result, allocator, opt_spec.long, parsed_val);
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            // Short option: -x or -x value
            const short_char = arg[1];

            const opt_spec = findOptionByShort(spec.options, short_char) orelse {
                return CliError.UnknownOption;
            };

            if (opt_spec.kind == .bool) {
                try appendEntry(&result, allocator, opt_spec.long, .{ .bool = true });
            } else {
                // Value comes next
                if (i + 1 >= args.len) return CliError.MissingOptionValue;
                if (std.mem.startsWith(u8, args[i + 1], "-")) return CliError.MissingOptionValue;
                i += 1;
                const parsed_val = try parseValue(allocator, opt_spec.kind, args[i]);
                try appendEntry(&result, allocator, opt_spec.long, parsed_val);
            }
        } else {
            // Positional argument
            if (positional_index < spec.positionals.len) {
                const val = allocator.dupe(u8, arg) catch return CliError.OutOfMemory;
                errdefer allocator.free(val);
                result.positionals.append(allocator, val) catch return CliError.OutOfMemory;
                if (!spec.positionals[positional_index].multiple) {
                    positional_index += 1;
                }
            } else {
                return CliError.UnexpectedArgument;
            }
        }
    }

    // Apply defaults for missing options
    for (spec.options) |opt| {
        if (result.findEntry(opt.long) == null) {
            if (opt.default) |def| {
                const val = try parseValue(allocator, opt.kind, def);
                try appendEntry(&result, allocator, opt.long, val);
            } else if (opt.kind == .bool) {
                // Bool flags default to false
                try appendEntry(&result, allocator, opt.long, .{ .bool = false });
            }
        }
    }

    // Check required options
    for (spec.options) |opt| {
        if (opt.required and result.findEntry(opt.long) == null) {
            return CliError.MissingRequiredOption;
        }
    }

    // Check required positionals
    for (spec.positionals, 0..) |pos, idx| {
        if (pos.required and idx >= result.positionals.items.len) {
            return CliError.MissingRequiredOption;
        }
    }

    return result;
}

fn findOptionByLong(options: []const OptionSpec, name: []const u8) ?OptionSpec {
    for (options) |opt| {
        if (std.mem.eql(u8, opt.long, name)) return opt;
    }
    return null;
}

fn findOptionByShort(options: []const OptionSpec, char: u8) ?OptionSpec {
    for (options) |opt| {
        if (opt.short) |s| {
            if (s == char) return opt;
        }
    }
    return null;
}

/// Appends a value to the named option entry (creating it if needed).
/// `name` must outlive the result (e.g., points into spec's `long` field).
fn appendEntry(
    result: *ParseResult,
    allocator: std.mem.Allocator,
    name: []const u8,
    val: Value,
) CliError!void {
    if (result.findEntry(name)) |existing| {
        existing.values.append(allocator, val) catch return CliError.OutOfMemory;
    } else {
        var list: std.ArrayList(Value) = .empty;
        list.append(allocator, val) catch return CliError.OutOfMemory;
        result.entries.append(allocator, .{ .name = name, .values = list }) catch return CliError.OutOfMemory;
    }
}

fn parseValue(allocator: std.mem.Allocator, kind: ValueKind, raw: []const u8) CliError!Value {
    return switch (kind) {
        .bool => if (std.mem.eql(u8, raw, "true") or std.mem.eql(u8, raw, "1"))
            .{ .bool = true }
        else if (std.mem.eql(u8, raw, "false") or std.mem.eql(u8, raw, "0"))
            .{ .bool = false }
        else
            CliError.InvalidOptionValue,
        .string => .{ .string = allocator.dupe(u8, raw) catch return CliError.OutOfMemory },
        .path => .{ .path = allocator.dupe(u8, raw) catch return CliError.OutOfMemory },
        .int => blk: {
            const n = std.fmt.parseInt(i64, raw, 10) catch return CliError.InvalidOptionValue;
            break :blk .{ .int = n };
        },
        .float => blk: {
            const f = std.fmt.parseFloat(f64, raw) catch return CliError.InvalidOptionValue;
            break :blk .{ .float = f };
        },
    };
}
