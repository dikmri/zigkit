const std = @import("std");

/// Writes a JSON-escaped string to the writer.
pub fn writeEscapedString(writer: *std.Io.Writer, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\t' => try writer.writeAll("\\t"),
            '\r' => try writer.writeAll("\\r"),
            0x00...0x08, 0x0b...0x0c, 0x0e...0x1f => {
                try writer.print("\\u{x:0>4}", .{c});
            },
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

/// Returns true if two JSON strings are semantically equal.
/// Object key order is ignored; array order is preserved.
pub fn jsonEqual(allocator: std.mem.Allocator, a: []const u8, b: []const u8) !bool {
    const parsed_a = std.json.parseFromSlice(std.json.Value, allocator, a, .{}) catch return false;
    defer parsed_a.deinit();
    const parsed_b = std.json.parseFromSlice(std.json.Value, allocator, b, .{}) catch return false;
    defer parsed_b.deinit();
    return jsonValueEqual(parsed_a.value, parsed_b.value);
}

fn jsonValueEqual(a: std.json.Value, b: std.json.Value) bool {
    if (@as(std.meta.Tag(std.json.Value), a) != @as(std.meta.Tag(std.json.Value), b)) return false;
    return switch (a) {
        .null => true,
        .bool => |av| av == b.bool,
        .integer => |av| av == b.integer,
        .float => |av| av == b.float,
        .number_string => |av| std.mem.eql(u8, av, b.number_string),
        .string => |av| std.mem.eql(u8, av, b.string),
        .array => |av| blk: {
            if (av.items.len != b.array.items.len) break :blk false;
            for (av.items, b.array.items) |ai, bi| {
                if (!jsonValueEqual(ai, bi)) break :blk false;
            }
            break :blk true;
        },
        .object => |av| blk: {
            if (av.count() != b.object.count()) break :blk false;
            var it = av.iterator();
            while (it.next()) |entry| {
                const bval = b.object.get(entry.key_ptr.*) orelse break :blk false;
                if (!jsonValueEqual(entry.value_ptr.*, bval)) break :blk false;
            }
            break :blk true;
        },
    };
}
