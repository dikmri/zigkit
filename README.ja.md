# zigkit

Zig 0.16.x 向け軽量ツールキット。CLIツール・バッチ処理・APIクライアントを作るための実用部品集。

[![CI](https://github.com/dikmri/zigkit/actions/workflows/ci.yml/badge.svg)](https://github.com/dikmri/zigkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 特徴

- **zigkit-cli** — CLIの引数を安全にパース。サブコマンド・help・version生成対応
- **zigkit-config** — ZON/JSON設定ファイル＋環境変数＋オーバーライドを統合して型付き設定を読み込む
- **zigkit-log** — text/json形式の構造化ログ
- **zigkit-test** — `std.testing` を補完するテストヘルパー

## 動作環境

- Zig `0.16.x`
- Linux x86_64
- macOS x86_64 / aarch64
- Windows x86_64

## インストール

### zig fetch でインストール

```sh
zig fetch --save git+https://github.com/dikmri/zigkit#v0.1.0
```

### build.zig に追記

```zig
const zigkit = b.dependency("zigkit", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zigkit", zigkit.module("zigkit"));
```

## クイックスタート

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

設定ファイル例 (`app.zon`):

```zig
.{
    .host = "0.0.0.0",
    .port = 3000,
    .debug = true,
    .database_url = "postgres://localhost/myapp",
}
```

環境変数も使えます:

```sh
APP_DATABASE_URL=postgres://prod/myapp APP_DEBUG=false ./myapp
```

優先順位: **オーバーライド > 環境変数 > ファイル > struct デフォルト**

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

タイムスタンプあり (`timestamp = true`) の場合は Unix ミリ秒を使用します:

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

## モジュール一覧

| モジュール | 説明 | ドキュメント |
|---|---|---|
| `zigkit.cli` | CLIパーサ | [docs/cli.md](docs/cli.md) |
| `zigkit.config` | 設定ローダー | [docs/config.md](docs/config.md) |
| `zigkit.log` | 構造化ロガー | [docs/log.md](docs/log.md) |
| `zigkit.testing` | テストヘルパー | [docs/test.md](docs/test.md) |

## ビルド

```sh
zig build test       # テスト実行
zig build examples   # examplesビルド
zig build docs       # ドキュメント生成
```

## ライセンス

MIT License — 詳しくは [LICENSE](LICENSE) を参照。

## ロードマップ

- **v0.1.0** — cli / config / log / test （現在）
- **v0.2.0** — http クライアント
- **v0.3.0** — sqlite ラッパー

詳しくは [docs/roadmap.md](docs/roadmap.md) を参照。
