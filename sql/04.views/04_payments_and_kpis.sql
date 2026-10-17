-- Payment and KPI dashboard views. Run after the seller views.

-- Payment metrics: defined methods; usage shares overlap.
-- avg_payment_value now averages summed order-method values, not individual payment records.
CREATE OR REPLACE VIEW vw_payment_behavior AS

WITH order_payment_values AS (
    SELECT 
        order_id, 
        payment_type, 
        SUM(payment_value) AS payment_value
    
    FROM olist_order_payments_dataset
    
    WHERE payment_type <> 'not_defined'
    GROUP BY order_id, payment_type
),
payment_type_metrics AS (
    SELECT
        payment_type,

        COUNT(DISTINCT order_id) AS orders_using_method,

        ROUND(SUM(payment_value), 2) AS total_payment_value,

        ROUND(AVG(payment_value), 2) AS avg_payment_value

    FROM order_payment_values

    WHERE payment_type <> 'not_defined'

    GROUP BY payment_type
),

total_orders AS (
    SELECT
        COUNT(DISTINCT order_id) AS all_paid_orders
    
    FROM olist_order_payments_dataset
    WHERE payment_type <> 'not_defined'
)

SELECT
    p.payment_type,

    p.orders_using_method,

    p.total_payment_value,

    p.avg_payment_value,

    ROUND(
        p.orders_using_method /
        t.all_paid_orders * 100,
        2
    ) AS order_usage_pct,

    ROUND(
        p.total_payment_value /
        SUM(p.total_payment_value) OVER () * 100,
        2
    ) AS payment_value_share_pct

FROM payment_type_metrics p

CROSS JOIN total_orders t;

-- KPI view: shared sales, latest-review and chronological delivery definitions.
-- Seller KPIs read vw_seller_performance directly; unused alternative risk CTEs removed.
CREATE OR REPLACE VIEW vw_kpis AS

WITH order_revenue AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_revenue
    
    FROM olist_order_items_dataset
    GROUP BY order_id
),
sales_metrics AS (
    SELECT
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(r.order_revenue) AS total_revenue,
        AVG(r.order_revenue) AS avg_order_value

    FROM olist_orders_dataset o

    LEFT JOIN order_revenue r
        ON o.order_id = r.order_id
),
customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders

    FROM olist_orders_dataset o

    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id

    GROUP BY
        c.customer_unique_id
),
customer_metrics AS (
    SELECT
        COUNT(*) AS unique_customers,
        SUM(total_orders > 1) AS repeat_customers

    FROM customer_orders
),
delivery_metrics AS (
    SELECT
        COUNT(*) AS delivered_orders,

        AVG(
            TIMESTAMPDIFF(
                SECOND,
                order_purchase_timestamp,
                order_delivered_customer_date
            ) / 86400.0
        ) AS avg_delivery_days,

        SUM(
            order_delivered_customer_date >
            order_estimated_delivery_date
        ) AS late_orders

    FROM olist_orders_dataset

    WHERE
        order_status = 'delivered'

        AND order_purchase_timestamp IS NOT NULL
        AND order_approved_at IS NOT NULL
        AND order_delivered_carrier_date IS NOT NULL
        AND order_delivered_customer_date IS NOT NULL
        AND order_estimated_delivery_date IS NOT NULL

        AND order_approved_at >= order_purchase_timestamp
        AND order_delivered_carrier_date >= order_approved_at
        AND order_delivered_customer_date >=
            order_delivered_carrier_date
),
ranked_reviews AS (
    SELECT
        r.order_id,
        r.review_score,

        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY
                r.review_answer_timestamp DESC,
                r.review_row_id DESC
        ) AS rn

    FROM olist_order_reviews_dataset r
),
deduplicated_reviews AS (
    SELECT
        order_id,
        review_score

    FROM ranked_reviews

    WHERE rn = 1
),
review_metrics AS (
    SELECT
        COUNT(*) AS reviewed_orders,
        AVG(review_score) AS avg_review_score,
        SUM(review_score <= 2) AS negative_reviews

    FROM deduplicated_reviews
),
seller_metrics AS (
    SELECT
        COUNT(*) AS active_sellers,

        SUM(
            seller_segment = 'High Performance Risk'
        ) AS high_risk_sellers

    FROM vw_seller_performance
)
SELECT  
    ROUND(s.total_revenue, 2)
        AS total_revenue,

    s.total_orders,

    ROUND(s.avg_order_value, 2)
        AS avg_order_value,
    
    c.unique_customers,

    ROUND(
        c.repeat_customers * 100.0 /
        NULLIF(c.unique_customers, 0),
        2
    ) AS repeat_customer_rate_pct,

    
    ROUND(d.avg_delivery_days, 2)
        AS avg_delivery_days,

    ROUND(
        d.late_orders * 100.0 /
        NULLIF(d.delivered_orders, 0),
        2
    ) AS late_delivery_rate_pct,

    ROUND(r.avg_review_score, 2)
        AS avg_review_score,

    ROUND(
        r.negative_reviews * 100.0 /
        NULLIF(r.reviewed_orders, 0),
        2
    ) AS negative_review_rate_pct,
   
    sm.active_sellers,

    sm.high_risk_sellers,

    ROUND(
        sm.high_risk_sellers * 100.0 /
        NULLIF(sm.active_sellers, 0),
        2
    ) AS high_risk_seller_rate_pct

FROM sales_metrics s

CROSS JOIN customer_metrics c
CROSS JOIN delivery_metrics d
CROSS JOIN review_metrics r
CROSS JOIN seller_metrics sm;

