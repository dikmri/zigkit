const std = @import("std");
const zk = @import("zigkit");

const spec = zk.cli.CommandSpec{
    .name = "hello-cli",
    .version = "0.1.0",
    .about = "a hello world CLI example",
    .options = &.{
        .{
            .long = "name",
            .short = 'n',
            .value_name = "NAME",
            .kind = .string,
            .required = true,
            .help = "your name",
        },
        .{
            .long = "verbose",
            .short = 'v',
            .kind = .bool,
            .help = "enable verbose logging",
        },
    },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Get args slice (includes argv[0]), skip it
    const all_args_z = try init.minimal.args.toSlice(allocator);
    defer allocator.free(all_args_z);
    // [:0]const u8 and []const u8 have the same layout — safe ptrCast
    const all_args = @as([]const []const u8, @ptrCast(all_args_z));
    const args = if (all_args.len > 1) all_args[1..] else &[_][]const u8{};

    var result = zk.cli.parse(allocator, spec, args) catch |err| switch (err) {
        error.HelpRequested => {
            const help = try zk.cli.renderHelpAlloc(allocator, spec);
            defer allocator.free(help);
            std.debug.print("{s}", .{help});
            return;
        },
        error.VersionRequested => {
            const ver = try zk.cli.renderVersionAlloc(allocator, spec);
            defer allocator.free(ver);
            std.debug.print("{s}", .{ver});
            return;
        },
        else => return err,
    };
    defer result.deinit();

    const name = result.getString("name").?;
    const verbose = result.getBool("verbose") orelse false;

    std.debug.print("hello, {s}\n", .{name});
    if (verbose) {
        std.debug.print("verbose: true\n", .{});
    }
}
