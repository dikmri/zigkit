# zigkit 設計ドキュメント

## 設計思想

zigkit は Zig 本体の思想に従い、以下を徹底します。

### 明示的なメモリ管理

- 隠れたアロケーションをしない
- メモリ確保が必要な関数には `std.mem.Allocator` を明示的に受け取る
- `alloc` / `free` または `init` / `deinit` のペアを必ず提供する
- 所有権は API 名・コメントで明確にする

### シンプルな API

- グローバル状態を持たない
- 魔法のような自動探索・自動設定をしない
- API は小さく保つ
- Examples を重視する

### エラーハンドリング

- Zig の `error{}` を使う
- エラーメッセージを人間が読めるようにする
- 詳細エラーが必要な場合は `*Report` 構造体を提供する

## モジュール構成

```
src/
  zigkit.zig         # 公開APIのre-export
  cli.zig            # CLIパーサ
  config.zig         # 設定ローダー
  log.zig            # 構造化ロガー
  test.zig           # テストヘルパー
  internal/
    json.zig         # JSON書き出し・比較（内部用）
    string.zig       # 文字列ユーティリティ（内部用）
    ansi.zig         # ANSIカラー（内部用、将来使用）
    fs.zig           # ファイルシステム（内部用）
```

## Zig 0.16.x 特記事項

### std.Io.Writer

Zig 0.16 で `std.Io.Writer`（大文字 I）が新しい vtable ベースの型消去 writer になりました。
テスト用の growing buffer には `std.Io.Writer.Allocating` を使います。

```zig
var aw: std.Io.Writer.Allocating = .init(allocator);
defer allocator.free(aw.writer.buffer);
// aw.writer.buffered() で書き込み済みバイト列を取得
```

### Io コンテキスト

`std.Io.Threaded.global_single_threaded.io()` でテスト外での Io コンテキストを取得します。
テスト内では `std.testing.io` が使えます（ただし zigkit では前者を統一して使用）。

### ファイル操作

```zig
const io = std.Io.Threaded.global_single_threaded.io();
const file = try std.Io.Dir.cwd().openFile(io, path, .{});
defer file.close(io);
```

### main() シグネチャ

Zig 0.16 では以下が使えます:

```zig
pub fn main() !void                              // 最小
pub fn main(init: std.process.Init.Minimal) !void
pub fn main(init: std.process.Init) !void        // gpa・io・args付き
```

args は `init.minimal.args.toSlice(allocator)` で取得します（`argsAlloc` は廃止）。

## テスト戦略

- `tests/*_test.zig` に各モジュールのブラックボックステスト
- `src/zigkit.zig` の `test {}` ブロックで `refAllDecls` によるコンパイルチェック
- スナップショットテストは `tests/snapshots/` に保存

## バージョニング

[Semantic Versioning](https://semver.org/) に従います。

- `v0.x.y` の間は破壊的変更が起こりえます
- `v1.0.0` 以降は安定 API を保証します
