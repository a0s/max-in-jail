#!/bin/bash

# Cleanup script for Max Messenger Android Setup
# Removes all files and installations created by max-in-box.sh

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Configuration (same as main script)
AVD_NAME="max_messenger_avd"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
APK_DIR="$SCRIPT_DIR/apk"
LOG_FILE="$SCRIPT_DIR/setup.log"

# Load utility functions
source "$LIB_DIR/utils.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Confirmation prompt
confirm_cleanup() {
    echo -e "${YELLOW}ВНИМАНИЕ: Этот скрипт удалит:${NC}"
    echo "  - Android SDK (если был установлен скриптом)"
    echo "  - Android Virtual Device (AVD): $AVD_NAME"
    echo "  - Скачанные APK файлы в: $APK_DIR"
    echo "  - Лог файлы"
    echo ""
    echo -e "${RED}Это действие нельзя отменить!${NC}"
    echo ""
    read -p "Продолжить? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Отменено."
        exit 0
    fi
}

# Stop emulator if running
stop_emulator() {
    log "Checking for running emulator..."

    export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

    # Find and kill emulator processes
    local emulator_pids
    emulator_pids=$(pgrep -f "emulator.*$AVD_NAME" 2>/dev/null || true)

    if [ -n "$emulator_pids" ]; then
        log "Stopping emulator processes..."
        echo "$emulator_pids" | while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                log "Stopping emulator (PID: $pid)..."
                kill "$pid" 2>/dev/null || true
                sleep 2
                # Force kill if still running
                if kill -0 "$pid" 2>/dev/null; then
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi
        done
        log "Emulator stopped"
    else
        log "No running emulator found"
    fi
}

# Remove AVD
remove_avd() {
    log "Removing Android Virtual Device..."

    export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
    local avdmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"

    if [ -f "$avdmanager" ]; then
        # Check if AVD exists
        if "$avdmanager" list avd 2>/dev/null | grep -q "$AVD_NAME"; then
            log "Deleting AVD: $AVD_NAME"
            if "$avdmanager" delete avd -n "$AVD_NAME" 2>/dev/null; then
                log "AVD deleted successfully"
            else
                warn "Failed to delete AVD via avdmanager, trying manual removal..."
                # Manual removal
                local avd_dir="$HOME/.android/avd/${AVD_NAME}.avd"
                local avd_config="$HOME/.android/avd/${AVD_NAME}.ini"
                if [ -d "$avd_dir" ]; then
                    rm -rf "$avd_dir"
                    log "Removed AVD directory: $avd_dir"
                fi
                if [ -f "$avd_config" ]; then
                    rm -f "$avd_config"
                    log "Removed AVD config: $avd_config"
                fi
            fi
        else
            log "AVD '$AVD_NAME' not found"
        fi
    else
        warn "avdmanager not found, trying manual AVD removal..."
        local avd_dir="$HOME/.android/avd/${AVD_NAME}.avd"
        local avd_config="$HOME/.android/avd/${AVD_NAME}.ini"
        if [ -d "$avd_dir" ] || [ -f "$avd_config" ]; then
            rm -rf "$avd_dir" "$avd_config" 2>/dev/null || true
            log "Removed AVD files manually"
        fi
    fi
}

# Remove Android SDK (optional - only if installed by script)
remove_android_sdk() {
    log "Checking Android SDK..."

    if [ -d "$ANDROID_SDK_ROOT" ]; then
        echo -e "${YELLOW}Android SDK найден в: $ANDROID_SDK_ROOT${NC}"
        echo -e "${YELLOW}ВНИМАНИЕ: Удаление SDK может затронуть другие проекты!${NC}"
        read -p "Удалить Android SDK? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Removing Android SDK..."
            rm -rf "$ANDROID_SDK_ROOT"
            log "Android SDK removed"
        else
            log "Skipping Android SDK removal"
        fi
    else
        log "Android SDK not found at $ANDROID_SDK_ROOT"
    fi
}

# Remove APK files
remove_apk_files() {
    log "Removing APK files..."

    if [ -d "$APK_DIR" ]; then
        local apk_count
        apk_count=$(find "$APK_DIR" -name "*.apk" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ "$apk_count" -gt 0 ]; then
            log "Found $apk_count APK file(s)"
            rm -f "$APK_DIR"/*.apk
            log "APK files removed"
        else
            log "No APK files found"
        fi
    else
        log "APK directory not found"
    fi
}

# Remove log files
remove_logs() {
    log "Removing log files..."

    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        log "Log file removed: $LOG_FILE"
    else
        log "Log file not found"
    fi
}

# Remove empty directories
remove_empty_dirs() {
    log "Cleaning up empty directories..."

    # Remove APK directory if empty
    if [ -d "$APK_DIR" ] && [ -z "$(ls -A "$APK_DIR" 2>/dev/null)" ]; then
        rmdir "$APK_DIR" 2>/dev/null && log "Removed empty APK directory" || true
    fi

    # Remove .android/avd if empty
    local avd_base_dir="$HOME/.android/avd"
    if [ -d "$avd_base_dir" ] && [ -z "$(ls -A "$avd_base_dir" 2>/dev/null)" ]; then
        rmdir "$avd_base_dir" 2>/dev/null || true
        # Also remove .android if empty
        if [ -d "$HOME/.android" ] && [ -z "$(ls -A "$HOME/.android" 2>/dev/null)" ]; then
            rmdir "$HOME/.android" 2>/dev/null || true
        fi
    fi
}

# Main cleanup function
main() {
    echo -e "${GREEN}=== Max Messenger Setup Cleanup ===${NC}"
    echo ""

    confirm_cleanup

    echo ""
    log "Starting cleanup..."

    stop_emulator
    remove_avd
    remove_apk_files
    remove_logs
    remove_empty_dirs

    # Ask about SDK removal last
    echo ""
    remove_android_sdk

    echo ""
    log "Cleanup complete!"
    echo -e "${GREEN}Все файлы, созданные скриптом, были удалены.${NC}"
    echo ""
    echo "Примечание: Установленные зависимости (Java, Python, jq) не были удалены,"
    echo "так как они могут использоваться другими приложениями."
    echo "Если хотите удалить их вручную:"
    echo "  brew uninstall openjdk python3 jq"
}

# Run main function
main "$@"

