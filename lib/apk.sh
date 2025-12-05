#!/bin/bash
# APK download and management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Download Max Messenger APK (idempotent - skips if already exists)
download_max_apk() {
    log "Downloading Max Messenger APK..."

    ensure_dir "$APK_DIR"

    # Try to find Max Messenger package name if not set
    if [ -z "$MAX_PACKAGE_NAME" ]; then
        log "Package name not specified, attempting to detect..."
        MAX_PACKAGE_NAME=$(detect_max_package_name)
    fi

    if [ -z "$MAX_PACKAGE_NAME" ]; then
        error "Could not determine Max Messenger package name"
        error "Please set MAX_PACKAGE_NAME environment variable"
        error "Example: export MAX_PACKAGE_NAME=ru.max.messenger"
        return 1
    fi

    log "Using package name: $MAX_PACKAGE_NAME"

    local apk_file="$APK_DIR/max-messenger.apk"

    # Check if APK already exists (idempotent)
    if [ -f "$apk_file" ]; then
        log "APK file already exists at $apk_file"
        # Verify it's a valid APK
        if file_exists "$apk_file"; then
            return 0
        else
            warn "Existing APK file appears invalid, re-downloading..."
            rm -f "$apk_file"
        fi
    fi

    # Try to download from various sources
    log "Attempting to download APK..."

    # Method 1: Try RuStore (most reliable for Russian apps)
    if download_from_rustore "$MAX_PACKAGE_NAME" "$apk_file"; then
        log "Successfully downloaded APK from RuStore"
        return 0
    fi

    # Method 2: Try APKMirror
    if download_from_apkmirror "$MAX_PACKAGE_NAME" "$apk_file"; then
        log "Successfully downloaded APK from APKMirror"
        return 0
    fi

    # Method 3: Try APKPure
    if download_from_apkpure "$MAX_PACKAGE_NAME" "$apk_file"; then
        log "Successfully downloaded APK from APKPure"
        return 0
    fi

    # Method 4: Try using apkeep (requires Google account)
    if command_exists apkeep; then
        log "Attempting to download using apkeep..."
        if download_with_apkeep "$MAX_PACKAGE_NAME" "$apk_file"; then
            log "Successfully downloaded APK using apkeep"
            return 0
        fi
    fi

    error "Failed to download APK. Please download manually and place at: $apk_file"
    error "Or install apkeep: pip3 install apkeep"
    error "You can also set MAX_PACKAGE_NAME to help with detection"
    return 1
}

# Detect Max Messenger package name
detect_max_package_name() {
    # Common package names to try (RuStore package name for Max is ru.oneme.app)
    local possible_names=(
        "ru.oneme.app"
        "ru.max.messenger"
        "com.max.messenger"
        "ru.max"
        "com.max"
        "ru.vk.max"
    )

    # Try to find installed package in emulator
    export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"

    if [ -f "$adb" ] && "$adb" devices 2>/dev/null | grep -q "device$"; then
        for name in "${possible_names[@]}"; do
            if "$adb" shell pm list packages 2>/dev/null | grep -q "$name"; then
                echo "$name"
                return 0
            fi
        done
    fi

    # Return RuStore package name as default (most reliable)
    echo "ru.oneme.app"
}

# Download from RuStore (most reliable for Russian apps)
# Uses exact same logic as download_max_from_rustore.sh
download_from_rustore() {
    local package_name=$1
    local output_file=$2

    # Check if jq is available (required for JSON parsing)
    if ! command_exists jq; then
        warn "jq not found, skipping RuStore download. Install with: brew install jq"
        return 1
    fi

    # Use ru.oneme.app for RuStore (this is the correct package name for Max in RuStore)
    local rustore_package="ru.oneme.app"
    local info_url="https://backapi.rustore.ru/applicationData/overallInfo/${rustore_package}"
    local dl_url="https://backapi.rustore.ru/applicationData/download-link"

    log "Fetching app info from RuStore (${rustore_package})..."

    # Get app information (exact same as working script)
    local info_json
    info_json=$(curl -fsSL "$info_url") || {
        warn "Failed to get app info from RuStore"
        return 1
    }

    # Check response code
    local code
    code=$(echo "$info_json" | jq -r '.code // empty')
    if [ "$code" != "OK" ]; then
        warn "RuStore returned unexpected code: ${code:-<none>}"
        return 1
    fi

    # Extract app details (exact same as working script)
    local app_id version_name version_code
    app_id=$(echo "$info_json" | jq -r '.body.appId')
    version_name=$(echo "$info_json" | jq -r '.body.versionName')
    version_code=$(echo "$info_json" | jq -r '.body.versionCode')

    if [ -z "$app_id" ] || [ -z "$version_name" ] || [ -z "$version_code" ]; then
        warn "Failed to extract app details from RuStore response"
        return 1
    fi

    log "Found version: ${version_name} (code=${version_code}, appId=${app_id})"

    # Request download link (exact same as working script)
    log "Requesting APK download link..."
    local dl_req_json
    dl_req_json=$(jq -n --argjson appId "$app_id" '{appId: $appId, firstInstall: true}')

    local dl_json
    dl_json=$(curl -fsSL \
        -H "Content-Type: application/json; charset=utf-8" \
        -d "$dl_req_json" \
        "$dl_url") || {
        warn "Failed to get download link from RuStore"
        return 1
    }

    # Check download response code
    local dl_code
    dl_code=$(echo "$dl_json" | jq -r '.code // empty')
    if [ "$dl_code" != "OK" ]; then
        warn "RuStore download-link returned unexpected code: ${dl_code:-<none>}"
        return 1
    fi

    # Extract APK URL
    local apk_url
    apk_url=$(echo "$dl_json" | jq -r '.body.apkUrl // empty')

    if [ -z "$apk_url" ]; then
        warn "Failed to extract apkUrl from RuStore response"
        return 1
    fi

    log "Downloading APK from RuStore..."
    # Use exact same curl command as working script: -fSL -C -
    if curl -fSL -C - -o "$output_file" "$apk_url"; then
        if [ -f "$output_file" ]; then
            log "APK downloaded successfully: ${version_name} (${version_code})"
            return 0
        fi
    fi

    warn "Failed to download APK from RuStore"
    rm -f "$output_file"
    return 1
}

# Download from APKMirror
download_from_apkmirror() {
    local package_name=$1
    local output_file=$2

    # APKMirror requires specific URL format
    # This is a simplified version - may need adjustment
    local search_url="https://www.apkmirror.com/?post_type=app_release&searchtype=apk&s=${package_name}"

    # Try to extract download link (macOS compatible - no -P flag)
    local download_url=$(curl -s "$search_url" 2>/dev/null | grep -o 'href="[^"]*apk[^"]*"' | head -1 | sed 's/href="//;s/"$//')

    if [ -n "$download_url" ]; then
        if curl -L -o "$output_file" "https://www.apkmirror.com$download_url" 2>/dev/null && [ -f "$output_file" ]; then
            return 0
        fi
    fi

    return 1
}

# Download from APKPure
download_from_apkpure() {
    local package_name=$1
    local output_file=$2

    # APKPure URL format
    local app_url="https://apkpure.com/${package_name}/${package_name}/download"

    # Try to get download link (macOS compatible - no -P flag)
    local download_url=$(curl -s "$app_url" 2>/dev/null | grep -o 'href="[^"]*apk[^"]*download[^"]*"' | head -1 | sed 's/href="//;s/"$//')

    if [ -n "$download_url" ]; then
        if curl -L -o "$output_file" "$download_url" 2>/dev/null && [ -f "$output_file" ]; then
            return 0
        fi
    fi

    return 1
}

# Download using apkeep
download_with_apkeep() {
    local package_name=$1
    local output_file=$2

    # apkeep requires Google account credentials
    if [ -z "${GOOGLE_EMAIL:-}" ] || [ -z "${GOOGLE_PASSWORD:-}" ]; then
        warn "apkeep requires GOOGLE_EMAIL and GOOGLE_PASSWORD environment variables"
        return 1
    fi

    if apkeep -a "$package_name" -o "$APK_DIR" 2>/dev/null; then
        # Find downloaded APK
        local downloaded_apk=$(find "$APK_DIR" -name "*.apk" -type f | head -1)
        if [ -n "$downloaded_apk" ] && [ "$downloaded_apk" != "$output_file" ]; then
            mv "$downloaded_apk" "$output_file"
            return 0
        elif [ -f "$output_file" ]; then
            return 0
        fi
    fi

    return 1
}

