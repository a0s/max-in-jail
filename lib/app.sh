#!/bin/bash
# App installation and launch management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# List all installed packages (for debugging)
list_installed_packages() {
    export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"

    if [ ! -f "$adb" ]; then
        return 1
    fi

    log "Listing all installed packages (including disabled):"
    "$adb" shell pm list packages -u 2>/dev/null | sed 's/package://' | sort | while read -r pkg; do
        log "  - $pkg"
    done
}

# Verify package is actually installed
verify_package_installed() {
    local package_name=$1
    export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"

    if [ ! -f "$adb" ]; then
        return 1
    fi

    # Check enabled packages
    if "$adb" shell pm list packages 2>/dev/null | grep -q "^package:$package_name$"; then
        return 0
    fi

    # Check disabled packages
    if "$adb" shell pm list packages -u 2>/dev/null | grep -q "^package:$package_name$"; then
        log "Package $package_name is installed but disabled"
        return 0
    fi

    return 1
}

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

    # Extract actual package name from APK
    log "Extracting package name from APK..."
    local extracted_package
    extracted_package=$(extract_package_name_from_apk "$apk_file" 2>/dev/null)

    # Validate extracted package name looks reasonable
    if [ -n "$extracted_package" ] && echo "$extracted_package" | grep -qE '^[a-zA-Z][a-zA-Z0-9_.]*$' && [ "$extracted_package" != "${extracted_package//[^0-9]/}" ]; then
        log "Package name extracted from APK: $extracted_package"
        MAX_PACKAGE_NAME="$extracted_package"
    else
        if [ -n "$extracted_package" ]; then
            warn "Extracted value '$extracted_package' doesn't look like a valid package name, using detection instead"
        else
            warn "Could not extract package name from APK, using detection..."
        fi

        # Try to detect from installed packages first
        if [ -z "$MAX_PACKAGE_NAME" ]; then
            MAX_PACKAGE_NAME=$(detect_max_package_name)
        fi

        # Fallback to ru.oneme.app if detection fails
        if [ -z "$MAX_PACKAGE_NAME" ] || [ "$MAX_PACKAGE_NAME" = "${MAX_PACKAGE_NAME//[^0-9]/}" ]; then
            warn "Detection failed, using default: ru.oneme.app"
            MAX_PACKAGE_NAME="ru.oneme.app"
        fi
    fi

    log "Using package name: $MAX_PACKAGE_NAME"

    # List all installed packages for debugging
    log "Current installed packages before installation:"
    list_installed_packages

    # Check if package is installed (idempotent check)
    local is_installed=false
    if verify_package_installed "$MAX_PACKAGE_NAME"; then
        is_installed=true
        log "Max Messenger is already installed. Checking for updates..."

        # Get installed version
        local installed_version=$("$adb" shell dumpsys package "$MAX_PACKAGE_NAME" 2>/dev/null | grep versionName | head -1 | cut -d'=' -f2 | tr -d '\r' || echo "unknown")
        log "Installed version: $installed_version"

        # Install/update (idempotent - -r flag allows reinstall)
        log "Installing/updating to latest version..."
        log "Running: adb install -r $apk_file"
        local install_output
        install_output=$("$adb" install -r "$apk_file" 2>&1)
        local install_exit_code=$?
        log "Installation output:"
        echo "$install_output" | while IFS= read -r line; do
            log "  $line"
        done
        echo "$install_output" | tee -a "$LOG_FILE"

        if [ $install_exit_code -ne 0 ]; then
            error "Failed to install/update Max Messenger (exit code: $install_exit_code)"
            return 1
        fi
    else
        log "Installing Max Messenger (first time)..."
        log "Running: adb install $apk_file"
        local install_output
        install_output=$("$adb" install "$apk_file" 2>&1)
        local install_exit_code=$?
        log "Installation output:"
        echo "$install_output" | while IFS= read -r line; do
            log "  $line"
        done
        echo "$install_output" | tee -a "$LOG_FILE"

        if [ $install_exit_code -ne 0 ]; then
            error "Failed to install Max Messenger (exit code: $install_exit_code)"
            return 1
        fi
    fi

    # Wait a moment for package manager to register the app
    log "Waiting for package manager to register the app..."
    sleep 2

    # Verify installation
    log "Verifying installation..."
    log "Current installed packages after installation:"
    list_installed_packages

    if verify_package_installed "$MAX_PACKAGE_NAME"; then
        log "Max Messenger installed successfully (package: $MAX_PACKAGE_NAME)"

        # Get package info
        log "Package information:"
        local package_info
        package_info=$("$adb" shell dumpsys package "$MAX_PACKAGE_NAME" 2>/dev/null | head -20)
        echo "$package_info" | while IFS= read -r line; do
            log "  $line"
        done

        return 0
    else
        error "Installation reported success but package $MAX_PACKAGE_NAME not found!"

        # Try to find the actual installed package
        log "Searching for installed Max Messenger package..."
        local found_package
        found_package=$("$adb" shell pm list packages 2>/dev/null | grep -iE "max|messenger|oneme" | sed 's/package://' | head -1)

        if [ -n "$found_package" ]; then
            warn "Found installed package: $found_package"
            warn "Updating MAX_PACKAGE_NAME to match installed package"
            MAX_PACKAGE_NAME="$found_package"
            export MAX_PACKAGE_NAME

            # Verify again with correct package name
            if verify_package_installed "$MAX_PACKAGE_NAME"; then
                log "Max Messenger installed successfully (package: $MAX_PACKAGE_NAME)"
                return 0
            fi
        else
            error "Trying to find similar packages..."
            "$adb" shell pm list packages 2>/dev/null | grep -iE "max|messenger|oneme" | while read -r pkg; do
                warn "Found similar package: $pkg"
            done
        fi

        return 1
    fi
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

    log "Checking for package: $MAX_PACKAGE_NAME"

    # Verify app is installed (check both enabled and disabled)
    if ! verify_package_installed "$MAX_PACKAGE_NAME"; then
        warn "Package $MAX_PACKAGE_NAME not found, searching for installed Max Messenger package..."

        # Try to find the actual installed package
        local found_package
        found_package=$("$adb" shell pm list packages 2>/dev/null | grep -iE "max|messenger|oneme" | sed 's/package://' | head -1)

        if [ -n "$found_package" ]; then
            warn "Found installed package: $found_package"
            warn "Updating MAX_PACKAGE_NAME to match installed package"
            MAX_PACKAGE_NAME="$found_package"
            export MAX_PACKAGE_NAME

            # Verify again with correct package name
            if ! verify_package_installed "$MAX_PACKAGE_NAME"; then
                error "Max Messenger is not installed"
                error "Package name checked: $MAX_PACKAGE_NAME"

                log "Listing all installed packages to help debug:"
                list_installed_packages

                return 1
            fi
        else
            error "Max Messenger is not installed"
            error "Package name checked: $MAX_PACKAGE_NAME"

            log "Listing all installed packages to help debug:"
            list_installed_packages

            # Try to find packages with similar names
            log "Searching for packages with 'max', 'messenger', or 'oneme' in name:"
            "$adb" shell pm list packages 2>/dev/null | grep -iE "max|messenger|oneme" | while read -r pkg; do
                warn "Found similar package: $pkg"
            done

            return 1
        fi
    fi

    log "Package $MAX_PACKAGE_NAME is installed"

    # Check if package is disabled
    if ! "$adb" shell pm list packages 2>/dev/null | grep -q "^package:$MAX_PACKAGE_NAME$"; then
        log "Package is disabled, attempting to enable..."
        "$adb" shell pm enable "$MAX_PACKAGE_NAME" 2>/dev/null || warn "Could not enable package"
        sleep 1
    fi

    # Get the main activity (macOS compatible - no -P flag)
    log "Extracting main activity from package..."
    local main_activity=$("$adb" shell pm dump "$MAX_PACKAGE_NAME" 2>/dev/null | grep -A 1 "android.intent.action.MAIN" | grep -oE '[0-9a-f]+ [0-9a-f]+ [^/]+/[^ ]+' | head -1 | awk '{print $NF}')

    if [ -z "$main_activity" ]; then
        warn "Could not extract main activity from pm dump"
        # Try alternative method using dumpsys
        main_activity=$("$adb" shell dumpsys package "$MAX_PACKAGE_NAME" 2>/dev/null | grep -A 5 "android.intent.action.MAIN" | grep -oE '[a-zA-Z0-9._]+/[a-zA-Z0-9._]+' | head -1)

        if [ -z "$main_activity" ]; then
            # Fallback: try common activity patterns
            warn "Using fallback activity pattern"
            main_activity="$MAX_PACKAGE_NAME/.MainActivity"
        fi
    fi

    log "Starting activity: $main_activity"
    log "Running: adb shell am start -n $main_activity"

    # Try to start the app (idempotent - if already running, brings to foreground)
    local start_output
    start_output=$("$adb" shell am start -n "$main_activity" 2>&1)
    local start_exit_code=$?

    log "Start command output:"
    echo "$start_output" | while IFS= read -r line; do
        log "  $line"
    done

    if [ $start_exit_code -ne 0 ] || echo "$start_output" | grep -qi "error\|exception\|not found"; then
        # Try alternative method
        log "Trying alternative launch method (monkey)..."
        log "Running: adb shell monkey -p $MAX_PACKAGE_NAME -c android.intent.category.LAUNCHER 1"

        local monkey_output
        monkey_output=$("$adb" shell monkey -p "$MAX_PACKAGE_NAME" -c android.intent.category.LAUNCHER 1 2>&1)
        local monkey_exit_code=$?

        log "Monkey command output:"
        echo "$monkey_output" | while IFS= read -r line; do
            log "  $line"
        done

        if [ $monkey_exit_code -ne 0 ] || echo "$monkey_output" | grep -qi "error\|exception\|not found"; then
            error "Failed to launch Max Messenger"
            error "Package name: $MAX_PACKAGE_NAME"
            error "Activity: $main_activity"
            error "Exit code: $monkey_exit_code"

            # Try to get more info about the package
            log "Package details:"
            "$adb" shell dumpsys package "$MAX_PACKAGE_NAME" 2>/dev/null | grep -E "versionName|versionCode|enabled|state" | head -10 | while IFS= read -r line; do
                log "  $line"
            done

            return 1
        fi
    fi

    log "Max Messenger launched successfully"
    return 0
}

# Detect Max Messenger package name (shared with apk.sh)
detect_max_package_name() {
    # Common package names to try (RuStore uses ru.oneme.app)
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
        # Check enabled packages first
        for name in "${possible_names[@]}"; do
            if "$adb" shell pm list packages 2>/dev/null | grep -q "^package:$name$"; then
                echo "$name"
                return 0
            fi
        done

        # Check disabled packages
        for name in "${possible_names[@]}"; do
            if "$adb" shell pm list packages -u 2>/dev/null | grep -q "^package:$name$"; then
                echo "$name"
                return 0
            fi
        done
    fi

    # Try to extract from APK if available
    local apk_file="$APK_DIR/max-messenger.apk"
    if [ -f "$apk_file" ]; then
        local extracted_package
        extracted_package=$(extract_package_name_from_apk "$apk_file" 2>/dev/null)
        if [ -n "$extracted_package" ]; then
            echo "$extracted_package"
            return 0
        fi
    fi

    # Return RuStore package name as default (most reliable)
    echo "ru.oneme.app"
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

