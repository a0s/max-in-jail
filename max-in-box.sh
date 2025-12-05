#!/bin/bash

# Max Messenger Android Setup Script for macOS
# This script automates the setup and launch of Max Messenger in an Android emulator

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Configuration
AVD_NAME="max_messenger_avd"
MAX_PACKAGE_NAME="${MAX_PACKAGE_NAME:-}"  # Will be detected or can be set via env var
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
APK_DIR="$SCRIPT_DIR/apk"
LOG_FILE="$SCRIPT_DIR/setup.log"

# Export configuration for modules
export AVD_NAME
export MAX_PACKAGE_NAME
export ANDROID_SDK_ROOT
export APK_DIR
export LOG_FILE

# Load utility functions
source "$LIB_DIR/utils.sh"

# Global state
EMULATOR_PID=""
SCRIPT_EXIT_CODE=0

# Cleanup function
cleanup() {
    local exit_code=$?

    # Only cleanup on error or interrupt, not on normal exit
    if [ $exit_code -ne 0 ] || [ -n "${FORCE_CLEANUP:-}" ]; then
        if [ -n "${EMULATOR_PID:-}" ] && kill -0 "$EMULATOR_PID" 2>/dev/null; then
            log "Stopping emulator (PID: $EMULATOR_PID)..."
            kill "$EMULATOR_PID" 2>/dev/null || true
            # Wait a bit for graceful shutdown
            sleep 2
            # Force kill if still running
            if kill -0 "$EMULATOR_PID" 2>/dev/null; then
                kill -9 "$EMULATOR_PID" 2>/dev/null || true
            fi
        fi
    fi

    exit ${SCRIPT_EXIT_CODE:-$exit_code}
}

trap cleanup EXIT INT TERM

# Main execution
main() {
    log "Starting Max Messenger setup..."
    log "Log file: $LOG_FILE"

    # Create necessary directories
    ensure_dir "$APK_DIR"

    # Load modules
    source "$LIB_DIR/dependencies.sh"
    source "$LIB_DIR/android_sdk.sh"
    source "$LIB_DIR/avd.sh"
    source "$LIB_DIR/apk.sh"
    source "$LIB_DIR/app.sh"

    # Run setup steps with error handling (all idempotent)
    # Step 1: Install dependencies
    if ! install_dependencies; then
        error "Failed to install dependencies"
        SCRIPT_EXIT_CODE=1
        return 1
    fi

    # Step 2: Setup Android SDK (needed for APK download verification, but minimal)
    if ! setup_android_sdk; then
        error "Failed to setup Android SDK"
        SCRIPT_EXIT_CODE=1
        return 1
    fi

    # Step 3: Download APK FIRST (before starting emulator to save resources)
    if ! download_max_apk; then
        error "Failed to download Max Messenger APK"
        error "Cannot proceed without APK file"
        SCRIPT_EXIT_CODE=1
        return 1
    fi

    # Step 4: Create and start AVD (only after APK is downloaded)
    if ! create_or_start_avd; then
        error "Failed to create or start AVD"
        SCRIPT_EXIT_CODE=1
        return 1
    fi

    # Step 5: Wait for emulator to be ready
    if ! wait_for_emulator; then
        error "Emulator failed to start properly"
        SCRIPT_EXIT_CODE=1
        return 1
    fi

    # Step 6: Install app (APK is already downloaded)
    if ! install_max_app; then
        error "Failed to install Max Messenger"
        SCRIPT_EXIT_CODE=1
        return 1
    fi

    # Step 7: Launch app
    if ! launch_max_app; then
        error "Failed to launch Max Messenger"
        SCRIPT_EXIT_CODE=1
        return 1
    fi

    log "Setup complete! Max Messenger should be running in the emulator."
    log "To stop the emulator, press Ctrl+C or close the emulator window."
    SCRIPT_EXIT_CODE=0
}

# Run main function
main "$@"
