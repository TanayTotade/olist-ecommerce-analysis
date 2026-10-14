-- Original regional, seller and category risk views.

-- State Performance View

CREATE OR REPLACE VIEW vw_state_performance AS

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
-- 2. SALES METRICS BY STATE
-- =========================================================
state_sales AS (
    SELECT
        c.customer_state,
        COUNT(DISTINCT o.order_id) AS total_orders,
        COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
        SUM(COALESCE(r.order_revenue, 0)) AS total_revenue
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id
    LEFT JOIN order_revenue r
        ON o.order_id = r.order_id
    GROUP BY c.customer_state
),

-- =========================================================
-- 3. VALID DELIVERY ORDERS
-- Same chronological validation used in
-- vw_delivery_performance
-- =========================================================
valid_deliveries AS (
    SELECT
        o.order_id,
        c.customer_state,
        
        TIMESTAMPDIFF(
            SECOND,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) / 86400.0 AS delivery_days,

        CASE
            WHEN o.order_delivered_customer_date >
                 o.order_estimated_delivery_date
            THEN 1
            ELSE 0
        END AS is_late

    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id

    WHERE o.order_status = 'delivered'

      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_approved_at IS NOT NULL
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL

      -- chronological validation
      AND o.order_approved_at >= o.order_purchase_timestamp
      AND o.order_delivered_carrier_date >= o.order_approved_at
      AND o.order_delivered_customer_date >=
          o.order_delivered_carrier_date
),

-- =========================================================
-- 4. DELIVERY METRICS BY STATE
-- =========================================================
state_delivery AS (
    SELECT
        customer_state,
        COUNT(*) AS valid_delivered_orders,
        AVG(delivery_days) AS avg_delivery_days,
        AVG(is_late) * 100 AS late_delivery_pct
    FROM valid_deliveries
    GROUP BY customer_state
),

-- =========================================================
-- 5. DEDUPLICATE REVIEWS
-- Keep latest review per order
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

deduplicated_reviews AS (
    SELECT
        order_id,
        review_score
    FROM ranked_reviews
    WHERE rn = 1
),

-- =========================================================
-- 6. REVIEW METRICS BY STATE
-- =========================================================
state_reviews AS (
    SELECT
        c.customer_state,
        COUNT(*) AS reviewed_orders,
        AVG(r.review_score) AS avg_review_score,

        AVG(
            CASE
                WHEN r.review_score <= 2 THEN 1
                ELSE 0
            END
        ) * 100 AS negative_review_pct

    FROM deduplicated_reviews r
    JOIN olist_orders_dataset o
        ON r.order_id = o.order_id
    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id

    GROUP BY c.customer_state
)

-- =========================================================
-- 7. FINAL STATE-LEVEL VIEW
-- =========================================================
SELECT
    s.customer_state,

    -- Sales
    s.total_orders,
    s.unique_customers,
    ROUND(s.total_revenue, 2) AS total_revenue,

    ROUND(
        s.total_revenue /
        SUM(s.total_revenue) OVER () * 100,
        2
    ) AS revenue_share_pct,

    -- Delivery
    d.valid_delivered_orders,
    ROUND(d.avg_delivery_days, 2) AS avg_delivery_days,
    ROUND(d.late_delivery_pct, 2) AS late_delivery_pct,

    -- Satisfaction
    r.reviewed_orders,
    ROUND(r.avg_review_score, 2) AS avg_review_score,
    ROUND(r.negative_review_pct, 2) AS negative_review_pct

FROM state_sales s

LEFT JOIN state_delivery d
    ON s.customer_state = d.customer_state

LEFT JOIN state_reviews r
    ON s.customer_state = r.customer_state;

-- Seller Performance View

CREATE OR REPLACE VIEW vw_seller_performance AS

WITH
-- =========================================================
-- 1. SELLER-ORDER LEVEL
-- Prevent multiple items from the same seller/order
-- from multiplying order-based metrics.
-- =========================================================
seller_orders AS (
    SELECT
        seller_id,
        order_id,
        SUM(price + freight_value) AS seller_revenue
    FROM olist_order_items_dataset
    GROUP BY
        seller_id,
        order_id
),

-- =========================================================
-- 2. LATEST REVIEW PER ORDER
-- Same review methodology as vw_review_performance.
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

deduplicated_reviews AS (
    SELECT
        order_id,
        review_score
    FROM ranked_reviews
    WHERE rn = 1
),

-- =========================================================
-- 3. SELLER METRICS
-- =========================================================
seller_metrics AS (
    SELECT
        so.seller_id,

        COUNT(DISTINCT so.order_id) AS total_orders,

        SUM(so.seller_revenue) AS total_revenue,

        -- Purchase -> carrier handoff
        AVG(
            CASE
                WHEN o.order_purchase_timestamp IS NOT NULL
                 AND o.order_delivered_carrier_date IS NOT NULL
                 AND o.order_delivered_carrier_date >=
                     o.order_purchase_timestamp

                THEN TIMESTAMPDIFF(
                    SECOND,
                    o.order_purchase_timestamp,
                    o.order_delivered_carrier_date
                ) / 86400.0
            END
        ) AS avg_dispatch_days,

        -- Late delivery rate
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

    LEFT JOIN deduplicated_reviews r
        ON so.order_id = r.order_id

    GROUP BY
        so.seller_id
),

-- =========================================================
-- 4. SELLER BENCHMARKS
-- =========================================================
seller_benchmarks AS (
    SELECT
        AVG(total_orders) AS avg_total_orders,
        AVG(avg_dispatch_days) AS avg_dispatch_days,
        AVG(late_delivery_pct) AS avg_late_delivery_pct,
        AVG(avg_review_score) AS avg_review_score,
        AVG(negative_review_pct) AS avg_negative_review_pct

    FROM seller_metrics
),

-- =========================================================
-- 5. SCORE EACH SELLER AGAINST BENCHMARKS
-- =========================================================
seller_scores AS (
    SELECT
        s.*,

        (
            CASE
                WHEN s.total_orders < b.avg_total_orders
                THEN 1 ELSE 0
            END
            +
            CASE
                WHEN s.avg_dispatch_days > b.avg_dispatch_days
                THEN 1 ELSE 0
            END
            +
            CASE
                WHEN s.late_delivery_pct > b.avg_late_delivery_pct
                THEN 1 ELSE 0
            END
            +
            CASE
                WHEN s.avg_review_score < b.avg_review_score
                THEN 1 ELSE 0
            END
            +
            CASE
                WHEN s.negative_review_pct >
                     b.avg_negative_review_pct
                THEN 1 ELSE 0
            END
        ) AS underperforming_kpis

    FROM seller_metrics s

    CROSS JOIN seller_benchmarks b
)

-- =========================================================
-- 6. FINAL SELLER VIEW
-- =========================================================
SELECT
    seller_id,

    total_orders,

    ROUND(total_revenue, 2)
        AS total_revenue,

    ROUND(avg_dispatch_days, 2)
        AS avg_dispatch_days,

    ROUND(late_delivery_pct, 2)
        AS late_delivery_pct,

    ROUND(avg_review_score, 2)
        AS avg_review_score,

    ROUND(negative_review_pct, 2)
        AS negative_review_pct,

    underperforming_kpis,

    CASE
        WHEN underperforming_kpis >= 4
            THEN 'High Performance Risk'
        ELSE 'Normal'
    END AS seller_segment

FROM seller_scores;

-- Seller Risk View

CREATE OR REPLACE VIEW vw_seller_risk_impact AS

WITH single_seller_orders AS (
    SELECT
        order_id,
        MIN(seller_id) AS seller_id
    FROM olist_order_items_dataset
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),

order_reviews AS (
    SELECT
        order_id,
        AVG(review_score) AS review_score
    FROM olist_order_reviews_dataset
    GROUP BY order_id
),

order_data AS (
    SELECT
        o.order_id,
        sso.seller_id,

        CASE
            WHEN sp.seller_segment = 'High Performance Risk'
                THEN 'Risky seller'
            ELSE 'Normal seller'
        END AS seller_risk,

        CASE
            WHEN o.order_delivered_customer_date
                 <= o.order_estimated_delivery_date
                THEN 'On Time / Early'
            ELSE 'Late'
        END AS delivery_status,

        r.review_score

    FROM olist_orders_dataset o

    INNER JOIN single_seller_orders sso
        ON o.order_id = sso.order_id

    INNER JOIN vw_seller_performance sp
        ON sso.seller_id = sp.seller_id

    INNER JOIN order_reviews r
        ON o.order_id = r.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)

SELECT
    delivery_status,
    seller_risk,

    COUNT(*) AS reviewed_orders,

    ROUND(
        AVG(review_score),
        2
    ) AS avg_review_score,

    SUM(
        CASE
            WHEN review_score <= 2 THEN 1
            ELSE 0
        END
    ) AS negative_reviews,

    ROUND(
        100.0 *
        SUM(
            CASE
                WHEN review_score <= 2 THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS negative_review_pct

FROM order_data

GROUP BY
    delivery_status,
    seller_risk;

-- Category Risk View

CREATE OR REPLACE VIEW vw_category_risk_impact AS

WITH order_reviews AS (
    SELECT
        order_id,
        AVG(review_score) AS review_score
    FROM olist_order_reviews_dataset
    GROUP BY order_id
),

single_category_orders AS (
    SELECT
        oi.order_id,
        MIN(p.product_category_name) AS category_name
    FROM olist_order_items_dataset oi

    INNER JOIN olist_products_dataset p
        ON oi.product_id = p.product_id

    WHERE p.product_category_name IS NOT NULL

    GROUP BY oi.order_id

    HAVING COUNT(DISTINCT p.product_category_name) = 1
),

category_performance AS (
    SELECT
        sco.category_name,

        COUNT(*) AS reviewed_orders,

        AVG(r.review_score) AS avg_review_score,

        100.0 *
        SUM(
            CASE
                WHEN r.review_score <= 2 THEN 1
                ELSE 0
            END
        ) / COUNT(*) AS negative_review_pct

    FROM single_category_orders sco

    INNER JOIN order_reviews r
        ON sco.order_id = r.order_id

    GROUP BY sco.category_name
),

category_benchmark AS (
    SELECT
        100.0 *
        SUM(
            CASE
                WHEN review_score <= 2 THEN 1
                ELSE 0
            END
        ) / COUNT(*) AS overall_negative_review_pct

    FROM order_reviews
),

classified_categories AS (
    SELECT
        cp.category_name,

        CASE
            WHEN cp.negative_review_pct >
                 cb.overall_negative_review_pct
                THEN 'High-risk category'
            ELSE 'Normal category'
        END AS category_risk

    FROM category_performance cp
    CROSS JOIN category_benchmark cb
),

order_data AS (
    SELECT
        o.order_id,

        cc.category_risk,

        CASE
            WHEN o.order_delivered_customer_date
                 <= o.order_estimated_delivery_date
                THEN 'On Time / Early'
            ELSE 'Late'
        END AS delivery_status,

        r.review_score

    FROM olist_orders_dataset o

    INNER JOIN single_category_orders sco
        ON o.order_id = sco.order_id

    INNER JOIN classified_categories cc
        ON sco.category_name = cc.category_name

    INNER JOIN order_reviews r
        ON o.order_id = r.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)

SELECT
    delivery_status,
    category_risk,

    COUNT(*) AS reviewed_orders,

    ROUND(
        AVG(review_score),
        2
    ) AS avg_review_score,

    SUM(
        CASE
            WHEN review_score <= 2 THEN 1
            ELSE 0
        END
    ) AS negative_reviews,

    ROUND(
        100.0 *
        SUM(
            CASE
                WHEN review_score <= 2 THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS negative_review_pct

FROM order_data

GROUP BY
    delivery_status,
    category_risk;
