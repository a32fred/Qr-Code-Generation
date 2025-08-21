#!/bin/bash

echo "🐍 QR API Python - Ultra Simple"
echo "================================"

# Install Python if not exists
if ! command -v python3 &> /dev/null; then
    echo "Installing Python..."
    sudo apt update && sudo apt install -y python3 python3-pip
fi

# Install dependencies
echo "Installing dependencies..."
pip3 install -r requirements.txt

# Create data directory
mkdir -p data

# Run the app
echo "🚀 Starting QR API on port 5000..."
python3 app.py