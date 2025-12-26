# Extensions Folder

Place your Chrome extension .crx files here:

## Required Files

1. **automa.crx** - Automa browser automation extension
2. **captcha-solver.crx** - Your captcha solver extension

## How to Get .crx Files

### Method 1: CRX Extractor (Easiest)

1. Install "CRX Extractor/Downloader" extension in Chrome
2. Go to the Chrome Web Store page for the extension you want
3. Click the CRX Extractor icon
4. Download the .crx file
5. Rename and place in this folder

### Method 2: Pack Extension Manually

1. Go to `chrome://extensions` in Chrome
2. Enable "Developer mode" (top right toggle)
3. Find the extension you want
4. Note the extension ID
5. Go to: `C:\Users\<USER>\AppData\Local\Google\Chrome\User Data\Default\Extensions\<ID>`
   - On Mac: `~/Library/Application Support/Google/Chrome/Default/Extensions/<ID>`
   - On Linux: `~/.config/google-chrome/Default/Extensions/<ID>`
6. Copy the version folder (e.g., `1.0.0_0`)
7. In Chrome extensions page, click "Pack extension"
8. Select the folder you copied
9. This creates a .crx file

## Note

Keep this folder in your Git repo so the EC2 instance can download the extensions.
