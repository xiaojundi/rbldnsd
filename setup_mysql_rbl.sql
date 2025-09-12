-- Setup MySQL database for rbldnsd
CREATE DATABASE IF NOT EXISTS rbl_db;
USE rbl_db;

-- Create table for RBL data
CREATE TABLE IF NOT EXISTS rbl_ips (
    id INT AUTO_INCREMENT PRIMARY KEY,
    zone VARCHAR(255) NOT NULL,           -- e.g., xbl.spamhaus.org
    ip VARCHAR(45) NOT NULL,              -- IPv4 or IPv6 address
    return_code VARCHAR(15) DEFAULT '127.0.0.2',  -- Return value for DNS query
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_zone (zone),
    INDEX idx_ip (ip),
    UNIQUE KEY unique_zone_ip (zone, ip)
);

-- Insert sample data
INSERT INTO rbl_ips (zone, ip, return_code) VALUES
('xbl.spamhaus.org', '103.87.141.54', '127.0.0.2'),
('xbl.spamhaus.org', '104.87.141.54', '127.0.0.3'),
('xbl.spamhaus.org', '192.168.1.0/24', '127.0.0.4'),
('xbl.spamhaus.org', '10.0.0.1', '127.0.0.5'),
('sbl.spamhaus.org', '203.0.113.1', '127.0.0.2'),
('sbl.spamhaus.org', '203.0.113.2', '127.0.0.3');

-- Show the data
SELECT * FROM rbl_ips;
