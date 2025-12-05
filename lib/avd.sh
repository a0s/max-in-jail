#!/bin/bash
# Android Virtual Device (AVD) management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Create or start AVD (idempotent)
create_or_start_avd() {
    log "Managing Android Virtual Device..."

    export ANDROID_SDK_ROOT
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

    local avdmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
    local emulator="$ANDROID_SDK_ROOT/emulator/emulator"

    # Verify tools exist
    if [ ! -f "$avdmanager" ]; then
        error "avdmanager not found"
        return 1
    fi

    if [ ! -f "$emulator" ]; then
        error "emulator not found"
        return 1
    fi

    # Check if AVD already exists (idempotent)
    if "$avdmanager" list avd 2>/dev/null | grep -q "$AVD_NAME"; then
        log "AVD '$AVD_NAME' already exists"
        # Check if AVD is compatible with current architecture
        local current_arch="x86_64"
        if [ "$(uname -m)" = "arm64" ]; then
            current_arch="arm64-v8a"
        fi
        local avd_config="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"
        if [ -f "$avd_config" ] && grep -q "x86_64" "$avd_config" && [ "$current_arch" = "arm64-v8a" ]; then
            warn "Existing AVD uses x86_64 architecture but host is arm64"
            warn "Deleting incompatible AVD and creating new one..."
            "$avdmanager" delete avd -n "$AVD_NAME" 2>/dev/null || true
            if ! create_avd; then
                return 1
            fi
        fi
    else
        log "Creating new AVD '$AVD_NAME'..."
        if ! create_avd; then
            return 1
        fi
    fi

    # Start emulator if not already running (idempotent)
    if ! start_emulator; then
        return 1
    fi

    return 0
}

# Create AVD
create_avd() {
    local avdmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"

    # Detect architecture for system image
    local arch="${ANDROID_SYSTEM_IMAGE_ARCH:-x86_64}"
    if [ -z "${ANDROID_SYSTEM_IMAGE_ARCH:-}" ]; then
        if [ "$(uname -m)" = "arm64" ]; then
            arch="arm64-v8a"
        fi
    fi

    log "Creating AVD with architecture: $arch"

    # Create AVD with Google APIs (includes Google Play)
    if ! "$avdmanager" create avd \
        --name "$AVD_NAME" \
        --package "system-images;android-33;google_apis;${arch}" \
        --device "pixel_5" \
        --force; then
        error "Failed to create AVD"
        error "Make sure system image is installed: system-images;android-33;google_apis;${arch}"
        return 1
    fi

    log "AVD created successfully"
    return 0
}

# Start emulator (idempotent - checks if already running)
start_emulator() {
    local emulator="$ANDROID_SDK_ROOT/emulator/emulator"

    # Check if emulator is already running
    if pgrep -f "emulator.*$AVD_NAME" >/dev/null; then
        log "Emulator is already running"
        # Get the PID of running emulator
        EMULATOR_PID=$(pgrep -f "emulator.*$AVD_NAME" | head -1)
        log "Using existing emulator with PID $EMULATOR_PID"
        return 0
    fi

    log "Starting emulator..."
    # Start emulator in background
    "$emulator" -avd "$AVD_NAME" -no-snapshot-save >/dev/null 2>&1 &
    EMULATOR_PID=$!
    sleep 2

    # Verify emulator started
    if ! kill -0 "$EMULATOR_PID" 2>/dev/null; then
        error "Failed to start emulator"
        return 1
    fi

    log "Emulator started with PID $EMULATOR_PID"
    return 0
}

# Wait for emulator to be ready (idempotent - can be called multiple times)
wait_for_emulator() {
    log "Waiting for emulator to be ready..."

    export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"

    if [ ! -f "$adb" ]; then
        error "adb not found"
        return 1
    fi

    # Wait for device to be connected
    log "Waiting for ADB connection..."
    if ! "$adb" wait-for-device; then
        error "Failed to connect to emulator via ADB"
        return 1
    fi

    # Wait for boot to complete
    log "Waiting for Android to boot..."
    local boot_completed=false
    local max_wait=300  # 5 minutes max
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if "$adb" shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
            boot_completed=true
            break
        fi
        sleep 2
        waited=$((waited + 2))
        if [ $((waited % 10)) -eq 0 ]; then
            log "Still waiting for boot... (${waited}s)"
        fi
    done

    if [ "$boot_completed" = false ]; then
        error "Emulator failed to boot within timeout"
        return 1
    fi

    # Additional wait for system to be fully ready
    sleep 5
    log "Emulator is ready"
    return 0
}

# Check if emulator is running
is_emulator_running() {
    pgrep -f "emulator.*$AVD_NAME" >/dev/null
}

