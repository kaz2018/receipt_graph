# レシート取り込みWebアプリ 要件定義

最終更新: 2026-04-21

## 1. 目的

紙のレシートを撮影・アップロードするだけで、自動で構造化データ化し、DBに蓄積して後から検索・集計できる個人用家計記録ツールを構築する。

## 2. 前提・非機能要件

- **利用者**: 自分1人のみ（シングルテナント）
- **認証**: Cloudflare Access (Zero Trust) による保護。自前認証は作らない
- **可用性**: 個人用のためSLAなし。ただしデータロスは許容しない（R2 + DB定期バックアップ）
- **コスト目標**: Cloudflare 無料枠 + Gemini 従量 + SurrealDB Cloud 最小プランで月数ドル以内
- **対応デバイス**: スマホブラウザ優先（カメラ起動→即アップロード）、PCブラウザも可
- **PWA**: ホーム画面追加対応、カメラ直撮りを1タップで起動

## 3. 技術スタック

| 層             | 採用技術                                                                        |
| -------------- | ------------------------------------------------------------------------------- |
| Frontend       | SvelteKit (SSR/SPA hybrid)                                                      |
| Hosting        | Cloudflare Pages + Pages Functions                                              |
| 画像圧縮       | Cloudflare Workers（クライアント側で先にHEIC→JPEG変換後、Workerで WebP 再圧縮） |
| 画像ストレージ | Cloudflare R2（圧縮後のみ保存、原本は破棄）                                     |
| AI/OCR         | Google AI Studio API `gemini-3-flash-preview`                                   |
| AI Gateway     | Cloudflare AI Gateway（キャッシュ・ログ・レートリミット・フォールバック）       |
| DB             | SurrealDB Cloud                                                                 |

モデル名は preview のため、`GEMINI_MODEL` 環境変数で差し替え可能にする。AI Gateway のフォールバック先として `gemini-2.5-flash` 等の安定版を設定。

## 4. 機能要件

### 4.1 画像アップロード

- 単一 or 複数画像（JPEG/PNG/HEIC/WebP/PDF 1ページ目）対応
- スマホはカメラ直撮り → 即アップロード
- クライアント側で長辺 2048px 目安に縮小 + HEIC→JPEG 変換（`browser-image-compression` 等）
- Worker で WebP 再圧縮して R2 に保存（キー: `receipts/yyyy/mm/{uuid}.webp`）
- **圧縮後のみ保存、原本は破棄**

### 4.2 OCR / 構造化

- R2 保存後、AI Gateway 経由で Gemini に画像+プロンプトを送信
- Gemini は **Structured Output (JSON schema)** モードで呼び出し、自由文パースはしない
- 取得フィールド:
  - `store_name` 店舗名
  - `purchased_at` 購入日時 (ISO8601)
  - `total` 合計金額
  - `tax` 税額
  - `payment_method` 支払方法（現金/クレカ/電子マネー等、推定）
  - `category` カテゴリ（食費/交通/日用品など、LLMで分類）
  - `items[]`: `{name, qty, unit_price, price, category}`
  - `currency` (デフォルト JPY)
  - `raw_text` 生OCRテキスト（フォールバック検索用）
  - `confidence` LLM 自己申告 0–1

### 4.3 確認・編集UI

- アップロード直後に抽出結果を表示、ユーザーが修正して保存
- 画像サムネイルと抽出フィールドを左右並列
- 金額不一致（`sum(items) != total`）などを警告バッジ表示

### 4.4 一覧・検索

- 期間 / 店舗 / カテゴリ / 金額レンジ で絞り込み
- 月別・カテゴリ別の集計グラフ（棒・円）
- 全文検索は `raw_text` に対して実施（SurrealDB の full-text index）

### 4.5 エクスポート

- CSV / JSON ダウンロード（確定申告・家計簿連携用）

## 5. データモデル（SurrealDB）

```
receipt:
  id
  store_name
  purchased_at
  total
  tax
  payment_method
  category
  currency
  raw_text
  confidence
  image_key         # R2 オブジェクトキー
  image_hash        # SHA-256（重複検出用）
  extractor_version # 例: "gemini-3-flash-preview@prompt-v1"
  status            # pending | confirmed | rejected
  created_at
  updated_at

receipt_item:
  id
  receipt           # → receipt
  name
  qty
  unit_price
  price
  category
```

集計の柔軟性を優先し `receipt_item` は別テーブルとする。

## 6. 処理フロー

1. SvelteKit でファイル選択/撮影 → クライアント側で縮小・形式変換
2. `PUT /api/upload` (Pages Function) → R2 保存（Worker 経由で WebP 圧縮）
3. `POST /api/extract` → AI Gateway → Gemini で構造化抽出、JSON 返却
4. ユーザーが確認・編集 → `POST /api/receipts` で SurrealDB に確定保存
5. 一覧・検索は `GET /api/receipts?...`

## 7. セキュリティ

- APIキー（Gemini, SurrealDB）は Pages/Workers の Secret に格納、クライアントに出さない
- Cloudflare Access で全ルート保護
- R2 はパブリック非公開。Worker 経由 or 署名付きURLで配信

## 8. 運用・改善事項

### 採用する改善案

- **AI Gateway 経由**: キャッシュで Gemini コスト削減、preview モデル落ち時のフォールバック、使用量の可視化
- **プロンプト + モデルのバージョニング**: `extractor_version` をレコードに保持。将来の再抽出・精度比較に使用
- **重複検出**: `image_hash` (SHA-256) + `store + purchased_at + total` の二段で警告
- **カテゴリ辞書の自己学習**: 過去に確定した `store_name → category` を SurrealDB に蓄積、プロンプトに few-shot 注入
- **定期バックアップ**: SurrealDB Cloud のエクスポートを Cron Worker で R2 に保存
- **費用ガード**: AI Gateway のレートリミット機能で Gemini 呼び出し上限を設定

### 将来検討

- **Cloudflare Queues で非同期化**: 複数枚まとめてアップロード時のUX改善・リトライ容易化
- **再OCR機能**: モデル改善時に過去レコードを再抽出し精度向上

## 9. MVP スコープ

**v1 (MVP)**: 以下4フィールドのみ抽出・保存する。items 配列は扱わない。

- `store_name`
- `purchased_at`
- `total`
- `category`

一覧表示、月別集計、CSVエクスポートまで。

**v2 以降**:

- `items[]` 詳細抽出
- 全文検索
- カテゴリ自己学習
- 非同期キュー化
- 再OCR機能

## 10. 次のアクション

1. MVP スコープの確定レビュー
2. 画面ワイヤーフレーム作成
3. SurrealDB スキーマ DDL 確定
4. Cloudflare リソース（Pages / R2 / AI Gateway / Access）プロビジョニング
5. SvelteKit プロジェクト初期化
