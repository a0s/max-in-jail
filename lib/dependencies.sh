#!/bin/bash
# Dependency management - automatically installs missing dependencies

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Install all required dependencies
install_dependencies() {
    log "Checking and installing dependencies..."

    local all_installed=true

    # Check and install Homebrew if needed
    if ! brew_installed; then
        warn "Homebrew is not installed. Installing Homebrew..."
        if ! install_homebrew; then
            error "Failed to install Homebrew"
            return 1
        fi
    fi

    # Java (OpenJDK)
    # Check if Java works
    local java_works=false
    if command_exists java && java -version 2>&1 | grep -q "version"; then
        java_works=true
    elif [ -f "/opt/homebrew/opt/openjdk/bin/java" ] && /opt/homebrew/opt/openjdk/bin/java -version 2>&1 | grep -q "version"; then
        java_works=true
        export JAVA_HOME="/opt/homebrew/opt/openjdk"
        export PATH="$JAVA_HOME/bin:$PATH"
    elif [ -f "/usr/local/opt/openjdk/bin/java" ] && /usr/local/opt/openjdk/bin/java -version 2>&1 | grep -q "version"; then
        java_works=true
        export JAVA_HOME="/usr/local/opt/openjdk"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi

    if [ "$java_works" = false ]; then
        log "Java not found or not working, installing via Homebrew..."
        if ! brew_install_if_missing java "openjdk"; then
            all_installed=false
        else
            # Set JAVA_HOME after installation
            if [ -d "/opt/homebrew/opt/openjdk" ]; then
                export JAVA_HOME="/opt/homebrew/opt/openjdk"
                export PATH="$JAVA_HOME/bin:$PATH"
            elif [ -d "/usr/local/opt/openjdk" ]; then
                export JAVA_HOME="/usr/local/opt/openjdk"
                export PATH="$JAVA_HOME/bin:$PATH"
            fi
        fi
    else
        local java_version=$(java -version 2>&1 | head -1)
        log "Found: $java_version"
        # Set JAVA_HOME if not set
        if [ -z "${JAVA_HOME:-}" ]; then
            if [ -d "/opt/homebrew/opt/openjdk" ]; then
                export JAVA_HOME="/opt/homebrew/opt/openjdk"
                export PATH="$JAVA_HOME/bin:$PATH"
            elif [ -d "/usr/local/opt/openjdk" ]; then
                export JAVA_HOME="/usr/local/opt/openjdk"
                export PATH="$JAVA_HOME/bin:$PATH"
            fi
        fi
    fi

    # Python 3
    if ! command_exists python3; then
        log "Python 3 not found, installing via Homebrew..."
        if ! brew_install_if_missing python3; then
            all_installed=false
        fi
    else
        local python_version=$(python3 --version 2>&1)
        log "Found: $python_version"
    fi

    # curl (usually pre-installed on macOS)
    if ! command_exists curl; then
        warn "curl not found, installing via Homebrew..."
        if ! brew_install_if_missing curl; then
            all_installed=false
        fi
    fi

    # unzip (usually pre-installed on macOS)
    if ! command_exists unzip; then
        warn "unzip not found, installing via Homebrew..."
        if ! brew_install_if_missing unzip; then
            all_installed=false
        fi
    fi

    # jq (for JSON parsing in RuStore download)
    if ! command_exists jq; then
        log "jq not found, installing via Homebrew (needed for RuStore download)..."
        if ! brew_install_if_missing jq; then
            warn "jq installation failed, RuStore download will be skipped"
        fi
    fi

    # pv (pipe viewer - for beautiful progress bars)
    if ! command_exists pv; then
        log "pv not found, installing via Homebrew (for download progress bar)..."
        if ! brew_install_if_missing pv; then
            warn "pv installation failed, will use basic progress bar"
        fi
    fi

    if [ "$all_installed" = true ]; then
        log "All dependencies are installed"
        return 0
    else
        error "Some dependencies failed to install"
        return 1
    fi
}

# Install Homebrew
install_homebrew() {
    if brew_installed; then
        log "Homebrew is already installed"
        return 0
    fi

    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error "Failed to install Homebrew"
        return 1
    }

    # Add Homebrew to PATH for Apple Silicon Macs
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    log "Homebrew installed successfully"
    return 0
}

# Verify all dependencies are installed
verify_dependencies() {
    local missing=()

    if ! command_exists java; then
        missing+=("java")
    fi

    if ! command_exists python3; then
        missing+=("python3")
    fi

    if ! command_exists curl; then
        missing+=("curl")
    fi

    if ! command_exists unzip; then
        missing+=("unzip")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing dependencies: ${missing[*]}"
        return 1
    fi

    return 0
}

