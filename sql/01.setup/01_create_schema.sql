-- New database only: no DROP/TRUNCATE; CREATE fails if tables already exist.

CREATE DATABASE IF NOT EXISTS olist CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE olist;

CREATE TABLE olist_customers_dataset (
    `customer_id` CHAR(32) NOT NULL,
    `customer_unique_id` CHAR(32) NULL,
    `customer_zip_code_prefix` CHAR(5) NULL,
    `customer_city` VARCHAR(255) NULL,
    `customer_state` CHAR(2) NULL,
    PRIMARY KEY (`customer_id`)
) ENGINE=InnoDB;

CREATE TABLE olist_geolocation_dataset (
    `geolocation_zip_code_prefix` CHAR(5) NULL,
    `geolocation_lat` DECIMAL(12,8) NULL,
    `geolocation_lng` DECIMAL(12,8) NULL,
    `geolocation_city` VARCHAR(255) NULL,
    `geolocation_state` CHAR(2) NULL
) ENGINE=InnoDB;

CREATE TABLE olist_order_items_dataset (
    `order_id` CHAR(32) NOT NULL,
    `order_item_id` INT NOT NULL,
    `product_id` CHAR(32) NULL,
    `seller_id` CHAR(32) NULL,
    `shipping_limit_date` DATETIME NULL,
    `price` DECIMAL(12,2) NULL,
    `freight_value` DECIMAL(12,2) NULL,
    PRIMARY KEY (`order_id`, `order_item_id`),
    INDEX idx_seller_id (`seller_id`),
    INDEX idx_product_id (`product_id`)
) ENGINE=InnoDB;

CREATE TABLE olist_order_payments_dataset (
    `order_id` CHAR(32) NOT NULL,
    `payment_sequential` INT NOT NULL,
    `payment_type` VARCHAR(255) NULL,
    `payment_installments` INT NULL,
    `payment_value` DECIMAL(12,2) NULL,
    PRIMARY KEY (`order_id`, `payment_sequential`)
) ENGINE=InnoDB;

CREATE TABLE olist_order_reviews_dataset (
    review_row_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `review_id` CHAR(32) NULL,
    `order_id` CHAR(32) NULL,
    `review_score` INT NULL,
    `review_comment_title` TEXT NULL,
    `review_comment_message` TEXT NULL,
    `review_creation_date` DATETIME NULL,
    `review_answer_timestamp` DATETIME NULL,
    INDEX idx_order_id (`order_id`)
) ENGINE=InnoDB;

CREATE TABLE olist_orders_dataset (
    `order_id` CHAR(32) NOT NULL,
    `customer_id` CHAR(32) NULL,
    `order_status` VARCHAR(255) NULL,
    `order_purchase_timestamp` DATETIME NULL,
    `order_approved_at` DATETIME NULL,
    `order_delivered_carrier_date` DATETIME NULL,
    `order_delivered_customer_date` DATETIME NULL,
    `order_estimated_delivery_date` DATETIME NULL,
    PRIMARY KEY (`order_id`),
    INDEX idx_customer_id (`customer_id`)
) ENGINE=InnoDB;

CREATE TABLE olist_products_dataset (
    `product_id` CHAR(32) NOT NULL,
    `product_category_name` VARCHAR(255) NULL,
    `product_name_lenght` INT NULL,
    `product_description_lenght` INT NULL,
    `product_photos_qty` INT NULL,
    `product_weight_g` INT NULL,
    `product_length_cm` INT NULL,
    `product_height_cm` INT NULL,
    `product_width_cm` INT NULL,
    PRIMARY KEY (`product_id`)
) ENGINE=InnoDB;

CREATE TABLE olist_sellers_dataset (
    `seller_id` CHAR(32) NOT NULL,
    `seller_zip_code_prefix` CHAR(5) NULL,
    `seller_city` VARCHAR(255) NULL,
    `seller_state` CHAR(2) NULL,
    PRIMARY KEY (`seller_id`)
) ENGINE=InnoDB;

CREATE TABLE product_category_name_translation (
    `product_category_name` VARCHAR(255) NOT NULL,
    `product_category_name_english` VARCHAR(255) NULL,
    PRIMARY KEY (`product_category_name`)
) ENGINE=InnoDB;
