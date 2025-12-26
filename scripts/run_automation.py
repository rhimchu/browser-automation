#!/usr/bin/env python3
"""
run_automation.py
Launches browser with Automa and captcha solver extensions.
Automa handles the entire workflow including captcha waiting.
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
# CONFIGURATION
# ============================================
TARGET_URL = "https://example.com/your-form-page"  # Your target website
WORKFLOW_TIMEOUT = 120  # Max seconds to wait for Automa workflow to complete
# ============================================

# Paths
BASE_DIR = Path("/opt/automation")
EXTENSIONS_DIR = BASE_DIR / "extensions"
WORKFLOWS_DIR = BASE_DIR / "workflows"
TEMP_EXT_DIR = Path("/tmp/extensions")


def extract_crx(crx_path, extract_dir):
    """Extract CRX extension to a folder."""
    extract_path = extract_dir / crx_path.stem
    extract_path.mkdir(parents=True, exist_ok=True)
    
    print(f"  Extracting {crx_path.name}...")
    
    with open(crx_path, 'rb') as f:
        data = f.read()
    
    # Find the ZIP signature (PK) - skip CRX header
    zip_start = data.find(b'PK\x03\x04')
    
    if zip_start == -1:
        raise ValueError(f"Could not find ZIP data in {crx_path}")
    
    zip_data = io.BytesIO(data[zip_start:])
    with zipfile.ZipFile(zip_data, 'r') as zip_ref:
        zip_ref.extractall(extract_path)
    
    print(f"  ✓ Extracted to {extract_path}")
    return extract_path


def setup_browser():
    """Set up Chromium browser with extensions loaded."""
    
    print("Setting up browser...")
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
    
    # Required for running headless on server
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1920,1080")
    
    # Anti-detection
    options.add_argument("--disable-blink-features=AutomationControlled")
    options.add_experimental_option("excludeSwitches", ["enable-automation"])
    options.add_experimental_option("useAutomationExtension", False)
    
    service = Service("/usr/bin/chromedriver")
    driver = webdriver.Chrome(service=service, options=options)
    driver.implicitly_wait(10)
    driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
    
    print("✓ Browser ready with extensions loaded")
    return driver


def wait_for_automa_completion(driver, timeout):
    """
    Wait for Automa workflow to complete.
    Checks for success indicators on the page.
    """
    print(f"Waiting for Automa workflow (max {timeout}s)...")
    
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            # Check for common success indicators
            # Customize these selectors based on your form's success message
            success_selectors = [
                ".success-message",
                ".thank-you", 
                "[data-success]",
                ".form-success",
                "#success"
            ]
            
            for selector in success_selectors:
                try:
                    element = driver.find_element(By.CSS_SELECTOR, selector)
                    if element.is_displayed():
                        print(f"✓ Success element detected: {selector}")
                        return True
                except:
                    pass
                
        except Exception:
            pass
        
        time.sleep(2)
    
    print(f"⚠ Timeout after {timeout}s")
    return False


def main():
    print("=" * 50)
    print("  Browser Automation - Automa Controlled")
    print("=" * 50)
    print(f"Target URL: {TARGET_URL}")
    print(f"Timeout: {WORKFLOW_TIMEOUT}s")
    print("")
    
    driver = None
    exit_code = 0
    
    try:
        driver = setup_browser()
        
        # Navigate to target - Automa will take over from here
        print(f"Navigating to: {TARGET_URL}")
        driver.get(TARGET_URL)
        
        WebDriverWait(driver, 30).until(
            EC.presence_of_element_located((By.TAG_NAME, "body"))
        )
        print("✓ Page loaded - Automa workflow running...")
        
        # Let Automa handle everything (form filling, captcha, submit)
        wait_for_automa_completion(driver, WORKFLOW_TIMEOUT)
        
        # Take screenshot for verification
        screenshot_path = "/tmp/result.png"
        driver.save_screenshot(screenshot_path)
        print(f"✓ Screenshot saved to {screenshot_path}")
        
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
        print("  SUCCESS")
    else:
        print("  FAILED - Check errors above")
    print("=" * 50)
    
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
