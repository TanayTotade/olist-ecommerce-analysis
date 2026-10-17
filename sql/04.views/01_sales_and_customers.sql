-- Sales and customer dashboard views with shared metric definitions.

-- Dashboard monthly sales: all statuses; freight included; AOV excludes missing item values.
CREATE OR REPLACE VIEW vw_monthly_sales AS

WITH order_revenue AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_revenue
    FROM olist_order_items_dataset
    GROUP BY order_id
)

SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS purchase_month,

    COUNT(DISTINCT o.order_id) AS total_orders,

    ROUND(
        SUM(COALESCE(r.order_revenue, 0)),
        2
    ) AS total_revenue,

    ROUND(
        AVG(r.order_revenue),
        2
    ) AS avg_order_value

FROM olist_orders_dataset o

LEFT JOIN order_revenue r
    ON o.order_id = r.order_id

GROUP BY
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01');

-- Dashboard category sales: count distinct people, not order-specific customer records.
-- Multi-category customer/order counts overlap.
CREATE OR REPLACE VIEW vw_category_sales AS

SELECT
    COALESCE(t.product_category_name_english, 'Unknown') AS category_name,

    COUNT(DISTINCT oi.order_id) AS total_orders,

    ROUND(
        SUM(oi.price + oi.freight_value),
        2
    ) AS total_revenue,

    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,

    COUNT(DISTINCT oi.product_id) AS unique_products,

    COUNT(*) AS items_sold,

    ROUND(
        AVG(oi.price),
        2
    ) AS avg_item_price

FROM olist_order_items_dataset oi

JOIN olist_orders_dataset o
    ON oi.order_id = o.order_id

JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id

JOIN olist_products_dataset p
    ON oi.product_id = p.product_id

LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name

GROUP BY
    COALESCE(t.product_category_name_english, 'Unknown');

-- Dashboard customer segments: all statuses; item-plus-freight revenue.
CREATE OR REPLACE VIEW vw_customer_segments AS

WITH order_revenue AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_revenue
    FROM olist_order_items_dataset
    GROUP BY order_id
),

customer_metrics AS (
    SELECT
        c.customer_unique_id,

        COUNT(DISTINCT o.order_id) AS total_orders,

        SUM(COALESCE(r.order_revenue, 0)) AS total_revenue

    FROM olist_customers_dataset c

    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id

    LEFT JOIN order_revenue r
        ON o.order_id = r.order_id

    GROUP BY
        c.customer_unique_id
),

customer_segments AS (
    SELECT
        customer_unique_id,
        total_orders,
        total_revenue,

        CASE
            WHEN total_orders = 1 THEN 'One-time Customer'
            ELSE 'Repeat Customer'
        END AS customer_segment

    FROM customer_metrics
)

SELECT
    customer_segment,

    COUNT(*) AS unique_customers,

    SUM(total_orders) AS total_orders,

    ROUND(SUM(total_revenue), 2) AS total_revenue,

    ROUND(AVG(total_orders), 2) AS avg_orders_per_customer,

    ROUND(AVG(total_revenue), 2) AS avg_revenue_per_customer,

    ROUND(
        COUNT(*) /
        SUM(COUNT(*)) OVER () * 100,
        2
    ) AS customer_share_pct,
 
    ROUND(
        SUM(total_revenue) /
        SUM(SUM(total_revenue)) OVER () * 100,
        2
    ) AS revenue_share_pct

FROM customer_segments

GROUP BY
    customer_segment;

-- Dashboard purchase-number retention: all statuses with purchase timestamps.
CREATE OR REPLACE VIEW vw_customer_retention AS

WITH customer_order_history AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,

        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY
                o.order_purchase_timestamp,
                o.order_id
        ) AS order_number

    FROM olist_orders_dataset o

    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id

    WHERE o.order_purchase_timestamp IS NOT NULL
),
retention_counts AS (
    SELECT
        order_number,

        COUNT(DISTINCT customer_unique_id)
            AS customers_reaching_order

    FROM customer_order_history

    GROUP BY
        order_number
),
customer_base AS (
    SELECT
        MAX(
            CASE
                WHEN order_number = 1
                THEN customers_reaching_order
            END
        ) AS total_customers

    FROM retention_counts
)
SELECT
    r.order_number,

    r.customers_reaching_order,

    ROUND(
        r.customers_reaching_order * 100.0 /
        NULLIF(b.total_customers, 0),
        2
    ) AS retention_pct

FROM retention_counts r

CROSS JOIN customer_base b;

-- Dashboard cohort retention: explicit zero activity within the observed month range.
-- Future months are absent; endpoint months may have incomplete coverage.
CREATE OR REPLACE VIEW vw_cohort_retention AS
    
WITH RECURSIVE customer_orders AS (
    SELECT 
        c.customer_unique_id,
        
        CAST(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS DATE) AS order_month
    
    FROM olist_orders_dataset o
    
    JOIN olist_customers_dataset c 
        ON o.customer_id = c.customer_id
    
    WHERE o.order_purchase_timestamp IS NOT NULL
),
observation_end AS (
    SELECT MAX(order_month) AS last_month FROM customer_orders
),
customer_first_purchase AS (
    SELECT 
        customer_unique_id, 
        MIN(order_month) AS cohort_month
    
    FROM customer_orders 
    GROUP BY customer_unique_id
),
cohort_sizes AS (
    SELECT 
        cohort_month, 
        COUNT(*) AS cohort_size
    
    FROM customer_first_purchase 
    GROUP BY cohort_month
),
cohort_months AS (
    SELECT 
        cohort_month, 
        cohort_month AS activity_month
    FROM cohort_sizes
    
    UNION ALL
    
    SELECT 
        cm.cohort_month, 
        cm.activity_month + INTERVAL 1 MONTH
    
    FROM cohort_months cm 
    
    CROSS JOIN observation_end e
    
    WHERE cm.activity_month + INTERVAL 1 MONTH <= e.last_month
),
cohort_activity AS (
    SELECT 
        fp.cohort_month, 
        co.order_month,
        
        COUNT(DISTINCT co.customer_unique_id) AS retained_customers
    
    FROM customer_orders co
    
    JOIN customer_first_purchase fp 
        ON co.customer_unique_id = fp.customer_unique_id
    
    GROUP BY fp.cohort_month, co.order_month
)
SELECT 
    cm.cohort_month,
    
    TIMESTAMPDIFF(
        MONTH, 
        cm.cohort_month, 
        cm.activity_month) AS months_since_first_purchase,
    
    cs.cohort_size, 
    COALESCE(ca.retained_customers, 0) AS retained_customers,
    
    ROUND(
        100.0 * COALESCE(ca.retained_customers, 0) / 
        NULLIF(cs.cohort_size, 0), 2) AS retention_pct

FROM cohort_months cm

JOIN cohort_sizes cs 
    ON cm.cohort_month = cs.cohort_month

LEFT JOIN cohort_activity ca 
    ON cm.cohort_month = ca.cohort_month
    AND cm.activity_month = ca.order_month

ORDER BY cm.cohort_month, months_since_first_purchase;

