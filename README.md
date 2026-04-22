# Receipt Graph

レシート画像をアップロードすると Gemini で構造化データに変換し、SurrealDB に蓄積する個人用家計記録 Web アプリ。

## 主要機能 (MVP)

- スマホカメラ or ファイル選択でレシート画像をアップロード
- Gemini による自動抽出（店舗名 / 日時 / 合計金額 / カテゴリ）
- 抽出結果を確認・編集して保存
- 月別・カテゴリ別の集計ダッシュボード
- CSV / JSON エクスポート
- PWA 対応（ホーム画面からワンタップで撮影）

## 技術スタック

| 層             | 採用                                                           |
| -------------- | -------------------------------------------------------------- |
| Frontend       | SvelteKit + TypeScript + Tailwind CSS                          |
| Hosting        | Cloudflare Pages + Pages Functions                             |
| 画像圧縮       | Cloudflare Workers（クライアント先行縮小 + Worker で WebP 化） |
| 画像ストレージ | Cloudflare R2（圧縮後のみ保存）                                |
| AI/OCR         | Google AI Studio `gemini-3-flash-preview`（AI Gateway 経由）   |
| DB             | SurrealDB Cloud                                                |
| 認証           | Cloudflare Access (Google OAuth、オーナー単独利用)             |

## ドキュメント

実装・仕様に関わるすべては `docs/` に集約しています。**Copilot に作業を依頼する際は必ず該当ドキュメントをコンテキストに含めてください。**

| ファイル                                                   | 内容                               |
| ---------------------------------------------------------- | ---------------------------------- |
| [docs/requirements.md](docs/requirements.md)               | 要件定義（機能・非機能・スコープ） |
| [docs/wireframes.md](docs/wireframes.md)                   | 全画面のワイヤーフレーム           |
| [docs/schema.surql](docs/schema.surql)                     | SurrealDB スキーマ（SoT）          |
| [docs/implementation-plan.md](docs/implementation-plan.md) | フェーズ分けされた実装進行プラン   |
| [docs/infrastructure.md](docs/infrastructure.md)           | 非秘密のインフラ設定メモ           |

## 開発セットアップ

```bash
nvm use
npm install
cp .env.example .env   # 値を埋める
npm run dev
```

### 必要な環境変数

`.env.example` を参照。主要なもの:

- `GEMINI_API_KEY` — Google AI Studio
- `GEMINI_MODEL` — 既定は `gemini-3-flash-preview`、将来差し替え可能
- `AI_GATEWAY_URL` — Cloudflare AI Gateway エンドポイント
- `SURREAL_URL` / `SURREAL_NS` / `SURREAL_DB`
- `SURREAL_USERNAME` / `SURREAL_PASSWORD`
- R2 バインディングは `wrangler.toml` 側で設定

### スクリプト

```bash
npm run dev       # 開発サーバ
npm run build     # 本番ビルド (adapter-cloudflare)
npm run preview   # ビルド後ローカル確認
npm run test      # Vitest
npm run test:e2e  # Playwright
npm run lint
npm run format
```

## デプロイ

Cloudflare Pages に接続。`main` ブランチへの push で自動デプロイ。Pages Functions と Worker（`workers/compress/`）を含む。

インフラ初期構築手順は [docs/implementation-plan.md §フェーズ 1](docs/implementation-plan.md) を参照。

## スコープ方針

- 利用者は**オーナー1人のみ**。マルチテナント設計はしない。
- v1 (MVP) はレシート 1 枚の 4 フィールド (`store_name` / `purchased_at` / `total` / `category`) のみ扱う。
- 明細 `items[]` や全文検索は v2 以降。詳細は [requirements.md §9](docs/requirements.md) 参照。

## ライセンス

Private / unpublished.
