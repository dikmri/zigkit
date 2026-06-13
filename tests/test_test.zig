const std = @import("std");
const testing = std.testing;
const zkt = @import("zigkit").testing;

test "expectContains: success" {
    try zkt.expectContains("hello world", "world");
}

test "expectContains: failure" {
    try testing.expectError(
        error.TestUnexpectedResult,
        zkt.expectContains("hello world", "xyz"),
    );
}

test "expectStartsWith: success" {
    try zkt.expectStartsWith("hello world", "hello");
}

test "expectStartsWith: failure" {
    try testing.expectError(
        error.TestUnexpectedResult,
        zkt.expectStartsWith("hello world", "world"),
    );
}

test "expectEndsWith: success" {
    try zkt.expectEndsWith("hello world", "world");
}

test "expectEndsWith: failure" {
    try testing.expectError(
        error.TestUnexpectedResult,
        zkt.expectEndsWith("hello world", "hello"),
    );
}

test "expectEqualStringPretty: success" {
    try zkt.expectEqualStringPretty("abc", "abc");
}

test "expectEqualStringPretty: failure" {
    try testing.expectError(
        error.TestExpectedEqual,
        zkt.expectEqualStringPretty("abc", "xyz"),
    );
}

test "expectJsonEqual: key order ignored" {
    const allocator = testing.allocator;
    try zkt.expectJsonEqual(allocator,
        \\{"b":2,"a":1}
    ,
        \\{"a":1,"b":2}
    );
}

test "expectJsonEqual: array order preserved" {
    const allocator = testing.allocator;
    try testing.expectError(
        error.TestExpectedEqual,
        zkt.expectJsonEqual(allocator,
            \\[1,2,3]
        ,
            \\[3,2,1]
        ),
    );
}

test "TempDir: write and read" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("hello.txt", "hello zigkit");
    const content = try tmp.readFile("hello.txt", allocator);
    defer allocator.free(content);

    try testing.expectEqualStrings("hello zigkit", content);
}

test "TempDir: deinit removes directory" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    const path = try allocator.dupe(u8, tmp.path);
    defer allocator.free(path);

    tmp.deinit();

    // Verify directory is gone
    const io = std.Io.Threaded.global_single_threaded.io();
    const result = std.Io.Dir.cwd().openDir(io, path, .{});
    try testing.expectError(error.FileNotFound, result);
}

test "expectSnapshot: fails when snapshot does not exist" {
    const allocator = testing.allocator;
    const result = zkt.expectSnapshot(allocator, "nonexistent-test-snap", "content");
    try testing.expectError(error.TestUnexpectedResult, result);
}
