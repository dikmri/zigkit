# zigkit ロードマップ

## v0.1.0（現在）

- [x] `zigkit-cli` — CLIパーサ（long/short オプション、bool フラグ、サブコマンド、help/version生成）
- [x] `zigkit-config` — 設定ローダー（ZON/JSON/env/overrides、優先順位管理）
- [x] `zigkit-log` — 構造化ロガー（text/json形式、レベルフィルタ、k-vフィールド）
- [x] `zigkit-test` — テストヘルパー（TempDir、snapshot、JSON比較）
- [x] GitHub Actions CI（Linux/macOS/Windows）
- [x] GitHub Actions リリース自動化
- [x] README 多言語自動翻訳（EN/ZH/KO）

## v0.2.0（予定）

- [ ] `zigkit-http` — 軽量 HTTP クライアント
  - GET/POST/PUT/DELETE
  - カスタムヘッダー
  - JSON レスポンスパース
  - タイムアウト設定
  - リダイレクト対応
- [ ] `zigkit-cli` 強化
  - shell completion 生成
  - 環境変数連携

## v0.3.0（予定）

- [ ] `zigkit-sqlite` — SQLite ラッパー
  - `zig-sqlite` または直接 sqlite3 C API
  - 型安全な SELECT/INSERT/UPDATE
  - トランザクション

## v0.4.0 以降（アイデア段階）

- `zigkit-csv` — CSV の読み書き
- `zigkit-template` — シンプルなテキストテンプレート
- `zigkit-retry` — リトライ・バックオフユーティリティ

## 設計方針

- 外部依存は最小限に抑える
- Zig 最新安定版のみをサポート（古いバージョンの LTS はしない）
- API は小さく保ち、必要になってから拡張する
