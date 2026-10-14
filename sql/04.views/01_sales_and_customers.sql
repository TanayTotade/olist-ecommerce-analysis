-- Original sales and customer dashboard views.

-- Monthly Sales View

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

-- Category Sales View

CREATE OR REPLACE VIEW vw_category_sales AS

SELECT
    COALESCE(t.product_category_name_english, 'Unknown') AS category_name,

    COUNT(DISTINCT oi.order_id) AS total_orders,

    ROUND(
        SUM(oi.price + oi.freight_value),
        2
    ) AS total_revenue,

    COUNT(DISTINCT o.customer_id) AS unique_customers,

    COUNT(DISTINCT oi.product_id) AS unique_products,

    COUNT(*) AS items_sold,

    ROUND(
        AVG(oi.price),
        2
    ) AS avg_item_price

FROM olist_order_items_dataset oi

JOIN olist_orders_dataset o
    ON oi.order_id = o.order_id

JOIN olist_products_dataset p
    ON oi.product_id = p.product_id

LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name

GROUP BY
    COALESCE(t.product_category_name_english, 'Unknown');

-- Customer Segments View

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

-- Customer Retention View

CREATE OR REPLACE VIEW vw_customer_retention AS

WITH
-- =========================================================
-- 1. CUSTOMER ORDER HISTORY
--
-- customer_unique_id identifies the actual customer.
-- customer_id identifies an order-specific customer record.
-- =========================================================
customer_order_history AS (
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

-- =========================================================
-- 2. CUSTOMERS REACHING EACH ORDER NUMBER
-- =========================================================
retention_counts AS (
    SELECT
        order_number,

        COUNT(DISTINCT customer_unique_id)
            AS customers_reaching_order

    FROM customer_order_history

    GROUP BY
        order_number
),

-- =========================================================
-- 3. TOTAL CUSTOMER BASE
--
-- Everyone with a valid purchase timestamp has order #1.
-- =========================================================
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

-- =========================================================
-- 4. FINAL RETENTION CURVE
-- =========================================================
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

-- Cohort Retention View

CREATE OR REPLACE VIEW vw_cohort_retention AS

WITH customer_orders AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS order_month
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id
    WHERE o.order_purchase_timestamp IS NOT NULL
),

customer_first_purchase AS (
    SELECT
        customer_unique_id,
        MIN(order_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_unique_id
),

customer_activity AS (
    SELECT DISTINCT
        co.customer_unique_id,
        fp.cohort_month,
        co.order_month,
        
        TIMESTAMPDIFF(
            MONTH,
            fp.cohort_month,
            co.order_month
        ) AS months_since_first_purchase
        
    FROM customer_orders co
    JOIN customer_first_purchase fp
        ON co.customer_unique_id = fp.customer_unique_id
),

cohort_activity AS (
    SELECT
        cohort_month,
        months_since_first_purchase,
        COUNT(DISTINCT customer_unique_id) AS retained_customers
    FROM customer_activity
    GROUP BY
        cohort_month,
        months_since_first_purchase
),

cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM customer_first_purchase
    GROUP BY cohort_month
)

SELECT
    ca.cohort_month,
    ca.months_since_first_purchase,
    cs.cohort_size,
    ca.retained_customers,
    
    ROUND(
        100.0 * ca.retained_customers / cs.cohort_size,
        2
    ) AS retention_pct

FROM cohort_activity ca
JOIN cohort_sizes cs
    ON ca.cohort_month = cs.cohort_month

ORDER BY
    ca.cohort_month,
    ca.months_since_first_purchase;
