# 実装進行プラン

最終更新: 2026-04-21
前提: 実装は GitHub Copilot（および Copilot Coding Agent）に委譲する。

## このドキュメントの使い方 (Copilot 向け)

- 各フェーズは **独立した PR 単位** を想定しています。1 PR = 1 フェーズ内の 1 タスクが目安。
- 作業開始前に必ず以下を読み込むこと:
  - [requirements.md](requirements.md) — 要件定義
  - [wireframes.md](wireframes.md) — 画面仕様
  - [schema.surql](schema.surql) — DBスキーマ（SoT）
- 型定義は `src/lib/types.ts` を唯一の真実の源とし、再定義禁止。
- 秘密情報は `.env` / Wrangler Secrets に置き、**コードにハードコードしない**。
- 各タスクは「DoD (Done の定義)」を満たすまで完了としない。

---

## フェーズ 0: リポジトリ準備

**目的**: Copilot が読み取れる土台を作る。

タスク:
- [x] `README.md` に概要とスタック
- [x] `.editorconfig`
- [x] `.gitignore` (Node, SvelteKit, Wrangler)
- [x] `.nvmrc` (Node LTS)
- [x] `.env.example` (必要な環境変数の列挙、値は空)

**DoD**: `docs/` 一式 + README + 上記設定ファイルがコミット済み。

---

## フェーズ 1: Cloudflare リソースのプロビジョニング（手動）

**Copilot 対象外**。オーナーが手動で実施。

- [ ] Cloudflare Pages プロジェクト作成
- [ ] R2 バケット `receipts` 作成
- [ ] AI Gateway 作成
  - Google AI Studio を BYOK で接続
  - フォールバック先 `gemini-2.5-flash` 設定
  - レートリミット: 月あたり上限を設定
- [ ] SurrealDB Cloud インスタンス作成
  - `docs/schema.surql` を適用
- [ ] Cloudflare Access 設定
  - Google OAuth
  - 許可メール: オーナー本人のみ
- [ ] Secrets 登録（Pages / Worker）:
  - `GEMINI_API_KEY`
  - `AI_GATEWAY_URL`
  - `SURREAL_URL`
  - `SURREAL_NS`
  - `SURREAL_DB`
  - `SURREAL_TOKEN`

**DoD**: 上記リソースの ID・URL が `docs/infrastructure.md`（別途作成）にまとめられている。

---

## フェーズ 2: SvelteKit 初期化

タスク:
- [ ] `npm create svelte@latest` で初期化（TypeScript / ESLint / Prettier / Vitest 有効）
- [ ] `@sveltejs/adapter-cloudflare` 導入
- [ ] Tailwind CSS 導入（スマホ優先UI）
- [ ] `wrangler.toml` 作成（R2 バインディング、環境変数マッピング）
- [ ] ルートレイアウト `src/routes/+layout.svelte` にヘッダ共通コンポーネント

**DoD**: `npm run dev` でトップページが表示され、`npm run build` が Pages 向けに成功。

---

## フェーズ 3: 共通レイヤー

各ファイル 1 PR 粒度。

- [ ] `src/lib/types.ts` — `Receipt`, `ReceiptItem`, `ExtractedReceipt` 型（schema.surql と整合）
- [ ] `src/lib/server/surreal.ts` — SurrealDB HTTP クライアント薄ラッパー
- [ ] `src/lib/server/r2.ts` — R2 put / get / delete
- [ ] `src/lib/server/gemini.ts` — AI Gateway 経由呼び出し + Structured Output JSON Schema
- [ ] `src/lib/server/hash.ts` — SHA-256 計算（Web Crypto API）
- [ ] `src/lib/server/auth.ts` — Cloudflare Access JWT 検証（念のため二重防御）

**DoD**: 各モジュール単体テスト（Vitest）がグリーン。外部サービスはモック。

---

## フェーズ 4: API エンドポイント（MVP）

`src/routes/api/` に配置。

- [ ] `POST /api/upload` — R2 保存 + hash 返却（`image_hash` 重複時は既存 ID を返す）
- [ ] `POST /api/extract` — Gemini で構造化抽出、DB 書き込みはしない（プレビュー用）
- [ ] `GET /api/receipts` — 一覧（フィルタ: 期間 / カテゴリ / 店舗）
- [ ] `POST /api/receipts` — 確定保存（`status=confirmed`）、`store_category_hint` も upsert
- [ ] `GET /api/receipts/[id]`
- [ ] `PATCH /api/receipts/[id]`
- [ ] `DELETE /api/receipts/[id]` — R2 画像も同時削除
- [ ] `GET /api/export?format=csv|json`

**DoD**:
- 各エンドポイントに Vitest の統合テスト（SurrealDB / R2 / Gemini は MSW or モック）
- エラー時のレスポンス形状統一（`{ error: string, code: string }`）

---

## フェーズ 5: 画像圧縮 Worker

- [ ] クライアント側縮小: `browser-image-compression` で長辺 2048px + HEIC→JPEG
- [ ] Worker 側: `workers/compress/` に分離、WebP 化（`wasm-image-optimization` 等）
- [ ] Pages Function から Service Binding で呼び出し
- [ ] 失敗時はオリジナル JPEG を保存（フォールバック）

**DoD**: 10MB HEIC → 200KB 前後 WebP に変換できる。単体テストあり。

---

## フェーズ 6: UI 画面

1 画面 1 PR 推奨。各 PR で [wireframes.md](wireframes.md) の該当セクションを参照。

- [ ] `/` ホーム一覧（wireframes §1）
- [ ] `/upload` 撮影・選択（§2）
- [ ] `/upload/review` 確認・編集（§3）
  - `confidence < 0.7` のフィールドは視覚的強調
  - 重複候補ヒット時の警告表示
- [ ] `/receipts/[id]` 詳細（§4）
- [ ] `/stats` 集計（§5、`layerchart` 使用）
- [ ] `/settings` 設定（§6）

**DoD**: 各画面が実 API と接続して動作。Lighthouse モバイルスコア 90+。

---

## フェーズ 7: PWA 化

- [ ] `static/manifest.json` + アイコン（192/512）
- [ ] Service Worker（閲覧オフライン対応のみ、アップロードは要オンライン）
- [ ] iOS ホーム画面追加で全画面起動確認

**DoD**: iOS Safari で「ホーム画面に追加」→ スタンドアロン起動できる。

---

## フェーズ 8: 運用機能

- [ ] Cron Worker: SurrealDB エクスポート → R2 `backups/yyyy-mm-dd.surql.gz`（日次）
- [ ] AI Gateway レートリミットの最終調整
- [ ] `store_category_hint` の自動更新確認（フェーズ 4 で実装済みの動作確認）
- [ ] 監視: AI Gateway ダッシュボードを週次チェックするだけの運用で可

**DoD**: バックアップが 3 日連続で自動生成されていることを確認。

---

## フェーズ 9: E2E + 本番投入

- [ ] Playwright で主要フロー（アップロード→確認→保存→一覧→詳細→削除）
- [ ] 実レシート 10 枚で精度チェック
  - 精度が低いフィールドがあればプロンプト調整（`src/lib/server/gemini.ts`）
  - `extractor_version` を更新
- [ ] Cloudflare Access を有効化して本番デプロイ

**DoD**: 本番 URL でスマホから 1 枚取り込み・保存ができる。

---

## フェーズ 10: v2 以降

MVP ローンチ後に検討。詳細は [requirements.md](requirements.md) の v2 セクション参照。

- [ ] `items[]` 抽出 + 編集 UI（`receipt_item` テーブル活用）
- [ ] 全文検索（`raw_text` の BM25 インデックス活用）
- [ ] 再 OCR 機能（過去レコードを新しいモデルで再抽出）
- [ ] カテゴリ学習の few-shot プロンプト組み込み（`store_category_hint` 活用）
- [ ] Cloudflare Queues による非同期化（複数枚同時アップロード対応）

---

## Copilot への指示テンプレ

各 Issue / PR で以下を明示すると精度が安定します。

```
## コンテキスト
- docs/requirements.md §<該当節>
- docs/wireframes.md §<該当節>
- docs/schema.surql（関連テーブル: <名前>）

## 対象
<ファイルパス / 機能>

## 完了条件
- [ ] <具体的な振る舞い>
- [ ] テスト追加（Vitest / Playwright）
- [ ] 型は src/lib/types.ts を使用（再定義しない）
- [ ] 環境変数は .env.example に追記

## 非対象
<スコープ外の明示>
```

## 禁止事項

- `src/lib/types.ts` 以外での型重複定義
- 秘密情報のハードコード
- `docs/schema.surql` に無いフィールドの使用
- MVP スコープ外の機能追加（v2 項目の先行実装）
- `any` / `unknown` の濫用
