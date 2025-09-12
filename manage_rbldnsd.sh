#!/bin/bash

# rbldnsd Management Script

SERVER_PORT=1053
MYSQL_DB="rbl_db"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if rbldnsd is running
is_running() {
    pgrep -f "rbldnsd.*$SERVER_PORT" > /dev/null
}

# Function to start the server
start_server() {
    if is_running; then
        print_warning "rbldnsd is already running on port $SERVER_PORT"
        return 1
    fi
    
    print_status "Starting rbldnsd server on port $SERVER_PORT..."
    ./rbldnsd -b 0.0.0.0/$SERVER_PORT -c 3 mysql &
    sleep 2
    
    if is_running; then
        print_status "rbldnsd started successfully"
        echo "PID: $(pgrep -f "rbldnsd.*$SERVER_PORT")"
    else
        print_error "Failed to start rbldnsd"
        return 1
    fi
}

# Function to start server in debug mode
start_debug() {
    if is_running; then
        print_warning "rbldnsd is already running on port $SERVER_PORT"
        return 1
    fi
    
    print_status "Starting rbldnsd in debug mode..."
    ./rbldnsd -n -b 0.0.0.0/$SERVER_PORT -c 3 mysql
}

# Function to stop the server
stop_server() {
    if ! is_running; then
        print_warning "rbldnsd is not running"
        return 1
    fi
    
    print_status "Stopping rbldnsd..."
    pkill -9 -f "rbldnsd.*$SERVER_PORT"
    sleep 1
    
    if ! is_running; then
        print_status "rbldnsd stopped successfully"
    else
        print_error "Failed to stop rbldnsd"
        return 1
    fi
}

# Function to restart the server
restart_server() {
    print_status "Restarting rbldnsd..."
    stop_server
    sleep 1
    start_server
}

# Function to check server status
status() {
    if is_running; then
        print_status "rbldnsd is running on port $SERVER_PORT"
        echo "PID: $(pgrep -f "rbldnsd.*$SERVER_PORT")"
        echo "Port: $SERVER_PORT"
    else
        print_warning "rbldnsd is not running"
    fi
}

# Function to test DNS queries
test_query() {
    local ip="$1"
    local zone="$2"
    
    if [ -z "$ip" ] || [ -z "$zone" ]; then
        echo "Usage: $0 test <IP> <ZONE>"
        echo "Example: $0 test 103.87.141.54 xbl.spamhaus.org"
        return 1
    fi
    
    if ! is_running; then
        print_error "rbldnsd is not running. Start it first with: $0 start"
        return 1
    fi
    
    print_status "Testing query: $ip.$zone"
    dig @127.0.0.1 -p $SERVER_PORT $ip.$zone
}

# Function to add IP to database
add_ip() {
    local ip="$1"
    local zone="$2"
    local return_code="$3"
    
    if [ -z "$ip" ] || [ -z "$zone" ] || [ -z "$return_code" ]; then
        echo "Usage: $0 add <IP> <ZONE> <RETURN_CODE>"
        echo "Example: $0 add 192.168.1.100 xbl.spamhaus.org 127.0.0.2"
        return 1
    fi
    
    # Reverse the IP
    local reversed_ip=$(echo $ip | awk -F. '{print $4"."$3"."$2"."$1}')
    
    print_status "Adding IP $ip (reversed: $reversed_ip) to zone $zone with return code $return_code"
    
    mysql -u root -e "USE $MYSQL_DB; INSERT INTO rbl_ips (zone, ip, return_code) VALUES ('$zone', '$reversed_ip', '$return_code');" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_status "IP added successfully"
        echo "You can test with: $0 test $ip $zone"
    else
        print_error "Failed to add IP to database"
        return 1
    fi
}

# Function to show database contents
show_db() {
    local zone="$1"
    
    if [ -n "$zone" ]; then
        print_status "Showing IPs for zone: $zone"
        mysql -u root -e "USE $MYSQL_DB; SELECT ip, return_code FROM rbl_ips WHERE zone = '$zone' ORDER BY ip;" 2>/dev/null
    else
        print_status "Showing all IPs in database:"
        mysql -u root -e "USE $MYSQL_DB; SELECT zone, ip, return_code FROM rbl_ips ORDER BY zone, ip;" 2>/dev/null
    fi
}

# Function to compile the server
compile() {
    print_status "Compiling rbldnsd..."
    make clean && make
    
    if [ $? -eq 0 ]; then
        print_status "Compilation successful"
    else
        print_error "Compilation failed"
        return 1
    fi
}

# Function to show help
show_help() {
    echo "rbldnsd Management Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  start       Start rbldnsd server in background"
    echo "  debug       Start rbldnsd server in debug mode (foreground)"
    echo "  stop        Stop rbldnsd server"
    echo "  restart     Restart rbldnsd server"
    echo "  status      Show server status"
    echo "  test <IP> <ZONE>     Test DNS query"
    echo "  add <IP> <ZONE> <CODE>  Add IP to database"
    echo "  show [ZONE]           Show database contents"
    echo "  compile     Compile rbldnsd"
    echo "  help        Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 test 103.87.141.54 xbl.spamhaus.org"
    echo "  $0 add 192.168.1.100 xbl.spamhaus.org 127.0.0.2"
    echo "  $0 show xbl.spamhaus.org"
}

# Main script logic
case "$1" in
    start)
        start_server
        ;;
    debug)
        start_debug
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        status
        ;;
    test)
        test_query "$2" "$3"
        ;;
    add)
        add_ip "$2" "$3" "$4"
        ;;
    show)
        show_db "$2"
        ;;
    compile)
        compile
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
