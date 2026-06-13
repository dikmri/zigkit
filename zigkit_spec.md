# zigkit 実装仕様書

## 0. この仕様書の目的

この仕様書は、Zig 0.16.x 対応のOSSライブラリ `zigkit` を、CodexなどのAI実装エージェントにそのまま渡して、初期リリース `v0.1.0` まで実装できるようにするための実装指示書です。

`zigkit` は、ZigでCLIツール、バッチ処理、APIクライアント、小型実用アプリを作るための軽量ツールキットです。

最初から巨大なWebフレームワークやORMを作らず、まずはZigで実用アプリを作る時に毎回必要になる基礎部品を整備します。

---

## 1. 前提・対象バージョン

### 1.1 対象Zigバージョン

- Zig: `0.16.x`
- 初期開発・CIでは `0.16.0` を基準にする
- `main` ブランチは最新安定版Zigのみをサポートする
- 古いZigバージョンの長期サポートは行わない

### 1.2 ライセンス

- MIT License

### 1.3 対象プラットフォーム

最低限以下で `zig build test` が通ること。

- Linux x86_64
- macOS x86_64 / aarch64
- Windows x86_64

---

## 2. プロジェクト概要

### 2.1 コンセプト

`zigkit` は、以下を実現するための小さな標準部品集です。

- CLI引数を安全にパースする
- 設定ファイルと環境変数から型付き設定を読み込む
- text/json形式の構造化ログを出す
- Zig標準テストを補助する
- 将来的にHTTPクライアントやSQLiteラッパーを追加する

### 2.2 設計思想

Zig本体の思想に合わせ、以下を徹底します。

- 隠れたメモリアロケーションを避ける
- メモリ確保が必要なAPIは `std.mem.Allocator` を明示的に受け取る
- グローバル状態を避ける
- 所有権をAPI名・README・コメントで明確にする
- `init/deinit` または `alloc/free` の対を用意する
- APIは小さく保つ
- 魔法のような自動探索・自動設定を避ける
- エラーメッセージを人間が読めるようにする
- examplesを重視する
- AIが実装・修正しやすい単純な構造にする

### 2.3 v0.1.0 の対象モジュール

`v0.1.0` では以下4モジュールのみ実装します。

- `zigkit-cli`
- `zigkit-config`
- `zigkit-log`
- `zigkit-test`

以下は `v0.2.0` 以降の予定として、ファイルだけプレースホルダを用意してもよいですが、`v0.1.0` では実装必須ではありません。

- `zigkit-http`
- `zigkit-sqlite`

---

## 3. 成果物

### 3.1 必須ファイル構成

```text
zigkit/
  build.zig
  build.zig.zon
  README.md
  LICENSE
  .gitignore
  .github/
    workflows/
      ci.yml
  docs/
    design.md
    cli.md
    config.md
    log.md
    test.md
    roadmap.md
  examples/
    hello-cli/
      build.zig
      src/main.zig
    config-app/
      build.zig
      app.zon
      src/main.zig
    json-log/
      build.zig
      src/main.zig
  src/
    zigkit.zig
    cli.zig
    config.zig
    log.zig
    test.zig
    internal/
      string.zig
      ansi.zig
      fs.zig
      json.zig
  tests/
    cli_test.zig
    config_test.zig
    log_test.zig
    test_test.zig
    snapshots/
      .gitkeep
```

### 3.2 任意ファイル

```text
  src/http.zig
  src/sqlite.zig
  docs/http.md
  docs/sqlite.md
```

これらはv0.2以降のための空プレースホルダでもよいです。

---

## 4. build.zig 仕様

### 4.1 必須ビルドステップ

以下のコマンドが動くこと。

```bash
zig build test
zig build examples
zig build docs
```

`zig build fmt` も可能なら用意します。ただし、Zig標準の `zig fmt --check` が使えるならCI側で直接実行してもよいです。

### 4.2 build.zig 要件

- `src/zigkit.zig` を root source とする `zigkit` module を公開する
- `zig build test` で `tests/*_test.zig` または `src/zigkit.zig` 配下のtestを実行する
- examplesをビルドするステップを持つ
- docs生成ステップを持つ
- target / optimize は標準オプションを使う

### 4.3 build.zig の実装方針

`build.zig` はZig 0.16.xのAPIに合わせて実装してください。以下は概念例です。実際のAPI差異がある場合はZig 0.16.0でコンパイルが通る形に修正してください。

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigkit_mod = b.addModule("zigkit", .{
        .root_source_file = b.path("src/zigkit.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_source_file = b.path("src/zigkit.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("zigkit", zigkit_mod);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run zigkit tests");
    test_step.dependOn(&run_tests.step);

    const examples_step = b.step("examples", "Build examples");
    _ = examples_step;

    const docs_step = b.step("docs", "Generate docs");
    _ = docs_step;
}
```

---

## 5. build.zig.zon 仕様

### 5.1 必須項目

`build.zig.zon` は以下のような内容にしてください。

```zig
.{
    .name = .zigkit,
    .version = "0.1.0",
    .minimum_zig_version = "0.16.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "README.md",
        "LICENSE",
    },
}
```

Zig 0.16.0でフィールド名や形式が変わっている場合は、コンパイルが通る形式に合わせてください。

---

## 6. ルートモジュール `src/zigkit.zig`

### 6.1 目的

`zigkit.zig` は各モジュールを再exportするだけの薄い入口です。

### 6.2 実装

```zig
pub const cli = @import("cli.zig");
pub const config = @import("config.zig");
pub const log = @import("log.zig");
pub const testing = @import("test.zig");
```

将来のPhase 2で以下を追加します。

```zig
pub const http = @import("http.zig");
pub const sqlite = @import("sqlite.zig");
```

---

# 7. zigkit-cli 仕様

## 7.1 目的

`zigkit-cli` は、ZigでCLIツールを作るための軽量引数パーサです。

目標は以下です。

- Go標準 `flag` より便利
- Rust `clap` より薄い
- サブコマンド対応
- help/version生成対応
- エラーメッセージが人間に読める

## 7.2 対応機能

### 必須

- long option
  - `--name value`
  - `--name=value`
- short option
  - `-n value`
- bool flag
  - `--verbose`
  - `-v`
- required option
- default value
- positional argument
- repeated option
- subcommand
- help生成
  - `--help`
  - `-h`
- version表示
  - `--version`
  - `-V`
- unknown option検出
- missing value検出
- 型変換
  - bool
  - string
  - int
  - float
  - path treated as string

### 後回し

- shell completion生成
- git-style alias
- 対話式プロンプト
- env連携
- 複雑なバリデーションDSL

## 7.3 公開型

```zig
const std = @import("std");

pub const ValueKind = enum {
    bool,
    string,
    int,
    float,
    path,
};

pub const OptionSpec = struct {
    long: []const u8,
    short: ?u8 = null,
    value_name: ?[]const u8 = null,
    kind: ValueKind = .string,
    required: bool = false,
    multiple: bool = false,
    default: ?[]const u8 = null,
    help: []const u8 = "",
};

pub const PositionalSpec = struct {
    name: []const u8,
    required: bool = true,
    multiple: bool = false,
    help: []const u8 = "",
};

pub const CommandSpec = struct {
    name: []const u8,
    version: ?[]const u8 = null,
    about: []const u8 = "",
    options: []const OptionSpec = &.{},
    positionals: []const PositionalSpec = &.{},
    subcommands: []const CommandSpec = &.{},
};

pub const Value = union(ValueKind) {
    bool: bool,
    string: []const u8,
    int: i64,
    float: f64,
    path: []const u8,
};

pub const ParseResult = struct {
    allocator: std.mem.Allocator,
    command: []const u8,
    selected_subcommand: ?[]const u8 = null,

    pub fn deinit(self: *ParseResult) void;
    pub fn getBool(self: *const ParseResult, name: []const u8) ?bool;
    pub fn getString(self: *const ParseResult, name: []const u8) ?[]const u8;
    pub fn getInt(self: *const ParseResult, name: []const u8) ?i64;
    pub fn getFloat(self: *const ParseResult, name: []const u8) ?f64;
    pub fn getStrings(self: *const ParseResult, name: []const u8) []const []const u8;
    pub fn positional(self: *const ParseResult, index: usize) ?[]const u8;
};
```

内部表現は自由ですが、`ParseResult` は所有するメモリを `deinit()` で解放できること。

## 7.4 エラー仕様

```zig
pub const CliError = error{
    UnknownOption,
    MissingOptionValue,
    MissingRequiredOption,
    InvalidOptionValue,
    UnexpectedArgument,
    UnknownCommand,
    DuplicateOption,
    HelpRequested,
    VersionRequested,
    OutOfMemory,
};
```

ただし、エラー表示のために以下の詳細構造体も用意してください。

```zig
pub const ErrorReport = struct {
    kind: anyerror,
    message: []const u8,
    hint: ?[]const u8 = null,
    option: ?[]const u8 = null,
    command: ?[]const u8 = null,

    pub fn deinit(self: *ErrorReport, allocator: std.mem.Allocator) void;
};
```

簡易APIとして `parse()` が `!ParseResult` を返し、詳細エラーが必要な場合のAPIとして `parseDetailed()` を用意してください。

```zig
pub fn parse(
    allocator: std.mem.Allocator,
    spec: CommandSpec,
    args: []const []const u8,
) !ParseResult;

pub fn parseDetailed(
    allocator: std.mem.Allocator,
    spec: CommandSpec,
    args: []const []const u8,
) ParseDetailedResult;

pub const ParseDetailedResult = union(enum) {
    ok: ParseResult,
    err: ErrorReport,
};
```

## 7.5 help生成

```zig
pub fn renderHelpAlloc(
    allocator: std.mem.Allocator,
    spec: CommandSpec,
) ![]u8;

pub fn renderVersionAlloc(
    allocator: std.mem.Allocator,
    spec: CommandSpec,
) ![]u8;
```

### help出力例

```text
imgtool 0.1.0
small image utility

USAGE:
  imgtool [OPTIONS] <input>

ARGS:
  <input>    input file path

OPTIONS:
  -o, --output <PATH>    output file path
  -v, --verbose          enable verbose logging
  -h, --help             show help
  -V, --version          show version
```

## 7.6 使用例

```zig
const std = @import("std");
const zk = @import("zigkit");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const spec = zk.cli.CommandSpec{
        .name = "imgtool",
        .version = "0.1.0",
        .about = "small image utility",
        .options = &.{
            .{
                .long = "input",
                .short = 'i',
                .value_name = "PATH",
                .kind = .string,
                .required = true,
                .help = "input file path",
            },
            .{
                .long = "verbose",
                .short = 'v',
                .kind = .bool,
                .help = "enable verbose logging",
            },
        },
    };

    var result = try zk.cli.parse(allocator, spec, std.os.argv);
    defer result.deinit();

    const input = result.getString("input").?;
    const verbose = result.getBool("verbose") orelse false;

    _ = input;
    _ = verbose;
}
```

## 7.7 cliテスト必須項目

`tests/cli_test.zig` に以下を実装してください。

- `--name value` が読める
- `--name=value` が読める
- `-n value` が読める
- bool flag が読める
- required不足でエラー
- unknown optionでエラー
- missing valueでエラー
- default valueが使える
- positionalが読める
- repeated optionが読める
- subcommandが読める
- helpに主要項目が含まれる
- versionにバージョンが含まれる

---

# 8. zigkit-config 仕様

## 8.1 目的

`zigkit-config` は、設定ファイル・環境変数・明示的オーバーライドを統合して、型付き設定として読み込むモジュールです。

## 8.2 対応形式

### 必須

- ZON
- JSON
- 環境変数
- デフォルト値
- 必須値チェック

### 後回し

- YAML
- TOML
- ネストした配列
- 複雑なバリデーションDSL
- hot reload

## 8.3 設定優先順位

優先順位は以下で固定します。

```text
overrides > env > file > struct default
```

CLI由来の値を渡す場合は `overrides` を使います。

## 8.4 公開API

```zig
const std = @import("std");

pub const FileFormat = enum {
    auto,
    zon,
    json,
};

pub const Override = struct {
    key: []const u8,
    value: []const u8,
};

pub const LoadOptions = struct {
    file_path: ?[]const u8 = null,
    file_format: FileFormat = .auto,
    env_prefix: ?[]const u8 = null,
    overrides: []const Override = &.{},
    allow_unknown_fields: bool = false,
};

pub fn load(
    comptime T: type,
    allocator: std.mem.Allocator,
    options: LoadOptions,
) !T;

pub fn free(
    comptime T: type,
    allocator: std.mem.Allocator,
    value: T,
) void;
```

## 8.5 対応型

必須対応型は以下です。

- `bool`
- `u8`, `u16`, `u32`, `u64`, `usize`
- `i8`, `i16`, `i32`, `i64`, `isize`
- `f32`, `f64`
- `[]const u8`
- `?T`
- `enum`
- ネストした `struct`

後回しでよい型。

- `[]const T`
- `ArrayList`
- `HashMap`
- `union`

## 8.6 文字列所有権

`load()` が返す `T` に含まれる `[]const u8` は、原則として allocator で複製して所有するものとします。

そのため、利用者は必ず以下を呼びます。

```zig
defer zk.config.free(AppConfig, allocator, cfg);
```

`free()` は `T` のフィールドを再帰的に辿り、所有している文字列を解放します。

## 8.7 env変換ルール

`env_prefix = "APP_"` の場合、struct field名を大文字snakeに変換します。

```zig
const AppConfig = struct {
    database_url: []const u8,
    max_connections: u16 = 10,
};
```

対応する環境変数。

```text
APP_DATABASE_URL
APP_MAX_CONNECTIONS
```

## 8.8 ファイル形式判定

`file_format = .auto` の場合、拡張子で判定します。

- `.zon` -> ZON
- `.json` -> JSON
- その他 -> `ConfigError.UnsupportedFormat`

## 8.9 エラー仕様

```zig
pub const ConfigError = error{
    FileNotFound,
    UnsupportedFormat,
    InvalidFormat,
    UnknownField,
    MissingRequiredField,
    InvalidValue,
    UnsupportedType,
    OutOfMemory,
};
```

詳細エラー用に以下を用意します。

```zig
pub const ConfigErrorReport = struct {
    kind: anyerror,
    message: []const u8,
    field: ?[]const u8 = null,
    source: ?[]const u8 = null,

    pub fn deinit(self: *ConfigErrorReport, allocator: std.mem.Allocator) void;
};
```

## 8.10 使用例

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

ZON例。

```zig
.{
    .host = "0.0.0.0",
    .port = 3000,
    .debug = true,
    .database_url = "sqlite://app.db",
}
```

JSON例。

```json
{
  "host": "0.0.0.0",
  "port": 3000,
  "debug": true,
  "database_url": "sqlite://app.db"
}
```

## 8.11 configテスト必須項目

`tests/config_test.zig` に以下を実装してください。

- ZONからstructを読める
- JSONからstructを読める
- デフォルト値が使われる
- envで上書きできる
- overridesで上書きできる
- 優先順位 `overrides > env > file > default` が守られる
- 必須値不足でエラー
- 不正な型でエラー
- enumが読める
- optionalが読める
- ネストstructが読める
- `free()` で文字列を解放できる

---

# 9. zigkit-log 仕様

## 9.1 目的

`zigkit-log` は、text/json形式の構造化ログを出す軽量loggerです。

## 9.2 対応機能

### 必須

- text log
- json log
- level filter
- key-value fields
- writer指定
- timestamp optional
- 1行1ログ
- 1行1JSON

### 後回し

- async logging
- file rotation
- OpenTelemetry
- global logger
- color auto detection

## 9.3 公開型

```zig
const std = @import("std");

pub const Level = enum(u8) {
    trace,
    debug,
    info,
    warn,
    err,
    fatal,
};

pub const Format = enum {
    text,
    json,
};

pub const ColorMode = enum {
    auto,
    always,
    never,
};

pub const LoggerOptions = struct {
    level: Level = .info,
    format: Format = .text,
    timestamp: bool = true,
    color: ColorMode = .never,
};

pub const Logger = struct {
    pub fn init(writer: anytype, options: LoggerOptions) Logger;

    pub fn enabled(self: *const Logger, level: Level) bool;

    pub fn trace(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn debug(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn info(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn warn(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn err(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn fatal(self: *Logger, message: []const u8, fields: anytype) !void;
};
```

`writer: anytype` をstruct内部に保持する実装が難しい場合は、以下のどちらかにしてください。

1. `Logger(comptime WriterType: type)` 型を返すgeneric設計にする
2. 各ログ出力時にwriterを渡す設計にする

ただし、利用者側APIはなるべく自然にしてください。

## 9.4 出力仕様

### text形式

```text
INFO server started host=127.0.0.1 port=8080
ERROR request failed status=500 path=/api/users
```

### json形式

```json
{"level":"info","message":"server started","host":"127.0.0.1","port":8080}
{"level":"err","message":"request failed","status":500,"path":"/api/users"}
```

`timestamp = true` の場合、以下のようなフィールドを含めます。

```json
{"time":"2026-06-14T12:34:56Z","level":"info","message":"started"}
```

Zig標準だけでISO 8601生成が面倒な場合、v0.1.0ではUnix timestampでもよいです。その場合READMEに明記してください。

```json
{"time_unix_ms":1781421296000,"level":"info","message":"started"}
```

## 9.5 fields仕様

以下のような匿名structを受け取れること。

```zig
try logger.info("server started", .{
    .host = "127.0.0.1",
    .port = 8080,
    .debug = false,
});
```

対応するfield型。

- bool
- int
- float
- string
- enum
- null optional

複雑な型は `@compileError` または文字列化不可エラーにしてください。

## 9.6 JSON escaping

JSONログでは以下を正しくescapeしてください。

- `"`
- `\`
- newline
- tab
- carriage return

## 9.7 使用例

```zig
var buffer = std.ArrayList(u8).init(allocator);
defer buffer.deinit();

var logger = zk.log.Logger.init(buffer.writer(), .{
    .level = .info,
    .format = .json,
    .timestamp = false,
});

try logger.info("server started", .{
    .host = "127.0.0.1",
    .port = 8080,
});
```

## 9.8 logテスト必須項目

`tests/log_test.zig` に以下を実装してください。

- text logが出る
- json logが出る
- level filterが効く
- info以上設定時にdebugが出ない
- key-value fieldsが出る
- JSON escapingが正しい
- timestamp=falseで時刻が出ない
- bool/int/float/string/enumが出せる

---

# 10. zigkit-test 仕様

## 10.1 目的

`zigkit-test` は、Zig標準の `std.testing` を補助する小さなテストユーティリティです。

## 10.2 対応機能

### 必須

- `expectContains`
- `expectStartsWith`
- `expectEndsWith`
- `expectEqualStringPretty`
- `expectJsonEqual`
- `TempDir`
- snapshot testing
- fixture file reader

### 後回し

- fuzz統合
- property based testing
- HTTP mock server
- fake clock

## 10.3 公開API

```zig
const std = @import("std");

pub fn expectContains(haystack: []const u8, needle: []const u8) !void;
pub fn expectStartsWith(actual: []const u8, prefix: []const u8) !void;
pub fn expectEndsWith(actual: []const u8, suffix: []const u8) !void;
pub fn expectEqualStringPretty(expected: []const u8, actual: []const u8) !void;

pub fn expectJsonEqual(
    allocator: std.mem.Allocator,
    expected: []const u8,
    actual: []const u8,
) !void;

pub const TempDir = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !TempDir;
    pub fn deinit(self: *TempDir) void;
    pub fn writeFile(self: *TempDir, name: []const u8, content: []const u8) !void;
    pub fn readFile(self: *TempDir, name: []const u8, allocator: std.mem.Allocator) ![]u8;
    pub fn pathJoinAlloc(self: *TempDir, allocator: std.mem.Allocator, name: []const u8) ![]u8;
};

pub fn fixtureAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8;

pub fn expectSnapshot(
    allocator: std.mem.Allocator,
    name: []const u8,
    actual: []const u8,
) !void;
```

## 10.4 snapshot仕様

snapshotファイルは以下に保存します。

```text
tests/snapshots/{name}.snap
```

`ZIGKIT_UPDATE_SNAPSHOTS=1` が指定されている場合、snapshotを作成・更新します。

指定がない場合、snapshotが存在しなければエラーにします。

エラーメッセージ例。

```text
snapshot not found: tests/snapshots/cli-help.snap
run with ZIGKIT_UPDATE_SNAPSHOTS=1 to create it
```

## 10.5 expectJsonEqual仕様

- JSONとしてparseする
- オブジェクトのkey順序差は無視する
- 配列順序は保持する
- 数値差は厳密比較でよい
- diff表示は簡易でよい

## 10.6 TempDir仕様

- OSの一時ディレクトリ配下に一意なディレクトリを作成する
- `deinit()` で再帰削除する
- Windowsでも動くこと
- path文字列はallocatorで所有する

## 10.7 testモジュールのテスト必須項目

`tests/test_test.zig` に以下を実装してください。

- expectContains成功/失敗
- expectStartsWith成功/失敗
- expectEndsWith成功/失敗
- expectEqualStringPretty成功/失敗
- expectJsonEqualでkey順序差を許容
- TempDirでwrite/readできる
- TempDir deinitで削除される
- snapshot更新モードで作成できる
- snapshot比較できる

---

# 11. internalモジュール仕様

`src/internal` 配下は公開APIではありません。READMEに直接使用しないよう書いてください。

## 11.1 `internal/string.zig`

以下の補助関数を実装します。

```zig
pub fn eql(a: []const u8, b: []const u8) bool;
pub fn startsWith(s: []const u8, prefix: []const u8) bool;
pub fn endsWith(s: []const u8, suffix: []const u8) bool;
pub fn toEnvNameAlloc(allocator: std.mem.Allocator, prefix: []const u8, field_name: []const u8) ![]u8;
pub fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8;
```

## 11.2 `internal/ansi.zig`

v0.1.0では最低限でよいです。

```zig
pub const reset = "\x1b[0m";
pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
```

## 11.3 `internal/fs.zig`

```zig
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8;
pub fn writeFile(path: []const u8, content: []const u8) !void;
pub fn ensureDir(path: []const u8) !void;
```

## 11.4 `internal/json.zig`

JSON escapingや比較処理をまとめます。

```zig
pub fn writeEscapedString(writer: anytype, s: []const u8) !void;
pub fn jsonEqual(allocator: std.mem.Allocator, a: []const u8, b: []const u8) !bool;
```

---

# 12. examples仕様

## 12.1 hello-cli

### 目的

`zigkit-cli` の最小サンプルです。

### 実行例

```bash
zig build run -- --name Daiki --verbose
```

### 出力例

```text
hello, Daiki
verbose: true
```

## 12.2 config-app

### 目的

`zigkit-config` でZON設定と環境変数上書きを確認するサンプルです。

### app.zon

```zig
.{
    .host = "0.0.0.0",
    .port = 3000,
    .debug = true,
}
```

### 実行例

```bash
APP_PORT=8080 zig build run
```

### 出力例

```text
host=0.0.0.0 port=8080 debug=true
```

## 12.3 json-log

### 目的

`zigkit-log` でJSONログを出すサンプルです。

### 出力例

```json
{"level":"info","message":"server started","host":"127.0.0.1","port":8080}
```

---

# 13. README仕様

READMEには最低限以下を書いてください。

```markdown
# zigkit

A small practical toolkit for building Zig applications.

## Features

- CLI parser
- Config loader
- Structured logger
- Test helpers

## Requirements

- Zig 0.16.x

## Install

## Quick Start

## Modules

### zigkit-cli
### zigkit-config
### zigkit-log
### zigkit-test

## Design Principles

- Explicit allocation
- No hidden global state
- Small APIs
- Clear ownership
- Good error messages

## Examples

## Compatibility Policy

## Roadmap

## License
```

---

# 14. docs仕様

## 14.1 docs/design.md

以下を説明してください。

- なぜ小さい部品集にするのか
- allocator明示の方針
- 所有権ルール
- グローバル状態を避ける理由
- comptime利用方針
- エラー設計

## 14.2 docs/cli.md

- CLI定義方法
- option種類
- positional
- subcommand
- help/version
- エラー処理

## 14.3 docs/config.md

- ZON/JSON/env/override
- 優先順位
- 対応型
- 文字列所有権
- freeの必要性

## 14.4 docs/log.md

- text/json形式
- level
- fields
- JSON escaping
- timestamp

## 14.5 docs/test.md

- assert helpers
- TempDir
- snapshot
- fixture

## 14.6 docs/roadmap.md

v0.2以降の予定を書いてください。

```text
v0.2.0 zigkit-http
v0.3.0 zigkit-sqlite
v0.4.0 OpenAPI client generator
v0.5.0 PostgreSQL wrapper
```

---

# 15. GitHub Actions CI仕様

`.github/workflows/ci.yml` を作成してください。

```yaml
name: CI

on:
  push:
  pull_request:

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.16.0
      - run: zig build test
      - run: zig build examples
      - run: zig fmt --check src tests examples build.zig
```

---

# 16. 品質基準

## 16.1 必須

- `zig build test` が通る
- Linux/macOS/Windows CIが通る
- `zig fmt --check` が通る
- READMEのQuick Startが動く
- examplesが動く
- 主要APIにdoc commentを書く
- メモリ所有権がREADMEに書かれている
- `GeneralPurposeAllocator` 使用時にリークしない

## 16.2 禁止事項

- 不必要なグローバル状態
- 暗黙のallocator使用
- 未解放の所有メモリ
- READMEにない複雑な挙動
- 巨大な抽象化
- v0.1.0でHTTP/SQLiteまで無理に完成させること

---

# 17. 実装順序

Codexは以下の順で実装してください。

## Step 1: プロジェクト雛形

- `build.zig`
- `build.zig.zon`
- `src/zigkit.zig`
- `README.md`
- `LICENSE`
- `.gitignore`
- `docs/design.md`

完了条件。

```bash
zig build test
```

が空テストでも通ること。

## Step 2: zigkit-test

- `src/test.zig`
- `tests/test_test.zig`

以下を実装。

- expectContains
- expectStartsWith
- expectEndsWith
- expectEqualStringPretty
- expectJsonEqual
- TempDir
- fixtureAlloc
- expectSnapshot

## Step 3: zigkit-log

- `src/log.zig`
- `tests/log_test.zig`
- `examples/json-log`
- `docs/log.md`

以下を実装。

- text/json log
- level filter
- key-value fields
- JSON escaping

## Step 4: zigkit-cli

- `src/cli.zig`
- `tests/cli_test.zig`
- `examples/hello-cli`
- `docs/cli.md`

以下を実装。

- option parser
- positional
- repeated option
- subcommand
- help/version
- error report

## Step 5: zigkit-config

- `src/config.zig`
- `tests/config_test.zig`
- `examples/config-app`
- `docs/config.md`

以下を実装。

- ZON
- JSON
- env
- overrides
- type conversion
- free

## Step 6: examples / docs / CI

- examplesがビルドできる
- README更新
- docs更新
- GitHub Actions追加

---

# 18. v0.1.0 完了条件

以下をすべて満たしたら `v0.1.0` 完了です。

```text
- Zig 0.16.0 で zig build test が通る
- Linux/macOS/Windows CIが通る
- zig fmt --check が通る
- README Quick Startが動く
- examplesが3つ以上ある
- cli/config/log/test のAPIが一通り使える
- メモリリークしない
- MIT Licenseがある
- docsが最低限揃っている
```

---

# 19. v0.2.0 予定: zigkit-http

v0.2.0ではHTTPクライアントラッパーを実装します。

## 19.1 目的

Zig標準の `std.http.Client` を実用向けに包む薄いラッパーです。

## 19.2 機能

- GET/POST/PUT/PATCH/DELETE
- header設定
- query parameter
- JSON request body
- JSON response parse
- timeout
- retry
- bearer token
- basic auth
- request/response logging

## 19.3 API案

```zig
pub const ClientOptions = struct {
    base_url: ?[]const u8 = null,
    timeout_ms: u64 = 30_000,
    user_agent: []const u8 = "zigkit-http",
    retry: ?RetryOptions = null,
    logger: ?*zk.log.Logger = null,
};

pub const RetryOptions = struct {
    max_attempts: u8 = 3,
    backoff_ms: u64 = 100,
    retry_on_5xx: bool = true,
    retry_on_timeout: bool = true,
};
```

---

# 20. v0.3.0 予定: zigkit-sqlite

v0.3.0ではSQLiteラッパーを実装します。

## 20.1 目的

SQLiteをZigから安全・簡単に使う薄いラッパーです。

## 20.2 機能

- open / close
- exec
- prepare
- bind
- query one
- query all
- transaction
- migration

## 20.3 API案

```zig
pub const Db = struct {
    pub fn open(path: []const u8) !Db;
    pub fn close(self: *Db) void;

    pub fn exec(self: *Db, sql: []const u8) !void;
    pub fn execParams(self: *Db, sql: []const u8, params: anytype) !void;

    pub fn queryOne(
        self: *Db,
        comptime T: type,
        allocator: std.mem.Allocator,
        sql: []const u8,
        params: anytype,
    ) !?T;
};
```

---

# 21. Codexへの最終指示

以下を守って実装してください。

1. まず `v0.1.0` の4モジュールだけ完成させる
2. 途中でHTTP/SQLiteを実装し始めない
3. `zig build test` が常に通る状態を保つ
4. 大きく作りすぎず、シンプルにする
5. READMEとexamplesを実装と同時に更新する
6. APIの所有権をコメントとREADMEに必ず書く
7. Zig 0.16.0で動かないコードは不可
8. 最後にCIを追加し、Linux/macOS/Windowsで通るようにする

---

# 22. 参考情報

この仕様書は、Zig公式サイト、Zig公式Build Systemガイド、Zig 0.16.0リリースノート、Zig標準ライブラリのJSON/HTTP関連情報を前提にしています。

- Zig公式サイト: https://ziglang.org/
- Zig 0.16.0 Release Notes: https://ziglang.org/download/0.16.0/release-notes.html
- Zig Build System: https://ziglang.org/learn/build-system/
- Zig Language Reference / Standard Library: https://ziglang.org/documentation/master/
