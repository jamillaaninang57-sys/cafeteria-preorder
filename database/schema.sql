-- CSPC Cafeteria Pre-Order System: database schema (MySQL 8 / MariaDB 10.5+)
-- Safe to run more than once (CREATE TABLE IF NOT EXISTS). It does NOT create or select a database,
-- so it also works on managed MySQL hosts: pick your database first, then run this file.
--   mysql -h HOST -P PORT -u USER -p DATABASE_NAME < database/schema.sql
-- Local XAMPP / phpMyAdmin: create a database named cafeteria_preorder, open it, then Import this file.

CREATE TABLE IF NOT EXISTS settings(
  setting_key   VARCHAR(64)  NOT NULL PRIMARY KEY,
  setting_value VARCHAR(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- utf8mb4_unicode_ci is case-insensitive, so email / ID number are unique regardless of upper or lower case
CREATE TABLE IF NOT EXISTS users(
  id            INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(60)  NOT NULL,
  id_number     VARCHAR(20)  NOT NULL UNIQUE,
  email         VARCHAR(80)  NOT NULL UNIQUE,
  role          ENUM('customer','staff') NOT NULL,
  user_type     ENUM('student','employee','instructor','administrator','staff') NOT NULL DEFAULT 'student',
  department    VARCHAR(60)  NOT NULL DEFAULT '',
  contact       VARCHAR(20)  NOT NULL DEFAULT '',
  password_hash VARCHAR(255) NOT NULL,
  photo         VARCHAR(255) NOT NULL DEFAULT '',
  pw_set        TINYINT      NOT NULL DEFAULT 1,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS menu_items(
  id           INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(40)  NOT NULL,
  category     ENUM('Main Dish','Snacks','Drinks','Dessert') NOT NULL,
  price        DECIMAL(8,2) NOT NULL,
  stock        INT          NOT NULL DEFAULT 0,
  prep_minutes INT          NOT NULL DEFAULT 10,
  description  TEXT,
  ingredients  TEXT,
  allergens    TEXT,
  rating       DECIMAL(2,1) NOT NULL DEFAULT 4.5,
  image        VARCHAR(255) NOT NULL DEFAULT '',
  active       TINYINT      NOT NULL DEFAULT 1,
  CONSTRAINT chk_menu_price CHECK (price >= 0),
  CONSTRAINT chk_menu_stock CHECK (stock >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- created_at on the tables below holds an ISO-8601 text timestamp written by the app (e.g. 2026-11-22T08:30:00.000Z)
CREATE TABLE IF NOT EXISTS orders(
  id          INT AUTO_INCREMENT PRIMARY KEY,
  order_no    VARCHAR(16)  NOT NULL UNIQUE,
  order_date  CHAR(8)      NOT NULL,
  user_id     INT          NOT NULL,
  slot        VARCHAR(5)   NOT NULL,
  slot_label  VARCHAR(30)  NOT NULL,
  service_fee DECIMAL(8,2) NOT NULL,
  total       DECIMAL(8,2) NOT NULL,
  status      ENUM('pending','preparing','ready','claimed','cancelled') NOT NULL DEFAULT 'pending',
  created_at  VARCHAR(30)  NOT NULL,
  payment     ENUM('cash','gcash') NOT NULL DEFAULT 'cash',
  CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES users(id),
  INDEX idx_orders_date (order_date, slot),
  INDEX idx_orders_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS order_items(
  id         INT AUTO_INCREMENT PRIMARY KEY,
  order_id   INT          NOT NULL,
  item_id    INT          NOT NULL,
  name       VARCHAR(40)  NOT NULL,
  category   VARCHAR(20),
  unit_price DECIMAL(8,2) NOT NULL,
  quantity   INT          NOT NULL,
  CONSTRAINT chk_oi_qty CHECK (quantity > 0),
  CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_oi_item  FOREIGN KEY (item_id)  REFERENCES menu_items(id),
  INDEX idx_items_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS order_status_log(
  id         INT AUTO_INCREMENT PRIMARY KEY,
  order_id   INT         NOT NULL,
  status     VARCHAR(12) NOT NULL,
  changed_at VARCHAR(30) NOT NULL,
  CONSTRAINT fk_log_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS audit_log(
  id         INT AUTO_INCREMENT PRIMARY KEY,
  created_at VARCHAR(30)  NOT NULL,
  user_ref   VARCHAR(20),
  role       VARCHAR(20),
  action     VARCHAR(40)  NOT NULL,
  detail     VARCHAR(500)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- In-app notifications (order updates for customers, new orders for staff). Kept in the database so a person
-- still sees them if they were offline when the status changed.
CREATE TABLE IF NOT EXISTS notifications(
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT          NOT NULL,
  order_no   VARCHAR(20),
  kind       VARCHAR(20)  NOT NULL,
  title      VARCHAR(255) NOT NULL,
  body       TEXT         NOT NULL,
  created_at VARCHAR(30)  NOT NULL,
  read_at    VARCHAR(30),
  CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES users(id),
  INDEX idx_notifications_user (user_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
