-- Exploratory on-time complaint risk comparisons at unique reviewed-order grain.

-- Question: Does negative feedback persist for sellers even when delivery is on time?
-- Single-seller eligible deliveries; one latest review per order.
-- Risk: 50+ on-time reviewed orders and at least 15% negative; exclude insufficient history.
-- This exploratory threshold differs intentionally from the dashboard seller-risk heuristic.
-- Classification and comparison use the same historical sample; this is not predictive validation.
WITH valid_deliveries AS (
    SELECT 
        o.*,
        TIMESTAMPDIFF(
            SECOND, 
            o.order_approved_at, o.order_delivered_carrier_date
        ) / 86400.0 AS stage_dispatch_days,
    
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
    SELECT 
        r.*, 
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY r.review_answer_timestamp DESC, 
                     r.review_row_id DESC
    ) AS review_rank
    
    FROM olist_order_reviews_dataset r
),
order_reviews AS (
    SELECT * FROM ranked_reviews WHERE review_rank = 1
),
single_seller_orders AS (
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

        COUNT(*) AS on_time_reviewed_orders,

        SUM(
            CASE
                WHEN r.review_score <= 2 THEN 1
                ELSE 0
            END
        ) AS on_time_negative_reviews

    FROM single_seller_orders sso

    JOIN valid_deliveries o
        ON sso.order_id = o.order_id

    JOIN order_reviews r
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
            WHEN on_time_reviewed_orders < 50
                THEN 'Insufficient history'

            WHEN 100.0 * on_time_negative_reviews /
                 on_time_reviewed_orders >= 15
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

    JOIN valid_deliveries o
        ON sso.order_id = o.order_id

    JOIN order_reviews r
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

-- Question: How do delivery outcome and category risk relate to negative feedback?
-- Only orders where every item resolves to one known, nonblank category.
-- Latest reviews and common eligible deliveries; require 100+ on-time reviewed orders.
-- High risk means >=12% on-time negative reviews, distinct from the dashboard category heuristic.
-- Descriptive same-sample associations do not establish causation.
WITH valid_deliveries AS (
    SELECT 
        o.*,
        TIMESTAMPDIFF(
            SECOND, 
            o.order_approved_at, o.order_delivered_carrier_date
        ) / 86400.0 AS stage_dispatch_days,
        
        CASE 
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 1 ELSE 0 
        END AS is_late
    
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
    SELECT 
        r.*, 
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY r.review_answer_timestamp DESC, 
                     r.review_row_id DESC
    ) AS review_rank
    
    FROM olist_order_reviews_dataset r
),
order_reviews AS (
    SELECT * FROM ranked_reviews WHERE review_rank = 1
),
single_category_orders AS (
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
       AND COUNT(*) = (SELECT COUNT(*) FROM olist_order_items_dataset all_items
                       WHERE all_items.order_id = oi.order_id)
),

category_performance AS (
    SELECT
        sco.product_category_name,

        COUNT(*) AS on_time_reviewed_orders,

        SUM(
            CASE
                WHEN r.review_score <= 2 THEN 1
                ELSE 0
            END
        ) AS on_time_negative_reviews

    FROM single_category_orders sco

    JOIN valid_deliveries o
        ON sco.order_id = o.order_id

    JOIN order_reviews r
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
            WHEN on_time_reviewed_orders < 100
                THEN 'Insufficient history'

            WHEN 100.0 * on_time_negative_reviews /
                 on_time_reviewed_orders >= 12
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

    JOIN valid_deliveries o
        ON sco.order_id = o.order_id

    JOIN order_reviews r
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

