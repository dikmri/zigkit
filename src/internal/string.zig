const std = @import("std");

/// Returns true if a == b.
pub fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Returns true if s starts with prefix.
pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, s, prefix);
}

/// Returns true if s ends with suffix.
pub fn endsWith(s: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, s, suffix);
}

/// Converts a struct field name to an environment variable name.
/// Example: prefix="APP_", field_name="database_url" -> "APP_DATABASE_URL"
/// Caller owns returned slice.
pub fn toEnvNameAlloc(allocator: std.mem.Allocator, prefix: []const u8, field_name: []const u8) ![]u8 {
    const total_len = prefix.len + field_name.len;
    const result = try allocator.alloc(u8, total_len);
    @memcpy(result[0..prefix.len], prefix);
    for (field_name, prefix.len..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

/// Duplicates an optional string. Returns null if value is null.
/// Caller owns returned slice.
pub fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |v| {
        return try allocator.dupe(u8, v);
    }
    return null;
}

test "toEnvNameAlloc" {
    const allocator = std.testing.allocator;
    const result = try toEnvNameAlloc(allocator, "APP_", "database_url");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("APP_DATABASE_URL", result);
}

test "dupeOptional" {
    const allocator = std.testing.allocator;
    const result = try dupeOptional(allocator, "hello");
    defer if (result) |r| allocator.free(r);
    try std.testing.expectEqualStrings("hello", result.?);

    const null_result = try dupeOptional(allocator, null);
    try std.testing.expectEqual(@as(?[]const u8, null), null_result);
}
