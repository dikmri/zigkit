# zigkit-config

設定ファイル・環境変数・オーバーライドを統合して、型付き設定を読み込むモジュール。

## API

```zig
pub const FileFormat = enum { auto, zon, json };

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

pub fn load(comptime T: type, allocator: std.mem.Allocator, options: LoadOptions) !T;
pub fn free(comptime T: type, allocator: std.mem.Allocator, value: T) void;
```

## 設定優先順位

```
overrides > 環境変数 > ファイル > struct デフォルト
```

## 対応型

| 型 | 説明 |
|---|---|
| `bool` | `"true"/"1"` → true, `"false"/"0"` → false |
| `u8`〜`u64`, `i8`〜`i64`, `usize`, `isize` | 整数 |
| `f32`, `f64` | 浮動小数点数 |
| `[]const u8` | 文字列（allocatorで複製） |
| `?T` | Optional。空文字列 → null |
| `enum` | `@tagName` でマッチ |
| nested `struct` | 再帰的に処理 |

## 環境変数のマッピング

`env_prefix = "APP_"` の場合、struct フィールド名を大文字スネークケースに変換:

```
field_name: database_url → APP_DATABASE_URL
field_name: port         → APP_PORT
```

## ファイル形式の自動判定

`file_format = .auto` の場合、拡張子で判定:

- `.zon` → ZON形式
- `.json` → JSON形式
- その他 → `ConfigError.UnsupportedFormat`

## 使用例

```zig
const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    debug: bool = false,
    database_url: []const u8,  // デフォルトなし = 必須
};

// ファイル + 環境変数
const cfg = try zk.config.load(AppConfig, allocator, .{
    .file_path = "app.zon",
    .env_prefix = "APP_",
});
defer zk.config.free(AppConfig, allocator, cfg);

// オーバーライドも可能
const cfg2 = try zk.config.load(AppConfig, allocator, .{
    .file_path = "app.json",
    .overrides = &.{
        .{ .key = "port", .value = "9090" },
    },
});
defer zk.config.free(AppConfig, allocator, cfg2);
```

## ZON ファイル例

```zig
.{
    .host = "0.0.0.0",
    .port = 3000,
    .debug = true,
    .database_url = "postgres://localhost/myapp",
}
```

## JSON ファイル例

```json
{
  "host": "0.0.0.0",
  "port": 3000,
  "debug": true,
  "database_url": "postgres://localhost/myapp"
}
```

## エラー

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

## 所有権

`load()` が返す `T` に含まれる `[]const u8` はすべて allocator で複製されています。
必ず `config.free(T, allocator, value)` で解放してください。
