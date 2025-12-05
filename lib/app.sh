#!/bin/bash
# App installation and launch management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Install Max Messenger app (idempotent - updates if already installed)
install_max_app() {
    log "Installing Max Messenger..."

    export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"
    local apk_file="$APK_DIR/max-messenger.apk"

    if [ ! -f "$adb" ]; then
        error "adb not found"
        return 1
    fi

    if [ ! -f "$apk_file" ]; then
        error "APK file not found: $apk_file"
        return 1
    fi

    # Check if app is already installed
    if [ -z "$MAX_PACKAGE_NAME" ]; then
        MAX_PACKAGE_NAME=$(detect_max_package_name)
    fi

    # Check if package is installed (idempotent check)
    if "$adb" shell pm list packages 2>/dev/null | grep -q "$MAX_PACKAGE_NAME"; then
        log "Max Messenger is already installed. Checking for updates..."

        # Get installed version
        local installed_version=$("$adb" shell dumpsys package "$MAX_PACKAGE_NAME" 2>/dev/null | grep versionName | head -1 | cut -d'=' -f2 | tr -d '\r' || echo "unknown")
        log "Installed version: $installed_version"

        # Install/update (idempotent - -r flag allows reinstall)
        log "Installing/updating to latest version..."
        if ! "$adb" install -r "$apk_file" 2>&1 | tee -a "$LOG_FILE"; then
            error "Failed to install/update Max Messenger"
            return 1
        fi
    else
        log "Installing Max Messenger..."
        if ! "$adb" install "$apk_file" 2>&1 | tee -a "$LOG_FILE"; then
            error "Failed to install Max Messenger"
            return 1
        fi
    fi

    log "Max Messenger installed successfully"
    return 0
}

# Launch Max Messenger app (idempotent - can be called multiple times)
launch_max_app() {
    log "Launching Max Messenger..."

    export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"

    if [ ! -f "$adb" ]; then
        error "adb not found"
        return 1
    fi

    if [ -z "$MAX_PACKAGE_NAME" ]; then
        MAX_PACKAGE_NAME=$(detect_max_package_name)
    fi

    # Verify app is installed
    if ! "$adb" shell pm list packages 2>/dev/null | grep -q "$MAX_PACKAGE_NAME"; then
        error "Max Messenger is not installed"
        return 1
    fi

    # Get the main activity (macOS compatible - no -P flag)
    local main_activity=$("$adb" shell pm dump "$MAX_PACKAGE_NAME" 2>/dev/null | grep -A 1 "android.intent.action.MAIN" | grep -oE '[0-9a-f]+ [0-9a-f]+ [^/]+/[^ ]+' | head -1 | awk '{print $NF}')

    if [ -z "$main_activity" ]; then
        # Fallback: try common activity patterns
        main_activity="$MAX_PACKAGE_NAME/.MainActivity"
    fi

    log "Starting activity: $main_activity"

    # Try to start the app (idempotent - if already running, brings to foreground)
    if ! "$adb" shell am start -n "$main_activity" 2>/dev/null; then
        # Try alternative method
        log "Trying alternative launch method..."
        if ! "$adb" shell monkey -p "$MAX_PACKAGE_NAME" -c android.intent.category.LAUNCHER 1; then
            error "Failed to launch Max Messenger"
            error "Package name: $MAX_PACKAGE_NAME"
            error "Activity: $main_activity"
            return 1
        fi
    fi

    log "Max Messenger launched successfully"
    return 0
}

# Detect Max Messenger package name (shared with apk.sh)
detect_max_package_name() {
    # Common package names to try
    local possible_names=(
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

    # Return first common name as default
    echo "ru.max.messenger"
}

# Check if app is installed
is_app_installed() {
    local package_name=${1:-$MAX_PACKAGE_NAME}

    if [ -z "$package_name" ]; then
        return 1
    fi

    export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"

    if [ ! -f "$adb" ]; then
        return 1
    fi

    "$adb" shell pm list packages 2>/dev/null | grep -q "$package_name"
}

