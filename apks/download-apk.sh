#!/bin/bash
# Download Max Messenger APK with version in filename
# Usage: ./download-apk.sh

set -euo pipefail

# Get script directory (apks folder)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APKS_DIR="$SCRIPT_DIR"

# Get repo root (one level up)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load utility functions
source "$REPO_ROOT/lib/utils.sh"

# Ensure apks directory exists
ensure_dir "$APKS_DIR"

# Check if jq is available (required for JSON parsing)
if ! command_exists jq; then
    error "jq is required but not found. Install with: brew install jq"
    exit 1
fi

# RuStore package name for Max Messenger
RUSTORE_PACKAGE="ru.oneme.app"
INFO_URL="https://backapi.rustore.ru/applicationData/overallInfo/${RUSTORE_PACKAGE}"
DL_URL="https://backapi.rustore.ru/applicationData/download-link"

log "Fetching app info from RuStore (${RUSTORE_PACKAGE})..."

# Get app information
INFO_JSON=$(curl -fsSL "$INFO_URL") || {
    error "Failed to get app info from RuStore"
    exit 1
}

# Check response code
CODE=$(echo "$INFO_JSON" | jq -r '.code // empty')
if [ "$CODE" != "OK" ]; then
    error "RuStore returned unexpected code: ${CODE:-<none>}"
    exit 1
fi

# Extract app details
APP_ID=$(echo "$INFO_JSON" | jq -r '.body.appId')
VERSION_NAME=$(echo "$INFO_JSON" | jq -r '.body.versionName')
VERSION_CODE=$(echo "$INFO_JSON" | jq -r '.body.versionCode')

if [ -z "$APP_ID" ] || [ -z "$VERSION_NAME" ] || [ -z "$VERSION_CODE" ]; then
    error "Failed to extract app details from RuStore response"
    exit 1
fi

log "Found version: ${VERSION_NAME} (code=${VERSION_CODE}, appId=${APP_ID})"

# Create output filename with version
OUTPUT_FILE="$APKS_DIR/max-${VERSION_NAME}.apk"

# Check if file already exists
if [ -f "$OUTPUT_FILE" ]; then
    log "APK file already exists: $OUTPUT_FILE"
    log "File size: $(ls -lh "$OUTPUT_FILE" | awk '{print $5}')"
    read -p "Download again? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping download"
        exit 0
    fi
    rm -f "$OUTPUT_FILE"
fi

# Request download link
log "Requesting APK download link..."
DL_REQ_JSON=$(jq -n --argjson appId "$APP_ID" '{appId: $appId, firstInstall: true}')

DL_JSON=$(curl -fsSL \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$DL_REQ_JSON" \
    "$DL_URL") || {
    error "Failed to get download link from RuStore"
    exit 1
}

# Check download response code
DL_CODE=$(echo "$DL_JSON" | jq -r '.code // empty')
if [ "$DL_CODE" != "OK" ]; then
    error "RuStore download-link returned unexpected code: ${DL_CODE:-<none>}"
    exit 1
fi

# Extract APK URL
APK_URL=$(echo "$DL_JSON" | jq -r '.body.apkUrl // empty')

if [ -z "$APK_URL" ]; then
    error "Failed to extract apkUrl from RuStore response"
    exit 1
fi

log "Downloading APK from RuStore..."

# RuStore returns a container ZIP with the actual APK inside
# Download to temporary file first
TEMP_CONTAINER="${OUTPUT_FILE}.container"

# Download container
if download_with_progress "$APK_URL" "$TEMP_CONTAINER" "true"; then
    if [ ! -f "$TEMP_CONTAINER" ]; then
        error "Downloaded file not found"
        exit 1
    fi

    log "Extracting APK from RuStore container..."

    # Extract the inner APK file from the container
    TEMP_DIR="$APKS_DIR/temp_extract_$$"
    mkdir -p "$TEMP_DIR"
    EXTRACTED_APK=""

    # Extract container
    if unzip -q "$TEMP_CONTAINER" -d "$TEMP_DIR" 2>/dev/null; then
        # Find all APK files in the container
        APK_FILES=$(find "$TEMP_DIR" -name "*.apk" -type f)

        if [ -z "$APK_FILES" ]; then
            error "No APK file found inside RuStore container"
            log "Contents of container:"
            find "$TEMP_DIR" -type f | head -10 | while read file; do
                log "  $file"
            done
            rm -rf "$TEMP_DIR"
            rm -f "$TEMP_CONTAINER"
            exit 1
        fi

        # Try to find a valid APK (one that contains AndroidManifest.xml)
        EXTRACTED_APK=""
        while IFS= read -r CANDIDATE_APK; do
            if [ -n "$CANDIDATE_APK" ] && [ -f "$CANDIDATE_APK" ]; then
                log "Checking candidate APK: $CANDIDATE_APK"
                MANIFEST_COUNT=$(unzip -l "$CANDIDATE_APK" 2>&1 | grep -c "AndroidManifest.xml" 2>/dev/null || echo "0")
                if [ "$MANIFEST_COUNT" -gt 0 ]; then
                    EXTRACTED_APK="$CANDIDATE_APK"
                    log "Found valid APK: $EXTRACTED_APK"
                    break
                fi
            fi
        done <<< "$APK_FILES"

        # If no valid APK found, use the first one
        if [ -z "$EXTRACTED_APK" ]; then
            EXTRACTED_APK=$(echo "$APK_FILES" | head -1)
            log "No APK with AndroidManifest.xml found, using first APK: $EXTRACTED_APK"
        fi

        if [ -z "$EXTRACTED_APK" ] || [ ! -f "$EXTRACTED_APK" ]; then
            error "Failed to find valid APK file inside RuStore container"
            rm -rf "$TEMP_DIR"
            rm -f "$TEMP_CONTAINER"
            exit 1
        fi

        # Verify the extracted APK contains AndroidManifest.xml
        log "Verifying extracted APK: $EXTRACTED_APK"
        MANIFEST_COUNT=$(unzip -l "$EXTRACTED_APK" 2>&1 | grep -c "AndroidManifest.xml" 2>/dev/null || echo "0")
        if [ "$MANIFEST_COUNT" -gt 0 ]; then
            log "APK verification successful - AndroidManifest.xml found"
        else
            error "Extracted file does not appear to be a valid APK (no AndroidManifest.xml)"
            rm -rf "$TEMP_DIR"
            rm -f "$TEMP_CONTAINER"
            exit 1
        fi

        # Move extracted APK to final location
        if mv "$EXTRACTED_APK" "$OUTPUT_FILE"; then
            log "APK downloaded successfully: $OUTPUT_FILE"
            log "Version: ${VERSION_NAME} (code=${VERSION_CODE})"
            log "File size: $(ls -lh "$OUTPUT_FILE" | awk '{print $5}')"
            # Cleanup temporary files
            log "Cleaning up temporary files..."
            rm -rf "$TEMP_DIR"
            rm -f "$TEMP_CONTAINER"
            log "Done!"
            exit 0
        else
            error "Failed to move extracted APK to final location"
            rm -rf "$TEMP_DIR"
            rm -f "$TEMP_CONTAINER"
            exit 1
        fi
    else
        error "Failed to extract APK from RuStore container"
        rm -rf "$TEMP_DIR"
        rm -f "$TEMP_CONTAINER"
        exit 1
    fi
fi

error "Failed to download APK from RuStore"
rm -f "$TEMP_CONTAINER"
exit 1
