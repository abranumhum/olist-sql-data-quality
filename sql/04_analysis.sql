-- 04_analysis.sql
-- Business analysis queries on the typed analytical layer.
-- Olist order_items is at line-item grain: one product/seller row within an order.
BEGIN;

-- 1. Monthly sales trend (use date_trunc for indexability)
CREATE TABLE analytics.kpi_summary AS
SELECT
    count(DISTINCT o.order_id)::integer AS total_orders,
    count(oi.order_id)::integer AS total_line_items,
    round(sum(oi.price + oi.freight_value), 2) AS total_revenue,
    round(sum(oi.price), 2) AS total_product_sales,
    round(sum(oi.freight_value), 2) AS total_freight,
    round(sum(oi.price + oi.freight_value) / count(DISTINCT o.order_id), 2) AS average_order_value
FROM analytics.orders o
JOIN analytics.order_items oi ON o.order_id = oi.order_id
WHERE o.order_status IN ('delivered', 'shipped', 'invoiced', 'processing');

-- 2. Monthly sales trend
CREATE TABLE analytics.monthly_sales AS
SELECT
    to_char(o.order_purchase_timestamp, 'YYYY-MM') AS month,
    count(DISTINCT o.order_id)::integer AS orders,
    count(*)::integer AS line_items,
    round(sum(oi.price + oi.freight_value), 2) AS total_revenue,
    round(sum(oi.price), 2) AS product_sales,
    round(sum(oi.freight_value), 2) AS freight
FROM analytics.orders o
JOIN analytics.order_items oi ON o.order_id = oi.order_id
WHERE o.order_status IN ('delivered', 'shipped', 'invoiced', 'processing')
  AND o.order_purchase_timestamp IS NOT NULL
GROUP BY to_char(o.order_purchase_timestamp, 'YYYY-MM')
ORDER BY month;

-- 3. Top 10 product categories by revenue
CREATE TABLE analytics.category_performance AS
SELECT
    COALESCE(c.product_category_name_english, p.product_category_name) AS category,
    count(DISTINCT o.order_id)::integer AS orders,
    count(*)::integer AS line_items,
    round(sum(oi.price + oi.freight_value), 2) AS total_revenue,
    round(avg(oi.price + oi.freight_value), 2) AS avg_line_item_value,
    round(avg(r.review_score), 2) AS avg_review_score
FROM analytics.order_items oi
JOIN analytics.orders o ON oi.order_id = o.order_id
LEFT JOIN analytics.products p ON oi.product_id = p.product_id
LEFT JOIN analytics.categories c ON p.product_category_name = c.product_category_name
LEFT JOIN analytics.reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY COALESCE(c.product_category_name_english, p.product_category_name)
ORDER BY total_revenue DESC
LIMIT 10;

-- 4. Top 10 sellers by revenue
CREATE TABLE analytics.seller_performance AS
SELECT
    s.seller_id,
    s.seller_city,
    s.seller_state,
    count(DISTINCT o.order_id)::integer AS orders,
    count(*)::integer AS line_items,
    round(sum(oi.price + oi.freight_value), 2) AS total_revenue,
    round(avg(oi.price + oi.freight_value), 2) AS avg_item_value
FROM analytics.order_items oi
JOIN analytics.orders o ON oi.order_id = o.order_id
JOIN analytics.sellers s ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id, s.seller_city, s.seller_state
ORDER BY total_revenue DESC
LIMIT 10;

-- 5. Repeat customer summary.
-- customer_id identifies one order; customer_unique_id identifies the person.
CREATE TABLE analytics.repeat_customer_summary AS
SELECT
    CASE
        WHEN order_count = 1 THEN 'One-time'
        WHEN order_count <= 5 THEN '2-5 orders'
        WHEN order_count <= 20 THEN '6-20 orders'
        ELSE '20+ orders'
    END AS customer_segment,
    count(*)::integer AS customers,
    round(avg(order_count), 1) AS avg_orders_per_customer,
    round(sum(total_spent), 2) AS total_revenue,
    round(avg(total_spent), 2) AS avg_customer_lifetime_value
FROM (
    SELECT c.customer_unique_id,
           count(DISTINCT o.order_id) AS order_count,
           sum(oi.price + oi.freight_value) AS total_spent
    FROM analytics.orders o
    JOIN analytics.customers c ON o.customer_id = c.customer_id
    JOIN analytics.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) cust
GROUP BY customer_segment
ORDER BY min(order_count);

-- 6. Order value distribution. Aggregate line items to order grain first.
CREATE TABLE analytics.order_value_distribution AS
SELECT
    CASE
        WHEN order_value <= 50 THEN '0-50 BRL'
        WHEN order_value <= 100 THEN '50-100 BRL'
        WHEN order_value <= 200 THEN '100-200 BRL'
        WHEN order_value <= 500 THEN '200-500 BRL'
        WHEN order_value <= 1000 THEN '500-1000 BRL'
        ELSE '1000+ BRL'
    END AS price_bucket,
    count(*)::integer AS orders,
    round(sum(order_value), 2) AS total_revenue,
    round(avg(order_value), 2) AS avg_order_value
FROM (
    SELECT oi.order_id, sum(oi.price + oi.freight_value) AS order_value
    FROM analytics.order_items oi
    JOIN analytics.orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.order_id
) order_totals
GROUP BY price_bucket
ORDER BY min(order_value);

-- 7. Payment method analysis
CREATE TABLE analytics.payment_method_summary AS
SELECT
    payment_type,
    count(DISTINCT order_id)::integer AS orders,
    count(*)::integer AS payment_entries,
    round(sum(payment_value), 2) AS total_revenue,
    round(avg(payment_value), 2) AS avg_payment,
    round(avg(payment_installments), 1) AS avg_installments
FROM analytics.payments
GROUP BY payment_type
ORDER BY total_revenue DESC;

-- 8. Delivery time vs review score
CREATE TABLE analytics.delivery_review_summary AS
SELECT
    r.review_score,
    count(*)::integer AS order_count,
    round(avg(extract(epoch FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400), 1) AS avg_delivery_days
FROM analytics.orders o
JOIN analytics.reviews r ON o.order_id = r.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
  AND o.order_purchase_timestamp IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score;

-- 9. Five orders with largest estimated vs actual delivery gap
CREATE TABLE analytics.worst_delivery_delays AS
SELECT
    o.order_id,
    o.customer_id,
    extract(day FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date)) AS days_early_or_late,
    o.order_purchase_timestamp,
    o.order_estimated_delivery_date,
    o.order_delivered_customer_date
FROM analytics.orders o
WHERE o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
ORDER BY abs(extract(day FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date))) DESC
LIMIT 5;

-- 10. Source-vs-analytical row and value preservation check.
CREATE TABLE analytics.business_summary AS
SELECT
    metric_name,
    source_value,
    analytical_value,
    round(source_value - analytical_value, 2) AS difference,
    round(100 * (source_value - analytical_value) / nullif(analytical_value, 0), 2) AS difference_pct
FROM (
    SELECT
        'total_sales' AS metric_name,
        sum(price::numeric + freight_value::numeric) AS source_value,
        (SELECT sum(price + freight_value) FROM analytics.order_items) AS analytical_value
    FROM raw.order_items
    WHERE price ~ '^-?[0-9]+\.?[0-9]*$'
      AND freight_value ~ '^-?[0-9]+\.?[0-9]*$'
    UNION ALL
    SELECT 'total_line_items',
           count(*),
           (SELECT count(*) FROM analytics.order_items)
    FROM raw.order_items
    UNION ALL
    SELECT 'total_orders',
           count(DISTINCT order_id),
           (SELECT count(DISTINCT order_id) FROM analytics.orders)
    FROM raw.orders
) reconciliation
ORDER BY metric_name;

COMMIT;
