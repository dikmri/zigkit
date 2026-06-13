const std = @import("std");
const testing = std.testing;
const zk = @import("zigkit");
const cli = zk.cli;

const simple_spec = cli.CommandSpec{
    .name = "test-cmd",
    .version = "1.0.0",
    .about = "a test command",
    .options = &.{
        .{ .long = "name", .short = 'n', .value_name = "NAME", .kind = .string, .help = "your name" },
        .{ .long = "count", .short = 'c', .value_name = "N", .kind = .int, .default = "5", .help = "count" },
        .{ .long = "ratio", .value_name = "R", .kind = .float, .help = "ratio" },
        .{ .long = "verbose", .short = 'v', .kind = .bool, .help = "verbose" },
        .{ .long = "required-opt", .kind = .string, .required = true, .help = "required option" },
        .{ .long = "tags", .kind = .string, .multiple = true, .help = "tags" },
    },
    .positionals = &.{
        .{ .name = "input", .required = true, .help = "input file" },
    },
};

fn doParse(spec: cli.CommandSpec, args: []const []const u8) cli.CliError!cli.ParseResult {
    return cli.parse(testing.allocator, spec, args);
}

test "--name value" {
    var r = try doParse(simple_spec, &.{ "--name", "Alice", "--required-opt", "x", "file.txt" });
    defer r.deinit();
    try testing.expectEqualStrings("Alice", r.getString("name").?);
}

test "--name=value" {
    var r = try doParse(simple_spec, &.{ "--name=Bob", "--required-opt", "x", "file.txt" });
    defer r.deinit();
    try testing.expectEqualStrings("Bob", r.getString("name").?);
}

test "-n value (short option)" {
    var r = try doParse(simple_spec, &.{ "-n", "Carol", "--required-opt", "x", "file.txt" });
    defer r.deinit();
    try testing.expectEqualStrings("Carol", r.getString("name").?);
}

test "bool flag" {
    var r = try doParse(simple_spec, &.{ "--verbose", "--required-opt", "x", "file.txt" });
    defer r.deinit();
    try testing.expect(r.getBool("verbose").? == true);
}

test "required option missing -> error" {
    try testing.expectError(
        cli.CliError.MissingRequiredOption,
        doParse(simple_spec, &.{"file.txt"}),
    );
}

test "unknown option -> error" {
    try testing.expectError(
        cli.CliError.UnknownOption,
        doParse(simple_spec, &.{ "--unknown", "--required-opt", "x", "file.txt" }),
    );
}

test "missing value -> error (option at end)" {
    try testing.expectError(
        cli.CliError.MissingOptionValue,
        doParse(simple_spec, &.{ "--required-opt", "x", "file.txt", "--name" }),
    );
}

test "default value" {
    var r = try doParse(simple_spec, &.{ "--required-opt", "x", "file.txt" });
    defer r.deinit();
    try testing.expectEqual(@as(?i64, 5), r.getInt("count"));
}

test "positional" {
    var r = try doParse(simple_spec, &.{ "--required-opt", "x", "myfile.txt" });
    defer r.deinit();
    try testing.expectEqualStrings("myfile.txt", r.positional(0).?);
}

test "repeated option (multiple)" {
    var r = try doParse(simple_spec, &.{ "--required-opt", "x", "file.txt", "--tags", "a", "--tags", "b" });
    defer r.deinit();
    const tags = r.getStrings("tags");
    try testing.expectEqual(@as(usize, 2), tags.len);
}

const sub_spec = cli.CommandSpec{
    .name = "tool",
    .version = "0.1.0",
    .subcommands = &.{
        .{
            .name = "build",
            .about = "build the project",
            .options = &.{
                .{ .long = "release", .kind = .bool, .help = "release mode" },
            },
        },
        .{
            .name = "test",
            .about = "run tests",
        },
    },
};

test "subcommand" {
    var r = try doParse(sub_spec, &.{ "build", "--release" });
    defer r.deinit();
    try testing.expectEqualStrings("build", r.selected_subcommand.?);
    try testing.expect(r.getBool("release").? == true);
}

test "help text contains key items" {
    const help = try cli.renderHelpAlloc(testing.allocator, simple_spec);
    defer testing.allocator.free(help);
    try testing.expect(std.mem.indexOf(u8, help, "test-cmd") != null);
    try testing.expect(std.mem.indexOf(u8, help, "--name") != null);
    try testing.expect(std.mem.indexOf(u8, help, "--verbose") != null);
    try testing.expect(std.mem.indexOf(u8, help, "--help") != null);
    try testing.expect(std.mem.indexOf(u8, help, "USAGE") != null);
}

test "version text contains version" {
    const ver = try cli.renderVersionAlloc(testing.allocator, simple_spec);
    defer testing.allocator.free(ver);
    try testing.expect(std.mem.indexOf(u8, ver, "1.0.0") != null);
}
