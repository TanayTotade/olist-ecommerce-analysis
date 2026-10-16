-- Seller commercial contribution, order failures and validated operational performance.
-- MySQL 8+. See docs/metric_definitions.md for shared definitions.

-- Question: How concentrated is item-plus-freight sales value among the top ten sellers?
-- All statuses; marketplace shares are calculated before filtering to the top ten.
WITH seller_revenue AS (
    SELECT
        seller_id, 
        SUM(price + freight_value) AS revenue
    FROM olist_order_items_dataset
    GROUP BY seller_id
),

seller_ranked AS (
    SELECT
        seller_id,
        revenue,
        ROW_NUMBER() OVER (
            ORDER BY revenue DESC
        ) AS seller_rank,

        SUM(revenue) OVER () AS total_revenue,

        SUM(revenue) OVER (
            ORDER BY revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_revenue

    FROM seller_revenue
)

SELECT
    seller_rank,
    seller_id,
    ROUND(revenue, 2) AS revenue,
    ROUND(revenue / total_revenue * 100, 2) AS revenue_pct,
    ROUND(cumulative_revenue / total_revenue * 100, 2)
        AS cumulative_revenue_pct
FROM seller_ranked
WHERE seller_rank<=10
ORDER BY seller_rank;

-- Question: Which established sellers have the highest order failure rates?
-- Distinct seller-order pairs; canceled/unavailable divided by all seller orders.
-- The 50-order minimum limits small samples; it is not the dashboard risk-classification rule.
WITH seller_orders AS (
    SELECT DISTINCT
        seller_id,
        order_id
    FROM olist_order_items_dataset
),

seller_status AS (
    SELECT
        so.seller_id,
        so.order_id,
        o.order_status
    FROM seller_orders so

    JOIN olist_orders_dataset o
        ON so.order_id = o.order_id
)

SELECT
    seller_id,

    COUNT(*) AS total_orders,

    SUM(order_status = 'delivered')
        AS delivered_orders,

    SUM(order_status = 'canceled')
        AS canceled_orders,

    SUM(order_status = 'unavailable')
        AS unavailable_orders,

    ROUND(
        SUM(order_status = 'canceled')
        / COUNT(*) * 100,
        2
    ) AS cancellation_pct,

    ROUND(
        SUM(order_status = 'unavailable')
        / COUNT(*) * 100,
        2
    ) AS unavailable_pct,

    ROUND(
        SUM(order_status IN ('canceled', 'unavailable'))
        / COUNT(*) * 100,
        2
    ) AS failed_order_pct

FROM seller_status

GROUP BY seller_id

HAVING COUNT(*) >= 50

ORDER BY failed_order_pct DESC;

-- Question: How do sellers with 50+ orders compare commercially and operationally?
-- Dispatch is approval to carrier on complete, chronological delivered orders.
-- Latest review per order; multi-seller orders attribute the same order outcome to each seller.
-- Revenue includes freight and all statuses; marketplace share uses all sellers.
-- Delivery and review averages exclude ineligible or missing observations separately.
WITH seller_orders AS (
    SELECT DISTINCT seller_id, order_id FROM olist_order_items_dataset
),
seller_commercial AS (
    SELECT seller_id, SUM(price + freight_value) AS total_revenue
    FROM olist_order_items_dataset GROUP BY seller_id
),
commercial_with_total AS (
    SELECT *, SUM(total_revenue) OVER () AS marketplace_revenue FROM seller_commercial
),
valid_deliveries AS (
    SELECT o.*,
        TIMESTAMPDIFF(SECOND, o.order_approved_at,
            o.order_delivered_carrier_date) / 86400.0 AS stage_dispatch_days,
        CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 1 ELSE 0 END AS is_late
    FROM olist_orders_dataset o
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_approved_at IS NOT NULL
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_approved_at >= o.order_purchase_timestamp
      AND o.order_delivered_carrier_date >= o.order_approved_at
      AND o.order_delivered_customer_date >= o.order_delivered_carrier_date
),
ranked_reviews AS (
    SELECT r.*, ROW_NUMBER() OVER (
        PARTITION BY r.order_id
        ORDER BY r.review_answer_timestamp DESC, r.review_row_id DESC
    ) AS review_rank
    FROM olist_order_reviews_dataset r
),
order_reviews AS (
    SELECT * FROM ranked_reviews WHERE review_rank = 1
),
seller_performance AS (
    SELECT so.seller_id, COUNT(*) AS total_orders,
        SUM(o.order_status = 'delivered') AS delivered_orders,
        AVG(vd.stage_dispatch_days) AS avg_dispatch_days,
        AVG(vd.is_late) * 100.0 AS late_delivery_pct,
        SUM(o.order_status IN ('canceled', 'unavailable')) * 100.0 / COUNT(*) AS failed_order_pct,
        AVG(r.review_score) AS avg_review_score,
        100.0 * SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(r.review_score), 0) AS negative_review_pct
    FROM seller_orders so
    JOIN olist_orders_dataset o ON so.order_id = o.order_id
    LEFT JOIN valid_deliveries vd ON so.order_id = vd.order_id
    LEFT JOIN order_reviews r ON so.order_id = r.order_id
    GROUP BY so.seller_id
)
SELECT sp.seller_id, sp.total_orders,
    ROUND(sc.total_revenue, 2) AS total_revenue,
    ROUND(sc.total_revenue * 100.0 / NULLIF(sc.marketplace_revenue, 0), 2) AS marketplace_revenue_pct,
    sp.delivered_orders,
    ROUND(sp.avg_dispatch_days, 2) AS avg_dispatch_days,
    ROUND(sp.late_delivery_pct, 2) AS late_delivery_pct,
    ROUND(sp.failed_order_pct, 2) AS failed_order_pct,
    ROUND(sp.avg_review_score, 2) AS avg_review_score,
    ROUND(sp.negative_review_pct, 2) AS negative_review_pct
FROM seller_performance sp
JOIN commercial_with_total sc ON sp.seller_id = sc.seller_id
WHERE sp.total_orders >= 50
ORDER BY total_revenue DESC;

