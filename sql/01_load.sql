-- 01_load.sql
-- Create schema and staging tables for all 9 Olist CSV files.
-- Source values remain unchanged; typing happens in 03_cleaning.sql.
BEGIN;

DROP SCHEMA IF EXISTS raw CASCADE;
DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA raw;
CREATE SCHEMA analytics;

CREATE TABLE raw.category_translation (
    load_row_id           bigint,
    product_category_name text,
    product_category_name_english text
);

CREATE TABLE raw.customers (
    load_row_id             bigint,
    customer_id             text,
    customer_unique_id      text,
    customer_zip_code_prefix text,
    customer_city           text,
    customer_state          text
);

CREATE TABLE raw.geolocation (
    load_row_id                bigint,
    geolocation_zip_code_prefix text,
    geolocation_lat            text,
    geolocation_lng            text,
    geolocation_city           text,
    geolocation_state          text
);

CREATE TABLE raw.orders (
    load_row_id                  bigint,
    order_id                     text,
    customer_id                  text,
    order_status                 text,
    order_purchase_timestamp     text,
    order_approved_at            text,
    order_delivered_carrier_date text,
    order_delivered_customer_date text,
    order_estimated_delivery_date text
);

CREATE TABLE raw.order_items (
    load_row_id      bigint,
    order_id         text,
    order_item_id    text,
    product_id       text,
    seller_id        text,
    shipping_limit_date text,
    price            text,
    freight_value    text
);

CREATE TABLE raw.payments (
    load_row_id        bigint,
    order_id           text,
    payment_sequential text,
    payment_type       text,
    payment_installments text,
    payment_value      text
);

CREATE TABLE raw.products (
    load_row_id              bigint,
    product_id               text,
    product_category_name    text,
    product_name_length      text,
    product_description_length text,
    product_photos_qty       text,
    product_weight_g         text,
    product_length_cm        text,
    product_height_cm        text,
    product_width_cm         text
);

CREATE TABLE raw.reviews (
    load_row_id            bigint,
    review_id              text,
    order_id               text,
    review_score           text,
    review_comment_title   text,
    review_comment_message text,
    review_creation_date   text,
    review_answer_timestamp text
);

CREATE TABLE raw.sellers (
    load_row_id      bigint,
    seller_id        text,
    seller_zip_code_prefix text,
    seller_city      text,
    seller_state     text
);

COMMIT;
