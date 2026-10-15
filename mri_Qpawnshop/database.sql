CREATE TABLE IF NOT EXISTS `pawnshop_shops` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(100) NOT NULL,
    `owner_cid` VARCHAR(50) DEFAULT NULL,
    `ownable` TINYINT(1) NOT NULL DEFAULT 1,
    `purchase_price` INT NOT NULL DEFAULT 75000,
    `starting_equity` INT NOT NULL DEFAULT 25000,
    `funds` INT NOT NULL DEFAULT 25000,
    `level` INT NOT NULL DEFAULT 1,
    `xp` INT NOT NULL DEFAULT 0,
    `rating` FLOAT NOT NULL DEFAULT 3.0,
    `os_theme` VARCHAR(20) NOT NULL DEFAULT 'classic',
    `is_open` TINYINT(1) NOT NULL DEFAULT 1,
    `buying_active` TINYINT(1) NOT NULL DEFAULT 1,
    `special_offers_active` TINYINT(1) NOT NULL DEFAULT 1,
    `collections_active` TINYINT(1) NOT NULL DEFAULT 1,
    `exports_active` TINYINT(1) NOT NULL DEFAULT 1,
    `ped_model` VARCHAR(60) NOT NULL DEFAULT 's_m_y_barman_01',
    `ped_scenario` VARCHAR(60) NOT NULL DEFAULT 'WORLD_HUMAN_STAND_IMPATIENT',
    `coords_data` LONGTEXT NOT NULL,
    `categories_data` LONGTEXT NOT NULL,
    `shelves_data` LONGTEXT DEFAULT NULL,
    `stashes_data` LONGTEXT DEFAULT NULL,
    `blip_data` LONGTEXT DEFAULT NULL,
    `stats_data` LONGTEXT DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `pawnshop_inventory` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `category` VARCHAR(50) NOT NULL,
    `item_name` VARCHAR(50) NOT NULL,
    `qty` INT NOT NULL DEFAULT 0,
    `price` INT NOT NULL DEFAULT 100,
    `rrp` INT NOT NULL DEFAULT 100,
    UNIQUE KEY `shop_item` (`shop_id`, `category`, `item_name`)
);

CREATE TABLE IF NOT EXISTS `pawnshop_pawns` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `item_name` VARCHAR(50) NOT NULL,
    `item_label` VARCHAR(100) NOT NULL,
    `qty` INT NOT NULL DEFAULT 1,
    `metadata` LONGTEXT DEFAULT NULL,
    `loan_amount` INT NOT NULL,
    `buyback_price` INT NOT NULL,
    `expires_at` INT NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'active',
    KEY `lookup_pawn` (`shop_id`, `citizenid`, `status`)
);

CREATE TABLE IF NOT EXISTS `pawnshop_workers` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `role_preset` VARCHAR(50) NOT NULL DEFAULT 'Caixa',
    `permissions` LONGTEXT NOT NULL,
    `rep_level` INT NOT NULL DEFAULT 1,
    `rep_xp` INT NOT NULL DEFAULT 0,
    `unclaimed_points` FLOAT NOT NULL DEFAULT 0,
    `total_sales` INT NOT NULL DEFAULT 0,
    UNIQUE KEY `shop_worker` (`shop_id`, `citizenid`)
);

CREATE TABLE IF NOT EXISTS `pawnshop_vehicles` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `model` VARCHAR(50) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `plate` VARCHAR(15) NOT NULL,
    `fuel` INT NOT NULL DEFAULT 100,
    `body` INT NOT NULL DEFAULT 100,
    `engine` INT NOT NULL DEFAULT 100,
    `status` VARCHAR(20) NOT NULL DEFAULT 'available',
    `insurance_cost` INT NOT NULL DEFAULT 500
);

CREATE TABLE IF NOT EXISTS `pawnshop_loyalty` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `customer_name` VARCHAR(100) NOT NULL,
    `tier` VARCHAR(20) NOT NULL DEFAULT 'Basico',
    `points` INT NOT NULL DEFAULT 0,
    `total_spent` INT NOT NULL DEFAULT 0,
    `expires_at` INT NOT NULL DEFAULT 0,
    UNIQUE KEY `shop_customer` (`shop_id`, `citizenid`)
);

CREATE TABLE IF NOT EXISTS `pawnshop_exports` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `item_name` VARCHAR(50) NOT NULL,
    `item_label` VARCHAR(100) NOT NULL,
    `qty` INT NOT NULL,
    `payout` INT NOT NULL,
    `xp_reward` INT NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
    `accepted_by` VARCHAR(100) DEFAULT NULL,
    `expires_at` INT NOT NULL
);

CREATE TABLE IF NOT EXISTS `pawnshop_emails` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `sender` VARCHAR(100) NOT NULL,
    `subject` VARCHAR(150) NOT NULL,
    `body` LONGTEXT NOT NULL,
    `action_type` VARCHAR(50) DEFAULT NULL,
    `action_status` VARCHAR(20) NOT NULL DEFAULT 'none',
    `is_confidential` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `pawnshop_logs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `log_type` VARCHAR(30) NOT NULL,
    `actor` VARCHAR(100) NOT NULL,
    `description` VARCHAR(255) NOT NULL,
    `amount` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS pawnshop_stock_lots (id INT AUTO_INCREMENT PRIMARY KEY,shop_id INT NOT NULL,category VARCHAR(50) NOT NULL,item_name VARCHAR(50) NOT NULL,qty INT NOT NULL,metadata LONGTEXT DEFAULT NULL,KEY stock_lookup(shop_id,category,item_name,qty));
CREATE TABLE IF NOT EXISTS pawnshop_supplier_missions (id INT AUTO_INCREMENT PRIMARY KEY,shop_id INT NOT NULL,citizenid VARCHAR(50) NOT NULL,cost INT NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'active',KEY active_missions(status,shop_id));
