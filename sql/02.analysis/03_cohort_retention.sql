-- Monthly cohort retention aligned with the dashboard cohort view.

-- Question: What share of each acquisition cohort purchases in each observed month?
-- All order statuses, valid purchase timestamps, and distinct people per active month.
-- Month 0 is 100%; observed months without activity are zero. Future months are absent.
-- The cutoff is the latest purchase month in the extract, not evidence of complete monthly coverage.
WITH RECURSIVE customer_orders AS (
    SELECT 
        c.customer_unique_id,
        CAST(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS DATE) AS order_month
    
    FROM olist_orders_dataset o
    
    JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
    
    WHERE o.order_purchase_timestamp IS NOT NULL
),
observation_end AS (
    SELECT 
        MAX(order_month) AS last_month 
    FROM customer_orders
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
        COUNT(*) AS cohort_customers
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
        
        COUNT(DISTINCT co.customer_unique_id) AS active_customers
    
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
    
    cs.cohort_customers, 
    COALESCE(ca.active_customers, 0) AS active_customers,
    
    ROUND(100.0 * COALESCE(ca.active_customers, 0) / NULLIF(cs.cohort_customers, 0), 2) AS retention_pct

FROM cohort_months cm

JOIN cohort_sizes cs 
    ON cm.cohort_month = cs.cohort_month

LEFT JOIN cohort_activity ca 
    ON cm.cohort_month = ca.cohort_month
    AND cm.activity_month = ca.order_month

    ORDER BY cm.cohort_month, months_since_first_purchase;

