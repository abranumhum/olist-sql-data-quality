-- 03_cleaning.sql
-- Build typed tables for safe analysis while leaving raw source data unchanged.
-- Suspicious business events remain visible; this layer does not "fix" them.
-- DISTINCT ON is used only where an analytical table needs one deterministic row
-- per business key (orders, payments, and reviews).
BEGIN;

-- Typed orders: parse timestamps and keep one deterministic row per order_id.
CREATE TABLE analytics.orders AS
SELECT
    load_row_id AS row_id,
    order_id,
    customer_id,
    order_status,
    CASE WHEN order_purchase_timestamp ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
         THEN order_purchase_timestamp::timestamp END AS order_purchase_timestamp,
    CASE WHEN order_approved_at ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
         THEN order_approved_at::timestamp END AS order_approved_at,
    CASE WHEN order_delivered_carrier_date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
         THEN order_delivered_carrier_date::timestamp END AS order_delivered_carrier_date,
    CASE WHEN order_delivered_customer_date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
         THEN order_delivered_customer_date::timestamp END AS order_delivered_customer_date,
    CASE WHEN order_estimated_delivery_date ~ '^\d{4}-\d{2}-\d{2}( \d{2}:\d{2}:\d{2})?$'
         THEN order_estimated_delivery_date::timestamp::date END AS order_estimated_delivery_date
FROM (
    SELECT DISTINCT ON (order_id)
           load_row_id, order_id, customer_id, order_status,
           order_purchase_timestamp, order_approved_at,
           order_delivered_carrier_date, order_delivered_customer_date,
           order_estimated_delivery_date
    FROM raw.orders
    WHERE order_id IS NOT NULL AND trim(order_id) IS NOT NULL
    ORDER BY order_id, load_row_id
) dedup
WHERE order_purchase_timestamp ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- Typed line items: one row per (order_id, order_item_id).
CREATE TABLE analytics.order_items AS
SELECT
    load_row_id AS row_id,
    order_id,
    order_item_id::integer AS order_item_id,
    product_id, seller_id,
    CASE WHEN shipping_limit_date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
         THEN shipping_limit_date::timestamp END AS shipping_limit_date,
    price::numeric(12,2) AS price,
    freight_value::numeric(12,2) AS freight_value
FROM (
    SELECT DISTINCT ON (order_id, order_item_id)
           load_row_id, order_id, order_item_id, product_id, seller_id,
           shipping_limit_date, price, freight_value
    FROM raw.order_items
    WHERE order_id IS NOT NULL
      AND product_id IS NOT NULL
      AND order_item_id IS NOT NULL
      AND order_item_id ~ '^\d+$'
    ORDER BY order_id, order_item_id, load_row_id
) dedup;

-- Typed payments: one row per (order_id, payment_sequential).
CREATE TABLE analytics.payments AS
SELECT
    load_row_id AS row_id,
    order_id,
    payment_sequential::integer AS payment_sequential,
    payment_type,
    payment_installments::integer AS payment_installments,
    payment_value::numeric(12,2) AS payment_value
FROM (
    SELECT DISTINCT ON (order_id, payment_sequential)
           load_row_id, order_id, payment_sequential, payment_type, payment_installments, payment_value
    FROM raw.payments
    WHERE order_id IS NOT NULL AND payment_sequential IS NOT NULL
      AND payment_sequential ~ '^\d+$'
    ORDER BY order_id, payment_sequential, load_row_id
) dedup;

-- Analytical reviews: one deterministic review row per order.
-- The 551 additional source rows remain documented in dq_summary.
CREATE TABLE analytics.reviews AS
SELECT
    review_id,
    order_id,
    review_score::integer AS review_score,
    COALESCE(NULLIF(trim(review_comment_title), ''), NULL) AS review_comment_title,
    COALESCE(NULLIF(trim(review_comment_message), ''), NULL) AS review_comment_message,
    CASE WHEN review_creation_date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
         THEN review_creation_date::timestamp END AS review_creation_date,
    CASE WHEN review_answer_timestamp ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
         THEN review_answer_timestamp::timestamp END AS review_answer_timestamp
FROM (
    SELECT DISTINCT ON (order_id)
           review_id, order_id, review_score, review_comment_title,
           review_comment_message, review_creation_date, review_answer_timestamp
    FROM raw.reviews
    WHERE order_id IS NOT NULL
    ORDER BY order_id, load_row_id
) dedup;

-- Typed product attributes. Missing categories/dimensions remain NULL.
CREATE TABLE analytics.products AS
SELECT
    product_id,
    product_category_name,
    product_name_length::integer AS product_name_length,
    product_description_length::integer AS product_description_length,
    product_photos_qty::integer AS product_photos_qty,
    product_weight_g::numeric(12,2) AS product_weight_g,
    product_length_cm::numeric(8,2) AS product_length_cm,
    product_height_cm::numeric(8,2) AS product_height_cm,
    product_width_cm::numeric(8,2) AS product_width_cm
FROM raw.products
WHERE product_id IS NOT NULL;

-- Customer identifiers used for order and repeat-customer analysis.
CREATE TABLE analytics.customers AS
SELECT
    customer_id, customer_unique_id,
    customer_zip_code_prefix, customer_city, customer_state
FROM raw.customers
WHERE customer_id IS NOT NULL;

-- Seller dimension for analysis.
CREATE TABLE analytics.sellers AS
SELECT
    seller_id, seller_zip_code_prefix, seller_city, seller_state
FROM raw.sellers
WHERE seller_id IS NOT NULL;

-- Product category translations (pt → en)
CREATE TABLE analytics.categories AS
SELECT product_category_name, product_category_name_english
FROM raw.category_translation
WHERE product_category_name IS NOT NULL;

-- Constraints
ALTER TABLE analytics.orders
    ADD PRIMARY KEY (order_id),
    ALTER COLUMN customer_id SET NOT NULL,
    ALTER COLUMN order_status SET NOT NULL;

ALTER TABLE analytics.order_items
    ADD PRIMARY KEY (row_id);

ALTER TABLE analytics.payments
    ADD PRIMARY KEY (row_id);

ALTER TABLE analytics.reviews
    ADD PRIMARY KEY (order_id);

CREATE INDEX idx_orders_customer ON analytics.orders (customer_id);
CREATE INDEX idx_orders_status ON analytics.orders (order_status);
CREATE INDEX idx_orders_purchase ON analytics.orders (order_purchase_timestamp);
CREATE INDEX idx_items_order ON analytics.order_items (order_id);
CREATE INDEX idx_items_product ON analytics.order_items (product_id);
CREATE INDEX idx_items_seller ON analytics.order_items (seller_id);
CREATE INDEX idx_payments_order ON analytics.payments (order_id);

COMMIT;
