-- Customer counts, spending and purchase progression using all order statuses.

-- Question: How many people purchased once versus more than once?
-- Use customer_unique_id to link people across order-specific customer_id records.
SELECT
    CASE
        WHEN order_count = 1 THEN 'One-time'
        WHEN order_count > 1 THEN 'Repeat'
    END AS customer_type,
    COUNT(*) AS customers
FROM (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
) x
GROUP BY customer_type;

-- Question: How is customer spending distributed?
-- Includes freight and all order statuses; orders without item values contribute zero spending.
SELECT
	CASE
		WHEN total_revenue < 100 THEN '<100'
        WHEN total_revenue < 250 THEN '100 - 249.99'
        WHEN total_revenue < 500 THEN '250 - 499.99'
        WHEN total_revenue < 1000 THEN '500 - 999.99'
        ELSE '1000+'
    END AS revenue_segment,
	COUNT(*) AS customers,
    ROUND(SUM(total_revenue), 2) AS revenue
FROM (
	SELECT
		c.customer_unique_id,
		SUM(COALESCE(oi.price + oi.freight_value, 0)) AS total_revenue
	FROM olist_customers_dataset c 
	JOIN olist_orders_dataset o 
		ON c.customer_id = o.customer_id
	LEFT JOIN olist_order_items_dataset oi
		ON o.order_id = oi.order_id	
	GROUP BY c.customer_unique_id
) AS customer_revenue
GROUP BY revenue_segment
ORDER BY
	CASE revenue_segment
		WHEN '<100' THEN 1
        WHEN '100 - 249.99' THEN 2
        WHEN '250 - 499.99' THEN 3
        WHEN '500 - 999.99' THEN 4
        WHEN '1000+' THEN 5
    END;

-- Question: How do one-time and repeat customers differ in value and frequency?
-- Combines customer counts, average value, total value, revenue share and order frequency.
-- All order statuses; item-plus-freight revenue; distinct orders avoid item multiplication.
WITH customer_summary AS (
	SELECT
		c.customer_unique_id,
		COUNT(DISTINCT o.order_id) AS orders,
		SUM(COALESCE(oi.price + oi.freight_value, 0)) AS total_revenue
	FROM olist_customers_dataset c 
	JOIN olist_orders_dataset o 
		ON c.customer_id = o.customer_id
	LEFT JOIN olist_order_items_dataset oi
		ON o.order_id = oi.order_id	
	GROUP BY c.customer_unique_id		
)
SELECT
	CASE
		WHEN orders = 1 THEN 'One-time'
        ELSE 'Repeat'
	END AS customer_type,
    COUNT(*) AS customers,
    ROUND(AVG(total_revenue), 2) AS avg_total_revenue,
    ROUND(SUM(total_revenue), 2) AS total_revenue,
    ROUND(SUM(total_revenue) * 100.0 / NULLIF(SUM(SUM(total_revenue)) OVER (), 0), 2) AS revenue_share_pct,
    ROUND(AVG(orders), 2) AS avg_orders_per_customer
FROM customer_summary
GROUP BY customer_type;

-- Question: How long is the interval between consecutive purchases?
-- All order statuses with purchase timestamps; each interval is an observation, not each person.
-- DATEDIFF measures calendar days. Order ID breaks equal-timestamp ties.
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        LAG(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp, o.order_id
        ) AS previous_purchase
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    WHERE o.order_purchase_timestamp IS NOT NULL   
),
purchase_intervals AS (
    SELECT
        customer_unique_id,
        DATEDIFF(
            order_purchase_timestamp,
            previous_purchase
        ) AS days_between_orders
    FROM customer_orders
    WHERE previous_purchase IS NOT NULL
)
SELECT
    COUNT(*) AS repeat_purchase_intervals,
    ROUND(AVG(days_between_orders), 2) AS avg_days_between_orders,
    MIN(days_between_orders) AS min_days_between_orders,
    MAX(days_between_orders) AS max_days_between_orders
FROM purchase_intervals;

-- Question: How long do returning customers take to reach their second purchase?
-- All order statuses with timestamps; only customers reaching purchase 2 contribute.
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp, o.order_id
        ) AS order_number
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    WHERE o.order_purchase_timestamp IS NOT NULL    
),
first_second AS (
    SELECT
        customer_unique_id,
        MAX(
            CASE
                WHEN order_number = 1
                THEN order_purchase_timestamp
            END
        ) AS first_order,
        MAX(
            CASE
                WHEN order_number = 2
                THEN order_purchase_timestamp
            END
        ) AS second_order
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS repeat_customers,
    ROUND(
        AVG(DATEDIFF(second_order, first_order)),
        2
    ) AS avg_days_to_second_order,
    MIN(DATEDIFF(second_order, first_order))
        AS min_days_to_second_order,
    MAX(DATEDIFF(second_order, first_order))
        AS max_days_to_second_order
FROM first_second
WHERE second_order IS NOT NULL;

-- Question: What share of customers at purchase N reaches N+1?
-- All order statuses with timestamps. Retains the terminal stage with zero next-stage customers.
-- This is purchase-stage progression, not monthly cohort retention.
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp, o.order_id
        ) AS order_number
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    WHERE o.order_purchase_timestamp IS NOT NULL    
),
purchase_counts AS (
    SELECT
        order_number,
        COUNT(DISTINCT customer_unique_id) AS customers
    FROM customer_orders
    GROUP BY order_number
)
SELECT
    p1.order_number AS from_purchase,
    p1.customers AS customers_at_stage,
    COALESCE(p2.customers, 0) AS customers_at_next_stage,
    ROUND(
        COALESCE(p2.customers, 0) * 1.0 / p1.customers * 100,
        2
    ) AS next_purchase_retention_pct
FROM purchase_counts p1
LEFT JOIN purchase_counts p2
    ON p2.order_number = p1.order_number + 1
ORDER BY p1.order_number;

