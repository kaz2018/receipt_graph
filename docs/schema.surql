-- ============================================================
-- Receipt Graph - SurrealDB schema
-- Target: SurrealDB 2.x (SurrealDB Cloud)
-- ============================================================

-- ------------------------------------------------------------
-- receipt: 1レシート = 1レコード
-- ------------------------------------------------------------
DEFINE TABLE receipt SCHEMAFULL;

-- コア項目（MVP で利用）
DEFINE FIELD store_name        ON receipt TYPE string                ASSERT string::len($value) > 0;
DEFINE FIELD purchased_at      ON receipt TYPE datetime;
DEFINE FIELD total             ON receipt TYPE number                ASSERT $value >= 0;
DEFINE FIELD category          ON receipt TYPE string                DEFAULT "uncategorized";
DEFINE FIELD currency          ON receipt TYPE string                DEFAULT "JPY";

-- 補助項目（v2 以降で活用、MVP では null 許容）
DEFINE FIELD tax               ON receipt TYPE option<number>;
DEFINE FIELD payment_method    ON receipt TYPE option<string>;        -- cash | credit | emoney | other
DEFINE FIELD raw_text          ON receipt TYPE option<string>;
DEFINE FIELD confidence        ON receipt TYPE option<number>        ASSERT $value = NONE OR ($value >= 0 AND $value <= 1);

-- 画像
DEFINE FIELD image_key         ON receipt TYPE string;                -- R2 object key: receipts/yyyy/mm/{uuid}.webp
DEFINE FIELD image_hash        ON receipt TYPE string;                -- SHA-256 of compressed image, 重複検出

-- 運用メタ
DEFINE FIELD extractor_version ON receipt TYPE string;                -- ex: "gemini-3-flash-preview@prompt-v1"
DEFINE FIELD status            ON receipt TYPE string                DEFAULT "pending"
                                ASSERT $value IN ["pending", "confirmed", "rejected"];
DEFINE FIELD created_at        ON receipt TYPE datetime              DEFAULT time::now() READONLY;
DEFINE FIELD updated_at        ON receipt TYPE datetime              DEFAULT time::now() VALUE time::now();

-- インデックス
DEFINE INDEX receipt_purchased_at_idx ON receipt FIELDS purchased_at;
DEFINE INDEX receipt_category_idx     ON receipt FIELDS category;
DEFINE INDEX receipt_store_idx        ON receipt FIELDS store_name;
DEFINE INDEX receipt_status_idx       ON receipt FIELDS status;
DEFINE INDEX receipt_image_hash_uniq  ON receipt FIELDS image_hash UNIQUE;  -- 同一画像の二重登録防止
DEFINE INDEX receipt_dup_guard        ON receipt FIELDS store_name, purchased_at, total;  -- 近似重複検出用

-- 全文検索（v2: raw_text 検索）
-- SurrealDB 2.x の全文検索インデックス定義は SEARCH ANALYZER ではなく
-- FULLTEXT ANALYZER を使う。旧記法のままだと現行ドキュメントとズレる。
DEFINE ANALYZER receipt_ascii TOKENIZERS blank, class FILTERS lowercase, ascii;
DEFINE INDEX receipt_raw_text_ft ON TABLE receipt FIELDS raw_text FULLTEXT ANALYZER receipt_ascii BM25 HIGHLIGHTS;


-- ------------------------------------------------------------
-- receipt_item: 明細行（v2 で利用、MVP では未使用）
-- ------------------------------------------------------------
DEFINE TABLE receipt_item SCHEMAFULL;

DEFINE FIELD receipt    ON receipt_item TYPE record<receipt>;
DEFINE FIELD name       ON receipt_item TYPE string;
DEFINE FIELD qty        ON receipt_item TYPE number       DEFAULT 1    ASSERT $value > 0;
DEFINE FIELD unit_price ON receipt_item TYPE option<number>;
DEFINE FIELD price      ON receipt_item TYPE number                    ASSERT $value >= 0;
DEFINE FIELD category   ON receipt_item TYPE option<string>;
DEFINE FIELD created_at ON receipt_item TYPE datetime     DEFAULT time::now() READONLY;

DEFINE INDEX receipt_item_receipt_idx  ON receipt_item FIELDS receipt;
DEFINE INDEX receipt_item_category_idx ON receipt_item FIELDS category;


-- ------------------------------------------------------------
-- store_category_hint: 店舗→カテゴリの学習辞書
-- 確定レシートから蓄積し、次回プロンプトに few-shot として注入
-- ------------------------------------------------------------
DEFINE TABLE store_category_hint SCHEMAFULL;

DEFINE FIELD store_name ON store_category_hint TYPE string;
DEFINE FIELD category   ON store_category_hint TYPE string;
DEFINE FIELD count      ON store_category_hint TYPE number   DEFAULT 1;   -- 出現回数で上書き優先度を決める
DEFINE FIELD updated_at ON store_category_hint TYPE datetime DEFAULT time::now() VALUE time::now();

DEFINE INDEX store_category_hint_uniq ON store_category_hint FIELDS store_name UNIQUE;


-- ============================================================
-- 参考クエリ
-- ============================================================

-- 月別合計
-- SELECT
--   time::format(purchased_at, "%Y-%m") AS month,
--   math::sum(total) AS total
-- FROM receipt
-- WHERE status = "confirmed"
-- GROUP BY month
-- ORDER BY month DESC;

-- カテゴリ別合計（直近30日）
-- SELECT category, math::sum(total) AS total, count() AS n
-- FROM receipt
-- WHERE status = "confirmed" AND purchased_at > time::now() - 30d
-- GROUP BY category
-- ORDER BY total DESC;

-- 近似重複チェック
-- SELECT * FROM receipt
-- WHERE store_name = $store AND purchased_at = $at AND total = $total;

-- 明細つきレシート取得（v2）
-- SELECT *, (SELECT * FROM receipt_item WHERE receipt = $parent.id) AS items
-- FROM receipt:⟨id⟩;
