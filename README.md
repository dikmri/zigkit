# zigkit

A lightweight toolkit for Zig 0.16.x. Practical building blocks for CLI tools, batch processors, and API clients.

[![CI](https://github.com/dikmri/zigkit/actions/workflows/ci.yml/badge.svg)](https://github.com/dikmri/zigkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **README in other languages:** [日本語](README.ja.md) | [中文](README.zh.md) | [한국어](README.ko.md)

## Features

- **zigkit-cli** — Safe CLI argument parsing with subcommands, help, and version generation
- **zigkit-config** — Load typed config from ZON/JSON files + environment variables + overrides
- **zigkit-log** — Structured logging in text or JSON format
- **zigkit-test** — Test helpers that complement `std.testing`

## Requirements

- Zig `0.16.x`
- Linux x86_64
- macOS x86_64 / aarch64
- Windows x86_64

## Installation

### Fetch with zig

```sh
zig fetch --save git+https://github.com/dikmri/zigkit#v0.1.0
```

### Add to build.zig

```zig
const zigkit = b.dependency("zigkit", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zigkit", zigkit.module("zigkit"));
```

## Quick Start

### CLI

```zig
const std = @import("std");
const zk = @import("zigkit");

pub fn main(init: std.process.Init) !void {
    const spec = zk.cli.CommandSpec{
        .name = "mytool",
        .version = "1.0.0",
        .about = "my CLI tool",
        .options = &.{
            .{ .long = "name", .short = 'n', .kind = .string, .required = true, .help = "your name" },
            .{ .long = "verbose", .short = 'v', .kind = .bool, .help = "verbose output" },
        },
    };

    const all_args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(all_args);
    const args = if (all_args.len > 1) all_args[1..] else &.{};

    var result = zk.cli.parse(init.gpa, spec, args) catch |err| switch (err) {
        error.HelpRequested => {
            const help = try zk.cli.renderHelpAlloc(init.gpa, spec);
            defer init.gpa.free(help);
            std.debug.print("{s}", .{help});
            return;
        },
        else => return err,
    };
    defer result.deinit();

    std.debug.print("Hello, {s}!\n", .{result.getString("name").?});
}
```

### Config

```zig
const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    debug: bool = false,
    database_url: []const u8,
};

const cfg = try zk.config.load(AppConfig, allocator, .{
    .file_path = "app.zon",
    .env_prefix = "APP_",
});
defer zk.config.free(AppConfig, allocator, cfg);
```

Config file (`app.zon`):

```zig
.{
    .host = "0.0.0.0",
    .port = 3000,
    .debug = true,
    .database_url = "postgres://localhost/myapp",
}
```

Environment variables work too:

```sh
APP_DATABASE_URL=postgres://prod/myapp APP_DEBUG=false ./myapp
```

Priority: **overrides > env > file > struct default**

### Logger

```zig
var logger = zk.log.Logger.init(&writer, .{
    .format = .json,
    .level = .info,
    .timestamp = false,
});

try logger.info("server started", .{ .host = "127.0.0.1", .port = 8080 });
// => {"level":"info","message":"server started","host":"127.0.0.1","port":8080}
```

When `timestamp = true`, Unix milliseconds are used:

```json
{"time_unix_ms":1781421296000,"level":"info","message":"started"}
```

### Test helpers

```zig
const zkt = @import("zigkit").testing;

test "example" {
    try zkt.expectContains("hello world", "world");
    try zkt.expectStartsWith("hello world", "hello");

    var tmp = try zkt.TempDir.init(testing.allocator);
    defer tmp.deinit();
    try tmp.writeFile("data.txt", "test content");
}
```

## Modules

| Module | Description | Docs |
|---|---|---|
| `zigkit.cli` | CLI argument parser | [docs/cli.md](docs/cli.md) |
| `zigkit.config` | Config loader | [docs/config.md](docs/config.md) |
| `zigkit.log` | Structured logger | [docs/log.md](docs/log.md) |
| `zigkit.testing` | Test helpers | [docs/test.md](docs/test.md) |

## Build

```sh
zig build test       # run tests
zig build examples   # build examples
zig build docs       # generate docs
```

## License

MIT License — see [LICENSE](LICENSE) for details.

## Roadmap

- **v0.1.0** — cli / config / log / test (current)
- **v0.2.0** — HTTP client
- **v0.3.0** — SQLite wrapper

See [docs/roadmap.md](docs/roadmap.md) for details.
