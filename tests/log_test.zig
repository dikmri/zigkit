const std = @import("std");
const testing = std.testing;
const zk = @import("zigkit");
const log = zk.log;

fn makeLogger(writer: *std.Io.Writer, opts: log.LoggerOptions) log.Logger {
    return log.Logger.init(writer, opts);
}

test "text log basic output" {
    const allocator = testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = makeLogger(&aw.writer, .{ .format = .text, .timestamp = false });
    try logger.info("hello", .{});

    try testing.expectEqualStrings("INFO hello\n", aw.writer.buffered());
}

test "json log basic output" {
    const allocator = testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = makeLogger(&aw.writer, .{ .format = .json, .timestamp = false });
    try logger.info("server started", .{ .host = "127.0.0.1", .port = @as(u16, 8080) });

    const out = aw.writer.buffered();
    try testing.expectEqualStrings("{\"level\":\"info\",\"message\":\"server started\",\"host\":\"127.0.0.1\",\"port\":8080}\n", out);
}

test "level filter: debug filtered when level=info" {
    const allocator = testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = makeLogger(&aw.writer, .{ .format = .text, .timestamp = false, .level = .info });
    try logger.debug("should not appear", .{});

    try testing.expectEqualStrings("", aw.writer.buffered());
}

test "level filter: info passes when level=info" {
    const allocator = testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = makeLogger(&aw.writer, .{ .format = .text, .timestamp = false, .level = .info });
    try logger.info("should appear", .{});

    try testing.expect(std.mem.indexOf(u8, aw.writer.buffered(), "should appear") != null);
}

test "key-value fields in text" {
    const allocator = testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = makeLogger(&aw.writer, .{ .format = .text, .timestamp = false });
    try logger.info("test", .{ .key = "value", .num = @as(i32, 42) });

    const out = aw.writer.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "key=value") != null);
    try testing.expect(std.mem.indexOf(u8, out, "num=42") != null);
}

test "JSON escaping" {
    const allocator = testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = makeLogger(&aw.writer, .{ .format = .json, .timestamp = false });
    try logger.info("test", .{ .msg = "say \"hello\"\nworld" });

    const out = aw.writer.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "\\\"hello\\\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\\n") != null);
}

test "timestamp=false: no time field" {
    const allocator = testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = makeLogger(&aw.writer, .{ .format = .json, .timestamp = false });
    try logger.info("test-msg", .{});

    const out = aw.writer.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "time_unix_ms") == null);
}

test "bool/int/float/string fields in JSON" {
    const allocator = testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = makeLogger(&aw.writer, .{ .format = .json, .timestamp = false });
    try logger.info("types", .{
        .flag = true,
        .count = @as(i64, 99),
        .ratio = @as(f64, 3.14),
        .label = "zig",
    });

    const out = aw.writer.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "\"flag\":true") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"count\":99") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"label\":\"zig\"") != null);
}
