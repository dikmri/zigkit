const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const zkt = @import("zigkit").testing;
const config = @import("zigkit").config;

// ─────────────────────────────────────────────────────────────────────────────
// Shared test structs
// ─────────────────────────────────────────────────────────────────────────────

const BasicConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    debug: bool = false,
};

// Has a required field (no default, not optional)
const RequiredConfig = struct {
    host: []const u8 = "localhost",
    database_url: []const u8, // required - no default
};

const EnumConfig = struct {
    level: LogLevel = .info,
    host: []const u8 = "localhost",
};

const LogLevel = enum { debug, info, warn, err };

const OptionalConfig = struct {
    host: []const u8 = "localhost",
    secret: ?[]const u8 = null,
    timeout: ?u32 = null,
};

const NestedConfig = struct {
    host: []const u8 = "localhost",
    db: DbConfig = .{},
};

const DbConfig = struct {
    url: []const u8 = "postgres://localhost/db",
    pool_size: u32 = 5,
};

// ─────────────────────────────────────────────────────────────────────────────
// Test: defaults only (no file/env/overrides)
// ─────────────────────────────────────────────────────────────────────────────

test "デフォルト値が使われる" {
    const allocator = testing.allocator;
    const cfg = try config.load(BasicConfig, allocator, .{});
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("127.0.0.1", cfg.host);
    try testing.expectEqual(@as(u16, 8080), cfg.port);
    try testing.expectEqual(false, cfg.debug);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: ZON file parsing
// ─────────────────────────────────────────────────────────────────────────────

test "ZONからstructを読める" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("config.zon",
        \\.{ .host = "myhost", .port = 9000, .debug = true }
    );

    const path = try tmp.pathJoinAlloc(allocator, "config.zon");
    defer allocator.free(path);

    const cfg = try config.load(BasicConfig, allocator, .{ .file_path = path });
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("myhost", cfg.host);
    try testing.expectEqual(@as(u16, 9000), cfg.port);
    try testing.expectEqual(true, cfg.debug);
}

test "ZON: 部分的なフィールドでデフォルトが補完される" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    // Only set host; port and debug should use defaults
    try tmp.writeFile("partial.zon",
        \\.{ .host = "partial-host" }
    );

    const path = try tmp.pathJoinAlloc(allocator, "partial.zon");
    defer allocator.free(path);

    const cfg = try config.load(BasicConfig, allocator, .{ .file_path = path });
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("partial-host", cfg.host);
    try testing.expectEqual(@as(u16, 8080), cfg.port);
    try testing.expectEqual(false, cfg.debug);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: JSON file parsing
// ─────────────────────────────────────────────────────────────────────────────

test "JSONからstructを読める" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("config.json",
        \\{"host":"jsonhost","port":7777,"debug":true}
    );

    const path = try tmp.pathJoinAlloc(allocator, "config.json");
    defer allocator.free(path);

    const cfg = try config.load(BasicConfig, allocator, .{ .file_path = path });
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("jsonhost", cfg.host);
    try testing.expectEqual(@as(u16, 7777), cfg.port);
    try testing.expectEqual(true, cfg.debug);
}

test "JSON: 部分的なフィールドでデフォルトが補完される" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("partial.json",
        \\{"host":"json-partial"}
    );

    const path = try tmp.pathJoinAlloc(allocator, "partial.json");
    defer allocator.free(path);

    const cfg = try config.load(BasicConfig, allocator, .{ .file_path = path });
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("json-partial", cfg.host);
    try testing.expectEqual(@as(u16, 8080), cfg.port);
    try testing.expectEqual(false, cfg.debug);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: env var overrides
// ─────────────────────────────────────────────────────────────────────────────

// Platform-specific env var manipulation (needed for testing env prefix logic).
// On Windows, std.c.getenv reads from MSVCRT's env cache, so we must use
// _putenv_s (via "c" linkage) to update it — SetEnvironmentVariableA alone is not enough.
const platform_env = switch (builtin.os.tag) {
    .windows => struct {
        extern "c" fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) c_int;
    },
    else => struct {
        extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
        extern "c" fn unsetenv(name: [*:0]const u8) c_int;
    },
};

fn setEnvVar(name: [*:0]const u8, value: [*:0]const u8) void {
    if (comptime builtin.os.tag == .windows) {
        _ = platform_env._putenv_s(name, value);
    } else {
        _ = platform_env.setenv(name, value, 1);
    }
}

fn unsetEnvVar(name: [*:0]const u8) void {
    if (comptime builtin.os.tag == .windows) {
        _ = platform_env._putenv_s(name, "");
    } else {
        _ = platform_env.unsetenv(name);
    }
}

test "envで上書きできる" {
    const allocator = testing.allocator;

    setEnvVar("CFGTEST_HOST", "envhost");
    setEnvVar("CFGTEST_PORT", "1234");
    defer {
        unsetEnvVar("CFGTEST_HOST");
        unsetEnvVar("CFGTEST_PORT");
    }

    const cfg = try config.load(BasicConfig, allocator, .{
        .env_prefix = "CFGTEST_",
    });
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("envhost", cfg.host);
    try testing.expectEqual(@as(u16, 1234), cfg.port);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: overrides (explicit key-value)
// ─────────────────────────────────────────────────────────────────────────────

test "overridesで上書きできる" {
    const allocator = testing.allocator;
    const cfg = try config.load(BasicConfig, allocator, .{
        .overrides = &.{
            .{ .key = "host", .value = "override-host" },
            .{ .key = "port", .value = "5555" },
            .{ .key = "debug", .value = "true" },
        },
    });
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("override-host", cfg.host);
    try testing.expectEqual(@as(u16, 5555), cfg.port);
    try testing.expectEqual(true, cfg.debug);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: priority order: overrides > env > file > default
// ─────────────────────────────────────────────────────────────────────────────

test "優先順位 overrides > env > file > default が守られる" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    // File sets host="file-host" and port=2000
    try tmp.writeFile("prio.zon",
        \\.{ .host = "file-host", .port = 2000, .debug = false }
    );
    const path = try tmp.pathJoinAlloc(allocator, "prio.zon");
    defer allocator.free(path);

    // Env overrides host to "env-host" (and port stays from file)
    setEnvVar("PRIOTEST_HOST", "env-host");
    defer unsetEnvVar("PRIOTEST_HOST");

    // Override overrides host to "override-host" (highest priority)
    const cfg = try config.load(BasicConfig, allocator, .{
        .file_path = path,
        .env_prefix = "PRIOTEST_",
        .overrides = &.{
            .{ .key = "host", .value = "override-host" },
        },
    });
    defer config.free(BasicConfig, allocator, cfg);

    // override wins for host
    try testing.expectEqualStrings("override-host", cfg.host);
    // env didn't touch port; file set it to 2000
    try testing.expectEqual(@as(u16, 2000), cfg.port);
    // default is false, file is false, no env/override for debug
    try testing.expectEqual(false, cfg.debug);
}

test "default < file: fileがdefaultを上書きする" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("over.zon",
        \\.{ .host = "file-wins", .port = 3333, .debug = true }
    );
    const path = try tmp.pathJoinAlloc(allocator, "over.zon");
    defer allocator.free(path);

    const cfg = try config.load(BasicConfig, allocator, .{ .file_path = path });
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("file-wins", cfg.host);
    try testing.expectEqual(@as(u16, 3333), cfg.port);
    try testing.expectEqual(true, cfg.debug);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: required field missing
// ─────────────────────────────────────────────────────────────────────────────

test "必須値不足でエラー" {
    const allocator = testing.allocator;
    // database_url has no default → MissingRequiredField
    const result = config.load(RequiredConfig, allocator, .{});
    try testing.expectError(config.ConfigError.MissingRequiredField, result);
}

test "必須値がoverridesで提供されれば成功" {
    const allocator = testing.allocator;
    const cfg = try config.load(RequiredConfig, allocator, .{
        .overrides = &.{
            .{ .key = "database_url", .value = "postgres://user:pass@db/prod" },
        },
    });
    defer config.free(RequiredConfig, allocator, cfg);

    try testing.expectEqualStrings("postgres://user:pass@db/prod", cfg.database_url);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: invalid values
// ─────────────────────────────────────────────────────────────────────────────

test "不正な型でエラー: 数値フィールドに文字列" {
    const allocator = testing.allocator;
    const result = config.load(BasicConfig, allocator, .{
        .overrides = &.{
            .{ .key = "port", .value = "not-a-number" },
        },
    });
    try testing.expectError(config.ConfigError.InvalidValue, result);
}

test "不正な型でエラー: boolフィールドに不正値" {
    const allocator = testing.allocator;
    const result = config.load(BasicConfig, allocator, .{
        .overrides = &.{
            .{ .key = "debug", .value = "maybe" },
        },
    });
    try testing.expectError(config.ConfigError.InvalidValue, result);
}

test "存在しないファイルでFileNotFoundエラー" {
    const allocator = testing.allocator;
    const result = config.load(BasicConfig, allocator, .{
        .file_path = "/does/not/exist/config.zon",
    });
    try testing.expectError(config.ConfigError.FileNotFound, result);
}

test "不明なフィールドでUnknownFieldエラー" {
    const allocator = testing.allocator;
    const result = config.load(BasicConfig, allocator, .{
        .overrides = &.{
            .{ .key = "nonexistent_field", .value = "value" },
        },
    });
    try testing.expectError(config.ConfigError.UnknownField, result);
}

test "allow_unknown_fields=trueで不明フィールドを無視" {
    const allocator = testing.allocator;
    const cfg = try config.load(BasicConfig, allocator, .{
        .allow_unknown_fields = true,
        .overrides = &.{
            .{ .key = "nonexistent_field", .value = "value" },
        },
    });
    defer config.free(BasicConfig, allocator, cfg);
    // Just verifying no error is returned and defaults are intact
    try testing.expectEqualStrings("127.0.0.1", cfg.host);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: enum fields
// ─────────────────────────────────────────────────────────────────────────────

test "enumが読める: ZON" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("enum.zon",
        \\.{ .level = .warn, .host = "enumhost" }
    );
    const path = try tmp.pathJoinAlloc(allocator, "enum.zon");
    defer allocator.free(path);

    const cfg = try config.load(EnumConfig, allocator, .{ .file_path = path });
    defer config.free(EnumConfig, allocator, cfg);

    try testing.expectEqual(LogLevel.warn, cfg.level);
    try testing.expectEqualStrings("enumhost", cfg.host);
}

test "enumが読める: overrideから文字列でパース" {
    const allocator = testing.allocator;
    const cfg = try config.load(EnumConfig, allocator, .{
        .overrides = &.{
            .{ .key = "level", .value = "debug" },
        },
    });
    defer config.free(EnumConfig, allocator, cfg);

    try testing.expectEqual(LogLevel.debug, cfg.level);
}

test "enumが読める: JSON" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("enum.json",
        \\{"level":"err","host":"json-enum"}
    );
    const path = try tmp.pathJoinAlloc(allocator, "enum.json");
    defer allocator.free(path);

    const cfg = try config.load(EnumConfig, allocator, .{ .file_path = path });
    defer config.free(EnumConfig, allocator, cfg);

    try testing.expectEqual(LogLevel.err, cfg.level);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: optional fields
// ─────────────────────────────────────────────────────────────────────────────

test "optionalが読める: デフォルトはnull" {
    const allocator = testing.allocator;
    const cfg = try config.load(OptionalConfig, allocator, .{});
    defer config.free(OptionalConfig, allocator, cfg);

    try testing.expectEqual(@as(?[]const u8, null), cfg.secret);
    try testing.expectEqual(@as(?u32, null), cfg.timeout);
}

test "optionalが読める: ZONで値を設定" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("opt.zon",
        \\.{ .host = "opthost", .secret = "mysecret", .timeout = 30 }
    );
    const path = try tmp.pathJoinAlloc(allocator, "opt.zon");
    defer allocator.free(path);

    const cfg = try config.load(OptionalConfig, allocator, .{ .file_path = path });
    defer config.free(OptionalConfig, allocator, cfg);

    try testing.expectEqualStrings("mysecret", cfg.secret.?);
    try testing.expectEqual(@as(?u32, 30), cfg.timeout);
}

test "optionalが読める: 空文字列でnullになる（env/override経由）" {
    const allocator = testing.allocator;
    const cfg = try config.load(OptionalConfig, allocator, .{
        .overrides = &.{
            .{ .key = "secret", .value = "" }, // empty → null
            .{ .key = "timeout", .value = "" }, // empty → null
        },
    });
    defer config.free(OptionalConfig, allocator, cfg);

    try testing.expectEqual(@as(?[]const u8, null), cfg.secret);
    try testing.expectEqual(@as(?u32, null), cfg.timeout);
}

test "optionalが読める: overrideで値を設定" {
    const allocator = testing.allocator;
    const cfg = try config.load(OptionalConfig, allocator, .{
        .overrides = &.{
            .{ .key = "secret", .value = "s3cr3t" },
            .{ .key = "timeout", .value = "60" },
        },
    });
    defer config.free(OptionalConfig, allocator, cfg);

    try testing.expectEqualStrings("s3cr3t", cfg.secret.?);
    try testing.expectEqual(@as(?u32, 60), cfg.timeout);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: nested struct
// ─────────────────────────────────────────────────────────────────────────────

test "ネストstructが読める: デフォルト" {
    const allocator = testing.allocator;
    const cfg = try config.load(NestedConfig, allocator, .{});
    defer config.free(NestedConfig, allocator, cfg);

    try testing.expectEqualStrings("localhost", cfg.host);
    try testing.expectEqualStrings("postgres://localhost/db", cfg.db.url);
    try testing.expectEqual(@as(u32, 5), cfg.db.pool_size);
}

test "ネストstructが読める: JSONから" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("nested.json",
        \\{"host":"nested-host","db":{"url":"postgres://prod/mydb","pool_size":20}}
    );
    const path = try tmp.pathJoinAlloc(allocator, "nested.json");
    defer allocator.free(path);

    const cfg = try config.load(NestedConfig, allocator, .{ .file_path = path });
    defer config.free(NestedConfig, allocator, cfg);

    try testing.expectEqualStrings("nested-host", cfg.host);
    try testing.expectEqualStrings("postgres://prod/mydb", cfg.db.url);
    try testing.expectEqual(@as(u32, 20), cfg.db.pool_size);
}

test "ネストstructが読める: ZONから" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    try tmp.writeFile("nested.zon",
        \\.{ .host = "zon-nested", .db = .{ .url = "postgres://zon/db", .pool_size = 10 } }
    );
    const path = try tmp.pathJoinAlloc(allocator, "nested.zon");
    defer allocator.free(path);

    const cfg = try config.load(NestedConfig, allocator, .{ .file_path = path });
    defer config.free(NestedConfig, allocator, cfg);

    try testing.expectEqualStrings("zon-nested", cfg.host);
    try testing.expectEqualStrings("postgres://zon/db", cfg.db.url);
    try testing.expectEqual(@as(u32, 10), cfg.db.pool_size);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: free() releases strings without double-free
// ─────────────────────────────────────────────────────────────────────────────

test "free()で文字列を解放できる" {
    const allocator = testing.allocator;

    // Load and free multiple times to ensure no leaks (testing allocator checks)
    {
        const cfg = try config.load(BasicConfig, allocator, .{
            .overrides = &.{
                .{ .key = "host", .value = "free-test-host" },
            },
        });
        // Free explicitly — testing allocator will catch leaks
        config.free(BasicConfig, allocator, cfg);
    }

    // Test with optional strings
    {
        const cfg = try config.load(OptionalConfig, allocator, .{
            .overrides = &.{
                .{ .key = "secret", .value = "secret-value" },
            },
        });
        config.free(OptionalConfig, allocator, cfg);
    }

    // Test with nested struct
    {
        const cfg = try config.load(NestedConfig, allocator, .{});
        config.free(NestedConfig, allocator, cfg);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: bool parsing variants
// ─────────────────────────────────────────────────────────────────────────────

test "bool: '1'と'0'も解釈できる" {
    const allocator = testing.allocator;
    const cfg1 = try config.load(BasicConfig, allocator, .{
        .overrides = &.{.{ .key = "debug", .value = "1" }},
    });
    defer config.free(BasicConfig, allocator, cfg1);
    try testing.expectEqual(true, cfg1.debug);

    const cfg0 = try config.load(BasicConfig, allocator, .{
        .overrides = &.{.{ .key = "debug", .value = "0" }},
    });
    defer config.free(BasicConfig, allocator, cfg0);
    try testing.expectEqual(false, cfg0.debug);
}

// ─────────────────────────────────────────────────────────────────────────────
// Test: format detection
// ─────────────────────────────────────────────────────────────────────────────

test "拡張子なしのファイルはUnsupportedFormatエラー" {
    const allocator = testing.allocator;
    const result = config.load(BasicConfig, allocator, .{
        .file_path = "/tmp/noext",
    });
    try testing.expectError(config.ConfigError.UnsupportedFormat, result);
}

test "file_format=.jsonで.zonファイルも明示的に読める" {
    const allocator = testing.allocator;
    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit();

    // Write JSON content but name it with no standard extension
    try tmp.writeFile("config.dat",
        \\{"host":"format-override","port":4242}
    );
    const path = try tmp.pathJoinAlloc(allocator, "config.dat");
    defer allocator.free(path);

    const cfg = try config.load(BasicConfig, allocator, .{
        .file_path = path,
        .file_format = .json,
    });
    defer config.free(BasicConfig, allocator, cfg);

    try testing.expectEqualStrings("format-override", cfg.host);
    try testing.expectEqual(@as(u16, 4242), cfg.port);
}
