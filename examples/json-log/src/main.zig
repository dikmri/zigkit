const std = @import("std");
const zk = @import("zigkit");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = zk.log.Logger.init(&aw.writer, .{
        .level = .info,
        .format = .json,
        .timestamp = false,
    });

    try logger.info("server started", .{
        .host = "127.0.0.1",
        .port = @as(u16, 8080),
    });
    try logger.warn("high memory", .{
        .used_mb = @as(u64, 512),
    });
    try logger.err("request failed", .{
        .status = @as(u16, 500),
        .path = "/api/users",
    });

    std.debug.print("{s}", .{aw.writer.buffered()});
}
