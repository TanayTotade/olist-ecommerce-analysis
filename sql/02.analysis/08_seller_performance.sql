-- Seller concentration, order failures and consolidated seller performance.

-- Seller Revenue Contribution

WITH seller_revenue AS (
    SELECT
        seller_id, 
        SUM(price) AS revenue
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

-- Seller Order failure rate

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

-- Seller Performance Table


WITH seller_orders AS (
    -- Establish one row per seller-order combination
    SELECT DISTINCT
        seller_id,
        order_id
    FROM olist_order_items_dataset
),

seller_commercial AS (
    -- Commercial performance for every seller
    SELECT
        seller_id,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(price) AS product_revenue
    FROM olist_order_items_dataset
    GROUP BY seller_id
),

commercial_with_total AS (
    -- Add total marketplace product revenue
    SELECT
        *,
        SUM(product_revenue) OVER () AS marketplace_revenue
    FROM seller_commercial
),

order_reviews AS (
    -- Reduce reviews to one row per order
    SELECT
        order_id,
        AVG(review_score) AS review_score
    FROM olist_order_reviews_dataset
    GROUP BY order_id
),

seller_metrics AS (
    SELECT
        so.seller_id,
        so.order_id,
        o.order_status,

        -- Time from approval until handoff to carrier
        CASE
            WHEN o.order_status = 'delivered'
                 AND o.order_approved_at IS NOT NULL
                 AND o.order_delivered_carrier_date IS NOT NULL
            THEN
                TIMESTAMPDIFF(
                    HOUR,
                    o.order_approved_at,
                    o.order_delivered_carrier_date
                ) / 24
        END AS dispatch_days,

        -- 1 = delivered late, 0 = delivered on time
        CASE
            WHEN o.order_status = 'delivered'
                 AND o.order_delivered_customer_date IS NOT NULL
                 AND o.order_estimated_delivery_date IS NOT NULL
            THEN
                o.order_delivered_customer_date >
                o.order_estimated_delivery_date
        END AS late_delivery,

        r.review_score

    FROM seller_orders so

    JOIN olist_orders_dataset o
        ON so.order_id = o.order_id

    LEFT JOIN order_reviews r
        ON so.order_id = r.order_id
),

seller_performance AS (
    SELECT
        seller_id,

        COUNT(*) AS total_orders,

        SUM(order_status = 'delivered')
            AS delivered_orders,

        ROUND(
            AVG(dispatch_days),
            2
        ) AS avg_dispatch_days,

        ROUND(
            AVG(late_delivery) * 100,
            2
        ) AS late_delivery_pct,

        ROUND(
            SUM(order_status IN ('canceled', 'unavailable'))
            / COUNT(*) * 100,
            2
        ) AS failed_order_pct,

        ROUND(
            AVG(review_score),
            2
        ) AS avg_review_score,

        ROUND(
            AVG(
                CASE
                    WHEN review_score <= 2 THEN 1
                    WHEN review_score IS NOT NULL THEN 0
                END
            ) * 100,
            2
        ) AS negative_review_pct

    FROM seller_metrics

    GROUP BY seller_id

    -- Only evaluate established sellers
    HAVING COUNT(*) >= 50
)

SELECT
    sp.seller_id,

    sp.total_orders,

    ROUND(
        sc.product_revenue,
        2
    ) AS product_revenue,

    ROUND(
        sc.product_revenue
        / sc.marketplace_revenue * 100,
        2
    ) AS marketplace_revenue_pct,

    sp.delivered_orders,
    sp.avg_dispatch_days,
    sp.late_delivery_pct,
    sp.failed_order_pct,
    sp.avg_review_score,
    sp.negative_review_pct

FROM seller_performance sp

JOIN commercial_with_total sc
    ON sp.seller_id = sc.seller_id

ORDER BY product_revenue DESC;
