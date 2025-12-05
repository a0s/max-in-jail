#!/bin/bash
# Utility functions for logging and common operations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE:-/dev/stdout}"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE:-/dev/stderr}" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "${LOG_FILE:-/dev/stdout}"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE:-/dev/stdout}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Homebrew is installed
brew_installed() {
    command_exists brew
}

# Install package via Homebrew if not installed
brew_install_if_missing() {
    local package=$1
    local formula=${2:-$package}

    # Special check for java - it might exist but not work
    if [ "$package" = "java" ]; then
        if command_exists java && java -version 2>&1 | grep -q "version"; then
            log "$package is already installed and working"
            return 0
        fi
    elif command_exists "$package"; then
        log "$package is already installed"
        return 0
    fi

    if ! brew_installed; then
        error "Homebrew is not installed. Please install it first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 1
    fi

    log "Installing $formula via Homebrew..."
    if brew install "$formula"; then
        log "$formula installed successfully"

        # Special handling for openjdk
        if [ "$formula" = "openjdk" ]; then
            # Link openjdk
            if [ -d "/opt/homebrew/opt/openjdk" ]; then
                sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk 2>/dev/null || true
                export JAVA_HOME="/opt/homebrew/opt/openjdk"
                export PATH="$JAVA_HOME/bin:$PATH"
            elif [ -d "/usr/local/opt/openjdk" ]; then
                sudo ln -sfn /usr/local/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk 2>/dev/null || true
                export JAVA_HOME="/usr/local/opt/openjdk"
                export PATH="$JAVA_HOME/bin:$PATH"
            fi
        fi

        return 0
    else
        error "Failed to install $formula"
        return 1
    fi
}

# Ensure directory exists
ensure_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log "Created directory: $dir"
    fi
}

# Check if file exists and is readable
file_exists() {
    [ -f "$1" ] && [ -r "$1" ]
}

# Check if directory exists and is writable
dir_exists() {
    [ -d "$1" ] && [ -w "$1" ]
}

