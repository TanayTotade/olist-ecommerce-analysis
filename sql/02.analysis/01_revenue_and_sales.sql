-- Sales baseline and monthly trend aligned with dashboard sales definitions.

-- Question: What are total sales, their components, and average order value?
-- All order statuses; total revenue includes freight. AOV excludes missing item values.
WITH order_revenue AS (
    SELECT 
        order_id, 
        
        SUM(price) AS product_revenue,
        SUM(freight_value) AS freight_revenue,
        SUM(price + freight_value) AS order_revenue
    
    FROM olist_order_items_dataset GROUP BY order_id
)
SELECT 
    COUNT(*) AS total_orders,
    COUNT(r.order_revenue) AS orders_with_item_value,
    
    ROUND(SUM(r.product_revenue), 2) AS product_revenue,
    ROUND(SUM(r.freight_revenue), 2) AS freight_revenue,
    ROUND(SUM(r.order_revenue), 2) AS total_revenue,
    ROUND(AVG(r.order_revenue), 2) AS average_order_value

FROM olist_orders_dataset o
LEFT JOIN order_revenue r ON o.order_id = r.order_id;

-- Question: How do sales change by purchase month?
WITH order_revenue AS (
    SELECT 
        order_id, 
        SUM(price + freight_value) AS order_revenue
    
    FROM olist_order_items_dataset GROUP BY order_id
)
SELECT 
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS purchase_month,
    COUNT(*) AS orders,
    
    ROUND(SUM(COALESCE(r.order_revenue, 0)), 2) AS revenue,
    ROUND(AVG(r.order_revenue), 2) AS average_order_value

FROM olist_orders_dataset o
LEFT JOIN order_revenue r ON o.order_id = r.order_id

GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY purchase_month;

