#!/bin/bash

# Ubuntu setup script for rbldnsd with MySQL support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🐧 Ubuntu Setup for rbldnsd with MySQL"
echo "======================================"

# Check if running on Ubuntu/Debian
if ! command -v apt-get &> /dev/null; then
    print_error "This script is designed for Ubuntu/Debian systems"
    exit 1
fi

print_step "1. Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libmysqlclient-dev \
    mysql-client \
    pkg-config \
    make \
    gcc

print_success "Dependencies installed"

print_step "2. Checking MySQL development libraries..."
if pkg-config --exists mysqlclient; then
    print_success "MySQL client found via pkg-config"
    echo "CFLAGS: $(pkg-config --cflags mysqlclient)"
    echo "LIBS: $(pkg-config --libs mysqlclient)"
elif [ -f /usr/include/mysql/mysql.h ]; then
    print_success "MySQL client found in /usr/include/mysql"
else
    print_error "MySQL client not found. Please install libmysqlclient-dev"
    exit 1
fi

print_step "3. Cleaning previous build..."
make -f Makefile.ubuntu clean 2>/dev/null || true

print_step "4. Compiling rbldnsd..."
make -f Makefile.ubuntu clean
make -f Makefile.ubuntu

if [ $? -eq 0 ]; then
    print_success "Compilation successful! 🎉"
else
    print_error "Compilation failed"
    exit 1
fi

print_step "5. Testing the binary..."
if [ -f "./rbldnsd" ]; then
    print_success "rbldnsd binary created successfully"
    echo "Binary size: $(ls -lh rbldnsd | awk '{print $5}')"
else
    print_error "rbldnsd binary not found"
    exit 1
fi

echo ""
print_success "Setup complete! 🎉"
echo ""
echo "📋 Next steps:"
echo "1. Start MySQL server:"
echo "   sudo systemctl start mysql"
echo "   # or with Docker:"
echo "   docker run --name rbldnsd-mysql -e MYSQL_ROOT_PASSWORD=password -e MYSQL_DATABASE=rbl_db -p 3306:3306 -d mysql:8.0"
echo ""
echo "2. Setup database:"
echo "   mysql -u root -p < setup_mysql_rbl.sql"
echo ""
echo "3. Start rbldnsd:"
echo "   ./rbldnsd -b 0.0.0.0/1053 -c 3 mysql"
echo ""
echo "4. Test:"
echo "   dig @127.0.0.1 -p 1053 103.87.141.54.xbl.spamhaus.org"
echo ""
echo "🔧 Management commands:"
echo "   Compile: make -f Makefile.ubuntu"
echo "   Clean:   make -f Makefile.ubuntu clean"
echo "   Test:    make -f Makefile.ubuntu test"
