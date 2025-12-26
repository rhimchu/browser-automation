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

os.environ["DISPLAY"] = ":99"

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
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
    # Load workflow JSON
    with open("/tmp/workflow.json", "r") as f:
        workflow = json.load(f)
    
    print("Opening Automa dashboard...")
    # Automa extension ID (standard)
    driver.get("chrome-extension://infppggnoaenmfagbfknfkancpbljcca/newtab.html")
    time.sleep(3)
    
    print("Importing workflow via JavaScript...")
    # Import workflow directly into Automa's storage
    import_script = """
    return new Promise((resolve, reject) => {
        const workflow = arguments[0];
        
        // Access Automa's background page to import
        chrome.runtime.sendMessage(
            'infppggnoaenmfagbfknfkancpbljcca',
            { 
                type: 'workflow:import', 
                data: workflow 
            },
            response => {
                if (chrome.runtime.lastError) {
                    reject(chrome.runtime.lastError);
                } else {
                    resolve(response);
                }
            }
        );
    });
    """
    
    # Alternative: Use localStorage/IndexedDB approach
    # First try to execute workflow directly
    execute_script = """
    const workflow = arguments[0];
    
    // Store in localStorage for Automa to pick up
    localStorage.setItem('automa-workflow-import', JSON.stringify(workflow));
    
    // Trigger import event
    window.dispatchEvent(new CustomEvent('automa:import-workflow', { detail: workflow }));
    
    return 'stored';
    """
    
    result = driver.execute_script(execute_script, workflow)
    print(f"Import result: {result}")
    
    time.sleep(2)
    
    # Refresh to see imported workflow
    driver.refresh()
    time.sleep(3)
    
    print("Looking for workflow to execute...")
    
    # Try to find and click the workflow
    try:
        # Look for workflow card or run button
        workflow_elements = driver.find_elements(By.CSS_SELECTOR, "[class*='workflow'], [class*='card']")
        print(f"Found {len(workflow_elements)} potential workflow elements")
        
        # Try clicking first workflow
        if workflow_elements:
            workflow_elements[0].click()
            time.sleep(2)
    except Exception as e:
        print(f"Could not click workflow: {e}")
    
    # Try to find and click play/run button
    try:
        run_buttons = driver.find_elements(By.CSS_SELECTOR, "button[title*='run'], button[title*='Run'], button[title*='play'], [class*='play'], [class*='run']")
        print(f"Found {len(run_buttons)} run buttons")
        for btn in run_buttons:
            try:
                btn.click()
                print("Clicked run button")
                break
            except:
                pass
    except Exception as e:
        print(f"Could not find run button: {e}")
    
    print("Waiting for workflow to complete...")
    time.sleep(60)
    
    # Take screenshot
    driver.save_screenshot("/tmp/screenshot.png")
    print("Screenshot saved to /tmp/screenshot.png")
    
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

# Download screenshot to see what happened
echo -e "${YELLOW}Downloading screenshot...${NC}"
scp -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$PUBLIC_IP:/tmp/screenshot.png ./screenshot-$(date +%Y%m%d-%H%M%S).png 2>/dev/null && echo -e "${GREEN}✓ Screenshot saved${NC}" || echo "No screenshot available"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Automation Complete!                 ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Instance will be terminated by cleanup trap
