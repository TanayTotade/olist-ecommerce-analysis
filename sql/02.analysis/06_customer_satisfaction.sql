-- Review distribution, monthly satisfaction, delay comparison and volume-filtered category ranking.

-- 1.Overall customer satisfaction

-- customer review distribution

SELECT
    review_score,
    COUNT(*) AS reviews,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS review_pct
FROM olist_order_reviews_dataset
GROUP BY review_score
ORDER BY review_score;

-- overall average review score

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

FROM olist_order_reviews_dataset;

-- Customer Satisfaction over Time

-- Monthly review performance

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

JOIN olist_order_reviews_dataset r
    ON o.order_id = r.order_id

GROUP BY
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')

ORDER BY
    purchase_month;

-- On-Time vs Late Reviews

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

FROM olist_orders_dataset o

JOIN olist_order_reviews_dataset r
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

-- Rank categories with meaningful volume

WITH order_categories AS (
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

JOIN olist_order_reviews_dataset r
    ON oc.order_id = r.order_id

GROUP BY
    oc.product_category_name

HAVING COUNT(*) >= 200

ORDER BY
    avg_review_score DESC;
