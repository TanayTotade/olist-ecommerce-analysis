-- Payment usage, order-level installments and customer outcomes.

-- Question: What share of paid orders uses each defined payment method?
-- Methods overlap within orders, so usage shares may exceed 100% in total. All order statuses.
SELECT
    payment_type,
    
    COUNT(DISTINCT order_id) AS orders,
    
    ROUND(
        COUNT(DISTINCT order_id) * 100.0 /
        (SELECT COUNT(DISTINCT order_id)
         FROM olist_order_payments_dataset WHERE payment_type <> 'not_defined'),
        2
    ) AS pct_of_orders

FROM olist_order_payments_dataset

WHERE payment_type <> 'not_defined'

GROUP BY payment_type
ORDER BY orders DESC;

-- Question: What share of recorded payment value belongs to each defined method?
-- Payment values are distinct from item-plus-freight sales; not_defined is excluded.
SELECT
    payment_type,

    ROUND(SUM(payment_value), 2) AS payment_value,
    ROUND(
        SUM(payment_value) * 100.0 /
        (SELECT SUM(payment_value)
         FROM olist_order_payments_dataset WHERE payment_type <> 'not_defined'),
        2
    ) AS pct_of_payment_value

FROM olist_order_payments_dataset

WHERE payment_type <> 'not_defined'

GROUP BY payment_type
ORDER BY payment_value DESC;

-- Question: How are credit-card orders distributed by installment count?
-- Classify each order once using its maximum recorded installment count.
-- This describes the longest recorded plan; it is not a single reconstructed repayment schedule.
WITH credit_card_orders AS (
    SELECT 
        order_id, 
        MAX(payment_installments) AS payment_installments,
        SUM(payment_value) AS payment_value
    
    FROM olist_order_payments_dataset
    
    WHERE payment_type = 'credit_card'
    
    GROUP BY order_id
)
SELECT 
    payment_installments, 
    COUNT(*) AS orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_credit_card_orders

FROM credit_card_orders

GROUP BY payment_installments 
ORDER BY payment_installments;

-- Question: How does credit-card value per order vary across installment bands?
-- One group per order using maximum installments; sum credit-card payment records first.
-- Keep unknown/invalid installment orders in a separate group.
WITH credit_card_orders AS (
    SELECT 
        order_id, 
        MAX(payment_installments) AS payment_installments,
        SUM(payment_value) AS payment_value
    
    FROM olist_order_payments_dataset
    
    WHERE payment_type = 'credit_card'
    GROUP BY order_id
)
SELECT
    CASE
        WHEN payment_installments IS NULL OR payment_installments <= 0 THEN 'Unknown / invalid'
        WHEN payment_installments = 1 THEN 'Single payment'
        WHEN payment_installments BETWEEN 2 AND 3 THEN 'Short-term (2-3)'
        WHEN payment_installments BETWEEN 4 AND 6 THEN 'Medium-term (4-6)'
        WHEN payment_installments BETWEEN 7 AND 12 THEN 'Long-term (7-12)'
        WHEN payment_installments >= 13 THEN 'Extended (13+)'
    END AS installment_group,
    
    COUNT(DISTINCT order_id) AS orders,
    
    ROUND(AVG(payment_value), 2) AS avg_credit_card_value_per_order

FROM credit_card_orders

GROUP BY installment_group

ORDER BY
    CASE installment_group
        WHEN 'Single payment' THEN 1
        WHEN 'Short-term (2-3)' THEN 2
        WHEN 'Medium-term (4-6)' THEN 3
        WHEN 'Long-term (7-12)' THEN 4
        WHEN 'Extended (13+)' THEN 5
    END;

-- Question: How many payment records does each order have?
-- Multiple records need not mean multiple distinct methods. Includes all recorded types.
WITH order_payments AS
(
    SELECT
        order_id,
        COUNT(*) AS payment_count

    FROM olist_order_payments_dataset
    
    GROUP BY order_id
)
SELECT
    payment_count,
    COUNT(*) AS orders,
    
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_orders

FROM order_payments

GROUP BY payment_count
ORDER BY payment_count;

-- Question: How many distinct payment methods does an order use?
-- Includes all recorded types, including not_defined, for a data-quality-complete count.
WITH order_payment_methods AS
(
    SELECT
        order_id,

        COUNT(*) AS payment_records,
        COUNT(DISTINCT payment_type) AS payment_methods
    
    FROM olist_order_payments_dataset
    GROUP BY order_id
)
SELECT
    payment_methods,
    COUNT(*) AS orders,
    
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_orders

FROM order_payment_methods

GROUP BY payment_methods
ORDER BY payment_methods;

-- Question: How does defined-method usage vary by purchase month?
-- Denominator: distinct orders with defined payments in each month; methods overlap.
WITH monthly_payments AS
(
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS purchase_month,
        
        p.payment_type,
        COUNT(DISTINCT p.order_id) AS orders
    
    FROM olist_order_payments_dataset p
    
    JOIN olist_orders_dataset o
        ON p.order_id = o.order_id
    
    WHERE p.payment_type <> 'not_defined'
    
    GROUP BY
        purchase_month,
        p.payment_type
),
monthly_orders AS
(
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS purchase_month,
        
        COUNT(DISTINCT p.order_id) AS total_orders
    
    FROM olist_order_payments_dataset p
    
    JOIN olist_orders_dataset o
        ON p.order_id = o.order_id
    
    WHERE p.payment_type <> 'not_defined'
    
    GROUP BY purchase_month
)
SELECT
    mp.purchase_month,
    mp.payment_type,
    mp.orders,
    
    ROUND(
        mp.orders * 100.0 / mo.total_orders,
        2
    ) AS pct_of_monthly_orders

FROM monthly_payments mp

JOIN monthly_orders mo
    ON mp.purchase_month = mo.purchase_month

ORDER BY
    mp.purchase_month,
    pct_of_monthly_orders DESC;

-- Question: How does defined-method usage vary by customer state?
-- Denominator: distinct orders with defined payments in each state; methods overlap.
WITH state_payment AS
(
    SELECT
        c.customer_state,
        p.payment_type,
        
        COUNT(DISTINCT p.order_id) AS orders
    
    FROM olist_order_payments_dataset p
    
    JOIN olist_orders_dataset o
        ON p.order_id = o.order_id
    
    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id
    
    WHERE p.payment_type <> 'not_defined'
    
    GROUP BY
        c.customer_state,
        p.payment_type
),
state_orders AS
(
    SELECT
        c.customer_state,
        COUNT(DISTINCT p.order_id) AS total_orders
    
    FROM olist_order_payments_dataset p
    
    JOIN olist_orders_dataset o
        ON p.order_id = o.order_id
    
    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id
    
    WHERE p.payment_type <> 'not_defined'
    
    GROUP BY c.customer_state
)
SELECT
    sp.customer_state,
    so.total_orders,  
    
    ROUND(
        SUM(CASE WHEN sp.payment_type = 'credit_card'
                 THEN sp.orders ELSE 0 END)
        * 100.0 / so.total_orders,
        2
    ) AS credit_card_pct,
    
    ROUND(
        SUM(CASE WHEN sp.payment_type = 'boleto'
                 THEN sp.orders ELSE 0 END)
        * 100.0 / so.total_orders,
        2
    ) AS boleto_pct,
    
    ROUND(
        SUM(CASE WHEN sp.payment_type = 'voucher'
                 THEN sp.orders ELSE 0 END)
        * 100.0 / so.total_orders,
        2
    ) AS voucher_pct,
    
    ROUND(
        SUM(CASE WHEN sp.payment_type = 'debit_card'
                 THEN sp.orders ELSE 0 END)
        * 100.0 / so.total_orders,
        2
    ) AS debit_card_pct

FROM state_payment sp

JOIN state_orders so
    ON sp.customer_state = so.customer_state

GROUP BY
    sp.customer_state,
    so.total_orders

ORDER BY so.total_orders DESC;

-- Question: What is the value paid through each method per order?
-- Aggregate records to order-method grain before averaging; excludes not_defined.
WITH order_payment_type AS
(
    SELECT
        order_id,
        payment_type,
        SUM(payment_value) AS payment_value
    
    FROM olist_order_payments_dataset
    
    WHERE payment_type <> 'not_defined'
    
    GROUP BY
        order_id,
        payment_type
)
SELECT
    payment_type,
    COUNT(*) AS orders_using_method,
    
    ROUND(AVG(payment_value), 2) AS avg_payment_value,
    ROUND(MIN(payment_value), 2) AS min_payment_value,
    ROUND(MAX(payment_value), 2) AS max_payment_value

FROM order_payment_type

GROUP BY payment_type
ORDER BY avg_payment_value DESC;

-- Question: How do review outcomes differ across defined payment methods?
-- Latest review per order; a mixed-method order contributes to every method it uses.
-- Associations do not establish an effect of payment choice on satisfaction.
WITH ranked_reviews AS (
    SELECT 
        r.*, 
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY r.review_answer_timestamp DESC, r.review_row_id DESC
        ) AS review_rank
    
    FROM olist_order_reviews_dataset r
),
order_reviews AS (
    SELECT * FROM ranked_reviews WHERE review_rank = 1
),
order_payment_method AS
(
    SELECT DISTINCT
        order_id,
        payment_type
    
    FROM olist_order_payments_dataset
    
    WHERE payment_type <> 'not_defined'
)
SELECT
    p.payment_type,
    COUNT(*) AS reviewed_orders,
    
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    
    SUM(
        CASE
            WHEN r.review_score <= 2 THEN 1
            ELSE 0
        END
    ) AS negative_reviews,
    
    ROUND(
        SUM(
            CASE
                WHEN r.review_score <= 2 THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS negative_review_pct

FROM order_payment_method p

JOIN order_reviews r
    ON p.order_id = r.order_id

GROUP BY p.payment_type
ORDER BY avg_review_score DESC;

-- Question: How do eligible delivery outcomes differ across payment methods?
-- Use common chronological delivery eligibility and elapsed seconds / 86400.0.
-- Mixed-method orders contribute once to each method; lateness compares full timestamps.
WITH valid_deliveries AS (
    SELECT 
        o.*,
        TIMESTAMPDIFF(
            SECOND, 
            o.order_approved_at, o.order_delivered_carrier_date
            ) / 86400.0 AS stage_dispatch_days,
        
        CASE 
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 1 
            ELSE 0 
        END AS is_late
    
    FROM olist_orders_dataset o
    
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_approved_at IS NOT NULL
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    
      AND o.order_approved_at >= o.order_purchase_timestamp
      AND o.order_delivered_carrier_date >= o.order_approved_at
      AND o.order_delivered_customer_date >= o.order_delivered_carrier_date
),
order_payment_method AS
(
    SELECT DISTINCT
        order_id,
        payment_type
    
    FROM olist_order_payments_dataset
    
    WHERE payment_type <> 'not_defined'
)
SELECT
    p.payment_type,
    COUNT(*) AS delivered_orders,
    
    ROUND(
        AVG(
            TIMESTAMPDIFF(SECOND,
                o.order_purchase_timestamp,
                o.order_delivered_customer_date
            )
        ) / 86400.0,
        2
    ) AS avg_delivery_days,
    
    ROUND(
        SUM(
            CASE
                WHEN o.order_delivered_customer_date >
                     o.order_estimated_delivery_date
                THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(*),
        2
    ) AS late_delivery_pct

FROM order_payment_method p

JOIN valid_deliveries o
    ON p.order_id = o.order_id

WHERE o.order_status = 'delivered'
    AND o.order_purchase_timestamp IS NOT NULL
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL

GROUP BY p.payment_type
ORDER BY avg_delivery_days;

