# zigkit-cli

CLIの引数を安全にパースするモジュール。

## API

```zig
pub const ValueKind = enum { bool, string, int, float, path };

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

pub fn parse(allocator, spec, args) CliError!ParseResult;
pub fn parseDetailed(allocator, spec, args) ParseDetailedResult;
pub fn renderHelpAlloc(allocator, spec) ![]u8;
pub fn renderVersionAlloc(allocator, spec) ![]u8;
```

## ParseResult メソッド

```zig
result.getBool("verbose")        // ?bool
result.getString("name")         // ?[]const u8
result.getInt("count")           // ?i64
result.getFloat("ratio")         // ?f64
result.getStrings("tags")        // []const Value (repeated options)
result.positional(0)             // ?[]const u8
result.selected_subcommand       // ?[]const u8
result.deinit()                  // メモリ解放
```

## エラー

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

## 使用例

```zig
const spec = zk.cli.CommandSpec{
    .name = "tool",
    .version = "1.0.0",
    .options = &.{
        .{ .long = "output", .short = 'o', .kind = .path, .help = "output path" },
        .{ .long = "count",  .short = 'c', .kind = .int, .default = "10" },
        .{ .long = "verbose",.short = 'v', .kind = .bool },
        .{ .long = "tag",    .multiple = true, .kind = .string },
    },
    .positionals = &.{
        .{ .name = "input", .required = true },
    },
    .subcommands = &.{
        .{ .name = "build", .about = "build the project" },
        .{ .name = "run",   .about = "run the project" },
    },
};

var r = try zk.cli.parse(allocator, spec, args);
defer r.deinit();

const verbose = r.getBool("verbose") orelse false;
const count   = r.getInt("count") orelse 10;
const input   = r.positional(0).?;
```

## 引数の書式

- `--name value` — 値付きオプション
- `--name=value` — イコール形式
- `-n value` — ショートオプション
- `--verbose` — bool フラグ
- `--` 以降はすべてポジショナルとして扱われる

## 所有権

`parse()` が返す `ParseResult` はすべての文字列を allocator で保持しています。
使い終わったら必ず `result.deinit()` を呼んでください。
