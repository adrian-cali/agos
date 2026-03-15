# iOS Deployment Guide (No Mac, Free Apple ID)

## Overview

This guide shows how to build and deploy the AGOS Flutter app to iOS without owning a Mac, using:
- **GitHub Actions** (cloud macOS to build IPA)
- **Sideloadly** (Windows tool to install on iPhone)
- **Free Apple ID** (personal/testing sideload)

## Limitations

- **7-day expiry:** Free Apple ID sideload certificates expire after ~7 days.
- **Weekly reinstall:** After expiry, you must re-sign and reinstall the app.
- **Single device:** Each device needs re-sideload per user.
- **Best for:** Personal use, small demos, internal testing.

For production/many users, you need a paid Apple Developer account (99 USD/year) for TestFlight or App Store.

---

## Part 1: GitHub Actions Setup

### Step 1.1: Create the workflow directory

In VS Code, create this folder structure:
```
.github/
  workflows/
    build-ios-ipa.yml
```

### Step 1.2: Add the workflow file

The file `.github/workflows/build-ios-ipa.yml` already exists in your repo with the correct content.

Verify it exists:
```powershell
Test-Path c:\Users\Adrian\agos\.github\workflows\build-ios-ipa.yml
```

### Step 1.3: Push to GitHub

```powershell
cd c:\Users\Adrian\agos
git add .github/
git commit -m "Add iOS IPA build workflow"
git push origin main
```

---

## Part 2: Build the IPA on GitHub Actions

### Step 2.1: Open GitHub Actions

1. Go to your GitHub repo: https://github.com/YOUR_USERNAME/agos
2. Click the **Actions** tab.
3. Left sidebar shows **Workflows**.
4. Click **Build iOS IPA**.

### Step 2.2: Run the workflow

1. Click **Run workflow** (green button top right).
2. Select branch: `main`.
3. Click **Run workflow** to confirm.

### Step 2.3: Wait for build

- Build will take **10-15 minutes**.
- You will see a yellow dot, then green checkmark when done.
- If red X, check the logs for errors (usually Firebase or dependency issues).

### Step 2.4: Download the IPA artifact

1. Click the workflow run name (top of the list).
2. Scroll down to **Artifacts** section.
3. Click **ios-ipa** to download.
4. Extract the `.zip` file.
5. You should have a file like `agos_app.ipa` (or similar).

---

## Part 3: Install Sideloadly on Windows

### Step 3.1: Download Sideloadly

- Visit: https://sideloadly.io/
- Click **Download**.
- Choose **Windows**.

### Step 3.2: Install

1. Run the installer (`.exe`).
2. Follow the installation wizard.
3. Restart Windows after install (recommended).

### Step 3.3: Launch Sideloadly

1. Open Sideloadly from Start menu.
2. You should see a window with:
   - **Select IPA** button
   - **Apple ID** field
   - **Password** field
   - **Start** button

---

## Part 4: Sideload IPA to iPhone

### Step 4.1: Connect iPhone to Windows

1. Plug iPhone into Windows via **USB cable**.
2. On iPhone screen, a dialog will appear: "Trust this Computer?"
3. Tap **Trust**.
4. Enter your iPhone passcode if prompted.
5. Windows should now recognize the device.

### Step 4.2: Open Sideloadly and select IPA

1. In Sideloadly window, click **Select IPA**.
2. Navigate to your downloaded `.ipa` file.
3. Click to select it.
4. Sideloadly will show the app name and details.

### Step 4.3: Enter Apple ID credentials

1. In the **Apple ID** field, enter your iCloud email (e.g., `example@icloud.com`).
2. In the **Password** field, enter your iCloud password.
3. Click **Start**.

### Step 4.4: Confirm on iPhone

1. Wait for the install process to complete (about 1-2 minutes).
2. If prompted on iPhone for app installation confirmation, tap **Install**.
3. After install, go to **Settings > General > VPN and Device Management**.
4. Find your Apple ID under "Developer App".
5. Tap it, then tap **Trust**.
6. You may need to verify with Face ID or passcode.

### Step 4.5: Open the app

1. Home screen should now show the **AGOS** app icon.
2. Tap to open.
3. App should launch.

---

## Part 5: Using the App

### Monitoring Features (Work)
- Login / Firebase Auth
- Dashboard and charts
- Notifications
- WebSocket live data
- Firestore reads

### Setup Features (May Not Work on iOS Web)
- Bluetooth device scanning ✓ (works in native app)
- WiFi provisioning ✓ (works in native app)
- BLE pairing ✓ (works in native app)

All of these work in the native sideloaded app because you have native iOS APIs available.

---

## Part 6: Weekly Refresh Cycle (Free Apple ID)

### Why the 7-day limit?

Free Apple ID signing certificates issued by Sideloadly expire after about 7 days. After expiry:
1. App will show a "Untrusted Developer" dialog.
2. It will not open.
3. You must re-sideload.

### How to refresh

Repeat **Part 4** (Sideload IPA to iPhone):

```
1. New GitHub Actions run → Download new IPA
2. Connect iPhone to Windows
3. Sideloadly: Select same IPA, enter Apple ID, Start
4. Confirm on iPhone: Trust developer
5. App refreshes, working for 7 more days
```

---

## Troubleshooting

### Error: "Quota exceeded" during build

**Cause:** GitHub Actions macOS runners can be slow with Flutter.

**Fix:**
1. Wait and retry (server queue issue).
2. If persistent, check repo size or large dependencies.

### Error: "IPA not found" or build fails

**Cause:** Firebase or dependency compilation error.

**Fix:**
1. Check workflow logs on GitHub Actions.
2. Verify `agos_app/pubspec.yaml` has all required packages.
3. Re-run workflow.

### Error: "Trust this computer?" not appearing on iPhone

**Cause:** Cable issue or device not recognized.

**Fix:**
1. Try a different USB cable (preferably Apple original).
2. Unplug and reconnect.
3. Unlock iPhone and try again.
4. Restart iPhone.

### Error: "Invalid provisioning profile" in Sideloadly

**Cause:** Apple ID revoked or certificate expired.

**Fix:**
1. Try with a different Apple ID.
2. If using same ID, wait a few minutes and retry.
3. Restart Sideloadly.

### App crashes immediately after opening

**Cause:** Firebase config issue or missing credential file.

**Fix:**
1. Verify `firebase_options.dart` is correct for iOS.
2. Check `ios/Runner/GoogleService-Info.plist` exists.
3. Run `flutter build ipa --release` locally on a Mac (if available) to test.

### "Developer not trusted" message keeps appearing

**Cause:** Profile trust not confirmed on iPhone.

**Fix:**
1. Go to **Settings > General > VPN and Device Management**.
2. Find your Apple ID.
3. Tap **Trust** and confirm with Face ID/passcode.
4. Close Settings and reopen app.

---

## Workflow at a Glance

```
┌─────────────────────────────────────────┐
│ 1. Push code to GitHub                  │
│    (git push)                           │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ 2. GitHub Actions builds IPA on macOS   │
│    (10-15 minutes)                      │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ 3. Download .ipa artifact               │
│    (Sideloadly-compatible)              │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ 4. Sideloadly: Select IPA + Apple ID    │
│    Install on iPhone                    │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│ 5. Open app on iPhone home screen       │
│    (7 days validity)                    │
└─────────────────┬───────────────────────┘
                  │
         ┌────────▼────────┐
         │ 7 days passed?  │
         └────────┬────────┘
                  │
              YES │  Repeat steps 2-5
                  │
              NO  │  Continue using
                  └─────► (working)
```

---

## Next Steps

1. **Commit the workflow** (if not done already):
   ```powershell
   git add .github/workflows/build-ios-ipa.yml
   git commit -m "Add iOS build workflow"
   git push
   ```

2. **Run the first build** on GitHub Actions.

3. **Download Sideloadly** and install on Windows.

4. **Sideload the IPA** to your iPhone.

5. **Test the app** and verify all features work.

6. **Schedule weekly refresh** in your calendar after 6-7 days.

---

## Future: Paid Apple Developer Account

When you are ready for production:
1. Enroll in Apple Developer Program (99 USD/year).
2. Can distribute via TestFlight (easy for testers) or App Store.
3. No 7-day expiry.
4. Users can install directly, no sideload needed.

For now, free sideload is perfect for demos and personal use.

