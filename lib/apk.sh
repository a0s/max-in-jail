#!/bin/bash
# APK download and management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Extract package name from APK file
extract_package_name_from_apk() {
    local apk_file=$1

    if [ ! -f "$apk_file" ]; then
        return 1
    fi

    # Try using aapt/aapt2 if available (most reliable)
    if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT/build-tools" ]; then
        # Find aapt2 or aapt tools
        local aapt2_tool=""
        local aapt_tool=""

        # Find the latest aapt2
        for build_tool_dir in "$ANDROID_SDK_ROOT/build-tools"/*/; do
            if [ -f "${build_tool_dir}aapt2" ]; then
                aapt2_tool="${build_tool_dir}aapt2"
                break
            fi
        done

        # Find the latest aapt if aapt2 not found
        if [ -z "$aapt2_tool" ]; then
            for build_tool_dir in "$ANDROID_SDK_ROOT/build-tools"/*/; do
                if [ -f "${build_tool_dir}aapt" ]; then
                    aapt_tool="${build_tool_dir}aapt"
                    break
                fi
            done
        fi

        # Try aapt2 first
        if [ -n "$aapt2_tool" ] && [ -f "$aapt2_tool" ]; then
            local badging_output
            badging_output=$("$aapt2_tool" dump badging "$apk_file" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$badging_output" ]; then
                # Extract package name - look for name='...' pattern
                local package_name
                package_name=$(echo "$badging_output" | grep "^package:" | sed -n "s/.*name='\([^']*\)'.*/\1/p" | head -1)
                # Validate it looks like a package name (contains dots, not just numbers)
                if [ -n "$package_name" ] && echo "$package_name" | grep -qE '^[a-zA-Z][a-zA-Z0-9_.]*$' && [ "$package_name" != "${package_name//[^0-9]/}" ]; then
                    echo "$package_name"
                    return 0
                fi
            fi
        fi

        # Try aapt as fallback
        if [ -n "$aapt_tool" ] && [ -f "$aapt_tool" ]; then
            local badging_output
            badging_output=$("$aapt_tool" dump badging "$apk_file" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$badging_output" ]; then
                # Extract package name - look for name='...' pattern
                local package_name
                package_name=$(echo "$badging_output" | grep "^package:" | sed -n "s/.*name='\([^']*\)'.*/\1/p" | head -1)
                # Validate it looks like a package name (contains dots, not just numbers)
                if [ -n "$package_name" ] && echo "$package_name" | grep -qE '^[a-zA-Z][a-zA-Z0-9_.]*$' && [ "$package_name" != "${package_name//[^0-9]/}" ]; then
                    echo "$package_name"
                    return 0
                fi
            fi
        fi
    fi

    # Fallback: Try to extract from AndroidManifest.xml using unzip and aapt
    # This is less reliable but might work if aapt is not available
    return 1
}

# Verify APK file is valid (contains AndroidManifest.xml)
verify_apk() {
    local apk_file=$1

    if [ ! -f "$apk_file" ]; then
        return 1
    fi

    # Check if file is a ZIP archive
    if ! file "$apk_file" | grep -q "Zip archive"; then
        return 1
    fi

    # Try using aapt/aapt2 if available (more reliable)
    if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
        local aapt2="$ANDROID_SDK_ROOT/build-tools/*/aapt2"
        local aapt="$ANDROID_SDK_ROOT/build-tools/*/aapt"

        # Try aapt2 first
        for tool in $aapt2 $aapt; do
            if [ -f "$tool" ] 2>/dev/null; then
                if "$tool" dump badging "$apk_file" >/dev/null 2>&1; then
                    return 0
                fi
            fi
        done
    fi

    # Fallback: Check if APK contains AndroidManifest.xml using unzip
    # Count matches - handle grep exit code properly
    local manifest_count
    manifest_count=$(unzip -l "$apk_file" 2>&1 | grep -c "AndroidManifest.xml" 2>/dev/null || echo "0")
    if [ "$manifest_count" -eq 0 ]; then
        return 1
    fi

    return 0
}

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
        if verify_apk "$apk_file"; then
            log "Existing APK file is valid, skipping download"
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
        if verify_apk "$apk_file"; then
            log "Successfully downloaded and verified APK from RuStore"
            return 0
        else
            warn "Downloaded APK from RuStore failed validation, trying other sources..."
            rm -f "$apk_file"
        fi
    fi

    # Method 2: Try APKMirror
    if download_from_apkmirror "$MAX_PACKAGE_NAME" "$apk_file"; then
        if verify_apk "$apk_file"; then
            log "Successfully downloaded and verified APK from APKMirror"
            return 0
        else
            warn "Downloaded APK from APKMirror failed validation, trying other sources..."
            rm -f "$apk_file"
        fi
    fi

    # Method 3: Try APKPure
    if download_from_apkpure "$MAX_PACKAGE_NAME" "$apk_file"; then
        if verify_apk "$apk_file"; then
            log "Successfully downloaded and verified APK from APKPure"
            return 0
        else
            warn "Downloaded APK from APKPure failed validation, trying other sources..."
            rm -f "$apk_file"
        fi
    fi

    # Method 4: Try using apkeep (requires Google account)
    if command_exists apkeep; then
        log "Attempting to download using apkeep..."
        if download_with_apkeep "$MAX_PACKAGE_NAME" "$apk_file"; then
            if verify_apk "$apk_file"; then
                log "Successfully downloaded and verified APK using apkeep"
                return 0
            else
                warn "Downloaded APK using apkeep failed validation"
                rm -f "$apk_file"
            fi
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

    # RuStore returns a container ZIP with the actual APK inside
    # Download to temporary file first
    local temp_container="${output_file}.container"

    # Use download_with_progress for better UX
    if download_with_progress "$apk_url" "$temp_container" "true"; then
        if [ ! -f "$temp_container" ]; then
            warn "Downloaded file not found"
            return 1
        fi

        log "Extracting APK from RuStore container..."

        # Extract the inner APK file from the container
        # RuStore containers typically contain a single .apk file
        # Use project directory for debugging purposes
        local temp_dir
        temp_dir="$APK_DIR/temp_extract_$$"
        mkdir -p "$temp_dir"
        local extracted_apk=""

        # Extract container
        if unzip -q "$temp_container" -d "$temp_dir" 2>/dev/null; then
            # Find all APK files in the container
            local apk_files
            apk_files=$(find "$temp_dir" -name "*.apk" -type f)

            if [ -z "$apk_files" ]; then
                warn "No APK file found inside RuStore container"
                log "Contents of container:"
                find "$temp_dir" -type f | head -10 | while read file; do
                    log "  $file"
                done
                warn "Temporary extraction directory preserved for debugging: $temp_dir"
                warn "Container file preserved for debugging: $temp_container"
                # Don't delete for debugging - user can clean up manually
                # rm -rf "$temp_dir"
                # rm -f "$temp_container"
                return 1
            fi

            # Try to find a valid APK (one that contains AndroidManifest.xml)
            extracted_apk=""
            while IFS= read -r candidate_apk; do
                if [ -n "$candidate_apk" ] && [ -f "$candidate_apk" ]; then
                    log "Checking candidate APK: $candidate_apk"
                    # Check by counting matches - handle grep exit code properly
                    local manifest_count
                    manifest_count=$(unzip -l "$candidate_apk" 2>&1 | grep -c "AndroidManifest.xml" 2>/dev/null || echo "0")
                    if [ "$manifest_count" -gt 0 ]; then
                        extracted_apk="$candidate_apk"
                        log "Found valid APK: $extracted_apk"
                        break
                    fi
                fi
            done <<< "$apk_files"

            # If no valid APK found, use the first one (might still work)
            if [ -z "$extracted_apk" ]; then
                extracted_apk=$(echo "$apk_files" | head -1)
                log "No APK with AndroidManifest.xml found, using first APK: $extracted_apk"
            fi

            if [ -z "$extracted_apk" ] || [ ! -f "$extracted_apk" ]; then
                warn "Failed to find valid APK file inside RuStore container"
                warn "Temporary extraction directory preserved for debugging: $temp_dir"
                warn "Container file preserved for debugging: $temp_container"
                # Don't delete for debugging - user can clean up manually
                # rm -rf "$temp_dir"
                # rm -f "$temp_container"
                return 1
            fi

            # Verify the extracted APK contains AndroidManifest.xml
            log "Verifying extracted APK: $extracted_apk"
            log "APK file size: $(ls -lh "$extracted_apk" 2>/dev/null | awk '{print $5}' || echo 'unknown')"

            # Check for AndroidManifest.xml by counting matches
            local manifest_count
            manifest_count=$(unzip -l "$extracted_apk" 2>&1 | grep -c "AndroidManifest.xml" 2>/dev/null || echo "0")
            if [ "$manifest_count" -gt 0 ]; then
                log "APK verification successful - AndroidManifest.xml found"
            else
                warn "Extracted file does not appear to be a valid APK (no AndroidManifest.xml)"
                warn "First few entries in APK:"
                unzip -l "$extracted_apk" 2>&1 | head -10 | while IFS= read -r line || [ -n "$line" ]; do
                    warn "  $line"
                done
                warn "Temporary extraction directory preserved for debugging: $temp_dir"
                warn "Container file preserved for debugging: $temp_container"
                warn "Extracted APK file: $extracted_apk"
                # Don't delete for debugging - user can clean up manually
                # rm -rf "$temp_dir"
                # rm -f "$temp_container"
                return 1
            fi

            # Move extracted APK to final location
            if mv "$extracted_apk" "$output_file"; then
                log "APK extracted successfully: ${version_name} (${version_code})"
                # Cleanup temporary files (keep for debugging on error)
                log "Cleaning up temporary files..."
                rm -rf "$temp_dir"
                rm -f "$temp_container"
                return 0
            else
                warn "Failed to move extracted APK to final location"
                warn "Temporary extraction directory preserved for debugging: $temp_dir"
                warn "Container file preserved for debugging: $temp_container"
                warn "Extracted APK file: $extracted_apk"
                # Don't delete for debugging - user can clean up manually
                # rm -rf "$temp_dir"
                # rm -f "$temp_container"
                return 1
            fi
        else
            warn "Failed to extract APK from RuStore container"
            rm -rf "$temp_dir"
            rm -f "$temp_container"
            return 1
        fi
    fi

    warn "Failed to download APK from RuStore"
    rm -f "$temp_container"
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
        if download_with_progress "https://www.apkmirror.com$download_url" "$output_file" && [ -f "$output_file" ]; then
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
        if download_with_progress "$download_url" "$output_file" && [ -f "$output_file" ]; then
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

