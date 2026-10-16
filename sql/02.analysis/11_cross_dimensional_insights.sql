-- Original single-seller and single-category risk comparisons; definitions differ from dashboard risk views.

-- Original SQL retained without logic changes. See docs/query_provenance.md.

-- Defining Risky Sellers
-- Question: Does negative feedback persist for risky sellers even on on-time deliveries?
-- Restrict to single-seller orders to make seller attribution unambiguous.
-- Risk uses on-time review rows: 50+ required and >=15% negative (scores 1-2).
-- Direct review joins preserve multiple reviews per order despite order-based output aliases.
-- These are descriptive thresholds, not a predictive model or evidence of causation.
-- Final comparison excludes insufficient history; NULL estimates fall into the on-time ELSE branch.

WITH single_seller_orders AS (
    SELECT
        order_id,
        MIN(seller_id) AS seller_id
    FROM olist_order_items_dataset
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),

seller_performance AS (
    SELECT
        sso.seller_id,

        COUNT(*) AS on_time_orders,

        SUM(
            CASE
                WHEN r.review_score <= 2 THEN 1
                ELSE 0
            END
        ) AS on_time_negative_reviews

    FROM single_seller_orders sso

    JOIN olist_orders_dataset o
        ON sso.order_id = o.order_id

    JOIN olist_order_reviews_dataset r
        ON o.order_id = r.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_delivered_customer_date <=
          o.order_estimated_delivery_date

    GROUP BY sso.seller_id
),

seller_risk AS (
    SELECT
        seller_id,

        CASE
            WHEN on_time_orders < 50
                THEN 'Insufficient history'

            WHEN 100.0 * on_time_negative_reviews /
                 on_time_orders >= 15
                THEN 'Risky seller'

            ELSE 'Normal seller'

        END AS seller_risk

    FROM seller_performance
),

order_base AS (
    SELECT
        o.order_id,
        sso.seller_id,
        sr.seller_risk,

        CASE
            WHEN o.order_delivered_customer_date >
                 o.order_estimated_delivery_date
            THEN 'Late'
            ELSE 'On time / Early'
        END AS delivery_status,

        CASE
            WHEN r.review_score <= 2
            THEN 1
            ELSE 0
        END AS negative_review

    FROM single_seller_orders sso

    JOIN olist_orders_dataset o
        ON sso.order_id = o.order_id

    JOIN olist_order_reviews_dataset r
        ON o.order_id = r.order_id

    JOIN seller_risk sr
        ON sso.seller_id = sr.seller_id

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)

SELECT
    delivery_status,
    seller_risk,

    COUNT(*) AS reviewed_orders,

    SUM(negative_review) AS negative_reviews,

    ROUND(
        100.0 * SUM(negative_review) / COUNT(*),
        2
    ) AS negative_review_pct

FROM order_base

WHERE seller_risk <> 'Insufficient history'

GROUP BY
    delivery_status,
    seller_risk

ORDER BY
    CASE delivery_status
        WHEN 'On time / Early' THEN 1
        WHEN 'Late' THEN 2
    END,
    CASE seller_risk
        WHEN 'Normal seller' THEN 1
        WHEN 'Risky seller' THEN 2
    END;

-- Delivery Category Risk
-- Question: How do delivery outcome and category risk relate to negative feedback?
-- Keep orders with exactly one known, nonblank category after filtering item categories.
-- Risk uses on-time review rows: 100+ required and >=12% negative.
-- Counts remain at review-record grain; final results omit insufficient-history categories.

WITH single_category_orders AS (
    SELECT
        oi.order_id,
        MIN(p.product_category_name) AS product_category_name

    FROM olist_order_items_dataset oi

    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id

    WHERE p.product_category_name IS NOT NULL
      AND p.product_category_name <> ''

    GROUP BY oi.order_id

    HAVING COUNT(DISTINCT p.product_category_name) = 1
),

category_performance AS (
    SELECT
        sco.product_category_name,

        COUNT(*) AS on_time_orders,

        SUM(
            CASE
                WHEN r.review_score <= 2 THEN 1
                ELSE 0
            END
        ) AS on_time_negative_reviews

    FROM single_category_orders sco

    JOIN olist_orders_dataset o
        ON sco.order_id = o.order_id

    JOIN olist_order_reviews_dataset r
        ON o.order_id = r.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL

      AND o.order_delivered_customer_date
            <= o.order_estimated_delivery_date

    GROUP BY sco.product_category_name
),

category_risk AS (
    SELECT
        product_category_name,

        CASE
            WHEN on_time_orders < 100
                THEN 'Insufficient history'

            WHEN 100.0 * on_time_negative_reviews /
                 on_time_orders >= 12
                THEN 'High-risk category'

            ELSE 'Normal category'

        END AS category_risk

    FROM category_performance
),

order_base AS (
    SELECT
        o.order_id,
        sco.product_category_name,
        cr.category_risk,

        CASE
            WHEN o.order_delivered_customer_date >
                 o.order_estimated_delivery_date
                THEN 'Late'
            ELSE 'On time / Early'
        END AS delivery_status,

        CASE
            WHEN r.review_score <= 2
                THEN 1
            ELSE 0
        END AS negative_review

    FROM single_category_orders sco

    JOIN olist_orders_dataset o
        ON sco.order_id = o.order_id

    JOIN olist_order_reviews_dataset r
        ON o.order_id = r.order_id

    JOIN category_risk cr
        ON sco.product_category_name =
           cr.product_category_name

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)

SELECT
    delivery_status,
    category_risk,

    COUNT(*) AS reviewed_orders,

    SUM(negative_review) AS negative_reviews,

    ROUND(
        100.0 * SUM(negative_review) /
        COUNT(*),
        2
    ) AS negative_review_pct

FROM order_base

WHERE category_risk <> 'Insufficient history'

GROUP BY
    delivery_status,
    category_risk

ORDER BY
    CASE delivery_status
        WHEN 'On time / Early' THEN 1
        WHEN 'Late' THEN 2
    END,

    CASE category_risk
        WHEN 'Normal category' THEN 1
        WHEN 'High-risk category' THEN 2
    END;
