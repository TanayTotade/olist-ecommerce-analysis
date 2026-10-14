-- Regional concentration, purchasing behavior and delivery performance.

-- cumulative revenue concentration by state

WITH order_revenue AS (
    SELECT
        o.order_id,
        c.customer_state,
        SUM(oi.price) AS order_revenue
    FROM olist_orders_dataset AS o
    JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items_dataset AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY
        o.order_id,
        c.customer_state
),

state_revenue AS (
    SELECT
        customer_state,
        COUNT(*) AS total_orders,
        SUM(order_revenue) AS revenue
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

-- regional purchasing behavior

WITH order_revenue AS (
    SELECT
        o.order_id,
        c.customer_unique_id,
        c.customer_state,
        SUM(oi.price) AS order_revenue
    FROM olist_orders_dataset AS o
    JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items_dataset AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
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
        SUM(order_revenue) AS revenue
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
        revenue / orders,
        2
    ) AS avg_order_value

FROM state_behavior
ORDER BY revenue_per_customer DESC;

-- delivery performance by state

SELECT
    c.customer_state,

    COUNT(*) AS delivered_orders,

    ROUND(
        AVG(
            TIMESTAMPDIFF(
                HOUR,
                o.order_purchase_timestamp,
                o.order_delivered_customer_date
            )
        ) / 24,
        2
    ) AS avg_delivery_days,

    SUM(
        o.order_delivered_customer_date >
        o.order_estimated_delivery_date
    ) AS late_orders,

    ROUND(
        SUM(
            o.order_delivered_customer_date >
            o.order_estimated_delivery_date
        ) * 100.0 / COUNT(*),
        2
    ) AS late_delivery_pct

FROM olist_orders_dataset AS o

JOIN olist_customers_dataset AS c
    ON o.customer_id = c.customer_id

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL

GROUP BY c.customer_state

ORDER BY avg_delivery_days DESC;
