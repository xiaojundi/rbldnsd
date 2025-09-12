# rbldnsd MySQL Setup Guide

This guide explains how to set up and use the rbldnsd DNS server with MySQL database for RBL (Real-time Blackhole List) functionality.

## Overview

rbldnsd is a DNS daemon that provides RBL services. When configured with MySQL, it loads IP blacklist data from a database and responds to DNS queries with appropriate return codes.

## Prerequisites

- MySQL server running
- MySQL client libraries installed
- Compiler (gcc) and make

## Database Setup

### 1. Create the Database and Table

```bash
mysql -u root -p
```

```sql
-- Create database
CREATE DATABASE IF NOT EXISTS rbl_db;
USE rbl_db;

-- Create table for RBL data
CREATE TABLE IF NOT EXISTS rbl_ips (
    id INT AUTO_INCREMENT PRIMARY KEY,
    zone VARCHAR(255) NOT NULL,           -- e.g., xbl.spamhaus.org
    ip VARCHAR(45) NOT NULL,              -- IPv4 address in REVERSED format
    return_code VARCHAR(15) DEFAULT '127.0.0.2',  -- Return value for DNS query
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_zone (zone),
    INDEX idx_ip (ip),
    UNIQUE KEY unique_zone_ip (zone, ip)
);
```

### 2. Insert Sample Data

**IMPORTANT**: IP addresses must be stored in REVERSED format (as they appear in DNS queries).

```sql
-- Insert sample data with REVERSED IPs
INSERT INTO rbl_ips (zone, ip, return_code) VALUES
('xbl.spamhaus.org', '54.141.87.103', '127.0.0.2'),  -- 103.87.141.54 reversed
('xbl.spamhaus.org', '54.141.87.104', '127.0.0.3'),  -- 104.87.141.54 reversed
('xbl.spamhaus.org', '1.1.168.192', '127.0.0.2'),    -- 192.168.1.1 reversed
('xbl.spamhaus.org', '1.0.0.10', '127.0.0.5'),       -- 10.0.0.1 reversed
('sbl.spamhaus.org', '1.113.0.203', '127.0.0.2'),    -- 203.0.113.1 reversed
('sbl.spamhaus.org', '2.113.0.203', '127.0.0.3');    -- 203.0.113.2 reversed
```

### 3. Verify Data

```sql
SELECT * FROM rbl_ips ORDER BY zone, ip;
```

## Compilation

```bash
# Compile the rbldnsd binary
make clean
make

# This creates the rbldnsd executable
```

## Running the Server

### Start the Server

```bash
# Kill any existing rbldnsd processes
pkill -9 rbldnsd

# Start rbldnsd with MySQL dataset
./rbldnsd -n -b 0.0.0.0/1053 -c 3 mysql

# Options:
# -n: Don't daemonize (run in foreground for debugging)
# -b 0.0.0.0/1053: Bind to all interfaces on port 1053
# -c 3: Check for updates every 3 seconds
# mysql: Use MySQL dataset type
```

### Run as Daemon (Background)

```bash
# Start in background
./rbldnsd -b 0.0.0.0/1053 -c 3 mysql &

# Check if running
ps aux | grep rbldnsd
```

## Testing with dig

### Basic Query Format

For RBL queries, the IP address is automatically reversed in the DNS query:

- **Original IP**: `103.87.141.54`
- **DNS Query**: `103.87.141.54.xbl.spamhaus.org`
- **What rbldnsd receives**: `54.141.87.103.xbl.spamhaus.org` (reversed)

### Test Queries

```bash
# Test xbl.spamhaus.org zone
dig @127.0.0.1 -p 1053 103.87.141.54.xbl.spamhaus.org
dig @127.0.0.1 -p 1053 104.87.141.54.xbl.spamhaus.org
dig @127.0.0.1 -p 1053 10.0.0.1.xbl.spamhaus.org

# Test sbl.spamhaus.org zone
dig @127.0.0.1 -p 1053 203.0.113.1.sbl.spamhaus.org
dig @127.0.0.1 -p 1053 203.0.113.2.sbl.spamhaus.org

# Test non-existent IP (should return NXDOMAIN)
dig @127.0.0.1 -p 1053 1.2.3.4.xbl.spamhaus.org
```

### Expected Responses

**Successful queries** return:
```
;; ANSWER SECTION:
103.87.141.54.xbl.spamhaus.org. 2100 IN A       127.0.0.2
```

**Non-existent IPs** return:
```
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 12345
```

## Understanding RBL Queries

### How IP Reversal Works

1. **User queries**: `103.87.141.54.xbl.spamhaus.org`
2. **DNS system automatically reverses**: `54.141.87.103.xbl.spamhaus.org`
3. **rbldnsd receives**: `54.141.87.103` (parsed from DNS query)
4. **Database lookup**: Searches for `54.141.87.103` in the `xbl.spamhaus.org` zone
5. **Response**: Returns the `return_code` from the database

### Database IP Format

Store IPs in the database in **reversed format** (as they appear in DNS queries):

| Original IP | Reversed IP (for DB) | DNS Query |
|-------------|---------------------|-----------|
| 103.87.141.54 | 54.141.87.103 | 103.87.141.54.xbl.spamhaus.org |
| 192.168.1.1 | 1.1.168.192 | 192.168.1.1.xbl.spamhaus.org |
| 10.0.0.1 | 1.0.0.10 | 10.0.0.1.xbl.spamhaus.org |

## Troubleshooting

### Check Server Status

```bash
# Check if rbldnsd is running
ps aux | grep rbldnsd

# Check port binding
netstat -an | grep 1053
```

### Debug Mode

Run with debug output to see what's happening:

```bash
./rbldnsd -n -b 0.0.0.0/1053 -c 3 mysql
```

Look for debug messages like:
- `DEBUG: Loading data from MySQL database for zone: xbl.spamhaus.org`
- `DEBUG: Querying IP: 54.141.87.103`
- `DEBUG: Found match! Returning: 127.0.0.2`

### Common Issues

1. **"Address already in use"**: Kill existing processes with `pkill -9 rbldnsd`
2. **"SERVFAIL" responses**: Check MySQL connection and database setup
3. **"NXDOMAIN" for known IPs**: Verify IP is stored in reversed format in database
4. **Wrong return codes**: Check the `return_code` column in database

### Database Verification

```sql
-- Check what's loaded for each zone
SELECT zone, ip, return_code FROM rbl_ips ORDER BY zone, ip;

-- Verify specific IP exists
SELECT * FROM rbl_ips WHERE ip = '54.141.87.103';
```

## Adding New IPs

To add new IPs to the blacklist:

1. **Reverse the IP**: `192.168.1.100` → `100.1.168.192`
2. **Insert into database**:

```sql
INSERT INTO rbl_ips (zone, ip, return_code) VALUES
('xbl.spamhaus.org', '100.1.168.192', '127.0.0.2');
```

3. **Test the query**:

```bash
dig @127.0.0.1 -p 1053 192.168.1.100.xbl.spamhaus.org
```

## Zone Management

Each zone operates independently:

- `xbl.spamhaus.org`: Contains IPs for XBL (Exploits Block List)
- `sbl.spamhaus.org`: Contains IPs for SBL (Spamhaus Block List)

IPs can exist in multiple zones with different return codes.

## Security Notes

- The server binds to `0.0.0.0` (all interfaces) - consider restricting this in production
- No authentication is required for DNS queries
- Consider firewall rules to limit access
- Monitor logs for abuse patterns

## Production Deployment

For production use:

1. **Run as daemon**: Remove `-n` flag
2. **Configure logging**: Set up proper log rotation
3. **Monitor performance**: Watch CPU and memory usage
4. **Backup database**: Regular MySQL backups
5. **Security hardening**: Restrict network access as needed

## Example Complete Workflow

```bash
# 1. Setup database
mysql -u root -p < setup_mysql_rbl.sql

# 2. Compile
make

# 3. Start server
./rbldnsd -b 0.0.0.0/1053 -c 3 mysql &

# 4. Test
dig @127.0.0.1 -p 1053 103.87.141.54.xbl.spamhaus.org

# 5. Add new IP
mysql -u root -p -e "USE rbl_db; INSERT INTO rbl_ips (zone, ip, return_code) VALUES ('xbl.spamhaus.org', '100.1.168.192', '127.0.0.2');"

# 6. Test new IP
dig @127.0.0.1 -p 1053 192.168.1.100.xbl.spamhaus.org
```

This setup provides a fully functional RBL DNS server with MySQL backend for dynamic IP blacklist management.
