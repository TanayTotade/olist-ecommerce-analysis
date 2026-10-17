-- Regional sales concentration and purchasing behavior; duplicate delivery query consolidated.

-- Question: How concentrated is item-plus-freight sales value across customer states?
-- All order statuses; retain orders without items in counts, with zero sales contribution.
WITH order_revenue AS (
    SELECT
        o.order_id,
        c.customer_state,
        SUM(oi.price + oi.freight_value) AS order_revenue
    
    FROM olist_orders_dataset AS o
    
    JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    
    LEFT JOIN olist_order_items_dataset AS oi
        ON o.order_id = oi.order_id
    
    GROUP BY
        o.order_id,
        c.customer_state
),

state_revenue AS (
    SELECT
        customer_state,
        COUNT(*) AS total_orders,
        SUM(COALESCE(order_revenue, 0)) AS revenue
    
    FROM order_revenue
    GROUP BY customer_state
),

state_metrics AS (
    SELECT
        customer_state,
        total_orders,
        revenue,

        revenue / SUM(revenue) OVER () * 100
            AS revenue_percentage

    FROM state_revenue
)

SELECT
    customer_state,
    total_orders,
    
    ROUND(revenue, 2) AS revenue,
    ROUND(revenue_percentage, 2) AS revenue_percentage,
    ROUND(
        SUM(revenue_percentage) OVER (
            ORDER BY revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        2
    ) AS cumulative_revenue_percentage

FROM state_metrics
ORDER BY revenue DESC;

-- Question: How do customer frequency and spending differ by state?
-- All order statuses; distinct people within each state. Revenue includes freight.
-- AOV excludes missing item values; orders-per-customer retains all orders.
-- See 05_delivery_performance.sql for the single authoritative supporting state-delivery query.
WITH order_revenue AS (
    SELECT
        o.order_id,
        c.customer_unique_id,
        c.customer_state,
        SUM(oi.price + oi.freight_value) AS order_revenue
    
    FROM olist_orders_dataset AS o
    
    JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    
    LEFT JOIN olist_order_items_dataset AS oi
        ON o.order_id = oi.order_id
    
    GROUP BY
        o.order_id,
        c.customer_unique_id,
        c.customer_state
),

state_behavior AS (
    SELECT
        customer_state,
        COUNT(DISTINCT customer_unique_id) AS customers,
        COUNT(*) AS orders,
    
        AVG(order_revenue) AS avg_item_order_value,
        SUM(COALESCE(order_revenue, 0)) AS revenue
    
    FROM order_revenue
    GROUP BY customer_state
)
SELECT
    customer_state,
    customers,
    orders,
    ROUND(revenue, 2) AS revenue,

    ROUND(
        orders / customers,
        2
    ) AS orders_per_customer,

    ROUND(
        revenue / customers,
        2
    ) AS revenue_per_customer,

    ROUND(
        avg_item_order_value,
        2
    ) AS avg_order_value

FROM state_behavior
ORDER BY revenue_per_customer DESC;

