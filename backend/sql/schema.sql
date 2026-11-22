-- RideSync MariaDB schema
-- Run in DBeaver, mariadb CLI, or via `python init_db.py`.

CREATE DATABASE IF NOT EXISTS ridesync
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE ridesync;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL DEFAULT '',
  name VARCHAR(100) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS rides (
  id INT AUTO_INCREMENT PRIMARY KEY,
  code CHAR(6) NOT NULL UNIQUE,
  destination VARCHAR(255) NOT NULL,
  dest_lat DOUBLE NULL,
  dest_lng DOUBLE NULL,
  host_id INT NOT NULL,
  started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at DATETIME NULL,
  CONSTRAINT fk_rides_host FOREIGN KEY (host_id) REFERENCES users (id)
);

CREATE TABLE IF NOT EXISTS ride_members (
  ride_id INT NOT NULL,
  user_id INT NOT NULL,
  joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (ride_id, user_id),
  CONSTRAINT fk_members_ride FOREIGN KEY (ride_id) REFERENCES rides (id) ON DELETE CASCADE,
  CONSTRAINT fk_members_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS positions (
  ride_id INT NOT NULL,
  user_id INT NOT NULL,
  latitude DOUBLE NOT NULL,
  longitude DOUBLE NOT NULL,
  speed DOUBLE NOT NULL DEFAULT 0,
  battery TINYINT UNSIGNED NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (ride_id, user_id),
  CONSTRAINT fk_positions_ride FOREIGN KEY (ride_id) REFERENCES rides (id) ON DELETE CASCADE,
  CONSTRAINT fk_positions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
