# DEBUG_NOTES.md

## macOS Screen Recording Permission

### Problem
macOS prompts for screen recording permission every time the app is rebuilt, even when previously granted.

### Root Cause
1. The app uses **adhoc code signing** (`CODE_SIGN_IDENTITY = "-"`), which changes with every build
2. macOS TCC (Transparency, Consent, Control) database tracks permissions by code signature hash
3. When the signature changes, macOS treats it as a different app

### Solutions Implemented

1. **Stable App Location** (`start_host_daemon.sh`)
   - App is built to `build/macos/Build/Products/Release/`
   - Copied to `/Applications/itermremote.app` (stable path)
   - Launched from stable location

2. **Usage Descriptions** (`Info.plist`)
   - Added `NSScreenCaptureUsageDescription` explaining why screen recording is needed

### Workarounds for Development

**Option 1: Debug mode** (avoids rebuild issues)
```bash
./scripts/start_host_daemon.sh --debug
```

**Option 2: Custom app path**
```bash
ITERMREMOTE_APP_PATH=/path/to/stable/app.app ./scripts/start_host_daemon.sh
```

**Option 3: Manual TCC pre-authorization** (advanced, not recommended)
Requires disabling SIP or using Apple Developer certificate for stable signing.

### Long-term Solution
Obtain Apple Developer certificate and configure proper code signing in Xcode:
- `CODE_SIGN_IDENTITY = "Apple Development"`
- `CODE_SIGN_STYLE = Automatic`
- Valid Team ID
