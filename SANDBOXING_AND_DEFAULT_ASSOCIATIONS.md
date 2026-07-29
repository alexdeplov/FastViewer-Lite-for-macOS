# Sandboxing and Default File Associations

## The Problem

Your app is **sandboxed** (`ENABLE_APP_SANDBOX = YES` in project settings). Sandboxed apps **cannot** programmatically set themselves as default file handlers using `LSSetDefaultRoleHandlerForContentType`.

This is a macOS security restriction - sandboxed apps cannot modify system-wide settings like default applications.

## Solutions

### Option 1: Disable Sandboxing (For Testing Only)

⚠️ **Warning:** Only do this for testing. App Store apps must be sandboxed.

1. Open Xcode project settings
2. Select the **FastViewer** target
3. Go to **Signing & Capabilities** tab
4. Find **App Sandbox** capability
5. **Uncheck** or **Remove** it
6. Build and run again

After disabling sandboxing, the default file associations should work.

### Option 2: Keep Sandboxing (Recommended for App Store)

If you plan to distribute via App Store, you **must** keep sandboxing enabled. In this case:

1. The code will detect sandboxing and skip the operation
2. Users will need to manually set FastViewer as default (instructions are printed to console)
3. You could add a UI dialog or help menu item with instructions

### Option 3: Add User Instructions in UI

You could add a menu item or dialog that shows users how to set FastViewer as default:

```swift
// Example: Add to Help menu
let helpMenuItem = NSMenuItem(title: "Set as Default Image Viewer...", action: #selector(showSetAsDefaultInstructions), keyEquivalent: "")
```

## Current Behavior

With the improved code:
- ✅ Detects if app is sandboxed
- ✅ Provides clear error messages in console
- ✅ Verifies if associations were actually set
- ✅ Shows instructions for manual setup

## Testing

1. **Check console output** when app launches - you'll see:
   - Whether sandboxing was detected
   - Whether associations were set
   - Verification of current default handlers

2. **To test without sandboxing:**
   - Temporarily disable App Sandbox
   - Reset first launch flag: `./reset_first_launch.sh`
   - Launch app and check console

3. **To verify manually:**
   - Right-click a JPG file > Get Info
   - Check "Open with" section
   - See if FastViewer is listed/selected

## Why This Limitation Exists

macOS sandboxing is designed to prevent apps from:
- Modifying system settings
- Accessing files without permission
- Changing default applications without user consent

This is a security feature, not a bug. Users must explicitly choose to set your app as default.




