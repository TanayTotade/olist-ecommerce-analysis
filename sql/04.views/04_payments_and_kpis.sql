-- Original payment and KPI views. Run after seller view file.

-- Payment Behavior View

CREATE OR REPLACE VIEW vw_payment_behavior AS

WITH payment_type_metrics AS (
    SELECT
        payment_type,

        COUNT(DISTINCT order_id) AS orders_using_method,

        ROUND(SUM(payment_value), 2) AS total_payment_value,

        ROUND(AVG(payment_value), 2) AS avg_payment_value

    FROM olist_order_payments_dataset

    WHERE payment_type <> 'not_defined'

    GROUP BY payment_type
),

total_orders AS (
    SELECT
        COUNT(DISTINCT order_id) AS all_paid_orders
    FROM olist_order_payments_dataset
    WHERE payment_type <> 'not_defined'
)

SELECT
    p.payment_type,

    p.orders_using_method,

    p.total_payment_value,

    p.avg_payment_value,

    ROUND(
        p.orders_using_method /
        t.all_paid_orders * 100,
        2
    ) AS order_usage_pct,

    ROUND(
        p.total_payment_value /
        SUM(p.total_payment_value) OVER () * 100,
        2
    ) AS payment_value_share_pct

FROM payment_type_metrics p

CROSS JOIN total_orders t;

-- KPI View

CREATE OR REPLACE VIEW vw_kpis AS

WITH
-- =========================================================
-- 1. ORDER-LEVEL REVENUE
-- =========================================================
order_revenue AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_revenue
    FROM olist_order_items_dataset
    GROUP BY order_id
),

-- =========================================================
-- 2. SALES KPIs
-- =========================================================
sales_metrics AS (
    SELECT
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(r.order_revenue) AS total_revenue,
        AVG(r.order_revenue) AS avg_order_value

    FROM olist_orders_dataset o

    LEFT JOIN order_revenue r
        ON o.order_id = r.order_id
),

-- =========================================================
-- 3. CUSTOMER ORDER COUNTS
-- =========================================================
customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders

    FROM olist_orders_dataset o

    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id

    GROUP BY
        c.customer_unique_id
),

-- =========================================================
-- 4. CUSTOMER KPIs
-- =========================================================
customer_metrics AS (
    SELECT
        COUNT(*) AS unique_customers,
        SUM(total_orders > 1) AS repeat_customers

    FROM customer_orders
),

-- =========================================================
-- 5. DELIVERY KPIs
--
-- Uses the same chronologically valid delivery population
-- as vw_delivery_performance.
-- Expected population: 95,082 orders
-- =========================================================
delivery_metrics AS (
    SELECT
        COUNT(*) AS delivered_orders,

        AVG(
            TIMESTAMPDIFF(
                SECOND,
                order_purchase_timestamp,
                order_delivered_customer_date
            ) / 86400.0
        ) AS avg_delivery_days,

        SUM(
            order_delivered_customer_date >
            order_estimated_delivery_date
        ) AS late_orders

    FROM olist_orders_dataset

    WHERE
        order_status = 'delivered'

        AND order_purchase_timestamp IS NOT NULL
        AND order_approved_at IS NOT NULL
        AND order_delivered_carrier_date IS NOT NULL
        AND order_delivered_customer_date IS NOT NULL
        AND order_estimated_delivery_date IS NOT NULL

        AND order_approved_at >= order_purchase_timestamp
        AND order_delivered_carrier_date >= order_approved_at
        AND order_delivered_customer_date >=
            order_delivered_carrier_date
),

-- =========================================================
-- 6. RANK REVIEWS
--
-- Some orders contain multiple review rows.
-- Keep the latest review for each order.
-- =========================================================
ranked_reviews AS (
    SELECT
        r.order_id,
        r.review_score,

        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY
                r.review_answer_timestamp DESC,
                r.review_row_id DESC
        ) AS rn

    FROM olist_order_reviews_dataset r
),

-- =========================================================
-- 7. DEDUPLICATED REVIEWS
-- Expected population: 98,672 reviewed orders
-- =========================================================
deduplicated_reviews AS (
    SELECT
        order_id,
        review_score

    FROM ranked_reviews

    WHERE rn = 1
),

-- =========================================================
-- 8. REVIEW KPIs
-- =========================================================
review_metrics AS (
    SELECT
        COUNT(*) AS reviewed_orders,
        AVG(review_score) AS avg_review_score,
        SUM(review_score <= 2) AS negative_reviews

    FROM deduplicated_reviews
),

-- =========================================================
-- 9. UNIQUE SELLER-ORDER COMBINATIONS
-- =========================================================
seller_orders AS (
    SELECT DISTINCT
        oi.seller_id,
        oi.order_id

    FROM olist_order_items_dataset oi
),

-- =========================================================
-- 10. ORDER-LEVEL REVIEW SCORE
--
-- TEMPORARILY retains the existing seller methodology.
-- We will reconcile this after vw_seller_performance
-- is created and validated.
-- =========================================================
order_reviews AS (
    SELECT
        order_id,
        AVG(review_score) AS review_score

    FROM olist_order_reviews_dataset

    GROUP BY
        order_id
),

-- =========================================================
-- 11. SELLER PERFORMANCE
-- =========================================================
seller_performance AS (
    SELECT
        so.seller_id,

        COUNT(DISTINCT so.order_id) AS total_orders,

        AVG(
            CASE
                WHEN o.order_delivered_carrier_date IS NOT NULL
                 AND o.order_purchase_timestamp IS NOT NULL

                THEN TIMESTAMPDIFF(
                    SECOND,
                    o.order_purchase_timestamp,
                    o.order_delivered_carrier_date
                ) / 86400.0
            END
        ) AS avg_dispatch_days,

        100.0 *
        SUM(
            CASE
                WHEN o.order_status = 'delivered'
                 AND o.order_delivered_customer_date IS NOT NULL
                 AND o.order_estimated_delivery_date IS NOT NULL
                 AND o.order_delivered_customer_date >
                     o.order_estimated_delivery_date

                THEN 1
                ELSE 0
            END
        )
        /
        NULLIF(
            SUM(
                CASE
                    WHEN o.order_status = 'delivered'
                     AND o.order_delivered_customer_date IS NOT NULL
                     AND o.order_estimated_delivery_date IS NOT NULL

                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS late_delivery_pct,

        AVG(r.review_score) AS avg_review_score,

        100.0 *
        SUM(
            CASE
                WHEN r.review_score <= 2
                THEN 1
                ELSE 0
            END
        )
        /
        NULLIF(
            COUNT(r.review_score),
            0
        ) AS negative_review_pct

    FROM seller_orders so

    JOIN olist_orders_dataset o
        ON so.order_id = o.order_id

    LEFT JOIN order_reviews r
        ON so.order_id = r.order_id

    GROUP BY
        so.seller_id
),

-- =========================================================
-- 12. SELLER BENCHMARKS
-- =========================================================
seller_benchmarks AS (
    SELECT
        AVG(total_orders) AS avg_total_orders,
        AVG(avg_dispatch_days) AS avg_dispatch_days,
        AVG(late_delivery_pct) AS avg_late_delivery_pct,
        AVG(avg_review_score) AS avg_review_score,
        AVG(negative_review_pct) AS avg_negative_review_pct

    FROM seller_performance
),

-- =========================================================
-- 13. SELLER RISK
-- =========================================================
seller_risk AS (
    SELECT
        sp.seller_id,

        (
            CASE
                WHEN sp.total_orders < b.avg_total_orders
                THEN 1
                ELSE 0
            END
            +
            CASE
                WHEN sp.avg_dispatch_days > b.avg_dispatch_days
                THEN 1
                ELSE 0
            END
            +
            CASE
                WHEN sp.late_delivery_pct > b.avg_late_delivery_pct
                THEN 1
                ELSE 0
            END
            +
            CASE
                WHEN sp.avg_review_score < b.avg_review_score
                THEN 1
                ELSE 0
            END
            +
            CASE
                WHEN sp.negative_review_pct >
                     b.avg_negative_review_pct
                THEN 1
                ELSE 0
            END
        ) AS underperforming_kpis

    FROM seller_performance sp

    CROSS JOIN seller_benchmarks b
),

-- =========================================================
-- 14. SELLER KPIs
-- =========================================================
seller_metrics AS (
    SELECT
        COUNT(*) AS active_sellers,

        SUM(
            seller_segment = 'High Performance Risk'
        ) AS high_risk_sellers

    FROM vw_seller_performance
)

-- =========================================================
-- 15. FINAL KPI OUTPUT
-- =========================================================
SELECT
    -- Revenue & Sales
    ROUND(s.total_revenue, 2)
        AS total_revenue,

    s.total_orders,

    ROUND(s.avg_order_value, 2)
        AS avg_order_value,

    -- Customers
    c.unique_customers,

    ROUND(
        c.repeat_customers * 100.0 /
        NULLIF(c.unique_customers, 0),
        2
    ) AS repeat_customer_rate_pct,

    -- Delivery
    ROUND(d.avg_delivery_days, 2)
        AS avg_delivery_days,

    ROUND(
        d.late_orders * 100.0 /
        NULLIF(d.delivered_orders, 0),
        2
    ) AS late_delivery_rate_pct,

    -- Customer Satisfaction
    ROUND(r.avg_review_score, 2)
        AS avg_review_score,

    ROUND(
        r.negative_reviews * 100.0 /
        NULLIF(r.reviewed_orders, 0),
        2
    ) AS negative_review_rate_pct,

    -- Sellers
    sm.active_sellers,

    sm.high_risk_sellers,

    ROUND(
        sm.high_risk_sellers * 100.0 /
        NULLIF(sm.active_sellers, 0),
        2
    ) AS high_risk_seller_rate_pct

FROM sales_metrics s

CROSS JOIN customer_metrics c
CROSS JOIN delivery_metrics d
CROSS JOIN review_metrics r
CROSS JOIN seller_metrics sm;
