#!/bin/bash
# setup.sh
# This runs ON the EC2 instance to install everything
# Save to: scripts/setup.sh

set -e

# CHANGE THIS to your GitHub username and repo
GITHUB_RAW="https://raw.githubusercontent.com/rhimchu/browser-automation/main"

echo "=== Setting up Browser Automation Environment ==="

# Install dependencies
echo "[1/5] Installing system packages..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    chromium-browser \
    chromium-chromedriver \
    xvfb \
    python3-pip \
    unzip \
    curl \
    wget

echo "[2/5] Installing Python packages..."
pip3 install selenium webdriver-manager

# Create directories
echo "[3/5] Creating directories..."
sudo mkdir -p /opt/automation/extensions
sudo mkdir -p /opt/automation/workflows
sudo chown -R ubuntu:ubuntu /opt/automation

cd /opt/automation

# Download extensions from GitHub
echo "[4/5] Downloading extensions from GitHub..."
curl -L "${GITHUB_RAW}/extensions/automa.crx" -o extensions/automa.crx
curl -L "${GITHUB_RAW}/extensions/captcha-solver.crx" -o extensions/captcha-solver.crx

# Download Automa workflow
echo "[5/5] Downloading workflow..."
curl -L "${GITHUB_RAW}/workflows/form-fill.automa.json" -o workflows/form-fill.automa.json

# Download automation script
curl -L "${GITHUB_RAW}/scripts/run_automation.py" -o run_automation.py

echo ""
echo "=== Setup Complete ==="
echo "Extensions downloaded to: /opt/automation/extensions/"
echo "Workflow downloaded to: /opt/automation/workflows/"
echo "Ready to run automation!"
