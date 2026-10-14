-- Original import statements; edit local CSV paths before use. Tables must already exist.

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/olist_customers_dataset.csv' 
INTO TABLE `olist_customers_dataset` 
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\n' 
IGNORE 1 ROWS 
(
	`customer_id`, 
    `customer_unique_id`, 
    `customer_zip_code_prefix`, 
    `customer_city`, 
    `customer_state`
);

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/olist_orders_dataset.csv'
INTO TABLE olist_orders_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    @order_id,
    @customer_id,
    @order_status,
    @order_purchase_timestamp,
    @order_approved_at,
    @order_delivered_carrier_date,
    @order_delivered_customer_date,
    @order_estimated_delivery_date
)
SET
    order_id = @order_id,
    customer_id = @customer_id,
    order_status = @order_status,

    order_purchase_timestamp =
        STR_TO_DATE(
            NULLIF(TRIM(@order_purchase_timestamp), ''),
            '%Y-%m-%d %H:%i:%s'
        ),

    order_approved_at =
        STR_TO_DATE(
            NULLIF(TRIM(@order_approved_at), ''),
            '%Y-%m-%d %H:%i:%s'
        ),

    order_delivered_carrier_date =
        STR_TO_DATE(
            NULLIF(TRIM(@order_delivered_carrier_date), ''),
            '%Y-%m-%d %H:%i:%s'
        ),

    order_delivered_customer_date =
        STR_TO_DATE(
            NULLIF(TRIM(@order_delivered_customer_date), ''),
            '%Y-%m-%d %H:%i:%s'
        ),

    order_estimated_delivery_date =
        STR_TO_DATE(
            NULLIF(TRIM(@order_estimated_delivery_date), ''),
            '%Y-%m-%d %H:%i:%s'
        );

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/olist_order_items_dataset.csv'
INTO TABLE `olist_order_items_dataset` 
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\n' 
IGNORE 1 ROWS 
(
	`order_id`, 
    `order_item_id`, 
    `product_id`, 
    `seller_id`, 
    `shipping_limit_date`, 
    `price`, 
    `freight_value`
);

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/olist_order_payments_dataset.csv' 
INTO TABLE `olist_order_payments_dataset` 
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\n' 
IGNORE 1 ROWS 
(
	`order_id`, 
    `payment_sequential`, 
    `payment_type`, 
    `payment_installments`, 
    `payment_value`
);

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/olist_order_reviews_dataset.csv' 
INTO TABLE `olist_order_reviews_dataset` 
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\r\n' 
IGNORE 1 ROWS 
(
`review_id`, 
`order_id`, 
`review_score`, 
`review_comment_title`, 
`review_comment_message`, 
`review_creation_date`, 
`review_answer_timestamp`);

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/olist_sellers_dataset.csv' 
INTO TABLE `olist_sellers_dataset` 
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\n' 
IGNORE 1 ROWS 
(
	`seller_id`, 
    `seller_zip_code_prefix`, 
    `seller_city`, 
    `seller_state`
);

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/olist_geolocation_dataset.csv' 
INTO TABLE `olist_geolocation_dataset` 
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\n' 
IGNORE 1 ROWS 
(
`geolocation_zip_code_prefix`, 
`geolocation_lat`, 
`geolocation_lng`, 
`geolocation_city`, 
`geolocation_state`);

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/product_category_name_translation.csv' 
INTO TABLE `product_category_name_translation` 
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\n' 
IGNORE 1 ROWS 
(
	`product_category_name`, 
    `product_category_name_english`
);

LOAD DATA LOCAL INFILE 'D:/Brazilian E-Commerce Public Dataset by Olist/olist_products_dataset.csv'
INTO TABLE olist_products_dataset
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    product_id,
    product_category_name,
    @product_name_lenght,
    @product_description_lenght,
    @product_photos_qty,
    @product_weight_g,
    @product_length_cm,
    @product_height_cm,
    @product_width_cm
)
SET
    product_name_lenght =
        NULLIF(@product_name_lenght, ''),
    product_description_lenght =
        NULLIF(@product_description_lenght, ''),
    product_photos_qty =
        NULLIF(@product_photos_qty, ''),
    product_weight_g =
        NULLIF(@product_weight_g, ''),
    product_length_cm =
        NULLIF(@product_length_cm, ''),
    product_height_cm =
        NULLIF(@product_height_cm, ''),
    product_width_cm =
        NULLIF(@product_width_cm, '');
