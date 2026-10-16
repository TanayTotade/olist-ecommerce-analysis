-- Order-level customer satisfaction using the latest review consistently.
-- MySQL 8+. See docs/metric_definitions.md for shared definitions.

-- Question: What is the distribution of latest scores across reviewed orders?
-- Latest answer timestamp wins; review_row_id breaks ties. One observation per order.
WITH ranked_reviews AS (
    SELECT r.*, ROW_NUMBER() OVER (
        PARTITION BY r.order_id
        ORDER BY r.review_answer_timestamp DESC, r.review_row_id DESC
    ) AS review_rank
    FROM olist_order_reviews_dataset r
),
order_reviews AS (
    SELECT * FROM ranked_reviews WHERE review_rank = 1
)
SELECT
    review_score,
    COUNT(*) AS reviews,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS review_pct
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;

-- Question: What are overall satisfaction levels?
-- Positive = 4-5, neutral = 3, negative = 1-2; denominator is reviewed orders.
WITH ranked_reviews AS (
    SELECT r.*, ROW_NUMBER() OVER (
        PARTITION BY r.order_id
        ORDER BY r.review_answer_timestamp DESC, r.review_row_id DESC
    ) AS review_rank
    FROM olist_order_reviews_dataset r
),
order_reviews AS (
    SELECT * FROM ranked_reviews WHERE review_rank = 1
)
SELECT
    COUNT(*) AS total_reviews,

    ROUND(AVG(review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN review_score >= 4 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS positive_review_pct,

    ROUND(
        SUM(CASE WHEN review_score = 3 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS neutral_review_pct,

    ROUND(
        SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS negative_review_pct

FROM order_reviews;

-- Question: How does satisfaction vary by purchase month?
-- All statuses; one latest review per order. Month refers to purchase, not review creation.
WITH ranked_reviews AS (
    SELECT r.*, ROW_NUMBER() OVER (
        PARTITION BY r.order_id
        ORDER BY r.review_answer_timestamp DESC, r.review_row_id DESC
    ) AS review_rank
    FROM olist_order_reviews_dataset r
),
order_reviews AS (
    SELECT * FROM ranked_reviews WHERE review_rank = 1
)
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS purchase_month,

    COUNT(*) AS reviews,

    ROUND(AVG(r.review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN r.review_score >= 4 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS positive_review_pct,

    ROUND(
        SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS negative_review_pct

FROM olist_orders_dataset o

JOIN order_reviews r
    ON o.order_id = r.order_id

GROUP BY
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')

ORDER BY
    purchase_month;

-- Question: How does satisfaction differ between on-time and late deliveries?
-- Uses the common complete, chronological delivery population and full timestamp comparison.
WITH valid_deliveries AS (
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
)
SELECT
    CASE
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
            THEN 'On Time'
        ELSE 'Late'
    END AS delivery_status,

    COUNT(*) AS reviews,

    ROUND(AVG(r.review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN r.review_score >= 4 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS positive_review_pct,

    ROUND(
        SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS negative_review_pct

FROM valid_deliveries o

JOIN order_reviews r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL

GROUP BY
    CASE
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
            THEN 'On Time'
        ELSE 'Late'
    END;

-- Question: Which categories have the strongest satisfaction with 200+ reviewed orders?
-- Distinct order-category pairs and latest reviews prevent item/review multiplication.
-- Multi-category orders contribute once to each category; the minimum limits small samples.
WITH ranked_reviews AS (
    SELECT r.*, ROW_NUMBER() OVER (
        PARTITION BY r.order_id
        ORDER BY r.review_answer_timestamp DESC, r.review_row_id DESC
    ) AS review_rank
    FROM olist_order_reviews_dataset r
),
order_reviews AS (
    SELECT * FROM ranked_reviews WHERE review_rank = 1
),
order_categories AS (
    SELECT DISTINCT
        oi.order_id,
        p.product_category_name
    FROM olist_order_items_dataset oi

    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id

    WHERE p.product_category_name IS NOT NULL
)

SELECT
    oc.product_category_name,
    COUNT(*) AS reviews,

    ROUND(AVG(r.review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN r.review_score >= 4 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS positive_review_pct,

    ROUND(
        SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
        / COUNT(*) * 100,
        2
    ) AS negative_review_pct

FROM order_categories oc

JOIN order_reviews r
    ON oc.order_id = r.order_id

GROUP BY
    oc.product_category_name

HAVING COUNT(*) >= 200

ORDER BY
    avg_review_score DESC;

