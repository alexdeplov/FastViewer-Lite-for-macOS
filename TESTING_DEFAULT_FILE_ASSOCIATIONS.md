# Testing Default File Associations

This guide explains how to test the default file association feature that sets FastViewer as the default app for JPG, PNG, and WebP files on first launch.

## Method 1: Run Unit Tests

The easiest way to test the logic is through unit tests:

```bash
# In Xcode, press Cmd+U to run all tests
# Or use the Test Navigator (Cmd+6) and run:
# - DefaultFileAssociationManagerTests
# - SettingsManagerTests (tests for hasSetDefaultFileAssociations)
```

## Method 2: Test First Launch Behavior

### Step 1: Reset the First Launch Flag

To test the first launch behavior, you need to reset the UserDefaults flag:

**Option A: Using Terminal**
```bash
# Reset the flag
defaults delete com.aleksandr.deplov.FastViewer DefaultFileAssociationsSet

# Verify it's deleted
defaults read com.aleksandr.deplov.FastViewer DefaultFileAssociationsSet
# Should return: "does not exist"
```

**Option B: Using Swift/Xcode**
Add this temporary code to test (remove after testing):
```swift
// In AppDelegate.swift, temporarily add to applicationDidFinishLaunching:
SettingsManager.shared.hasSetDefaultFileAssociations = false
```

### Step 2: Launch the App

1. Build and run the app in Xcode (Cmd+R)
2. Check the Xcode console for messages:
   - Success: "Successfully set default handler for public.jpeg"
   - Failure: "Failed to set default handler for..." (normal if app is sandboxed)

### Step 3: Verify the Flag Was Set

```bash
# Check if flag was set
defaults read com.aleksandr.deplov.FastViewer DefaultFileAssociationsSet
# Should return: 1 (true)
```

## Method 3: Verify System Default Applications

### Check Current Default Handler

**Using Terminal:**
```bash
# Check JPEG default handler
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsappinfo find bundleid=com.aleksandr.deplov.FastViewer

# Check what app handles JPEG files
mdls -name kMDItemContentTypeTree /path/to/test.jpg | grep -i jpeg

# Or use Launch Services directly:
# (This requires a small Swift script - see below)
```

**Using System Preferences:**
1. Right-click a .jpg file in Finder
2. Select "Get Info"
3. Expand "Open with:"
4. Check if "FastViewer" is selected
5. Click "Change All..." to see if it's the system default

## Method 4: Test by Double-Clicking Files

1. Create test image files (JPG, PNG, WebP)
2. Double-click a .jpg file in Finder
3. Verify FastViewer opens the file
4. Repeat for .png and .webp files

## Method 5: Programmatic Verification

You can add temporary test code to verify the associations:

```swift
// Add this temporarily to AppDelegate.applicationDidFinishLaunching
// after setupDefaultFileAssociationsIfNeeded()

let manager = DefaultFileAssociationManager.shared
print("Is default for JPEG: \(manager.isDefaultHandler(forContentType: "public.jpeg" as CFString))")
print("Is default for PNG: \(manager.isDefaultHandler(forContentType: "public.png" as CFString))")
print("Is default for WebP: \(manager.isDefaultHandler(forContentType: "org.webmproject.webp" as CFString))")
print("Is default for all: \(manager.isDefaultHandlerForAllTypes())")
```

## Important Notes

⚠️ **Sandboxing Limitation:**
- If your app is sandboxed, `LSSetDefaultRoleHandlerForContentType` will fail
- This is expected behavior - sandboxed apps cannot change system defaults
- The code handles this gracefully and won't crash
- To test fully, you may need to disable App Sandbox temporarily in Xcode project settings

⚠️ **System Permissions:**
- On macOS, changing default applications may require user approval
- The system may show a permission dialog
- Some systems may require admin privileges

## Troubleshooting

**If associations aren't being set:**
1. Check Xcode console for error messages
2. Verify the app is not sandboxed (check project settings)
3. Check if you have necessary permissions
4. Try running the app outside of Xcode (from Applications folder)

**To reset everything:**
```bash
# Reset all FastViewer preferences
defaults delete com.aleksandr.deplov.FastViewer

# Reset Launch Services database (use with caution)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
```




