# インフラ設定メモ

最終更新: 2026-04-22

このファイルには **秘密ではない設定値** と、手動セットアップ時の参照情報だけを記録する。  
API キーやパスワードそのものはコミットしない。

## 秘密情報の扱い

- `GEMINI_API_KEY` と `SURREAL_PASSWORD` は Cloudflare Pages / Workers の Secret に登録する
- ローカルで秘密情報をメモしたい場合は `docs/infrastructure.local.md` を使う
- `docs/infrastructure.local.md` は `.gitignore` 済み

## Cloudflare Pages

| 項目              | 値              | メモ                                             |
| ----------------- | --------------- | ------------------------------------------------ |
| Project           | `receipt_graph` | GitHub リポジトリ `kaz2018/receipt_graph` を接続 |
| Production branch | `main`          | `main` push でデプロイ                           |

## R2

| 項目              | 値                             | メモ                              |
| ----------------- | ------------------------------ | --------------------------------- |
| Bucket name       | `receipts`                     | レシート画像保存用                |
| Binding name      | `RECEIPTS_BUCKET`              | Pages / Worker から参照する環境名 |
| Public access     | `off`                          | 画像は公開しない                  |
| Object key format | `receipts/yyyy/mm/{uuid}.webp` | 圧縮後のみ保存                    |

## AI Gateway

| 項目                 | 値                                                                                           | メモ                     |
| -------------------- | -------------------------------------------------------------------------------------------- | ------------------------ |
| Gateway name         | `receipt-graph`                                                                              | Cloudflare AI Gateway 名 |
| Endpoint URL         | `https://gateway.ai.cloudflare.com/v1/f0c68089f1c1d003bd7fdd01000673e8/receipt-graph/compat` | `AI_GATEWAY_URL` に設定  |
| Default Gemini model | `gemini-3-flash-preview`                                                                     | `GEMINI_MODEL` に設定    |
| Fallback model       | `gemini-2.5-flash`                                                                           | Gateway 側で設定予定     |

## SurrealDB Cloud

| 項目        | 値                                                                          | メモ                      |
| ----------- | --------------------------------------------------------------------------- | ------------------------- |
| URL         | `https://surreal-dragon-06emvh2un1o932cjgupvfh8eno.aws-aps1.surreal.cloud/` | `SURREAL_URL`             |
| Namespace   | `receipt_graph`                                                             | `SURREAL_NS`              |
| Database    | `app`                                                                       | `SURREAL_DB`              |
| Username    | `app-server`                                                                | `SURREAL_USERNAME` に設定 |
| Password    | Secret                                                                      | `SURREAL_PASSWORD` に設定 |
| Schema file | `docs/schema.surql`                                                         | 適用済み                  |

## Cloudflare Access

| 項目              | 値               | メモ                 |
| ----------------- | ---------------- | -------------------- |
| Identity provider | Google OAuth     | オーナー本人のみ許可 |
| Protected routes  | `<to be filled>` | Pages 全体を保護予定 |

## Pages / Worker に入れる設定

### Variables

| 名前               | 用途                                     |
| ------------------ | ---------------------------------------- |
| `AI_GATEWAY_URL`   | Cloudflare AI Gateway の compat endpoint |
| `GEMINI_MODEL`     | 利用する Gemini モデル名                 |
| `SURREAL_URL`      | SurrealDB 接続先 URL                     |
| `SURREAL_NS`       | SurrealDB namespace                      |
| `SURREAL_DB`       | SurrealDB database                       |
| `SURREAL_USERNAME` | SurrealDB 接続ユーザー名                 |

### Secrets

| 名前               | 用途                               |
| ------------------ | ---------------------------------- |
| `GEMINI_API_KEY`   | Google AI Studio API キー          |
| `SURREAL_PASSWORD` | SurrealDB 接続ユーザーのパスワード |

## セットアップ後の確認項目

- R2 binding `RECEIPTS_BUCKET` が Pages に追加されている
- `AI_GATEWAY_URL` / `GEMINI_MODEL` が Variables に入っている
- `GEMINI_API_KEY` が Secret に入っている
- `SURREAL_NS=receipt_graph` / `SURREAL_DB=app` / `SURREAL_USERNAME=app-server` が反映されている
- `SURREAL_URL` は SurrealDB Cloud の接続画面から転記する

## ハマりどころメモ

### Cloudflare Pages

- 初回デプロイが `Cloning git repository` で失敗した場合、`index.html` 不足ではなく **GitHub 連携や push 状態** を先に疑う
- Cloudflare の UI 文言は変わることがあり、案内上の `Variables` は実画面では `Variables and Secrets`、`Variable` は `Type: Text` と表示されることがある
- Cloudflare Pages の現行 UI では `Variable` ではなく `Type: Text` という表記になっている
- `Text` は通常の環境変数、`Secret` は機密値、`JSON` は今回未使用

### R2 binding

- `Add binding` 画面に表示されるコードは **説明用サンプル** であり、HTML に書くものではない
- 実際に設定するのは `RECEIPTS_BUCKET` のような binding 名と、接続先バケット `receipts`

### AI Gateway

- `AI_GATEWAY_URL` には Gateway 名を含む compat endpoint をそのまま入れる  
  例: `https://gateway.ai.cloudflare.com/v1/<account-id>/receipt-graph/compat`

### SurrealDB Cloud

- このプロジェクトでは database 接続に **token 前提ではなく database user (`app-server`)** を使う
- SurrealDB Cloud の UI では `Database Authentication` から `New system user` を作る
- `New access method` の `Record` / `JWT` は今回の用途には使わない
- `app-server` の role は CRUD が必要なため `Editor` を使う
- SurrealDB のクエリ結果には `PASSHASH` が出ることがあるので、その出力全文は公開場所に貼らない

### SvelteKit scaffold

- 現行の SvelteKit 初期化コマンドは `npm create svelte@latest` ではなく `npx sv create`
- 古い案内に従うと `npm create svelte' has been replaced with 'npx sv create'` と表示されるので、その場合は `npx sv create .` に読み替えて進める
- scaffold 実行時に `.gitignore` を上書きすると、`.dev.vars*` や `docs/infrastructure.local.md` の除外が落ちることがあるため、実行後に差分確認する
