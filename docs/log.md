# zigkit-log

text/json形式の構造化ログを出力する軽量ロガー。

## API

```zig
pub const Level = enum(u8) { trace, debug, info, warn, err, fatal };
pub const Format = enum { text, json };
pub const ColorMode = enum { auto, always, never };

pub const LoggerOptions = struct {
    level: Level = .info,
    format: Format = .text,
    timestamp: bool = true,
    color: ColorMode = .never,
};

pub const Logger = struct {
    pub fn init(writer: *std.Io.Writer, options: LoggerOptions) Logger;
    pub fn enabled(self: *const Logger, level: Level) bool;
    pub fn trace(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn debug(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn info(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn warn(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn err(self: *Logger, message: []const u8, fields: anytype) !void;
    pub fn fatal(self: *Logger, message: []const u8, fields: anytype) !void;
};
```

## 出力形式

### text

```
INFO server started host=127.0.0.1 port=8080
ERROR request failed status=500 path=/api/users
```

### json

```json
{"level":"info","message":"server started","host":"127.0.0.1","port":8080}
{"level":"err","message":"request failed","status":500,"path":"/api/users"}
```

### タイムスタンプあり (`timestamp = true`)

v0.1.0 では Unix ミリ秒を使用します（将来のバージョンでISO 8601に変更予定）。

```json
{"time_unix_ms":1781421296000,"level":"info","message":"started"}
```

## fields 対応型

| 型 | JSON出力例 |
|---|---|
| `bool` | `true` / `false` |
| `int` / `float` | `42` / `3.14` |
| `[]const u8` | `"value"` |
| `enum` | `"tag_name"` |
| `?T` | null または T の値 |

## 使用例

```zig
// テスト用バッファに書き込む
var aw: std.Io.Writer.Allocating = .init(allocator);
defer allocator.free(aw.writer.buffer);

var logger = zk.log.Logger.init(&aw.writer, .{
    .format = .json,
    .level = .info,
    .timestamp = false,
});

try logger.info("server started", .{
    .host = "127.0.0.1",
    .port = @as(u16, 8080),
});

// stderr に書き込む
var io = std.Io.Threaded.global_single_threaded.io();
var stderr_file = std.Io.File.stderr.writer(io);
var prod_logger = zk.log.Logger.init(&stderr_file, .{
    .format = .json,
    .level = .warn,
    .timestamp = true,
});
```

## レベルフィルタ

`options.level` 以上のレベルのログのみ出力されます。

| level | 優先度 |
|---|---|
| trace | 0 (最低) |
| debug | 1 |
| info | 2 |
| warn | 3 |
| err | 4 |
| fatal | 5 (最高) |

## JSON エスケープ

JSON形式では以下の文字を正しくエスケープします:
- `"` → `\"`
- `\` → `\\`
- 改行 → `\n`
- タブ → `\t`
- CR → `\r`
- その他の制御文字 → `\uXXXX`
