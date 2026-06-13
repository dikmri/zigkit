# zigkit 使い方ガイド

Zig 初心者〜中級者向けに、各モジュールの使い方・オススメ用途・注意点をまとめたガイドです。

---

## 目次

- [zigkit-cli — CLIパーサ](#zigkit-cli--cliパーサ)
- [zigkit-config — 設定ローダー](#zigkit-config--設定ローダー)
- [zigkit-log — 構造化ロガー](#zigkit-log--構造化ロガー)
- [zigkit-test — テストヘルパー](#zigkit-test--テストヘルパー)

---

## zigkit-cli — CLIパーサ

### 何をするモジュール？

コマンドラインで受け取る引数（`--name Alice` や `-v` など）を安全にパースするモジュールです。  
ヘルプ文（`--help`）やバージョン表示（`--version`）も自動生成されます。

### 基本的な使い方

#### 1. CommandSpec を定義する

まずツールの仕様を `CommandSpec` で宣言します。

```zig
const std = @import("std");
const zk = @import("zigkit");

const spec = zk.cli.CommandSpec{
    .name = "mytool",
    .version = "1.0.0",
    .about = "画像を変換するツール",
    .options = &.{
        .{
            .long = "input",
            .short = 'i',
            .value_name = "FILE",
            .kind = .path,
            .required = true,
            .help = "入力ファイルのパス",
        },
        .{
            .long = "output",
            .short = 'o',
            .value_name = "FILE",
            .kind = .path,
            .help = "出力ファイルのパス",
        },
        .{
            .long = "quality",
            .short = 'q',
            .value_name = "N",
            .kind = .int,
            .default = "80",
            .help = "品質 (1-100)",
        },
        .{
            .long = "verbose",
            .short = 'v',
            .kind = .bool,
            .help = "詳細ログを出力",
        },
    },
};
```

#### 2. main 関数で引数をパースする

```zig
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // argv[0]（プログラム名）を除いた引数を取得
    const all_args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(all_args);
    const args = if (all_args.len > 1) all_args[1..] else &.{};

    // パース（--help / --version のハンドリングも忘れずに）
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
    defer result.deinit(); // 必ず呼ぶ！

    // 値の取り出し
    const input   = result.getString("input").?;   // required なので必ずある
    const output  = result.getString("output") orelse "out.png";
    const quality = result.getInt("quality") orelse 80;
    const verbose = result.getBool("verbose") orelse false;

    std.debug.print("変換: {s} -> {s} (品質={d}, verbose={any})\n",
        .{ input, output, quality, verbose });
}
```

#### 3. 実行例

```sh
# 通常の実行
./mytool -i photo.jpg -o result.png --quality 90

# ヘルプ表示
./mytool --help

# バージョン表示
./mytool --version
```

### 値の種類（ValueKind）

| kind | 説明 | 取り出し方 |
|---|---|---|
| `.string` | 文字列（デフォルト） | `getString()` |
| `.path` | ファイルパス（文字列と同じ） | `getString()` |
| `.int` | 整数（i64） | `getInt()` |
| `.float` | 浮動小数点（f64） | `getFloat()` |
| `.bool` | フラグ（値なし） | `getBool()` |

### ポジショナル引数（位置引数）

オプション名なしで渡す引数（例: `mytool input.txt`）は `positionals` で定義します。

```zig
const spec = zk.cli.CommandSpec{
    .name = "cat",
    .positionals = &.{
        .{ .name = "file", .required = true, .help = "読み込むファイル" },
    },
};

// 取り出し方
const file = result.positional(0).?;
```

### サブコマンド

`git commit` や `docker run` のようなサブコマンド構造を作れます。

```zig
const spec = zk.cli.CommandSpec{
    .name = "tool",
    .subcommands = &.{
        .{
            .name = "build",
            .about = "ビルドする",
            .options = &.{
                .{ .long = "release", .kind = .bool, .help = "リリースビルド" },
            },
        },
        .{ .name = "clean", .about = "クリーンアップ" },
    },
};

// 選択されたサブコマンドは:
const subcmd = result.selected_subcommand orelse "（未指定）";
```

### オススメ用途

- バッチ処理ツール（`./process --input data.csv --workers 4`）
- 開発用 CLI ツール（git のサブコマンド風）
- スクリプトの代替（シェルスクリプトより型安全に引数を扱いたい場合）

### 注意点

- **`result.deinit()` を必ず呼ぶ**: パース結果はヒープメモリを確保します。`defer result.deinit()` を書き忘れるとメモリリークします
- **`--help` / `--version` は必ず catch する**: これらは `error.HelpRequested` / `error.VersionRequested` を返すので、`catch` しないとプログラムがエラー終了します
- **`all_args[1..]` で argv[0] を除く**: `toSlice()` はプログラム名も含む全引数を返します。`parse()` に渡す前に最初の要素（プログラム名）を除いてください
- **`default` は文字列で指定する**: `.default = "80"` のように文字列で書きます（数値のように見えても文字列）

---

## zigkit-config — 設定ローダー

### 何をするモジュール？

設定ファイル（ZON・JSON）、環境変数、プログラム内オーバーライドを統合して、型付きの設定 struct に読み込むモジュールです。

優先順位は固定で `オーバーライド > 環境変数 > ファイル > struct のデフォルト` です。

### 基本的な使い方

#### 1. 設定 struct を定義する

```zig
const AppConfig = struct {
    // デフォルト値があるフィールド = 省略可能
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    debug: bool = false,
    log_level: []const u8 = "info",

    // デフォルト値がないフィールド = 必須（どこかで指定しないとエラー）
    database_url: []const u8,
};
```

#### 2. 設定ファイルを用意する（ZON形式）

`app.zon`:

```zig
.{
    .host = "0.0.0.0",
    .port = 3000,
    .database_url = "postgres://localhost/myapp",
}
```

#### 3. ロードする

```zig
const cfg = try zk.config.load(AppConfig, allocator, .{
    .file_path = "app.zon",
    .env_prefix = "APP_",
});
defer zk.config.free(AppConfig, allocator, cfg); // 必ず呼ぶ！

std.debug.print("接続先: {s}:{d}\n", .{ cfg.host, cfg.port });
```

#### 4. 環境変数で上書きする

`env_prefix = "APP_"` の場合、フィールド名を大文字スネークケースに変換した環境変数が使えます。

```sh
APP_DATABASE_URL=postgres://prod/myapp APP_PORT=443 ./myapp
```

| フィールド | 環境変数 |
|---|---|
| `database_url` | `APP_DATABASE_URL` |
| `port` | `APP_PORT` |
| `debug` | `APP_DEBUG` |

### JSON形式での設定ファイル

拡張子が `.json` なら自動的にJSON形式として読み込みます。

`app.json`:

```json
{
  "host": "0.0.0.0",
  "port": 3000,
  "database_url": "postgres://localhost/myapp"
}
```

### 明示的なオーバーライド（CLI引数との連携）

CLIで受け取った値を最優先で適用したい場合は `overrides` を使います。

```zig
// CLI で --port 9090 が渡された場合
const cli_port = result.getString("port");

const cfg = try zk.config.load(AppConfig, allocator, .{
    .file_path = "app.zon",
    .env_prefix = "APP_",
    .overrides = if (cli_port) |p| &.{
        .{ .key = "port", .value = p },
    } else &.{},
});
```

### Optional フィールド

値がない場合があるフィールドは `?T` で宣言します。

```zig
const Config = struct {
    redis_url: ?[]const u8 = null,  // 設定なしの場合は null
};

if (cfg.redis_url) |url| {
    // Redis が設定されている場合のみ接続
    _ = url;
}
```

### ネストした struct

```zig
const DatabaseConfig = struct {
    url: []const u8,
    pool_size: u16 = 5,
};

const AppConfig = struct {
    host: []const u8 = "localhost",
    database: DatabaseConfig,
};
```

ZON での記述:

```zig
.{
    .host = "0.0.0.0",
    .database = .{
        .url = "postgres://localhost/myapp",
        .pool_size = 10,
    },
}
```

### オススメ用途

- サーバーアプリの起動設定（ポート、DB接続文字列など）
- 開発・本番・テストの環境切り替え（環境変数で切り替え）
- CI/CD でのシークレット注入（環境変数経由でAPIキーを渡す）

### 注意点

- **`config.free()` を必ず呼ぶ**: `[]const u8` フィールドはすべてヒープにコピーされています。`defer zk.config.free(AppConfig, allocator, cfg)` を忘れるとメモリリークします
- **デフォルト値なし = 必須フィールド**: `database_url: []const u8` のようにデフォルト値がないフィールドは、ファイル・環境変数・オーバーライドのいずれかで必ず指定しないと `MissingRequiredField` エラーになります
- **環境変数はネストした struct の内部フィールドには対応していない**: `database.url` のようなネストしたフィールドは環境変数から設定できません。その場合はファイルかオーバーライドを使ってください
- **bool の環境変数は `"true"` か `"1"`**: シェルで `APP_DEBUG=true` または `APP_DEBUG=1` と書きます

---

## zigkit-log — 構造化ロガー

### 何をするモジュール？

ログを `text` 形式または `json` 形式で出力するロガーです。  
ログレベルによるフィルタリングと、任意のキー・バリューフィールドの付与ができます。

### 基本的な使い方

#### 1. ロガーを作る

ロガーは「どこに書くか（Writer）」と「どう書くか（オプション）」を受け取ります。

```zig
const std = @import("std");
const zk = @import("zigkit");

// stderr に JSON 形式で書き出す
var io = std.Io.Threaded.global_single_threaded.io();
var stderr_writer = std.Io.File.stderr.writer(io);

var logger = zk.log.Logger.init(&stderr_writer, .{
    .format = .json,
    .level = .info,
    .timestamp = true,
});
```

#### 2. ログを出力する

```zig
// シンプルなメッセージ
try logger.info("サーバー起動", .{});

// キー・バリューフィールド付き
try logger.info("リクエスト受信", .{
    .method = "GET",
    .path = "/api/users",
    .status = @as(u16, 200),
    .duration_ms = @as(f64, 3.14),
});

// エラーログ
try logger.err("DB接続失敗", .{
    .host = "localhost",
    .port = @as(u16, 5432),
});
```

#### 3. 出力結果

text 形式:
```
INFO サーバー起動
INFO リクエスト受信 method=GET path=/api/users status=200 duration_ms=3.14
ERROR DB接続失敗 host=localhost port=5432
```

json 形式（`timestamp = false` の場合）:
```json
{"level":"info","message":"サーバー起動"}
{"level":"info","message":"リクエスト受信","method":"GET","path":"/api/users","status":200,"duration_ms":3.14}
{"level":"err","message":"DB接続失敗","host":"localhost","port":5432}
```

### ログレベル

| レベル | 用途 |
|---|---|
| `trace` | 最も詳細なデバッグ情報（ほぼ使わない） |
| `debug` | デバッグ時のみ出力したい情報 |
| `info` | 通常の動作ログ（デフォルト） |
| `warn` | 注意が必要だが継続できる状態 |
| `err` | エラーが発生した（処理は続けられる可能性あり） |
| `fatal` | 致命的なエラー（プログラムを終了させる前に出力） |

`options.level` より低いレベルのログは出力されません。

```zig
// info 以上のみ出力（debug / trace は無視）
var logger = zk.log.Logger.init(&writer, .{ .level = .info });

try logger.debug("これは出力されない");
try logger.info("これは出力される");
```

### タイムスタンプ

`timestamp = true`（デフォルト）の場合、Unix ミリ秒が付きます。

```json
{"time_unix_ms":1781421296000,"level":"info","message":"started"}
```

> **Note**: v0.1.0 では ISO 8601 形式ではなく Unix ミリ秒を使用しています。将来のバージョンで変更予定です。

### テスト用バッファへの書き込み

テストでログ出力内容を検証したい場合は `std.Io.Writer.Allocating` を使います。

```zig
test "ログ出力を検証" {
    const allocator = std.testing.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer allocator.free(aw.writer.buffer);

    var logger = zk.log.Logger.init(&aw.writer, .{
        .format = .json,
        .timestamp = false,
    });

    try logger.info("test", .{ .key = "value" });

    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"key\":\"value\"") != null);
}
```

### フィールドの対応型

| Zig の型 | JSON 出力 | text 出力 |
|---|---|---|
| `bool` | `true` / `false` | `true` / `false` |
| `u8`〜`u64`, `i8`〜`i64` | `42` | `42` |
| `f32`, `f64` | `3.14` | `3.14` |
| `[]const u8` | `"hello"` | `hello` |
| `enum` | `"tag_name"` | `tag_name` |
| `?T`（null） | `null` | `null` |
| `?T`（値あり） | Tと同じ | Tと同じ |

### オススメ用途

- サーバーアプリのアクセスログ（JSON形式 + 外部ログ収集ツールと連携）
- バッチ処理の進捗ログ（text形式 + タイムスタンプで処理時間を確認）
- CLIツールの詳細ログ（`--verbose` フラグ時のみ debug レベルを出力）

### 注意点

- **Writer の寿命に注意**: `Logger` は `*std.Io.Writer` へのポインタを保持します。ロガーより先に Writer が解放されると未定義動作になります
- **非同期・並列書き込みには対応していない**: 複数スレッドから同じロガーに書き込む場合は外部でロックが必要です（v0.1.0 の制限）
- **コンパイル時型チェック**: 対応していない型（例: `[]u32`）を fields に渡すとコンパイルエラーになります。`@compileError` が出たら型を確認してください

---

## zigkit-test — テストヘルパー

### 何をするモジュール？

Zig 標準の `std.testing` を補完するテストユーティリティ集です。  
文字列の部分一致チェック、JSON の意味的比較、一時ディレクトリの管理、スナップショットテストができます。

### 基本的な使い方

テストファイルの先頭でインポートします。

```zig
const std = @import("std");
const testing = std.testing;
const zkt = @import("zigkit").testing;
```

### 文字列アサーション

```zig
test "文字列チェック" {
    // 部分一致
    try zkt.expectContains("hello, world", "world");

    // 前方一致
    try zkt.expectStartsWith("hello, world", "hello");

    // 後方一致
    try zkt.expectEndsWith("hello, world", "world");

    // 完全一致（失敗時に分かりやすいメッセージ）
    try zkt.expectEqualStringPretty("expected", "expected");
}
```

### JSON の比較（キー順序を無視）

API レスポンスなど、キーの順序が変わりうる JSON の比較に使います。

```zig
test "JSONの意味的等価" {
    try zkt.expectJsonEqual(testing.allocator,
        \\{"b":2,"a":1}
    ,
        \\{"a":1,"b":2}
    );
    // → キー順序が違っても等価とみなす ✓
}
```

### TempDir — 一時ディレクトリ

ファイル操作を伴うテストで使います。`deinit()` 時に自動でディレクトリごと削除されます。

```zig
test "設定ファイルの読み書き" {
    const allocator = testing.allocator;

    var tmp = try zkt.TempDir.init(allocator);
    defer tmp.deinit(); // テスト終了時に自動削除

    // ファイルを作る
    try tmp.writeFile("config.zon",
        \\.{ .port = 3000 }
    );

    // フルパスを取得（他の関数に渡すとき）
    const path = try tmp.pathJoinAlloc(allocator, "config.zon");
    defer allocator.free(path);

    // ファイルを読む
    const content = try tmp.readFile("config.zon", allocator);
    defer allocator.free(content);

    try zkt.expectContains(content, "3000");
}
```

### スナップショットテスト

出力の内容が「前回と同じ」ことを検証するテストです。  
最初の実行では自動でスナップショットが作られ、2回目以降はそれと比較します。

```zig
test "ヘルプ文のスナップショット" {
    const allocator = testing.allocator;

    const help = try zk.cli.renderHelpAlloc(allocator, my_spec);
    defer allocator.free(help);

    // 初回: ZIGKIT_UPDATE_SNAPSHOTS=1 で実行してスナップショットを作成
    // 以降: 差分があればテスト失敗
    try zkt.expectSnapshot(allocator, "my-tool-help", help);
}
```

**スナップショットの更新方法:**

```sh
# スナップショットファイルを新規作成 / 更新
ZIGKIT_UPDATE_SNAPSHOTS=1 zig build test

# 通常テスト（スナップショットと比較）
zig build test
```

スナップショットは `tests/snapshots/` に `.snap` ファイルとして保存されます。git で管理することで「意図した変更かどうか」のレビューができます。

### fixture ファイルの読み込み

`tests/fixtures/` にテスト用データを置いて読み込む場合に使います。

```zig
test "サンプルデータのパース" {
    const allocator = testing.allocator;

    // プロジェクトルートからの相対パス
    const data = try zkt.fixtureAlloc(allocator, "tests/fixtures/sample.json");
    defer allocator.free(data);

    // data を使ったテスト...
}
```

### オススメ用途

| ヘルパー | オススメ用途 |
|---|---|
| `expectContains` | ログ出力・HTML・設定値が特定の文字列を含むか確認 |
| `expectJsonEqual` | API レスポンスの JSON 比較（キー順序を無視したい場合） |
| `TempDir` | ファイル読み書きを伴う関数のテスト |
| `expectSnapshot` | CLI のヘルプ文・コード生成結果など「形が変わったら検知したい」出力 |
| `fixtureAlloc` | 大きなテストデータをファイルに切り出す |

### 注意点

- **`TempDir.deinit()` の後は path が無効**: `deinit()` を呼ぶとディレクトリが削除されるので、その後に path を使わないように注意してください
- **`readFile` の戻り値は allocator で確保**: `defer allocator.free(content)` を忘れずに
- **スナップショットはテスト環境によって変わりうる**: パスの区切り文字（`/` vs `\`）やタイムスタンプが混入するとプラットフォームごとに差異が出ます。スナップショットに含めるデータは決定的な値だけにしましょう
- **`fixtureAlloc` のパスはプロジェクトルート基準**: `zig build test` を実行したディレクトリ（通常はプロジェクトルート）からの相対パスです

---

## よくある質問

### Q. メモリリークを検出するには？

`std.testing.allocator` を使うとテスト終了時に自動でリーク検出が行われます。

```zig
test "リークがないことを確認" {
    const allocator = std.testing.allocator; // これを使う

    const result = try zk.cli.parse(allocator, spec, args);
    defer result.deinit(); // ← これを忘れるとテストがリーク検出エラーで失敗する
}
```

### Q. エラーの詳細を知りたい

`parse()` の代わりに `parseDetailed()` を使うと詳細なエラー情報が得られます。

```zig
const detail = zk.cli.parseDetailed(allocator, spec, args);
switch (detail) {
    .ok => |*r| {
        defer r.deinit();
        // 正常処理
    },
    .err => |*e| {
        defer e.deinit(allocator);
        std.debug.print("エラー: {s}\n", .{e.message});
        if (e.hint) |hint| std.debug.print("ヒント: {s}\n", .{hint});
    },
}
```

### Q. `[]const u8` はどこで解放すればいい？

zigkit の各 API で取得した文字列の解放方法をまとめます。

| API | 解放方法 |
|---|---|
| `cli.parse()` の結果 | `result.deinit()` |
| `cli.renderHelpAlloc()` | `allocator.free(help)` |
| `config.load()` の結果 | `config.free(T, allocator, cfg)` |
| `testing.TempDir.readFile()` | `allocator.free(content)` |
| `testing.fixtureAlloc()` | `allocator.free(data)` |
| `log.Logger` | 解放不要（Writerを外部で管理） |
