-- Source row counts, relationships, and date coverage.

SELECT COUNT(*) AS customers
FROM olist_customers_dataset;

SELECT COUNT(*) AS orders
FROM olist_orders_dataset;

SELECT COUNT(*) AS order_items
FROM olist_order_items_dataset;

SELECT COUNT(*) AS payments
FROM olist_order_payments_dataset;

SELECT COUNT(*) AS reviews
FROM olist_order_reviews_dataset;

SELECT COUNT(*) AS products
FROM olist_products_dataset;

SELECT COUNT(*) AS orders_without_customer
FROM olist_orders_dataset o
LEFT JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

SELECT
    order_id,
    COUNT(DISTINCT customer_id) AS customer_count
FROM olist_orders_dataset
GROUP BY order_id
HAVING COUNT(DISTINCT customer_id) > 1;

SELECT COUNT(*) AS payments_without_order
FROM olist_order_payments_dataset p
LEFT JOIN olist_orders_dataset o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

SELECT COUNT(*) AS reviews_without_order
FROM olist_order_reviews_dataset r
LEFT JOIN olist_orders_dataset o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;

SELECT COUNT(*) AS items_without_product
FROM olist_order_items_dataset oi
LEFT JOIN olist_products_dataset p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

SELECT
    COUNT(*) AS order_items,
    COUNT(DISTINCT order_id) AS orders_with_items,
    COUNT(DISTINCT product_id) AS products_sold
FROM olist_order_items_dataset;

SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order
FROM olist_orders_dataset;

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS orders
FROM olist_orders_dataset
GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;
