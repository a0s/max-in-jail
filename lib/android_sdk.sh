#!/bin/bash
# Android SDK setup and management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Setup Android SDK (idempotent)
setup_android_sdk() {
    log "Setting up Android SDK..."

    # Ensure JAVA_HOME is set
    if [ -z "${JAVA_HOME:-}" ]; then
        if [ -d "/opt/homebrew/opt/openjdk" ]; then
            export JAVA_HOME="/opt/homebrew/opt/openjdk"
        elif [ -d "/usr/local/opt/openjdk" ]; then
            export JAVA_HOME="/usr/local/opt/openjdk"
        fi
    fi

    if [ -n "${JAVA_HOME:-}" ]; then
        export PATH="$JAVA_HOME/bin:$PATH"
    fi

    # Verify Java is working
    if ! java -version 2>&1 | grep -q "version"; then
        error "Java is not working. Please install Java: brew install openjdk"
        return 1
    fi

    # Set SDK paths
    export ANDROID_SDK_ROOT
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

    # Check if SDK already exists and is complete
    if [ -d "$ANDROID_SDK_ROOT" ] && [ -f "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
        log "Android SDK found at $ANDROID_SDK_ROOT"
    else
        log "Android SDK not found. Installing Command Line Tools..."
        if ! install_android_sdk; then
            return 1
        fi
    fi

    # Install required SDK components (idempotent - sdkmanager skips already installed)
    if ! install_sdk_components; then
        return 1
    fi

    log "Android SDK setup complete"
    return 0
}

# Install Android SDK Command Line Tools (idempotent)
install_android_sdk() {
    # Check if already installed
    if [ -d "$ANDROID_SDK_ROOT/cmdline-tools/latest" ] && [ -f "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
        log "Android Command Line Tools already installed"
        return 0
    fi

    local sdk_url="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"
    local temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/cmdline-tools.zip"

    log "Downloading Android Command Line Tools..."
    if ! download_with_progress "$sdk_url" "$zip_file"; then
        error "Failed to download Android Command Line Tools"
        rm -rf "$temp_dir"
        return 1
    fi

    log "Extracting Android Command Line Tools..."
    ensure_dir "$ANDROID_SDK_ROOT/cmdline-tools"

    if ! unzip -q "$zip_file" -d "$temp_dir"; then
        error "Failed to extract Android Command Line Tools"
        rm -rf "$temp_dir"
        return 1
    fi

    # Move to correct location
    if [ -d "$temp_dir/cmdline-tools" ]; then
        if [ -d "$ANDROID_SDK_ROOT/cmdline-tools/latest" ]; then
            log "Removing existing installation..."
            rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        fi
        mv "$temp_dir/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest" || {
            error "Failed to move Command Line Tools"
            rm -rf "$temp_dir"
            return 1
        }
    else
        error "Command Line Tools directory not found in archive"
        rm -rf "$temp_dir"
        return 1
    fi

    rm -rf "$temp_dir"
    log "Android Command Line Tools installed"
    return 0
}

# Install required SDK components (idempotent)
install_sdk_components() {
    log "Installing required SDK components..."
    local sdkmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

    if [ ! -f "$sdkmanager" ]; then
        error "sdkmanager not found at $sdkmanager"
        return 1
    fi

    # Accept licenses (idempotent - only prompts if needed)
    log "Accepting Android SDK licenses..."
    yes | "$sdkmanager" --licenses >/dev/null 2>&1 || {
        warn "Some licenses may need manual acceptance"
    }

    # Detect architecture for system image
    local arch="x86_64"
    if [ "$(uname -m)" = "arm64" ]; then
        arch="arm64-v8a"
        log "Detected Apple Silicon (arm64), using arm64-v8a system image"
    fi

    # Components to install (sdkmanager is idempotent - skips already installed)
    local components=(
        "platform-tools"
        "platforms;android-33"
        "build-tools;33.0.0"
        "emulator"
        "system-images;android-33;google_apis;${arch}"
    )

    # Export architecture for AVD creation
    export ANDROID_SYSTEM_IMAGE_ARCH="$arch"

    log "Installing SDK components (this may take a while on first run)..."
    if ! "$sdkmanager" "${components[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        error "Failed to install SDK components"
        return 1
    fi

    log "SDK components installation complete"
    return 0
}

# Verify Android SDK is properly set up
verify_android_sdk() {
    if [ ! -d "$ANDROID_SDK_ROOT" ]; then
        error "Android SDK directory not found: $ANDROID_SDK_ROOT"
        return 1
    fi

    local sdkmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
    if [ ! -f "$sdkmanager" ]; then
        error "sdkmanager not found"
        return 1
    fi

    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"
    if [ ! -f "$adb" ]; then
        error "adb not found"
        return 1
    fi

    local emulator="$ANDROID_SDK_ROOT/emulator/emulator"
    if [ ! -f "$emulator" ]; then
        error "emulator not found"
        return 1
    fi

    return 0
}

