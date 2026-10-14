-- Products, category value and volume, freight, concentration, monthly growth and repeat purchases.

WITH product_sales AS (
    SELECT
        oi.product_id,
        p.product_category_name,
        COUNT(*) AS items_sold,
        SUM(oi.price) AS product_revenue
    FROM olist_order_items_dataset oi
    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id
    GROUP BY
        oi.product_id,
        p.product_category_name
),
ranked_products AS (
    SELECT
        product_id,
        product_category_name,
        items_sold,
        ROUND(product_revenue, 2) AS revenue,
        ROW_NUMBER() OVER (
            PARTITION BY product_category_name
            ORDER BY product_revenue DESC
        ) AS product_rank
    FROM product_sales
)
SELECT
    product_category_name,
    product_id,
    items_sold,
    revenue,
    product_rank
FROM ranked_products
WHERE product_rank <= 3
ORDER BY
    product_category_name,
    product_rank;

WITH category_performance AS (
    SELECT
        p.product_category_name,
        COUNT(*) AS items_sold,
        SUM(oi.price) AS revenue
    FROM olist_order_items_dataset oi
    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id
    GROUP BY p.product_category_name
),

category_shares AS (
    SELECT
        product_category_name,
        items_sold,
        revenue,
        items_sold / SUM(items_sold) OVER () * 100 AS volume_share_pct,
        revenue / SUM(revenue) OVER () * 100 AS revenue_share_pct
    FROM category_performance
)

SELECT
    product_category_name,
    items_sold,
    ROUND(revenue, 2) AS revenue,
    ROUND(volume_share_pct, 2) AS volume_share_pct,
    ROUND(revenue_share_pct, 2) AS revenue_share_pct,
    ROUND(revenue_share_pct - volume_share_pct, 2) AS revenue_volume_gap_pct,

    CASE
        WHEN revenue_share_pct > volume_share_pct
            THEN 'Revenue-heavy'
        WHEN revenue_share_pct < volume_share_pct
            THEN 'Volume-heavy'
        ELSE 'Balanced'
    END AS category_pattern

FROM category_shares
ORDER BY revenue_volume_gap_pct DESC;

SELECT
    p.product_category_name,
    COUNT(*) AS items_sold,
    ROUND(SUM(oi.price), 2) AS product_revenue,
    ROUND(SUM(oi.freight_value), 2) AS total_freight,
    ROUND(AVG(oi.price), 2) AS avg_item_price,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight,
    ROUND(
        SUM(oi.freight_value) / SUM(oi.price) * 100,
        2
    ) AS freight_to_product_pct
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p
    ON oi.product_id = p.product_id	
GROUP BY p.product_category_name
ORDER BY freight_to_product_pct DESC;

WITH product_revenue AS (
    SELECT
        p.product_category_name,
        oi.product_id,
        SUM(oi.price) AS product_revenue
    FROM olist_order_items_dataset oi
    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id
    WHERE p.product_category_name IS NOT NULL
    GROUP BY
        p.product_category_name,
        oi.product_id
),
ranked_products AS (
    SELECT
        product_category_name,
        product_id,
        product_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY product_category_name
            ORDER BY product_revenue DESC
        ) AS revenue_rank
    FROM product_revenue
)
SELECT
    product_category_name,
    COUNT(*) AS unique_products,
    ROUND(SUM(product_revenue), 2) AS category_revenue,
    ROUND(
        SUM(
            CASE
                WHEN revenue_rank <= 3
                THEN product_revenue
                ELSE 0
            END
        ) / SUM(product_revenue) * 100,
        2
    ) AS top_3_revenue_share_pct
FROM ranked_products
GROUP BY product_category_name
ORDER BY top_3_revenue_share_pct DESC;

-- MoM category growth

WITH RECURSIVE month_spine AS (

    SELECT
        CAST(
            DATE_FORMAT(
                MIN(order_purchase_timestamp),
                '%Y-%m-01'
            ) AS DATE
        ) AS month
    FROM olist_orders_dataset

    UNION ALL

    SELECT
        month + INTERVAL 1 MONTH
    FROM month_spine
    WHERE month + INTERVAL 1 MONTH <= (
        SELECT
            CAST(
                DATE_FORMAT(
                    MAX(order_purchase_timestamp),
                    '%Y-%m-01'
                ) AS DATE
            )
        FROM olist_orders_dataset
    )
),

categories AS (

    SELECT DISTINCT
        product_category_name
    FROM olist_products_dataset
    WHERE product_category_name IS NOT NULL

),

monthly_sales AS (

    SELECT
        CAST(
            DATE_FORMAT(
                o.order_purchase_timestamp,
                '%Y-%m-01'
            ) AS DATE
        ) AS month,

        p.product_category_name,

        COUNT(*) AS items_sold,
        SUM(oi.price) AS revenue

    FROM olist_orders_dataset o

    JOIN olist_order_items_dataset oi
        ON o.order_id = oi.order_id

    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id

    WHERE p.product_category_name IS NOT NULL

    GROUP BY
        CAST(
            DATE_FORMAT(
                o.order_purchase_timestamp,
                '%Y-%m-01'
            ) AS DATE
        ),
        p.product_category_name
),

complete_series AS (

    SELECT
        ms.month,
        c.product_category_name,

        COALESCE(s.items_sold, 0) AS items_sold,
        COALESCE(s.revenue, 0) AS revenue

    FROM month_spine ms

    CROSS JOIN categories c

    LEFT JOIN monthly_sales s
        ON ms.month = s.month
        AND c.product_category_name = s.product_category_name
),
category_growth AS (

    SELECT
        month,
        product_category_name,
        items_sold,
        revenue,

        LAG(revenue) OVER (
            PARTITION BY product_category_name
            ORDER BY month
        ) AS previous_month_revenue

    FROM complete_series
)

SELECT
    month,
    product_category_name,
    items_sold,

    ROUND(revenue, 2) AS revenue,
    ROUND(previous_month_revenue, 2) AS previous_month_revenue,

    ROUND(
        (revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0) * 100,
        2
    ) AS mom_growth_pct

FROM category_growth

ORDER BY
    product_category_name,
    month;

-- repeat customer rate by category

WITH customer_category_behavior AS (

    SELECT
        c.customer_unique_id,
        p.product_category_name,

        COUNT(DISTINCT o.order_id) AS category_orders

    FROM olist_customers_dataset c

    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id

    JOIN olist_order_items_dataset oi
        ON o.order_id = oi.order_id

    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id

    WHERE p.product_category_name IS NOT NULL

    GROUP BY
        c.customer_unique_id,
        p.product_category_name
)

SELECT
    product_category_name,

    COUNT(*) AS unique_customers,

    SUM(
        CASE
            WHEN category_orders > 1 THEN 1
            ELSE 0
        END
    ) AS repeat_customers,

    ROUND(
        SUM(
            CASE
                WHEN category_orders > 1 THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS repeat_customer_pct

FROM customer_category_behavior

GROUP BY product_category_name

ORDER BY repeat_customer_pct DESC;

WITH order_review AS (
    SELECT
        order_id,
        AVG(review_score) AS order_review_score
    FROM olist_order_reviews_dataset
    GROUP BY order_id
),

order_categories AS (
    SELECT DISTINCT
        oi.order_id,
        p.product_category_name
    FROM olist_order_items_dataset oi

    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id

    WHERE p.product_category_name IS NOT NULL
),

category_reviews AS (
    SELECT
        oc.product_category_name,

        COUNT(*) AS reviewed_orders,

        AVG(orv.order_review_score) AS avg_review_score

    FROM order_categories oc

    JOIN order_review orv
        ON oc.order_id = orv.order_id

    GROUP BY oc.product_category_name
),

category_sales AS (
    SELECT
        p.product_category_name,

        COUNT(*) AS items_sold,
        SUM(oi.price) AS revenue

    FROM olist_order_items_dataset oi

    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id

    WHERE p.product_category_name IS NOT NULL

    GROUP BY p.product_category_name
)

SELECT
    cs.product_category_name,

    cs.items_sold,

    ROUND(cs.revenue, 2)
        AS revenue,

    cr.reviewed_orders,

    ROUND(cr.avg_review_score, 2)
        AS avg_review_score

FROM category_sales cs

LEFT JOIN category_reviews cr
    ON cs.product_category_name =
       cr.product_category_name

ORDER BY cs.revenue DESC;
