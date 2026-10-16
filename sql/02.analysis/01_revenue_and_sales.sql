-- Product-only sales baseline and monthly revenue trend.


-- Revenue Baseline
-- Question: What are product sales and average value per order with items?
-- SUM(price) excludes freight; no order-status filter is applied.
-- Distinct order IDs prevent multiple items from inflating the AOV denominator.
SELECT
    ROUND(SUM(price), 2) AS total_revenue,
    COUNT(DISTINCT order_id) AS orders_with_items,
    ROUND(
        SUM(price) / COUNT(DISTINCT order_id),
        2
    ) AS average_order_value
FROM olist_order_items_dataset;

-- Monthly_revenue_trend
-- Question: How do product sales change by purchase month?
-- Only orders with matching item records contribute; missing months are not filled.
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
    ROUND(SUM(oi.price), 2) AS revenue,
    COUNT(DISTINCT o.order_id) AS orders
FROM olist_orders_dataset AS o
JOIN olist_order_items_dataset AS oi
    ON o.order_id = oi.order_id
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY month;
