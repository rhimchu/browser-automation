#!/bin/bash
# orchestrate.sh
# Run this from YOUR LOCAL MACHINE to start the automation
# Save to: scripts/orchestrate.sh

set -e

# ============================================
# CONFIGURATION - CHANGE THESE VALUES
# ============================================
REGION="ap-southeast-1"
INSTANCE_TYPE="t3.micro"                    # Free tier eligible
AMI_ID="ami-01811d4912b4ccb26"              # Ubuntu 22.04 in Singapore
KEY_NAME="browser-automation-key"            # From aws-initial-setup.sh
KEY_FILE="$HOME/.ssh/browser-automation-key.pem"
SECURITY_GROUP="sg-009d7b361acc0059f"                            # Fill this after running aws-initial-setup.sh

# Your GitHub repo URL (raw content URL)
GITHUB_USER="rhimchu"                        # Your GitHub username
GITHUB_REPO="browser-automation"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  AWS Browser Automation - Singapore   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if security group is set
if [ -z "$SECURITY_GROUP" ]; then
    echo -e "${RED}ERROR: SECURITY_GROUP is not set!${NC}"
    echo "Please run ./aws-initial-setup.sh first, then update this script."
    exit 1
fi

# Check if key file exists
if [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}ERROR: Key file not found: $KEY_FILE${NC}"
    echo "Please run ./aws-initial-setup.sh first."
    exit 1
fi

# 1. Launch EC2 instance
echo -e "${YELLOW}[1/5] Launching EC2 instance...${NC}"
INSTANCE_ID=$(aws ec2 run-instances \
    --region $REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=browser-automation-$(date +%Y%m%d-%H%M%S)}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✓ Instance launched: $INSTANCE_ID${NC}"

# Set trap to terminate instance on script exit (cleanup)
cleanup() {
    echo ""
    echo -e "${YELLOW}[5/5] Cleaning up - Terminating instance...${NC}"
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION > /dev/null
    echo -e "${GREEN}✓ Instance $INSTANCE_ID terminated${NC}"
}
trap cleanup EXIT

# 2. Wait for instance to be running
echo -e "${YELLOW}[2/5] Waiting for instance to start...${NC}"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

PUBLIC_IP=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo -e "${GREEN}✓ Instance running at: $PUBLIC_IP${NC}"

# 3. Wait for SSH to be ready
echo -e "${YELLOW}[3/5] Waiting for SSH to be ready...${NC}"
echo "    (This may take 30-60 seconds...)"

MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i "$KEY_FILE" ubuntu@$PUBLIC_IP "echo 'SSH ready'" 2>/dev/null; then
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "    Attempt $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${RED}ERROR: Could not connect via SSH${NC}"
    exit 1
fi

echo -e "${GREEN}✓ SSH connection established${NC}"

# 4. Run setup and automation
echo -e "${YELLOW}[4/5] Running automation on instance...${NC}"
echo ""

ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$PUBLIC_IP << REMOTE_SCRIPT
    set -e
    
    echo "=== Creating swap file (prevents memory issues) ==="
    sudo fallocate -l 1G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    
    echo "=== Installing dependencies ==="
    sudo apt-get update -qq
    
    # Install Google Chrome (avoids Ubuntu snap issues)
    wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo apt-get install -y /tmp/chrome.deb
    
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        xvfb \
        unzip \
        curl \
        imagemagick \
        python3-pip
    
    pip3 install selenium --break-system-packages
    
    echo "=== Downloading extensions from GitHub ==="
    mkdir -p /tmp/extensions
    cd /tmp/extensions
    
    # Download Automa (zipped folder with your workflows)
    curl -sL "${GITHUB_RAW}/extensions/1.29.12_0.zip" -o automa.zip
    unzip -o -q automa.zip -d .
    mv 1.29.12_0 automa
    
    # Download and extract captcha solver
    curl -sL "${GITHUB_RAW}/extensions/captcha-solver.crx" -o captcha-solver.crx
    mkdir -p captcha-solver
    unzip -o -q captcha-solver.crx -d captcha-solver 2>/dev/null || python3 -c "
import zipfile, io
data = open('captcha-solver.crx', 'rb').read()
start = data.find(b'PK\x03\x04')
zipfile.ZipFile(io.BytesIO(data[start:])).extractall('captcha-solver')
"
    
    echo "=== Starting browser with Automa ==="
    export DISPLAY=:99
    Xvfb :99 -screen 0 1920x1080x24 &
    sleep 2
    
    # Download workflow JSON
    curl -sL "${GITHUB_RAW}/workflows/form-fill.automa.json" -o /tmp/workflow.json
    
    # Create and run Python script to import workflow and execute
    cat > /tmp/run_automa.py << 'PYTHON_SCRIPT'
import os
import sys
import time
import json
import glob

os.environ["DISPLAY"] = ":99"

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

print("Setting up Chrome...")
options = Options()
options.binary_location = "/usr/bin/google-chrome"
options.add_argument("--load-extension=/tmp/extensions/automa,/tmp/extensions/captcha-solver")
options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")
options.add_argument("--disable-gpu")
options.add_argument("--window-size=1920,1080")
options.add_argument("--disable-blink-features=AutomationControlled")
options.add_argument("--no-first-run")
options.add_argument("--no-default-browser-check")

driver = webdriver.Chrome(options=options)
driver.implicitly_wait(10)

try:
    # First, go to chrome://extensions to find Automa's actual ID
    print("Finding Automa extension ID...")
    driver.get("chrome://extensions")
    time.sleep(3)
    
    driver.save_screenshot("/tmp/screenshot_1_extensions.png")
    print("Screenshot 1: Extensions page")
    
    # Enable developer mode to see extension IDs
    try:
        dev_toggle = driver.execute_script("""
            return document.querySelector('extensions-manager').shadowRoot
                .querySelector('extensions-toolbar').shadowRoot
                .querySelector('#devMode');
        """)
        if dev_toggle and not dev_toggle.get_attribute('checked'):
            driver.execute_script("""
                document.querySelector('extensions-manager').shadowRoot
                    .querySelector('extensions-toolbar').shadowRoot
                    .querySelector('#devMode').click();
            """)
            time.sleep(1)
    except Exception as e:
        print(f"Could not toggle dev mode: {e}")
    
    driver.save_screenshot("/tmp/screenshot_2_devmode.png")
    
    # Get all extension IDs
    ext_ids = driver.execute_script("""
        const manager = document.querySelector('extensions-manager');
        if (!manager) return [];
        const itemsList = manager.shadowRoot.querySelector('extensions-item-list');
        if (!itemsList) return [];
        const items = itemsList.shadowRoot.querySelectorAll('extensions-item');
        return Array.from(items).map(item => ({
            id: item.id,
            name: item.shadowRoot.querySelector('#name')?.textContent || 'unknown'
        }));
    """)
    
    print(f"Found extensions: {ext_ids}")
    
    # Find Automa extension ID
    automa_id = None
    for ext in ext_ids:
        if 'automa' in ext.get('name', '').lower():
            automa_id = ext['id']
            print(f"Found Automa with ID: {automa_id}")
            break
    
    if not automa_id:
        # Try reading from manifest
        print("Trying to read Automa ID from manifest...")
        # Check the extension folder for manifest
        import hashlib
        manifest_path = "/tmp/extensions/automa/manifest.json"
        if os.path.exists(manifest_path):
            with open(manifest_path) as f:
                manifest = json.load(f)
                print(f"Automa manifest name: {manifest.get('name')}")
    
    # If we found Automa ID, open its dashboard
    if automa_id:
        automa_url = f"chrome-extension://{automa_id}/newtab.html"
        print(f"Opening Automa at: {automa_url}")
        driver.get(automa_url)
        time.sleep(5)
    else:
        print("Could not find Automa ID, trying default URLs...")
        # Try different possible pages
        for url in [
            "chrome://newtab",
            "chrome-extension://infppggnoaenmfagbfknfkancpbljcca/newtab.html"
        ]:
            driver.get(url)
            time.sleep(2)
    
    driver.save_screenshot("/tmp/screenshot_3_automa.png")
    print(f"Screenshot 3: Page title = {driver.title}")
    print(f"Current URL: {driver.current_url}")
    
    # Print page info
    all_buttons = driver.find_elements(By.TAG_NAME, "button")
    print(f"Found {len(all_buttons)} buttons")
    for i, btn in enumerate(all_buttons[:15]):
        try:
            txt = btn.text[:30] if btn.text else btn.get_attribute('aria-label') or '(no text)'
            print(f"  Button {i}: {txt}")
        except:
            pass
    
    # Look for file input
    file_inputs = driver.find_elements(By.CSS_SELECTOR, "input[type='file']")
    print(f"Found {len(file_inputs)} file inputs")
    
    # Final screenshot
    driver.save_screenshot("/tmp/screenshot.png")
    print("Final screenshot saved")
    
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
    driver.save_screenshot("/tmp/screenshot.png")
    
finally:
    print("Closing browser...")
    driver.quit()

print("Done!")
PYTHON_SCRIPT

    python3 /tmp/run_automa.py
    
    echo "=== Done ==="
    
REMOTE_SCRIPT

# Download screenshots to see what happened
echo -e "${YELLOW}Downloading screenshots...${NC}"
scp -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$PUBLIC_IP:/tmp/screenshot*.png ./ 2>/dev/null && echo -e "${GREEN}✓ Screenshots saved${NC}" || echo "No screenshots available"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Automation Complete!                 ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Instance will be terminated by cleanup trap
