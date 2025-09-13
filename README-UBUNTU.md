# rbldnsd MySQL Setup for Ubuntu

This guide explains how to set up and compile rbldnsd with MySQL support on Ubuntu/Debian systems.

## Quick Start

### Option 1: Automated Setup

```bash
# Make the setup script executable
chmod +x setup-ubuntu.sh

# Run the automated setup
./setup-ubuntu.sh
```

### Option 2: Manual Setup

```bash
# 1. Install dependencies
sudo apt-get update
sudo apt-get install -y build-essential libmysqlclient-dev mysql-client pkg-config

# 2. Compile using Ubuntu Makefile
make -f Makefile.ubuntu clean
make -f Makefile.ubuntu

# 3. Test the binary
./rbldnsd --help
```

## Key Differences from macOS

The Ubuntu Makefile (`Makefile.ubuntu`) differs from the macOS version in several ways:

### 1. MySQL Library Detection

**macOS (Homebrew)**:
```makefile
CFLAGS += -I/opt/homebrew/opt/mysql-client/include
LIBS = -lz -L/opt/homebrew/opt/mysql-client/lib -lmysqlclient
```

**Ubuntu**:
```makefile
MYSQL_CFLAGS := $(shell pkg-config --cflags mysqlclient 2>/dev/null || echo "-I/usr/include/mysql")
MYSQL_LIBS := $(shell pkg-config --libs mysqlclient 2>/dev/null || echo "-lmysqlclient")
CFLAGS += $(MYSQL_CFLAGS)
LIBS = -lz $(MYSQL_LIBS)
```

### 2. Package Management

Ubuntu uses `apt-get` instead of Homebrew:
- `libmysqlclient-dev` instead of `mysql-client`
- Standard system paths instead of Homebrew paths
- `pkg-config` for library detection

## Dependencies

### Required Packages

```bash
sudo apt-get install -y \
    build-essential \
    libmysqlclient-dev \
    mysql-client \
    pkg-config \
    make \
    gcc
```

### Optional Packages

```bash
# For MySQL server (if not using Docker)
sudo apt-get install -y mysql-server

# For development tools
sudo apt-get install -y git vim
```

## Compilation

### Using Ubuntu Makefile

```bash
# Clean and compile
make -f Makefile.ubuntu clean
make -f Makefile.ubuntu

# Check if compilation was successful
ls -la rbldnsd
```

### Troubleshooting Compilation

If you get linking errors:

```bash
# Check if MySQL libraries are found
pkg-config --cflags mysqlclient
pkg-config --libs mysqlclient

# Check if MySQL headers exist
ls -la /usr/include/mysql/

# Check if MySQL libraries exist
ls -la /usr/lib/*/libmysqlclient*
```

## Running rbldnsd

### With Local MySQL

```bash
# Start MySQL service
sudo systemctl start mysql

# Setup database
mysql -u root -p < setup_mysql_rbl.sql

# Start rbldnsd
./rbldnsd -b 0.0.0.0/1053 -c 3 mysql
```

### With Docker MySQL

```bash
# Start MySQL container
docker run --name rbldnsd-mysql \
  -e MYSQL_ROOT_PASSWORD=password \
  -e MYSQL_DATABASE=rbl_db \
  -p 3306:3306 \
  -d mysql:8.0

# Wait for MySQL to start
sleep 30

# Setup database
docker exec -i rbldnsd-mysql mysql -u root -ppassword < setup_mysql_rbl.sql

# Start rbldnsd
./rbldnsd -b 0.0.0.0/1053 -c 3 mysql
```

## Testing

```bash
# Test DNS queries
dig @127.0.0.1 -p 1053 103.87.141.54.xbl.spamhaus.org
dig @127.0.0.1 -p 1053 203.0.113.1.sbl.spamhaus.org

# Test non-existent IP (should return NXDOMAIN)
dig @127.0.0.1 -p 1053 1.2.3.4.xbl.spamhaus.org
```

## Management Commands

```bash
# Compile
make -f Makefile.ubuntu

# Clean
make -f Makefile.ubuntu clean

# Check dependencies
make -f Makefile.ubuntu check-deps

# Install dependencies
make -f Makefile.ubuntu install-deps

# Run tests
make -f Makefile.ubuntu test
```

## Common Issues

### 1. "mysql.h: No such file or directory"

**Solution**: Install MySQL development libraries
```bash
sudo apt-get install libmysqlclient-dev
```

### 2. "undefined reference to `mysql_init'"

**Solution**: Ensure MySQL libraries are linked
```bash
# Check if libmysqlclient is available
ldconfig -p | grep mysql
```

### 3. "pkg-config: command not found"

**Solution**: Install pkg-config
```bash
sudo apt-get install pkg-config
```

### 4. "invalid zone spec mysql"

**Solution**: Ensure the binary was compiled with MySQL support
```bash
make -f Makefile.ubuntu clean
make -f Makefile.ubuntu
```

## File Structure

```
rbldnsd/
├── Makefile.ubuntu      # Ubuntu-specific Makefile
├── setup-ubuntu.sh      # Automated setup script
├── README-UBUNTU.md     # This file
├── rbldnsd_mysql.c      # MySQL dataset implementation
├── setup_mysql_rbl.sql  # Database setup script
└── ...                  # Other source files
```

## Production Deployment

For production use on Ubuntu:

1. **Use systemd service**:
   ```bash
   sudo cp contrib/systemd/rbldnsd.service /etc/systemd/system/
   sudo systemctl enable rbldnsd
   sudo systemctl start rbldnsd
   ```

2. **Configure firewall**:
   ```bash
   sudo ufw allow 1053/udp
   ```

3. **Setup log rotation**:
   ```bash
   sudo logrotate -d /etc/logrotate.d/rbldnsd
   ```

4. **Monitor with systemd**:
   ```bash
   sudo systemctl status rbldnsd
   sudo journalctl -u rbldnsd -f
   ```

This setup provides a complete rbldnsd environment optimized for Ubuntu systems.
