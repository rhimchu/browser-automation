#!/usr/bin/env python3
"""
run_automation.py
Main browser automation script with Automa and captcha solver
Save to: scripts/run_automation.py
"""

import os
import sys
import time
import json
import subprocess
import zipfile
import io
from pathlib import Path

# Start virtual display (Xvfb)
print("Starting virtual display...")
subprocess.Popen(["Xvfb", ":99", "-screen", "0", "1920x1080x24"], 
                 stdout=subprocess.DEVNULL, 
                 stderr=subprocess.DEVNULL)
os.environ["DISPLAY"] = ":99"
time.sleep(2)

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# ============================================
# CONFIGURATION - CHANGE THESE VALUES
# ============================================
TARGET_URL = "https://example.com/your-form-page"  # Your target website
WAIT_FOR_CAPTCHA = 15  # Seconds to wait for captcha solver
WAIT_AFTER_SUBMIT = 10  # Seconds to wait after form submission
# ============================================

# Paths
BASE_DIR = Path("/opt/automation")
EXTENSIONS_DIR = BASE_DIR / "extensions"
WORKFLOWS_DIR = BASE_DIR / "workflows"
TEMP_EXT_DIR = Path("/tmp/extensions")


def extract_crx(crx_path, extract_dir):
    """
    Extract CRX extension to a folder.
    CRX files are ZIP files with a special header.
    """
    extract_path = extract_dir / crx_path.stem
    extract_path.mkdir(parents=True, exist_ok=True)
    
    print(f"  Extracting {crx_path.name}...")
    
    with open(crx_path, 'rb') as f:
        data = f.read()
    
    # Find the ZIP signature (PK) - skip CRX header
    zip_start = data.find(b'PK\x03\x04')
    
    if zip_start == -1:
        raise ValueError(f"Could not find ZIP data in {crx_path}")
    
    # Extract from ZIP data
    zip_data = io.BytesIO(data[zip_start:])
    with zipfile.ZipFile(zip_data, 'r') as zip_ref:
        zip_ref.extractall(extract_path)
    
    print(f"  ✓ Extracted to {extract_path}")
    return extract_path


def setup_browser():
    """Set up Chromium browser with extensions loaded."""
    
    print("Setting up browser...")
    
    # Create temp directory for extracted extensions
    TEMP_EXT_DIR.mkdir(exist_ok=True)
    
    # Extract extensions
    print("Extracting extensions...")
    automa_path = extract_crx(EXTENSIONS_DIR / "automa.crx", TEMP_EXT_DIR)
    captcha_path = extract_crx(EXTENSIONS_DIR / "captcha-solver.crx", TEMP_EXT_DIR)
    
    # Chrome options
    options = Options()
    options.binary_location = "/usr/bin/chromium-browser"
    
    # Load extensions
    options.add_argument(f"--load-extension={automa_path},{captcha_path}")
    
    # Required for running in container/server
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1920,1080")
    
    # Make automation less detectable
    options.add_argument("--disable-blink-features=AutomationControlled")
    options.add_experimental_option("excludeSwitches", ["enable-automation"])
    options.add_experimental_option("useAutomationExtension", False)
    
    # Use system chromedriver
    service = Service("/usr/bin/chromedriver")
    
    driver = webdriver.Chrome(service=service, options=options)
    driver.implicitly_wait(10)
    
    # Additional anti-detection
    driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
    
    print("✓ Browser ready with extensions loaded")
    return driver


def load_workflow():
    """Load the Automa workflow JSON file."""
    workflow_file = WORKFLOWS_DIR / "form-fill.automa.json"
    
    if not workflow_file.exists():
        print(f"Warning: Workflow file not found at {workflow_file}")
        return None
    
    with open(workflow_file, 'r') as f:
        return json.load(f)


def run_automation(driver):
    """
    Main automation logic.
    Customize this function for your specific form!
    """
    
    print(f"Navigating to: {TARGET_URL}")
    driver.get(TARGET_URL)
    
    # Wait for page to fully load
    WebDriverWait(driver, 30).until(
        EC.presence_of_element_located((By.TAG_NAME, "body"))
    )
    print("✓ Page loaded")
    
    time.sleep(3)  # Extra wait for JavaScript to initialize
    
    # ============================================
    # OPTION 1: Let Automa handle everything
    # If you've configured Automa with a trigger (e.g., keyboard shortcut),
    # you can trigger it here. Otherwise, Automa may auto-run on page load.
    # ============================================
    
    # ============================================
    # OPTION 2: Manual form filling with Selenium
    # Uncomment and customize the code below for your form
    # ============================================
    
    """
    # Example: Fill out a contact form
    try:
        # Fill name field
        name_field = WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.NAME, "name"))
        )
        name_field.clear()
        name_field.send_keys("John Doe")
        print("✓ Filled name field")
        
        # Fill email field
        email_field = driver.find_element(By.NAME, "email")
        email_field.clear()
        email_field.send_keys("john.doe@example.com")
        print("✓ Filled email field")
        
        # Fill message field
        message_field = driver.find_element(By.NAME, "message")
        message_field.clear()
        message_field.send_keys("This is an automated message.")
        print("✓ Filled message field")
        
    except Exception as e:
        print(f"Error filling form: {e}")
        raise
    """
    
    # Wait for captcha solver to work
    print(f"Waiting {WAIT_FOR_CAPTCHA}s for captcha solver...")
    time.sleep(WAIT_FOR_CAPTCHA)
    
    # ============================================
    # Submit the form (uncomment when ready)
    # ============================================
    
    """
    try:
        submit_button = driver.find_element(By.CSS_SELECTOR, "button[type='submit']")
        submit_button.click()
        print("✓ Form submitted")
    except Exception as e:
        print(f"Error submitting form: {e}")
        raise
    """
    
    # Wait for submission to complete
    print(f"Waiting {WAIT_AFTER_SUBMIT}s for completion...")
    time.sleep(WAIT_AFTER_SUBMIT)
    
    # Take screenshot for verification
    screenshot_path = "/tmp/result.png"
    driver.save_screenshot(screenshot_path)
    print(f"✓ Screenshot saved to {screenshot_path}")
    
    print("✓ Automation completed successfully!")


def main():
    print("=" * 50)
    print("  Browser Automation Starting")
    print("=" * 50)
    print(f"Target URL: {TARGET_URL}")
    print("")
    
    driver = None
    exit_code = 0
    
    try:
        driver = setup_browser()
        
        workflow = load_workflow()
        if workflow:
            print(f"✓ Workflow loaded: {len(workflow)} items")
        
        run_automation(driver)
        
    except Exception as e:
        print(f"\n✗ ERROR: {e}")
        import traceback
        traceback.print_exc()
        exit_code = 1
        
    finally:
        if driver:
            print("\nClosing browser...")
            driver.quit()
            print("✓ Browser closed")
    
    print("")
    print("=" * 50)
    if exit_code == 0:
        print("  SUCCESS - Automation completed")
    else:
        print("  FAILED - Check errors above")
    print("=" * 50)
    
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
