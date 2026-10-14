-- Delivered-order cohort retention; distinct from all-status dashboard cohort view.

-- cohort retention %

WITH customer_first_purchase AS (
    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_purchase_date
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_FORMAT(
            cfp.first_purchase_date,
            '%Y-%m-01'
        ) AS cohort_month,
        DATE_FORMAT(
            o.order_purchase_timestamp,
            '%Y-%m-01'
        ) AS order_month
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    JOIN customer_first_purchase cfp
        ON c.customer_unique_id = cfp.customer_unique_id
    WHERE o.order_status = 'delivered'
),
cohort_activity AS (
    SELECT
        cohort_month,
        TIMESTAMPDIFF(
            MONTH,
            cohort_month,
            order_month
        ) AS months_since_first_purchase,
        COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM customer_orders
    GROUP BY
        cohort_month,
        order_month
),
cohort_sizes AS (
    SELECT
        cohort_month,
        active_customers AS cohort_customers
    FROM cohort_activity
    WHERE months_since_first_purchase = 0
)
SELECT
    ca.cohort_month,
    ca.months_since_first_purchase,
    ca.active_customers,
    cs.cohort_customers,
    ROUND(
        ca.active_customers /
        cs.cohort_customers * 100,
        2
    ) AS retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs
    ON ca.cohort_month = cs.cohort_month
ORDER BY
    ca.cohort_month,
    ca.months_since_first_purchase;
