# Browser Automation with AWS

Automated browser form filling using AWS EC2 (Free Tier), Chromium, Automa extension, and a captcha solver.

## 📁 Project Structure

```
browser-automation/
├── extensions/
│   ├── automa.crx              ← Automa extension (you add this)
│   └── captcha-solver.crx      ← Captcha solver extension (you add this)
├── workflows/
│   └── form-fill.automa.json   ← Your Automa workflow (exported from Automa)
├── scripts/
│   ├── aws-initial-setup.sh    ← One-time AWS setup
│   ├── setup.sh                ← Runs on EC2 to install dependencies
│   ├── run_automation.py       ← Main automation script
│   └── orchestrate.sh          ← Main script to run everything
├── config.env                  ← Generated after aws-initial-setup.sh
└── README.md
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI installed and configured**
   ```bash
   aws configure
   # Enter your AWS Access Key, Secret Key
   # Default region: ap-southeast-1 (Singapore)
   ```

2. **GitHub repository created** (private recommended)

### Step 1: Clone and Setup Repository

```bash
git clone https://github.com/YOUR_USERNAME/browser-automation.git
cd browser-automation
```

### Step 2: Add Your Extensions

1. **Get Automa extension (.crx)**
   - Install "CRX Extractor/Downloader" Chrome extension
   - Go to [Automa Chrome Web Store page](https://chrome.google.com/webstore/detail/automa/)
   - Use the extractor to download the .crx file
   - Save as `extensions/automa.crx`

2. **Get your captcha solver extension (.crx)**
   - Same process for your captcha solver extension
   - Save as `extensions/captcha-solver.crx`

### Step 3: Export Your Automa Workflow

1. Open Automa extension in Chrome
2. Create/edit your form-filling workflow
3. Click the menu (⋮) → Export
4. Save the JSON file as `workflows/form-fill.automa.json`

### Step 4: Configure the Scripts

1. Edit `scripts/setup.sh`:
   ```bash
   GITHUB_RAW="https://raw.githubusercontent.com/YOUR_USERNAME/browser-automation/main"
   ```

2. Edit `scripts/orchestrate.sh`:
   ```bash
   GITHUB_USER="YOUR_USERNAME"
   ```

3. Edit `scripts/run_automation.py`:
   ```python
   TARGET_URL = "https://your-target-website.com/form"
   ```

### Step 5: Push to GitHub

```bash
git add .
git commit -m "Initial setup"
git push origin main
```

### Step 6: Run AWS Initial Setup (One Time)

```bash
cd scripts
chmod +x aws-initial-setup.sh
./aws-initial-setup.sh
```

This creates:
- SSH key pair
- Security group
- `config.env` file with your settings

### Step 7: Update orchestrate.sh

Copy the `SECURITY_GROUP` value from the output and add it to `scripts/orchestrate.sh`:
```bash
SECURITY_GROUP="sg-xxxxxxxxx"  # Your security group ID
```

### Step 8: Run the Automation

```bash
chmod +x orchestrate.sh
./orchestrate.sh
```

## 💰 AWS Free Tier Limits

| Resource | Free Tier Limit | Notes |
|----------|-----------------|-------|
| t2.micro | 750 hours/month | ~31 days continuous |
| EBS Storage | 30 GB | For the AMI |
| Data Transfer | 15 GB/month outbound | |

**Cost Tip:** The script auto-terminates the instance after each run!

## 🔧 Customization

### Using Selenium Instead of Automa

Edit `scripts/run_automation.py` and uncomment the Selenium code:

```python
# Fill name field
name_field = driver.find_element(By.NAME, "name")
name_field.send_keys("John Doe")

# Fill email
email_field = driver.find_element(By.NAME, "email")
email_field.send_keys("john@example.com")

# Submit
submit_button = driver.find_element(By.CSS_SELECTOR, "button[type='submit']")
submit_button.click()
```

### Adjusting Timeouts

In `run_automation.py`:
```python
WAIT_FOR_CAPTCHA = 15  # Seconds to wait for captcha solver
WAIT_AFTER_SUBMIT = 10  # Seconds to wait after submission
```

## 🐛 Troubleshooting

### SSH Connection Refused
- Wait longer (instance may still be booting)
- Check security group allows your IP

### Extensions Not Loading
- Verify .crx files are valid
- Check file permissions
- Try re-downloading extensions

### Captcha Not Solving
- Ensure captcha solver extension has valid API key
- Increase `WAIT_FOR_CAPTCHA` timeout

### Check Logs on Instance
```bash
ssh -i ~/.ssh/browser-automation-key.pem ubuntu@<INSTANCE_IP>
cat /var/log/cloud-init-output.log
```

## 📝 License

MIT License
