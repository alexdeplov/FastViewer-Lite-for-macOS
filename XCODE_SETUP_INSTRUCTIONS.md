# Xcode Configuration Instructions for XPC Service

Follow these steps to integrate the XPC service into your FastViewer project:

## Step 1: Add XPC Service Target

1. Open `FastViewer.xcodeproj` in Xcode
2. Click on the project in the navigator (top-level "FastViewer")
3. At the bottom of the targets list, click the "+" button
4. Search for "XPC" and select **"XPC Service"**
5. Click "Next"
6. Configure the target:
   - **Product Name**: `FastViewerService`
   - **Organization Name**: `Pleeq`
   - **Organization Identifier**: `com.pleeg`
   - **Bundle Identifier**: Will auto-fill as `com.pleeg.FastViewerService`
   - **Language**: Swift
7. Click "Finish"
8. When asked "Would you like to activate the 'FastViewerService' scheme?", click **"Activate"**

## Step 2: Replace XPC Service Files

Xcode will create template files. Replace them with our implementation:

1. In the Project Navigator, find the `FastViewerService` folder (blue folder icon)
2. **Delete** the following template files (Move to Trash):
   - `main.swift` (the template version)
   - `FastViewerService.swift` (if exists)
   - Any other .swift files Xcode created

3. **Add our files** to the `FastViewerService` target:
   - Right-click on `FastViewerService` folder
   - Select "Add Files to 'FastViewer'..."
   - Navigate to: `FastViewer/FastViewerService/`
   - **Select these files** (hold Cmd to multi-select):
     - `main.swift`
     - `ImageProcessingService.swift`
     - `ImageProcessingProtocol.swift`
   - Make sure **"Copy items if needed"** is UNCHECKED
   - Under "Add to targets", check **FastViewerService** only
   - Click "Add"

4. **Replace Info.plist**:
   - Delete the auto-generated `Info.plist` from FastViewerService target
   - Add our `Info.plist` from `FastViewerService/Info.plist`

## Step 3: Add Protocol to Main App Target

The protocol needs to be shared between both targets:

1. Click on `ImageProcessingProtocol.swift` in the Project Navigator
2. In the File Inspector (right panel), under "Target Membership":
   - Check **both** `FastViewer` ✅ and `FastViewerService` ✅
3. This allows both the main app and service to use the same protocol

## Step 4: Add XPC Client to Main App

1. In Project Navigator, find the `FastViewer` folder (main app)
2. Right-click and select "Add Files to 'FastViewer'..."
3. Navigate to and select: `FastViewer/FastViewer/XPCImageLoader.swift`
4. Make sure **"Copy items if needed"** is UNCHECKED
5. Under "Add to targets", check **FastViewer** only (NOT FastViewerService)
6. Click "Add"

## Step 5: Configure Build Settings

### For FastViewerService Target:

1. Select the **FastViewerService** target
2. Go to "Build Settings" tab
3. Search for "Deployment"
4. Set **macOS Deployment Target** to `12.0` (same as main app)

### For FastViewer Target:

1. Select the **FastViewer** target (main app)
2. Go to "Build Phases" tab
3. Expand **"Embed XPC Services"** section (if it doesn't exist, create it):
   - Click "+" button at top left of Build Phases
   - Select "New Copy Files Phase"
   - Change destination to "XPC Services"
4. Click the "+" button in the "Embed XPC Services" section
5. Select **FastViewerService.xpc** from the list
6. Click "Add"

This ensures the XPC service is embedded in the main app bundle.

## Step 6: Build and Test

1. Select the **FastViewer** scheme (not FastViewerService) from the scheme selector
2. Build the project: `Cmd + B`
3. Fix any compilation errors if they appear
4. Run the app: `Cmd + R`

## Step 7: Verify XPC Service is Working

When you run FastViewer:

1. Open Console.app (Applications > Utilities > Console)
2. Search for "FastViewer"
3. You should see log messages:
   - `🎯 FastViewer XPC Service starting...`
   - `🚀 FastViewer XPC Service initialized - Image processing core is now resident in memory`
   - `✅ XPC Service accepted new connection from main app`
   - `🔗 XPC connection established to FastViewerService`

4. Open an image in FastViewer
5. In Activity Monitor (Applications > Utilities > Activity Monitor):
   - Search for "FastViewer"
   - You should see TWO processes:
     - `FastViewer` (main app)
     - `com.pleeg.FastViewerService` (XPC service)

6. Quit FastViewer (Cmd+Q)
7. The XPC service should remain running for a few minutes (managed by macOS)

## Troubleshooting

### "No such service" error
- Make sure FastViewerService.xpc is embedded in Build Phases
- Check bundle identifier is exactly: `com.pleeg.FastViewer.FastViewerService`

### XPC service not starting
- Check Console.app for error messages
- Verify Info.plist is correctly configured
- Make sure XPCService > ServiceType is "Application"

### Build errors
- Ensure ImageProcessingProtocol.swift is in both targets
- Check all files have correct target membership
- Clean build folder: Product > Clean Build Folder (Shift+Cmd+K)

### Service not staying resident
- This is normal! macOS controls the service lifecycle
- The service may terminate after a period of inactivity
- It will be relaunched automatically when needed
- The key benefit is it stays loaded during active use

## Next Steps

After successful integration, you can:
1. Test the performance improvements
2. Monitor memory usage
3. Optionally enable the XPC path in ImageLoader (currently uses fallback)

---

**Important**: Keep both the old `ImageLoader` and new `XPCImageLoader` for now. This allows for easy testing and fallback if needed.
