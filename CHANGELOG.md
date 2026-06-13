# Changelog

## [v0.1.0] - 2026-06-14

初回リリース。

### 追加

- **zigkit-cli**: CLIパーサ
  - long/short オプション（`--name value`, `--name=value`, `-n value`）
  - bool フラグ（`--verbose`）
  - required / optional / default value
  - positional arguments
  - repeated options（`--tag a --tag b`）
  - subcommands
  - help 生成（`--help`, `-h`）
  - version 表示（`--version`, `-V`）
  - 詳細エラーレポート（`parseDetailed`）

- **zigkit-config**: 設定ローダー
  - ZON ファイル読み込み
  - JSON ファイル読み込み
  - 環境変数からの読み込み（prefix指定）
  - 明示的オーバーライド
  - 優先順位管理（overrides > env > file > default）
  - 型安全な設定（bool, int, float, string, enum, optional, nested struct）
  - `free()` による所有文字列の再帰的解放

- **zigkit-log**: 構造化ロガー
  - text / JSON 出力形式
  - レベルフィルタ（trace / debug / info / warn / err / fatal）
  - k-v フィールド（bool, int, float, string, enum, optional）
  - タイムスタンプ（Unix ミリ秒）
  - JSON エスケープ

- **zigkit-test**: テストヘルパー
  - `expectContains` / `expectStartsWith` / `expectEndsWith`
  - `expectEqualStringPretty`（失敗時 diff 表示）
  - `expectJsonEqual`（キー順序無視）
  - `TempDir`（テスト用一時ディレクトリ）
  - `fixtureAlloc`（フィクスチャファイル読み込み）
  - `expectSnapshot`（スナップショットテスト）

- GitHub Actions CI（Linux / macOS / Windows）
- GitHub Actions リリース自動化
- GitHub Actions README 多言語自動翻訳（EN / ZH / KO）
