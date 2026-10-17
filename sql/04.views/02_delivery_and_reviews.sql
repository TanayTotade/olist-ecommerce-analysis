-- Delivery and latest-review dashboard views; shared delay definitions.

-- Eligible delivered orders: complete chronological stage dates and an estimate.
-- Full timestamp lateness; delay bands represent (0,3], (3,7], (7,14], and >14 days.
-- Labels are retained for Tableau compatibility; fractions of days are included.
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

-- Latest review per order for satisfaction and delivery context.
-- Includes reviewed orders outside operational eligibility; the impact view filters to eligible deliveries.
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

    CASE
        WHEN r.review_score <= 2 THEN 'Negative'
        WHEN r.review_score = 3 THEN 'Neutral'
        WHEN r.review_score >= 4 THEN 'Positive'
    END AS satisfaction_segment,

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

-- Delay impact: join eligible deliveries to the latest review by order.
-- Reuses the exact order-level delay bands and eligibility rather than a second definition.
CREATE OR REPLACE VIEW vw_delivery_review_impact AS
	
WITH bucketed AS (
    SELECT 
		d.delay_bucket, 
		r.review_score,
        
		CASE d.delay_bucket
            WHEN 'On Time / Early' THEN 1 WHEN '1-3 Days Late' THEN 2
            WHEN '4-7 Days Late' THEN 3 WHEN '8-14 Days Late' THEN 4 ELSE 5
        END AS delay_bucket_order
    
	FROM vw_delivery_performance d
    
	JOIN vw_review_performance r 
		ON d.order_id = r.order_id
)
SELECT 
	delay_bucket, 
	delay_bucket_order, 
	COUNT(*) AS reviewed_orders,
    
	ROUND(AVG(review_score), 2) AS avg_review_score,
    SUM(review_score <= 2) AS negative_reviews,
    ROUND(100.0 * SUM(review_score <= 2) / COUNT(*), 2) AS negative_review_pct

FROM bucketed 
GROUP BY delay_bucket, delay_bucket_order;

