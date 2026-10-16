-- Fulfillment, delivery distribution, stages, state/month patterns and review score distribution.

-- Order status and fulfillment rate
-- Question: What share of all orders is in each fulfillment status?

SELECT
    order_status,
    COUNT(*) AS total_orders,
    ROUND(
        COUNT(*) / SUM(COUNT(*)) OVER () * 100.0,
        2
    ) AS percentage_of_orders
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY total_orders DESC;

-- delivery time distribution
-- Question: How are eligible delivered orders distributed across delivery-time bands?
-- DATEDIFF uses calendar days; exclude missing delivery dates and delivery before purchase.
-- Percentages use only orders surviving these filters.

WITH delivery_times AS (
    SELECT
        order_id,
        DATEDIFF(
            order_delivered_customer_date,
            order_purchase_timestamp
        ) AS delivery_days
    FROM olist_orders_dataset
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
),
delivery_bands AS (
    SELECT
        order_id,
        CASE
            WHEN delivery_days <= 7  THEN '0–7 days'
            WHEN delivery_days <= 14 THEN '8–14 days'
            WHEN delivery_days <= 21 THEN '15–21 days'
            WHEN delivery_days <= 30 THEN '22–30 days'
            ELSE '31+ days'
        END AS delivery_band,
        CASE
            WHEN delivery_days <= 7  THEN 1
            WHEN delivery_days <= 14 THEN 2
            WHEN delivery_days <= 21 THEN 3
            WHEN delivery_days <= 30 THEN 4
            ELSE 5
        END AS band_order
    FROM delivery_times
)
SELECT
    delivery_band,
    COUNT(*) AS delivered_orders,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_delivered_orders
FROM delivery_bands
GROUP BY delivery_band, band_order
ORDER BY band_order;

-- Approval, Dispatch and Shipping Duration
-- Question: Which fulfillment stage accounts for elapsed delivery time?
-- Require all stage timestamps in chronological order to avoid negative durations.
-- Seconds / 86400.0 preserves fractional days; all stage averages use the same orders.

WITH fulfillment_durations AS (
    SELECT
        order_id,

        TIMESTAMPDIFF(
            SECOND,
            order_purchase_timestamp,
            order_approved_at
        ) / 86400.0 AS approval_days,

        TIMESTAMPDIFF(
            SECOND,
            order_approved_at,
            order_delivered_carrier_date
        ) / 86400.0 AS dispatch_days,

        TIMESTAMPDIFF(
            SECOND,
            order_delivered_carrier_date,
            order_delivered_customer_date
        ) / 86400.0 AS shipping_days

    FROM olist_orders_dataset
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_approved_at IS NOT NULL
      AND order_delivered_carrier_date IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL

      AND order_approved_at >= order_purchase_timestamp
      AND order_delivered_carrier_date >= order_approved_at
      AND order_delivered_customer_date >= order_delivered_carrier_date
)
SELECT
    COUNT(*) AS valid_delivered_orders,

    ROUND(AVG(approval_days), 2) AS avg_approval_days,
    ROUND(AVG(dispatch_days), 2) AS avg_dispatch_days,
    ROUND(AVG(shipping_days), 2) AS avg_shipping_days,

    ROUND(
        AVG(approval_days + dispatch_days + shipping_days),
        2
    ) AS avg_total_delivery_days
FROM fulfillment_durations;

-- Question: Which fulfillment stages differ between on-time and late deliveries?
-- Reuses chronological stage eligibility and also requires an estimated delivery date.
WITH fulfillment_durations AS (
    SELECT
        order_id,

        CASE
            WHEN DATEDIFF(
                order_delivered_customer_date,
                order_estimated_delivery_date
            ) <= 0 THEN 'On time'
            ELSE 'Late'
        END AS delivery_performance,

        TIMESTAMPDIFF(
            SECOND,
            order_purchase_timestamp,
            order_approved_at
        ) / 86400.0 AS approval_days,

        TIMESTAMPDIFF(
            SECOND,
            order_approved_at,
            order_delivered_carrier_date
        ) / 86400.0 AS dispatch_days,

        TIMESTAMPDIFF(
            SECOND,
            order_delivered_carrier_date,
            order_delivered_customer_date
        ) / 86400.0 AS shipping_days

    FROM olist_orders_dataset
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_approved_at IS NOT NULL
      AND order_delivered_carrier_date IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL

      AND order_approved_at >= order_purchase_timestamp
      AND order_delivered_carrier_date >= order_approved_at
      AND order_delivered_customer_date >= order_delivered_carrier_date
)
SELECT
    delivery_performance,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(approval_days), 2) AS avg_approval_days,
    ROUND(AVG(dispatch_days), 2) AS avg_dispatch_days,
    ROUND(AVG(shipping_days), 2) AS avg_shipping_days,
    ROUND(
        AVG(approval_days + dispatch_days + shipping_days),
        2
    ) AS avg_total_delivery_days
FROM fulfillment_durations
GROUP BY delivery_performance
ORDER BY FIELD(delivery_performance, 'On time', 'Late');

-- Delivery performance by state
-- Question: How do delivery speed and lateness vary by customer state?
-- Late means a positive calendar-day difference from the estimate.
-- avg_days_late excludes on-time orders; late_delivery_pct includes all eligible orders.

WITH state_delivery AS (
    SELECT
        o.order_id,
        c.customer_state,

        TIMESTAMPDIFF(
            SECOND,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) / 86400.0 AS delivery_days,

        DATEDIFF(
            o.order_delivered_customer_date,
            o.order_estimated_delivery_date
        ) AS days_vs_estimate

    FROM olist_orders_dataset AS o
    JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_customer_date >= o.order_purchase_timestamp
)
SELECT
    customer_state,
    COUNT(*) AS delivered_orders,

    ROUND(AVG(delivery_days), 2) AS avg_delivery_days,

    SUM(
        CASE WHEN days_vs_estimate > 0 THEN 1 ELSE 0 END
    ) AS late_orders,

    ROUND(
        AVG(
            CASE WHEN days_vs_estimate > 0 THEN 1 ELSE 0 END
        ) * 100,
        2
    ) AS late_delivery_pct,

    ROUND(
        AVG(
            CASE WHEN days_vs_estimate > 0 THEN days_vs_estimate END
        ),
        2
    ) AS avg_days_late

FROM state_delivery
GROUP BY customer_state
ORDER BY late_delivery_pct DESC, delivered_orders DESC;

-- monthly delivery performance
-- Question: How does delivery performance vary by purchase month?
-- Group by purchase month, not delivery month; eligibility follows this query's filters.

WITH delivery_metrics AS (
    SELECT
        order_id,
        DATE_FORMAT(
            order_purchase_timestamp, '%Y-%m'
        ) AS purchase_month,

        TIMESTAMPDIFF(
            SECOND,
            order_purchase_timestamp,
            order_delivered_customer_date
        ) / 86400.0 AS delivery_days,

        DATEDIFF(
            order_delivered_customer_date,
            order_estimated_delivery_date
        ) AS days_vs_estimate

    FROM olist_orders_dataset
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
)
SELECT
    purchase_month,
    COUNT(*) AS delivered_orders,

    ROUND(AVG(delivery_days), 2) AS avg_delivery_days,

    SUM(
        CASE WHEN days_vs_estimate > 0 THEN 1 ELSE 0 END
    ) AS late_orders,

    ROUND(
        AVG(
            CASE WHEN days_vs_estimate > 0 THEN 1 ELSE 0 END
        ) * 100,
        2
    ) AS late_delivery_pct,

    ROUND(
        AVG(
            CASE WHEN days_vs_estimate > 0 THEN days_vs_estimate END
        ),
        2
    ) AS avg_days_late

FROM delivery_metrics
GROUP BY purchase_month
ORDER BY purchase_month;

-- monthly approval, dispatch and shipping duration
-- Question: How do stage durations compare for purchases in February-June 2018?
-- This focused date window is narrower than the full-period analyses above.

WITH monthly_durations AS (
    SELECT
        DATE_FORMAT(
            order_purchase_timestamp, '%Y-%m'
        ) AS purchase_month,

        TIMESTAMPDIFF(
            SECOND,
            order_purchase_timestamp,
            order_approved_at
        ) / 86400.0 AS approval_days,

        TIMESTAMPDIFF(
            SECOND,
            order_approved_at,
            order_delivered_carrier_date
        ) / 86400.0 AS dispatch_days,

        TIMESTAMPDIFF(
            SECOND,
            order_delivered_carrier_date,
            order_delivered_customer_date
        ) / 86400.0 AS shipping_days

    FROM olist_orders_dataset
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2018-02-01'
      AND order_purchase_timestamp < '2018-07-01'

      AND order_approved_at IS NOT NULL
      AND order_delivered_carrier_date IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL

      AND order_approved_at >= order_purchase_timestamp
      AND order_delivered_carrier_date >= order_approved_at
      AND order_delivered_customer_date >= order_delivered_carrier_date
)
SELECT
    purchase_month,
    COUNT(*) AS valid_delivered_orders,
    ROUND(AVG(approval_days), 2) AS avg_approval_days,
    ROUND(AVG(dispatch_days), 2) AS avg_dispatch_days,
    ROUND(AVG(shipping_days), 2) AS avg_shipping_days,

    ROUND(
        AVG(approval_days + dispatch_days + shipping_days),
        2
    ) AS avg_total_delivery_days

FROM monthly_durations
GROUP BY purchase_month
ORDER BY purchase_month;

-- review score distribution
-- Question: How does the review-score mix differ between delivery outcomes?
-- Counts review records, so an order with multiple reviews contributes multiple rows.
-- Percentages sum to 100 within each delivery status.
-- This query compares full timestamps; earlier DATEDIFF comparisons use calendar dates.

SELECT
    CASE
        WHEN o.order_delivered_customer_date <=
             o.order_estimated_delivery_date
            THEN 'On time / Early'
        ELSE 'Late'
    END AS delivery_status,

    r.review_score,

    COUNT(*) AS reviews,

    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (
            PARTITION BY
                CASE
                    WHEN o.order_delivered_customer_date <=
                         o.order_estimated_delivery_date
                        THEN 'On time / Early'
                    ELSE 'Late'
                END
        ),
        2
    ) AS pct_of_reviews

FROM olist_orders_dataset AS o
JOIN olist_order_reviews_dataset AS r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL

GROUP BY
    delivery_status,
    r.review_score

ORDER BY
    delivery_status,
    r.review_score;
