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
    
    # Install Chromium (better extension support than Chrome for automation)
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        chromium-browser \
        chromium-chromedriver \
        xvfb \
        unzip \
        curl \
        imagemagick \
        python3-pip
    
    # Verify Chromium installed
    echo "Chromium version:"
    chromium-browser --version 2>/dev/null || chromium --version 2>/dev/null || echo "Chromium not found in expected path"
    
    pip3 install selenium --break-system-packages
    
    echo "=== Downloading extensions from GitHub ==="
    mkdir -p /tmp/extensions
    cd /tmp/extensions
    
    # Download Automa CRX file
    curl -sL "${GITHUB_RAW}/extensions/automa.crx" -o automa.crx
    
    # Extract CRX (it's a zip with a header)
    mkdir -p automa
    python3 -c "
import zipfile, io, json
data = open('automa.crx', 'rb').read()
start = data.find(b'PK\x03\x04')
if start == -1:
    print('ERROR: Not a valid CRX file')
else:
    zipfile.ZipFile(io.BytesIO(data[start:])).extractall('automa')
    # Remove update_url from manifest (causes issues with unpacked extensions)
    manifest_path = 'automa/manifest.json'
    with open(manifest_path, 'r') as f:
        manifest = json.load(f)
    if 'update_url' in manifest:
        del manifest['update_url']
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2)
        print('Removed update_url from manifest')
    print('Automa extracted successfully')
"
    
    # Fix permissions
    chmod -R 755 automa/
    
    # Verify manifest exists
    echo "Checking Automa manifest..."
    ls -la automa/manifest.json
    cat automa/manifest.json | grep -E '"name"|manifest_version'
    
    # Download and extract captcha solver
    curl -sL "${GITHUB_RAW}/extensions/captcha-solver.crx" -o captcha-solver.crx
    mkdir -p captcha-solver
    python3 -c "
import zipfile, io
data = open('captcha-solver.crx', 'rb').read()
start = data.find(b'PK\x03\x04')
if start != -1:
    zipfile.ZipFile(io.BytesIO(data[start:])).extractall('captcha-solver')
    print('Captcha solver extracted successfully')
"
    # Fix permissions for captcha solver too
    chmod -R 755 captcha-solver/
    
    echo "=== Starting browser with Automa ==="
    export DISPLAY=:99
    Xvfb :99 -screen 0 1920x1080x24 &
    sleep 2
    
    # Download workflow JSON
    curl -sL "${GITHUB_RAW}/workflows/form-fill.automa.json" -o /tmp/workflow.json
    
    # Remove _metadata folder which can cause issues
    rm -rf /tmp/extensions/automa/_metadata
    rm -rf /tmp/extensions/captcha-solver/_metadata
    
    # Check manifest
    echo "=== Automa manifest.json ==="
    cat /tmp/extensions/automa/manifest.json | head -30
    
    # Create and run Python script
    cat > /tmp/run_automa.py << 'PYTHON_SCRIPT'
import os
import sys
import time
import json

os.environ["DISPLAY"] = ":99"

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By

print("Setting up Chromium with extensions...")
options = Options()

# Try different Chromium binary locations
for binary in ["/usr/bin/chromium-browser", "/usr/bin/chromium", "/snap/bin/chromium"]:
    if os.path.exists(binary):
        options.binary_location = binary
        print(f"Using binary: {binary}")
        break
else:
    print("WARNING: No Chromium binary found, trying default")

# Load extensions
options.add_argument("--load-extension=/tmp/extensions/automa,/tmp/extensions/captcha-solver")
options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")
options.add_argument("--disable-gpu")
options.add_argument("--window-size=1920,1080")
options.add_argument("--no-first-run")
options.add_argument("--no-default-browser-check")
options.add_argument("--disable-extensions-except=/tmp/extensions/automa,/tmp/extensions/captcha-solver")
options.add_argument("--enable-logging")
options.add_argument("--v=1")

driver = webdriver.Chrome(options=options)
driver.implicitly_wait(10)

try:
    # First go to chrome://extensions to find what's loaded
    print("Checking chrome://extensions...")
    driver.get("chrome://extensions")
    time.sleep(3)
    driver.save_screenshot("/tmp/screenshot_1_extensions.png")
    
    # Enable developer mode and get extension info
    script = """
    try {
        const manager = document.querySelector('extensions-manager');
        if (!manager || !manager.shadowRoot) return JSON.stringify({error: 'no manager'});
        
        // Enable developer mode
        const toolbar = manager.shadowRoot.querySelector('extensions-toolbar');
        if (toolbar && toolbar.shadowRoot) {
            const toggle = toolbar.shadowRoot.querySelector('#devMode');
            if (toggle && !toggle.checked) {
                toggle.click();
                await new Promise(r => setTimeout(r, 500));
            }
        }
        
        const itemList = manager.shadowRoot.querySelector('extensions-item-list');
        if (!itemList || !itemList.shadowRoot) return JSON.stringify({error: 'no item list'});
        
        const items = itemList.shadowRoot.querySelectorAll('extensions-item');
        const results = [];
        items.forEach(item => {
            try {
                const name = item.shadowRoot.querySelector('#name');
                results.push({
                    id: item.id,
                    name: name ? name.textContent.trim() : 'unknown'
                });
            } catch(e) {}
        });
        return JSON.stringify({extensions: results, count: items.length});
    } catch(e) {
        return JSON.stringify({error: e.toString()});
    }
    """
    
    result = driver.execute_script(script)
    print(f"Extension check result: {result}")
    
    # Parse result
    try:
        data = json.loads(result) if isinstance(result, str) else result
    except:
        data = {"error": "parse failed", "raw": str(result)}
    
    print(f"Parsed data: {data}")
    driver.save_screenshot("/tmp/screenshot_2_devmode.png")
    
    # Find Automa extension ID
    automa_id = None
    if 'extensions' in data:
        for ext in data['extensions']:
            print(f"  Found extension: {ext}")
            if 'automa' in ext.get('name', '').lower():
                automa_id = ext['id']
                print(f"  -> Automa ID: {automa_id}")
    
    if automa_id:
        # Open Automa dashboard
        automa_url = f"chrome-extension://{automa_id}/newtab.html"
        print(f"Opening Automa: {automa_url}")
        driver.get(automa_url)
        time.sleep(5)
        
        print(f"Page title: {driver.title}")
        print(f"Page URL: {driver.current_url}")
        driver.save_screenshot("/tmp/screenshot_3_automa.png")
        
        # Check for UI elements
        buttons = driver.find_elements(By.TAG_NAME, "button")
        print(f"Found {len(buttons)} buttons")
        for i, b in enumerate(buttons[:15]):
            txt = b.text or b.get_attribute('aria-label') or b.get_attribute('title') or ''
            if txt:
                print(f"  {i}: {txt[:50]}")
    else:
        print("ERROR: No extensions loaded!")
        print("This usually means Chrome rejected the extension.")
        print("Checking Chrome logs...")
        
        # Try to get any error info
        logs = driver.get_log('browser')
        for log in logs[-20:]:
            print(f"  {log}")
    
    driver.save_screenshot("/tmp/screenshot.png")
    
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
    try:
        driver.save_screenshot("/tmp/screenshot.png")
    except:
        pass
    
finally:
    print("Closing browser...")
    driver.quit()

print("Done!")
PYTHON_SCRIPT

    python3 /tmp/run_automa.py
    
    echo "=== Screenshots as base64 (copy to view) ==="
    echo "--- screenshot_1_automa.png ---"
    base64 /tmp/screenshot_1_automa.png 2>/dev/null | head -50
    echo "..."
    echo ""
    
    # List files in /tmp
    echo "=== Files in /tmp ==="
    ls -la /tmp/*.png 2>/dev/null || echo "No PNG files"
    
    echo "=== Done ==="
    
REMOTE_SCRIPT

# Download screenshots to see what happened
echo -e "${YELLOW}Downloading screenshots...${NC}"
echo "Instance IP: $PUBLIC_IP"

# Try downloading each file with verbose output
for file in screenshot.png screenshot_1_extensions.png screenshot_2_devmode.png screenshot_3_automa.png; do
    echo "Downloading $file..."
    scp -v -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY_FILE" "ubuntu@${PUBLIC_IP}:/tmp/${file}" "./${file}" 2>&1 | tail -3
done

# List what we got
echo "Screenshots in current directory:"
ls -la *.png 2>/dev/null || echo "No PNG files found"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Automation Complete!                 ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Instance will be terminated by cleanup trap
