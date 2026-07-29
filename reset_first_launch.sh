#!/bin/bash

# Script to reset the first launch flag for testing default file associations
# Usage: ./reset_first_launch.sh

BUNDLE_ID="com.aleksandr.deplov.FastViewer"
KEY="DefaultFileAssociationsSet"

echo "Resetting first launch flag for FastViewer..."
echo "Bundle ID: $BUNDLE_ID"
echo "Key: $KEY"
echo ""

# Check if the key exists
if defaults read "$BUNDLE_ID" "$KEY" &>/dev/null; then
    echo "Current value: $(defaults read "$BUNDLE_ID" "$KEY")"
    echo ""
    echo "Deleting key..."
    defaults delete "$BUNDLE_ID" "$KEY"
    echo "✓ Key deleted successfully"
else
    echo "Key does not exist (already reset or first launch)"
fi

echo ""
echo "Verification:"
if defaults read "$BUNDLE_ID" "$KEY" &>/dev/null; then
    echo "✗ Key still exists: $(defaults read "$BUNDLE_ID" "$KEY")"
else
    echo "✓ Key does not exist - ready for first launch test"
fi

echo ""
echo "Next steps:"
echo "1. Launch FastViewer app"
echo "2. Check Xcode console for association messages"
echo "3. Verify files open with FastViewer when double-clicked"




