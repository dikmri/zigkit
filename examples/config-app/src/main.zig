//! config-app: Example demonstrating zigkit-config usage.
//!
//! Load configuration from a ZON file, with env var overrides and explicit overrides.

const std = @import("std");
const zk = @import("zigkit");

/// Application configuration struct.
const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    debug: bool = false,
    database_url: []const u8, // required — no default
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Load config from ZON file with optional env-var overrides.
    // Set APP_HOST, APP_PORT, APP_DEBUG, APP_DATABASE_URL to override.
    const cfg = zk.config.load(AppConfig, allocator, .{
        .file_path = "examples/config-app/app.zon",
        .env_prefix = "APP_",
    }) catch |err| {
        std.debug.print("Failed to load config: {}\n", .{err});
        return err;
    };
    defer zk.config.free(AppConfig, allocator, cfg);

    std.debug.print("=== config-app ===\n", .{});
    std.debug.print("host:         {s}\n", .{cfg.host});
    std.debug.print("port:         {d}\n", .{cfg.port});
    std.debug.print("debug:        {}\n", .{cfg.debug});
    std.debug.print("database_url: {s}\n", .{cfg.database_url});
}
