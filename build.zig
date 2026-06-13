const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Public module
    const zigkit_mod = b.addModule("zigkit", .{
        .root_source_file = b.path("src/zigkit.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Test module (for all tests in src/zigkit.zig including @import of tests/)
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/zigkit.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("zigkit", zigkit_mod);

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run zigkit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Additional test files in tests/
    const test_files = [_][]const u8{
        "tests/test_test.zig",
        "tests/log_test.zig",
        "tests/cli_test.zig",
        "tests/config_test.zig",
    };
    for (test_files) |tf| {
        const tf_mod = b.createModule(.{
            .root_source_file = b.path(tf),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        tf_mod.addImport("zigkit", zigkit_mod);
        const tf_test = b.addTest(.{
            .root_module = tf_mod,
        });
        const run_tf = b.addRunArtifact(tf_test);
        test_step.dependOn(&run_tf.step);
    }

    // Examples step
    const examples_step = b.step("examples", "Build examples");
    for ([_][]const u8{ "hello-cli", "config-app", "json-log" }) |name| {
        const example_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}/src/main.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        example_mod.addImport("zigkit", zigkit_mod);
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = example_mod,
        });
        const install = b.addInstallArtifact(exe, .{});
        examples_step.dependOn(&install.step);
    }

    // Docs step (placeholder - uses zig doc)
    const docs_step = b.step("docs", "Generate docs");
    const docs = b.addInstallDirectory(.{
        .source_dir = unit_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&docs.step);
}
