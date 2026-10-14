-- Original delivery and review dashboard views; methodology differences are preserved.

-- Delivery Performance View

CREATE OR REPLACE VIEW vw_delivery_performance AS

SELECT
    o.order_id,

    DATE(o.order_purchase_timestamp) AS purchase_date,

    DATE_FORMAT(
        o.order_purchase_timestamp,
        '%Y-%m-01'
    ) AS purchase_month,

    c.customer_state,

    ROUND(
        TIMESTAMPDIFF(
            SECOND,
            o.order_purchase_timestamp,
            o.order_approved_at
        ) / 86400.0,
        2
    ) AS approval_days,

    ROUND(
        TIMESTAMPDIFF(
            SECOND,
            o.order_approved_at,
            o.order_delivered_carrier_date
        ) / 86400,
        2
    ) AS dispatch_days,

    ROUND(
        TIMESTAMPDIFF(
            SECOND,
            o.order_delivered_carrier_date,
            o.order_delivered_customer_date
        ) / 86400,
        2
    ) AS shipping_days,

    ROUND(
        TIMESTAMPDIFF(
            SECOND,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) / 86400.0,
        2
    ) AS total_delivery_days,

    ROUND(
        TIMESTAMPDIFF(
            SECOND,
            o.order_estimated_delivery_date,
            o.order_delivered_customer_date
        ) / 86400,
        2
    ) AS days_vs_estimate,

    CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN 'Late'
        ELSE 'On Time / Early'
    END AS delivery_status,
    CASE
		WHEN o.order_delivered_customer_date <=
			 o.order_estimated_delivery_date
			THEN 'On Time / Early'

		WHEN TIMESTAMPDIFF(
			SECOND,
			o.order_estimated_delivery_date,
			o.order_delivered_customer_date
		) / 86400.0 <= 3
			THEN '1-3 Days Late'

		WHEN TIMESTAMPDIFF(
			SECOND,
			o.order_estimated_delivery_date,
			o.order_delivered_customer_date
		) / 86400.0 <= 7
			THEN '4-7 Days Late'

		WHEN TIMESTAMPDIFF(
			SECOND,
			o.order_estimated_delivery_date,
			o.order_delivered_customer_date
		) / 86400.0 <= 14
			THEN '8-14 Days Late'

		ELSE '15+ Days Late'
	END AS delay_bucket

FROM olist_orders_dataset o

JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id

WHERE
    o.order_status = 'delivered'
    AND o.order_purchase_timestamp IS NOT NULL
    AND o.order_approved_at IS NOT NULL
    AND o.order_delivered_carrier_date IS NOT NULL
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL
    AND o.order_approved_at >= o.order_purchase_timestamp
    AND o.order_delivered_carrier_date >= o.order_approved_at
    AND o.order_delivered_customer_date >= o.order_delivered_carrier_date;

-- Review Performance View

CREATE OR REPLACE VIEW vw_review_performance AS

WITH ranked_reviews AS (
    SELECT
        r.*,

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
)

SELECT
    o.order_id,

    DATE(o.order_purchase_timestamp) AS purchase_date,

    DATE_FORMAT(
        o.order_purchase_timestamp,
        '%Y-%m-01'
    ) AS purchase_month,

    c.customer_state,

    r.review_score,

    -- =====================================================
    -- SATISFACTION
    -- =====================================================
    CASE
        WHEN r.review_score <= 2 THEN 'Negative'
        WHEN r.review_score = 3 THEN 'Neutral'
        WHEN r.review_score >= 4 THEN 'Positive'
    END AS satisfaction_segment,

    -- =====================================================
    -- DELIVERY STATUS
    -- =====================================================
    CASE
        WHEN o.order_delivered_customer_date IS NULL
            THEN 'Not Delivered'

        WHEN o.order_estimated_delivery_date IS NULL
            THEN 'Unknown'

        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
            THEN 'Late'

        ELSE 'On Time / Early'
    END AS delivery_status,

    -- =====================================================
    -- TOTAL DELIVERY TIME
    -- =====================================================
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
             AND o.order_purchase_timestamp IS NOT NULL
        THEN ROUND(
            TIMESTAMPDIFF(
                SECOND,
                o.order_purchase_timestamp,
                o.order_delivered_customer_date
            ) / 86400.0,
            2
        )
    END AS delivery_days,

    -- =====================================================
    -- DAYS VS ESTIMATED DELIVERY
    -- =====================================================
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
             AND o.order_estimated_delivery_date IS NOT NULL
        THEN ROUND(
            TIMESTAMPDIFF(
                SECOND,
                o.order_estimated_delivery_date,
                o.order_delivered_customer_date
            ) / 86400.0,
            2
        )
    END AS days_vs_estimate,

    -- =====================================================
    -- DELAY SEVERITY
    -- =====================================================
    CASE
        WHEN o.order_delivered_customer_date IS NULL
            THEN 'Not Delivered'

        WHEN o.order_estimated_delivery_date IS NULL
            THEN 'Unknown'

        WHEN o.order_delivered_customer_date <=
             o.order_estimated_delivery_date
            THEN 'On Time / Early'

        WHEN TIMESTAMPDIFF(
            SECOND,
            o.order_estimated_delivery_date,
            o.order_delivered_customer_date
        ) / 86400.0 <= 3
            THEN '1-3 Days Late'

        WHEN TIMESTAMPDIFF(
            SECOND,
            o.order_estimated_delivery_date,
            o.order_delivered_customer_date
        ) / 86400.0 <= 7
            THEN '4-7 Days Late'

        WHEN TIMESTAMPDIFF(
            SECOND,
            o.order_estimated_delivery_date,
            o.order_delivered_customer_date
        ) / 86400.0 <= 14
            THEN '8-14 Days Late'

        ELSE '15+ Days Late'
    END AS delay_bucket

FROM olist_orders_dataset o

JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id

JOIN deduplicated_reviews r
    ON o.order_id = r.order_id;

-- Delivery impact View

CREATE OR REPLACE VIEW vw_delivery_review_impact AS

WITH order_reviews AS (
    -- Reduce reviews to one score per order.
    -- AVG protects against duplicate/multiple review rows.
    SELECT
        order_id,
        AVG(review_score) AS review_score
    FROM olist_order_reviews_dataset
    GROUP BY order_id
),

delivery_reviews AS (
    SELECT
        o.order_id,

        DATEDIFF(
            o.order_delivered_customer_date,
            o.order_estimated_delivery_date
        ) AS days_vs_estimate,

        r.review_score

    FROM olist_orders_dataset o

    INNER JOIN order_reviews r
        ON o.order_id = r.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
),

bucketed AS (
    SELECT
        order_id,
        review_score,

        CASE
            WHEN days_vs_estimate <= 0
                THEN 'On Time / Early'

            WHEN days_vs_estimate BETWEEN 1 AND 3
                THEN '1-3 Days Late'

            WHEN days_vs_estimate BETWEEN 4 AND 7
                THEN '4-7 Days Late'

            WHEN days_vs_estimate BETWEEN 8 AND 14
                THEN '8-14 Days Late'

            ELSE '15+ Days Late'
        END AS delay_bucket,

        CASE
            WHEN days_vs_estimate <= 0 THEN 1
            WHEN days_vs_estimate <= 3 THEN 2
            WHEN days_vs_estimate <= 7 THEN 3
            WHEN days_vs_estimate <= 14 THEN 4
            ELSE 5
        END AS delay_bucket_order

    FROM delivery_reviews
)

SELECT
    delay_bucket,
    delay_bucket_order,

    COUNT(*) AS reviewed_orders,

    ROUND(
        AVG(review_score),
        2
    ) AS avg_review_score,

    SUM(
        CASE
            WHEN review_score <= 2 THEN 1
            ELSE 0
        END
    ) AS negative_reviews,

    ROUND(
        100.0 *
        SUM(
            CASE
                WHEN review_score <= 2 THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS negative_review_pct

FROM bucketed

GROUP BY
    delay_bucket,
    delay_bucket_order;
