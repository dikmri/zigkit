# zigkit-test

`std.testing` を補完するテストヘルパー。

## API

### アサーション

```zig
// haystackにneedleが含まれることを確認
pub fn expectContains(haystack: []const u8, needle: []const u8) !void;

// actualがprefixで始まることを確認
pub fn expectStartsWith(actual: []const u8, prefix: []const u8) !void;

// actualがsuffixで終わることを確認
pub fn expectEndsWith(actual: []const u8, suffix: []const u8) !void;

// 文字列の等価チェック（失敗時にdiffを表示）
pub fn expectEqualStringPretty(expected: []const u8, actual: []const u8) !void;

// JSONの意味的な等価チェック（キー順序を無視）
pub fn expectJsonEqual(allocator: std.mem.Allocator, expected: []const u8, actual: []const u8) !void;
```

### TempDir

テスト用の一時ディレクトリを作成・管理します。

```zig
pub const TempDir = struct {
    pub fn init(allocator: std.mem.Allocator) !TempDir;
    pub fn deinit(self: *TempDir) void;                        // ディレクトリを削除
    pub fn writeFile(self: *TempDir, name: []const u8, content: []const u8) !void;
    pub fn readFile(self: *TempDir, name: []const u8, allocator: std.mem.Allocator) ![]u8;
    pub fn pathJoinAlloc(self: *TempDir, allocator: std.mem.Allocator, name: []const u8) ![]u8;
};
```

### Fixture

```zig
// テストフィクスチャファイルを読み込む（cwdからの相対パス）
pub fn fixtureAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8;
```

### Snapshot

```zig
// スナップショットテスト
pub fn expectSnapshot(allocator: std.mem.Allocator, name: []const u8, actual: []const u8) !void;
```

スナップショットは `tests/snapshots/{name}.snap` に保存されます。
`ZIGKIT_UPDATE_SNAPSHOTS=1` で自動更新します。

## 使用例

```zig
const std = @import("std");
const testing = std.testing;
const zkt = @import("zigkit").testing;

test "contains check" {
    try zkt.expectContains("hello world", "world");
    try zkt.expectStartsWith("hello world", "hello");
    try zkt.expectEndsWith("hello world", "world");
}

test "json equality ignores key order" {
    try zkt.expectJsonEqual(testing.allocator,
        \\{"b":2,"a":1}
    ,
        \\{"a":1,"b":2}
    );
}

test "temp file operations" {
    var tmp = try zkt.TempDir.init(testing.allocator);
    defer tmp.deinit();

    try tmp.writeFile("config.json", "{\"port\":3000}");
    const content = try tmp.readFile("config.json", testing.allocator);
    defer testing.allocator.free(content);

    try zkt.expectContains(content, "3000");
}

test "snapshot" {
    try zkt.expectSnapshot(testing.allocator, "my-snapshot", "expected output\n");
}
```

## スナップショット更新

```sh
ZIGKIT_UPDATE_SNAPSHOTS=1 zig build test
```

## TempDir のパス取得

OS の一時ディレクトリ（`TEMP`/`TMP` 環境変数、または `/tmp`）配下に `zigkit-test-{tid}-{ts}` という名前のディレクトリを作成します。
