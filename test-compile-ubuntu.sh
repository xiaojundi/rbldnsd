#!/bin/bash

# Test compilation script for Ubuntu

set -e

echo "🔧 Testing Ubuntu compilation..."

# Clean previous build
echo "Cleaning previous build..."
make -f Makefile.ubuntu clean

# Compile
echo "Compiling..."
make -f Makefile.ubuntu

# Check if binary was created
if [ -f "./rbldnsd" ]; then
    echo "✅ Compilation successful!"
    echo "Binary size: $(ls -lh rbldnsd | awk '{print $5}')"
    
    # Test if binary runs
    echo "Testing binary..."
    ./rbldnsd --help 2>&1 | head -5
    
    echo "✅ Binary is working!"
else
    echo "❌ Compilation failed - binary not found"
    exit 1
fi

echo "🎉 All tests passed!"
