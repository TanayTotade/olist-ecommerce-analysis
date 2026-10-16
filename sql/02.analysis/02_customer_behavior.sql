-- Customer mix, spend bands, repeat purchase value and purchase intervals.

-- One-time vs repeat customers

-- Identify people with customer_unique_id; customer_id identifies an order's customer record.
-- This first comparison includes all order statuses.
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

-- Customer revenue distribution
-- Question: How is delivered-order spending distributed across customers?
-- Spending includes item price plus freight; customers without delivered items are excluded.

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
		SUM(oi.price + oi.freight_value) AS total_revenue
	FROM olist_customers_dataset c 
	JOIN olist_orders_dataset o 
		ON c.customer_id = o.customer_id
	JOIN olist_order_items_dataset oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
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

-- One-time vs repeat customers comparison
-- Question: How do spending and order frequency differ between customer groups?
-- Here the group definition uses delivered orders only, unlike the first query.

WITH customer_summary AS (
	SELECT
		c.customer_unique_id,
		COUNT(DISTINCT o.order_id) AS orders,
		SUM(oi.price + oi.freight_value) AS total_revenue
	FROM olist_customers_dataset c 
	JOIN olist_orders_dataset o 
		ON c.customer_id = o.customer_id
	JOIN olist_order_items_dataset oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
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
    ROUND(AVG(orders), 2) AS avg_orders_per_customer
FROM customer_summary
GROUP BY customer_type;

-- Revenue contribution
-- Question: What share of delivered item-plus-freight revenue comes from each group?

WITH customer_summary AS (
	SELECT
		c.customer_unique_id,
		COUNT(DISTINCT o.order_id) AS orders,
		SUM(oi.price + oi.freight_value) AS revenue
	FROM olist_customers_dataset c 
	JOIN olist_orders_dataset o 
		ON c.customer_id = o.customer_id
	JOIN olist_order_items_dataset oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id		
),
customer_group AS (
	SELECT
		CASE
			WHEN orders = 1 THEN 'One-time'
			ELSE 'Repeat'
		END AS customer_type,
		COUNT(*) AS customers,
		SUM(revenue) AS total_revenue
	FROM customer_summary
    GROUP BY customer_type
)
SELECT
	customer_type,
    customers,
    total_revenue,
    ROUND(
		total_revenue / SUM(total_revenue) OVER() * 100,
        2
	) AS revenue_share_pct
FROM customer_group;

-- Summarizing repeat-purchase intervals
-- LAG compares consecutive delivered purchases for each person.
-- Each interval is one observation; frequent buyers can contribute multiple intervals.
-- DATEDIFF measures calendar-day differences.

WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        LAG(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS previous_purchase
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
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

-- first-to-second purchase behavior
-- Question: How long do returning customers take to place their second delivered order?
-- Customers without a second delivered order are excluded from these averages.

WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS order_number
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
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

-- Question: What share of buyers at purchase N reaches purchase N+1?
-- Uses delivered purchases; the inner join omits stages with no following stage.
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS order_number
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
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
    p2.customers AS customers_at_next_stage,
    ROUND(
        p2.customers / p1.customers * 100,
        2
    ) AS next_purchase_retention_pct
FROM purchase_counts p1
JOIN purchase_counts p2
    ON p2.order_number = p1.order_number + 1
ORDER BY p1.order_number;
