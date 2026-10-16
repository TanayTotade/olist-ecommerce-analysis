-- Payment usage and value, installments, payment complexity, monthly/state patterns and outcomes.

-- 1.Payment Method Usage
-- Question: What percentage of orders with payment records uses each method?
-- An order can use several methods, so method usage percentages can sum above 100.
-- No order-status filter is applied unless a later query explicitly adds one.

SELECT
    payment_type,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(
        COUNT(DISTINCT order_id) * 100.0 /
        (SELECT COUNT(DISTINCT order_id)
         FROM olist_order_payments_dataset),
        2
    ) AS pct_of_orders
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY orders DESC;

-- 2.Revenue/value by payment method
-- Payment-value share uses payment records, not item-price revenue.

SELECT
    payment_type,
    ROUND(SUM(payment_value), 2) AS payment_value,
    ROUND(
        SUM(payment_value) * 100.0 /
        (SELECT SUM(payment_value)
         FROM olist_order_payments_dataset),
        2
    ) AS pct_of_payment_value
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY payment_value DESC;

-- 3.Installment Behavior
-- Question: How are credit-card orders distributed by installment count?
-- An order with different installment counts on separate records can appear in several groups.

SELECT
    payment_installments,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(
        COUNT(DISTINCT order_id) * 100.0 /
        (
            SELECT COUNT(DISTINCT order_id)
            FROM olist_order_payments_dataset
            WHERE payment_type = 'credit_card'
        ),
        2
    ) AS pct_of_credit_card_orders
FROM olist_order_payments_dataset
WHERE payment_type = 'credit_card'
GROUP BY payment_installments
ORDER BY payment_installments;

-- Question: How does payment-record value vary across installment bands?
-- AVG(payment_value) is per payment record, not total order value; zero installments are excluded.
SELECT
    CASE
        WHEN payment_installments = 1 THEN 'Single payment'
        WHEN payment_installments BETWEEN 2 AND 3 THEN 'Short-term (2-3)'
        WHEN payment_installments BETWEEN 4 AND 6 THEN 'Medium-term (4-6)'
        WHEN payment_installments BETWEEN 7 AND 12 THEN 'Long-term (7-12)'
        WHEN payment_installments >= 13 THEN 'Extended (13+)'
    END AS installment_group,

    COUNT(DISTINCT order_id) AS orders,

    ROUND(AVG(payment_value), 2) AS avg_payment_value

FROM olist_order_payments_dataset

WHERE payment_type = 'credit_card'
    AND payment_installments > 0

GROUP BY installment_group

ORDER BY
    CASE installment_group
        WHEN 'Single payment' THEN 1
        WHEN 'Short-term (2-3)' THEN 2
        WHEN 'Medium-term (4-6)' THEN 3
        WHEN 'Long-term (7-12)' THEN 4
        WHEN 'Extended (13+)' THEN 5
    END;

-- 5.Multiple payment orders
-- Question: How many payment records does each order have?
-- Multiple records do not necessarily mean multiple distinct payment methods.

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

-- different payment method by order
-- Question: How many distinct payment methods does each order use?

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

-- Question: How does method usage change by purchase month?
-- Denominator: distinct orders with a defined method in that month; methods can overlap.
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

-- 7.Regional payment behavior
-- Question: How does payment-method usage vary by customer state?
-- Denominator: orders with defined payment methods in that state; shares can overlap.

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

-- 8.Payment method and Customer satisfaction
-- Question: How much is paid through each method per order?
-- Aggregate payment records to order-method grain before calculating value statistics.

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

-- customer satisfaction with payment method
-- Question: How do review outcomes differ across payment methods?
-- Average reviews to one score per order; negative means that average is <= 2.
-- A mixed-method order contributes to every method it uses; this is an association.

WITH order_payment_method AS
(
    SELECT DISTINCT
        order_id,
        payment_type
    FROM olist_order_payments_dataset
    WHERE payment_type <> 'not_defined'
),

order_reviews AS
(
    SELECT
        order_id,
        AVG(review_score) AS review_score
    FROM olist_order_reviews_dataset
    GROUP BY order_id
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

-- delivery performance
-- Question: How do delivery outcomes differ across payment methods?
-- Uses delivered orders with required dates; elapsed hours / 24 gives days.
-- Timestamp chronology is not validated here; mixed-method orders appear in each method.

WITH order_payment_method AS
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
            TIMESTAMPDIFF(
                HOUR,
                o.order_purchase_timestamp,
                o.order_delivered_customer_date
            )
        ) / 24,
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

JOIN olist_orders_dataset o
    ON p.order_id = o.order_id

WHERE o.order_status = 'delivered'
    AND o.order_purchase_timestamp IS NOT NULL
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL

GROUP BY p.payment_type

ORDER BY avg_delivery_days;
