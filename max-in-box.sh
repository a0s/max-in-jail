#!/bin/bash

# Max Messenger Android Setup Script for macOS
# This script automates the setup and launch of Max Messenger in an Android emulator
#
# Usage:
#   ./max-in-box.sh              # Run in foreground mode (follow logs, Ctrl+C stops emulator)
#   ./max-in-box.sh --detach     # Run in background mode (script exits, emulator keeps running)
#   ./max-in-box.sh --uninstall  # Remove all data created by script

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Configuration
AVD_NAME="max_messenger_avd"
MAX_PACKAGE_NAME="${MAX_PACKAGE_NAME:-}"  # Will be detected or can be set via env var

# Use cache directory for all user data (can be easily removed by deleting ~/.cache/max-in-box)
CACHE_DIR="${HOME}/.cache/max-in-box"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${CACHE_DIR}/android-sdk}"
APK_DIR="${CACHE_DIR}/apk"
LOG_FILE="${CACHE_DIR}/logs/setup.log"
AVD_HOME="${CACHE_DIR}/avd"

# Export configuration for modules
export AVD_NAME
export MAX_PACKAGE_NAME
export ANDROID_SDK_ROOT
export APK_DIR
export LOG_FILE
export ANDROID_AVD_HOME="$AVD_HOME"
export CACHE_DIR

# Load utility functions
source "$LIB_DIR/utils.sh"

# Global state
EMULATOR_PID=""
SCRIPT_EXIT_CODE=0
DETACH_MODE=false
UNINSTALL_MODE=false

# Cleanup function
cleanup() {
    local exit_code=$?

    # Only cleanup on error or interrupt, not on normal exit or detach mode
    if [ "$DETACH_MODE" = true ]; then
        exit ${SCRIPT_EXIT_CODE:-$exit_code}
    fi

    if [ $exit_code -ne 0 ] || [ -n "${FORCE_CLEANUP:-}" ]; then
        # Find and stop emulator (might be running from previous session)
        export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
        local emulator_pids
        emulator_pids=$(pgrep -f "emulator.*$AVD_NAME" 2>/dev/null || true)

        if [ -n "$emulator_pids" ]; then
            log "Stopping emulator..."
            echo "$emulator_pids" | while read -r pid; do
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null || true
                    sleep 2
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -9 "$pid" 2>/dev/null || true
                    fi
                fi
            done
        elif [ -n "${EMULATOR_PID:-}" ] && kill -0 "$EMULATOR_PID" 2>/dev/null; then
            log "Stopping emulator (PID: $EMULATOR_PID)..."
            kill "$EMULATOR_PID" 2>/dev/null || true
            sleep 2
            if kill -0 "$EMULATOR_PID" 2>/dev/null; then
                kill -9 "$EMULATOR_PID" 2>/dev/null || true
            fi
        fi
    fi

    exit ${SCRIPT_EXIT_CODE:-$exit_code}
}

trap cleanup EXIT INT TERM

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --detach)
                DETACH_MODE=true
                shift
                ;;
            --uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --detach     Run in background mode (script exits, emulator keeps running)"
                echo "  --uninstall  Remove all data created by script"
                echo "  -h, --help   Show this help message"
                echo ""
                echo "By default, script runs in foreground mode:"
                echo "  - Follows emulator logs"
                echo "  - Press Ctrl+C to stop emulator and exit"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                error "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Check if new APK version is available
check_apk_version() {
    log "Checking for new APK version in RuStore..."

    if ! command_exists jq; then
        warn "jq not found, skipping version check"
        return 0
    fi

    local rustore_package="ru.oneme.app"
    local info_url="https://backapi.rustore.ru/applicationData/overallInfo/${rustore_package}"

    local info_json
    info_json=$(curl -fsSL "$info_url" 2>/dev/null) || {
        warn "Failed to check version from RuStore"
        return 0
    }

    local code
    code=$(echo "$info_json" | jq -r '.code // empty')
    if [ "$code" != "OK" ]; then
        warn "RuStore returned unexpected code: ${code:-<none>}"
        return 0
    fi

    local store_version_name store_version_code
    store_version_name=$(echo "$info_json" | jq -r '.body.versionName // empty')
    store_version_code=$(echo "$info_json" | jq -r '.body.versionCode // empty')

    if [ -z "$store_version_name" ] || [ -z "$store_version_code" ]; then
        warn "Failed to extract version from RuStore"
        return 0
    fi

    log "Latest version in RuStore: ${store_version_name} (code=${store_version_code})"

    # Check if we have local APK and compare versions
    local apk_file="$APK_DIR/max-messenger.apk"
    if [ -f "$apk_file" ]; then
        # Try to extract version from local APK
        local local_version_code=""
        if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT/build-tools" ]; then
            local aapt2_tool=""
            for build_tool_dir in "$ANDROID_SDK_ROOT/build-tools"/*/; do
                if [ -f "${build_tool_dir}aapt2" ]; then
                    aapt2_tool="${build_tool_dir}aapt2"
                    break
                fi
            done

            if [ -n "$aapt2_tool" ] && [ -f "$aapt2_tool" ]; then
                local badging_output
                badging_output=$("$aapt2_tool" dump badging "$apk_file" 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$badging_output" ]; then
                    local_version_code=$(echo "$badging_output" | grep "^package:" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" | head -1)
                fi
            fi
        fi

        if [ -n "$local_version_code" ] && [ "$local_version_code" = "$store_version_code" ]; then
            log "Local APK is up to date (version code: $local_version_code)"
            return 0
        else
            if [ -n "$local_version_code" ]; then
                log "New version available! Local: $local_version_code, Store: $store_version_code"
            else
                log "New version available! Store: ${store_version_name} (${store_version_code})"
            fi
            log "Will download new version..."
            return 1
        fi
    else
        log "No local APK found, will download latest version"
        return 1
    fi
}

# Uninstall function (from cleanup.sh)
uninstall_all() {
    log "=== Max Messenger Setup Uninstall ==="
    echo ""

    echo -e "${YELLOW}WARNING: This will delete:${NC}"
    echo "  - All data in cache directory: $CACHE_DIR"
    echo "    * Android Virtual Device (AVD): $AVD_NAME"
    echo "    * Downloaded APK files"
    echo "    * Log files"
    echo "  - Android SDK"
    echo ""
    echo -e "${GREEN}Easy way to remove everything: rm -rf ~/.cache/max-in-box${NC}"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    echo ""
    log "Starting cleanup..."

    # Stop emulator
    export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
    local emulator_pids
    emulator_pids=$(pgrep -f "emulator.*$AVD_NAME" 2>/dev/null || true)

    if [ -n "$emulator_pids" ]; then
        log "Stopping emulator processes..."
        echo "$emulator_pids" | while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                log "Stopping emulator (PID: $pid)..."
                kill "$pid" 2>/dev/null || true
                sleep 2
                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi
        done
        log "Emulator stopped"
    fi

    # Remove cache directory (includes everything)
    if [ -d "$CACHE_DIR" ]; then
        log "Removing cache directory: $CACHE_DIR"
        rm -rf "$CACHE_DIR"
        log "Cache directory removed successfully"
    else
        log "Cache directory not found: $CACHE_DIR"
    fi

    # Clean up old .android/avd if empty
    local avd_base_dir="$HOME/.android/avd"
    if [ -d "$avd_base_dir" ] && [ -z "$(ls -A "$avd_base_dir" 2>/dev/null)" ]; then
        rmdir "$avd_base_dir" 2>/dev/null || true
        if [ -d "$HOME/.android" ] && [ -z "$(ls -A "$HOME/.android" 2>/dev/null)" ]; then
            rmdir "$HOME/.android" 2>/dev/null || true
        fi
    fi

    echo ""
    log "Uninstall complete!"
    echo -e "${GREEN}All files created by the script have been removed.${NC}"
    echo ""
    echo "Note: Installed dependencies (Java, Python, jq, pv) were not removed,"
    echo "as they may be used by other applications."
    echo "To remove them manually:"
    echo "  brew uninstall openjdk python3 jq pv"
    exit 0
}

# Follow emulator logs
follow_emulator_logs() {
    export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    local adb="$ANDROID_SDK_ROOT/platform-tools/adb"

    if [ ! -f "$adb" ]; then
        return 1
    fi

    log "Following emulator logs (Press Ctrl+C to stop emulator)..."
    echo ""

    # Follow logcat
    "$adb" logcat -c >/dev/null 2>&1  # Clear log
    "$adb" logcat
}

# Main execution
main() {
    # Parse command line arguments
    parse_args "$@"

    # Handle uninstall mode
    if [ "$UNINSTALL_MODE" = true ]; then
        # Load utilities for uninstall
        source "$LIB_DIR/utils.sh"
        uninstall_all
    fi

    # Create necessary directories FIRST (before any logging to file)
    ensure_dir "$CACHE_DIR"
    ensure_dir "$ANDROID_SDK_ROOT"
    ensure_dir "$APK_DIR"
    ensure_dir "$(dirname "$LOG_FILE")"
    ensure_dir "$AVD_HOME"

    log "Starting Max Messenger setup..."
    log "Cache directory: $CACHE_DIR"
    log "Log file: $LOG_FILE"

    # Step 0: Check and install Homebrew if needed (required for all other dependencies)
    # Load utils first to get brew_installed function
    source "$LIB_DIR/utils.sh"

    if ! brew_installed; then
        log "Homebrew not found. Installing Homebrew (this may take a few minutes)..."
        # Load dependencies module to get install_homebrew function
        source "$LIB_DIR/dependencies.sh"
        if ! install_homebrew; then
            error "Failed to install Homebrew. Cannot proceed without it."
            error "Please install Homebrew manually: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            SCRIPT_EXIT_CODE=1
            return 1
        fi
    else
        log "Homebrew is installed"
    fi

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

    # Step 3: Check for new APK version and download if needed
    if ! check_apk_version; then
        log "Downloading new APK version..."
    fi

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

    # Handle detach mode vs foreground mode
    if [ "$DETACH_MODE" = true ]; then
        log "Running in detach mode - script will exit, emulator will keep running."
        log "To stop emulator later, use: adb emu kill"
        SCRIPT_EXIT_CODE=0
        FORCE_CLEANUP=""  # Don't cleanup on exit in detach mode
        return 0
    else
        log "Running in foreground mode - following emulator logs."
        log "Press Ctrl+C to stop emulator and exit."
        echo ""

        # Follow logs until interrupted
        trap 'FORCE_CLEANUP=1; cleanup' INT TERM
        follow_emulator_logs
    fi

    SCRIPT_EXIT_CODE=0
}

# Run main function
main "$@"
