//! zigkit - A small practical toolkit for building Zig applications.
//!
//! Modules:
//! - cli: Command-line argument parser
//! - config: Configuration loader (ZON, JSON, env vars)
//! - log: Structured logger (text/JSON)
//! - testing: Test helpers
pub const cli = @import("cli.zig");
pub const config = @import("config.zig");
pub const log = @import("log.zig");
pub const testing = @import("test.zig");

test {
    _ = cli;
    _ = config;
    _ = log;
    _ = testing;
    @import("std").testing.refAllDecls(@This());
}
