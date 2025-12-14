#!/bin/bash
# =============================================================================
# Ubuntu Server Setup Script
# =============================================================================
# Description: Automated setup for a fresh Ubuntu server with Docker, k3s,
#              SSH Guard, Fail2Ban, UFW firewall, and SSH hardening.
#              Features custom port obfuscation for security.
# Author: Jonas
# Version: 1.0
# Date: 2025-12-14
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

# Function to check command success and log errors
run_cmd() {
    local cmd="$1"
    local description="${2:-}"

    if [[ -n "$description" ]]; then
        log "Running: $description"
    else
        log "Running: $cmd"
    fi

    if ! eval "$cmd"; then
        log "ERROR: Command failed: $cmd"
        return 1
    fi

    log "SUCCESS: Command completed: ${description:-$cmd}"
}

# Function to validate system state
validate_system_state() {
    local check_type="$1"

    case "$check_type" in
        "pre_install")
            log "Validating system state before installation"

            # Check disk space (need at least 5GB free)
            local free_space
            free_space=$(df / | tail -1 | awk '{print $4}')
            if [[ $free_space -lt 5242880 ]]; then  # 5GB in KB
                print_error "Insufficient disk space. Need at least 5GB free."
                return 1
            fi

            # Check memory (need at least 1GB)
            local total_mem
            total_mem=$(free -m | grep '^Mem:' | awk '{print $2}')
            if [[ $total_mem -lt 1024 ]]; then
                print_error "Insufficient memory. Need at least 1GB RAM."
                return 1
            fi

            # Check if required ports are available
            for port in "${PORT_MAP[@]}"; do
                if ss -tuln | grep -q ":${port} "; then
                    print_error "Port $port is already in use"
                    return 1
                fi
            done
            ;;

        "post_install")
            log "Validating system state after installation"

            # Check if critical services are running
            local critical_services=("sshd" "docker" "k3s" "ufw")
            for service in "${critical_services[@]}"; do
                if ! systemctl is-active --quiet "$service" 2>/dev/null; then
                    print_warning "Service $service is not running"
                fi
            done

            # Verify SSH is accessible on new port
            local ssh_port="${PORT_MAP[ssh]}"
            if ! ss -tuln | grep -q ":${ssh_port} "; then
                print_error "SSH is not listening on port $ssh_port"
                return 1
            fi
            ;;

        *)
            print_error "Unknown validation type: $check_type"
            return 1
            ;;
    esac

    log "System validation passed: $check_type"
    return 0
}

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/ubuntu-server-setup.log"
readonly PORT_CONFIG_FILE="/etc/server-ports.conf"
readonly REPORT_DIR="/root"
readonly ERROR_FILE="$SCRIPT_DIR/.ubuntu-server-setup.error"
readonly DEBUG_FILE="$SCRIPT_DIR/.ubuntu-server-setup.debug"

# Default ports (can be overridden by user)
DEFAULT_SSH_PORT=22
DEFAULT_K3S_API_PORT=6443

# =============================================================================
# COLOR DEFINITIONS
# =============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================
declare -A PORT_MAP
DRY_RUN=false
AUTO_YES=false
REPORT_ONLY=false
VERBOSE=false
SSH_PUBLIC_KEY=""

# Wizard configuration variables
CERTBOT_EMAIL=""
CERTBOT_DOMAIN=""
CERTBOT_SETUP=false

# =============================================================================
# ERROR HANDLING & LOGGING
# =============================================================================

# Error handling function
error_exit() {
    local error_code=$?
    local error_line=${BASH_LINENO[0]}
    local error_command="${BASH_COMMAND}"
    local error_function="${FUNCNAME[1]}"

    # Create error file with detailed information
    {
        echo "==============================================================================="
        echo "UBUNTU SERVER SETUP ERROR REPORT"
        echo "==============================================================================="
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"
        echo ""
        echo "ERROR DETAILS:"
        echo "Exit Code: $error_code"
        echo "Line Number: $error_line"
        echo "Function: ${error_function:-main}"
        echo "Command: $error_command"
        echo ""
        echo "SYSTEM INFORMATION:"
        echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || uname -s)"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
        echo "Disk Usage: $(df -h / | tail -1 | awk '{print $5}')"
        echo ""
        echo "RECENT LOG ENTRIES:"
        if [[ -f "$LOG_FILE" ]]; then
            tail -20 "$LOG_FILE" 2>/dev/null || echo "No log file available"
        else
            echo "No log file available"
        fi
        echo ""
        echo "RUNNING PROCESSES:"
        ps aux | head -20
        echo ""
        echo "NETWORK INTERFACES:"
        ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "Network info unavailable"
        echo ""
        echo "INSTALLED PACKAGES (last 10):"
        dpkg -l 2>/dev/null | tail -10 || rpm -qa 2>/dev/null | tail -10 || echo "Package list unavailable"
        echo ""
        echo "==============================================================================="
        echo "END OF ERROR REPORT"
        echo "==============================================================================="
    } > "$ERROR_FILE"

    # Also create a debug file with full environment
    {
        echo "Environment Variables:"
        env | sort
        echo ""
        echo "Shell Options:"
        set -o
        echo ""
        echo "Loaded Functions:"
        declare -F
        echo ""
        echo "Global Variables:"
        declare -p 2>/dev/null | grep -v "declare -[^ ]* PASSWORD" || echo "No global variables"
    } > "$DEBUG_FILE"

    print_error "Script failed with exit code $error_code"
    print_error "Error details saved to: $ERROR_FILE"
    print_error "Debug information saved to: $DEBUG_FILE"
    print_error "Please check these files for troubleshooting information"

    # Clean up any partial installations if needed
    cleanup_on_error

    exit $error_code
}

# Cleanup function for partial failures
cleanup_on_error() {
    print_warning "Performing cleanup due to error..."

    # Stop any services that might be in inconsistent state
    systemctl stop docker k3s sshguard fail2ban 2>/dev/null || true

    # Remove incomplete installations
    if [[ -f "/usr/local/bin/k3s" ]] && ! systemctl is-active --quiet k3s 2>/dev/null; then
        print_warning "Removing incomplete k3s installation..."
        /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
    fi

    # Reset firewall to default if it's in a bad state
    if command_exists ufw && ! ufw status | grep -q "Status: active"; then
        print_warning "Resetting firewall to defaults..."
        ufw --force reset 2>/dev/null || true
    fi

    print_info "Cleanup completed"
}

# Set up error traps
trap error_exit ERR
trap 'print_warning "Script interrupted by user"; cleanup_on_error; exit 130' INT TERM

# Enhanced logging function
log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to file
    echo "[$timestamp] $message" >> "$LOG_FILE"

    # Also log to console if verbose
    if [[ "$VERBOSE" == true ]]; then
        echo "[$timestamp] $message"
    fi
}

# Function to check command success and log errors
run_cmd() {
    local cmd="$1"
    local description="${2:-}"

    if [[ -n "$description" ]]; then
        log "Running: $description"
    else
        log "Running: $cmd"
    fi

    if ! eval "$cmd"; then
        log "ERROR: Command failed: $cmd"
        return 1
    fi

    log "SUCCESS: Command completed: ${description:-$cmd}"
}

# Function to validate system state
validate_system_state() {
    local check_type="$1"

    case "$check_type" in
        "pre_install")
            log "Validating system state before installation"

            # Check disk space (need at least 5GB free)
            local free_space
            free_space=$(df / | tail -1 | awk '{print $4}')
            if [[ $free_space -lt 5242880 ]]; then  # 5GB in KB
                print_error "Insufficient disk space. Need at least 5GB free."
                return 1
            fi

            # Check memory (need at least 1GB)
            local total_mem
            total_mem=$(free -m | grep '^Mem:' | awk '{print $2}')
            if [[ $total_mem -lt 1024 ]]; then
                print_error "Insufficient memory. Need at least 1GB RAM."
                return 1
            fi

            # Check if required ports are available
            for port in "${PORT_MAP[@]}"; do
                if ss -tuln | grep -q ":${port} "; then
                    print_error "Port $port is already in use"
                    return 1
                fi
            done
            ;;

        "post_install")
            log "Validating system state after installation"

            # Check if critical services are running
            local critical_services=("sshd" "docker" "k3s" "ufw")
            for service in "${critical_services[@]}"; do
                if ! systemctl is-active --quiet "$service" 2>/dev/null; then
                    print_warning "Service $service is not running"
                fi
            done

            # Verify SSH is accessible on new port
            local ssh_port="${PORT_MAP[ssh]}"
            if ! ss -tuln | grep -q ":${ssh_port} "; then
                print_error "SSH is not listening on port $ssh_port"
                return 1
            fi
            ;;

        *)
            print_error "Unknown validation type: $check_type"
            return 1
            ;;
    esac

    log "System validation passed: $check_type"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

print_error() {
    print_color "$RED" "✗ ERROR: $1" >&2
}

print_success() {
    print_color "$GREEN" "✓ $1"
}

print_warning() {
    print_color "$YELLOW" "⚠ WARNING: $1"
}

print_info() {
    print_color "$BLUE" "ℹ $1"
}

print_step() {
    print_color "$CYAN" "▶ $1"
}

print_header() {
    local title="$1"
    echo ""
    print_color "$MAGENTA" "═══════════════════════════════════════════════════════════════"
    print_color "$MAGENTA" "  $title"
    print_color "$MAGENTA" "═══════════════════════════════════════════════════════════════"
    echo ""
}

log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | sudo tee -a "$LOG_FILE" > /dev/null
    if [[ "$VERBOSE" == true ]]; then
        print_info "[LOG] $message"
    fi
}

show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

show_help() {
    cat << EOF
${BOLD}$SCRIPT_NAME${NC} - Ubuntu Server Setup Script v$SCRIPT_VERSION

${BOLD}DESCRIPTION:${NC}
    Automated setup for a fresh Ubuntu server with Docker, k3s, SSH Guard,
    Fail2Ban, UFW firewall configuration, and SSH hardening.
    Features custom port obfuscation for enhanced security.

${BOLD}USAGE:${NC}
    $SCRIPT_NAME [OPTIONS]

${BOLD}OPTIONS:${NC}
    -h, --help          Show this help message and exit
    -v, --version       Show version information and exit
    -y, --yes           Auto-confirm all prompts (use default values)
    -n, --dry-run       Show what would be done without making changes
    -r, --report-only   Generate report without installing anything
    --verbose           Enable verbose output
    --ssh-key <key>     SSH public key to add for authentication

${BOLD}EXAMPLES:${NC}
    # Interactive setup
    sudo $SCRIPT_NAME

    # Non-interactive setup with defaults
    sudo $SCRIPT_NAME --yes

    # Dry run to see what would be installed
    sudo $SCRIPT_NAME --dry-run

    # Generate report only
    sudo $SCRIPT_NAME --report-only

    # Setup with SSH key
    sudo $SCRIPT_NAME --ssh-key "ssh-rsa AAAA... user@host"

${BOLD}SERVICES INSTALLED:${NC}
    • Docker CE (Container runtime)
    • k3s (Lightweight Kubernetes with security hardening)
    • SSHGuard (Brute-force protection)
    • Fail2Ban (Intrusion prevention system)
    • Certbot (SSL certificates)
    • UFW (Uncomplicated Firewall)
    • Unattended Upgrades (Automatic security updates)

${BOLD}SECURITY FEATURES:${NC}
    • Custom port obfuscation for all services
    • SSH hardening (key-only auth, no root login)
    • UFW firewall with minimal open ports
    • SSHGuard brute-force protection

${BOLD}NOTES:${NC}
    • Must be run as root (sudo)
    • Requires a fresh Ubuntu 20.04+ installation
    • Creates a detailed report at $REPORT_DIR/server-setup-*.report

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This script is designed for Ubuntu. Detected: $ID"
        exit 1
    fi
    
    print_success "Detected Ubuntu $VERSION_ID ($VERSION_CODENAME)"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    
    if [[ "$AUTO_YES" == true ]]; then
        return 0
    fi
    
    local yn_prompt
    if [[ "$default" == "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi
    
    read -r -p "$(echo -e "${CYAN}$prompt $yn_prompt: ${NC}")" response
    response=${response:-$default}
    
    [[ "$response" =~ ^[Yy]$ ]]
}

run_cmd() {
    local cmd="$*"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log "Executing: $cmd"
    if ! eval "$cmd"; then
        log "ERROR: Command failed: $cmd"
        return 1
    fi
}

backup_file() {
    local file="$1"
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY-RUN] Would backup $file to $backup"
        else
            cp "$file" "$backup"
            print_success "Backed up $file to $backup"
            log "Created backup: $backup"
        fi
    fi
}

# =============================================================================
# SETUP WIZARD
# =============================================================================

setup_wizard() {
    print_header "SETUP WIZARD"
    
    print_info "Welcome to the Ubuntu Server Setup Wizard!"
    print_info "This wizard will collect configuration information for all services."
    print_info "You can skip optional settings by pressing Enter."
    echo ""
    
    if [[ "$AUTO_YES" == true ]]; then
        print_info "Auto-yes mode: Using default values for all prompts"
        CERTBOT_SETUP=false
        return
    fi
    
    # Certbot Configuration
    echo ""
    print_step "SSL Certificate Configuration (Certbot)"
    echo ""
    
    if confirm "Do you want to set up SSL certificates with Certbot?"; then
        CERTBOT_SETUP=true
        
        while true; do
            read -r -p "$(echo -e "${CYAN}Enter your email address for Let's Encrypt: ${NC}")" cert_email
            if [[ -z "$cert_email" ]]; then
                print_warning "Email is required for Let's Encrypt. Try again."
            elif [[ ! "$cert_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                print_warning "Invalid email format. Try again."
            else
                CERTBOT_EMAIL="$cert_email"
                break
            fi
        done
        
        read -r -p "$(echo -e "${CYAN}Enter domain name for SSL certificate: ${NC}")" cert_domain
        if [[ -n "$cert_domain" ]]; then
            CERTBOT_DOMAIN="$cert_domain"
            print_success "SSL certificate will be obtained for: $CERTBOT_DOMAIN"
        else
            print_warning "No domain specified. SSL setup will be skipped."
            CERTBOT_SETUP=false
        fi
    else
        CERTBOT_SETUP=false
        print_info "SSL certificate setup skipped"
    fi
    
    echo ""
    print_success "Setup wizard completed!"
    echo ""
}

# =============================================================================
# PORT CONFIGURATION FUNCTIONS
# =============================================================================

validate_port() {
    local port="$1"
    local name="$2"
    
    # Check if it's a number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "Invalid port number: $port"
        return 1
    fi
    
    # Check range
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        print_error "Port must be between 1 and 65535"
        return 1
    fi
    
    # Warn about privileged ports
    if [[ "$port" -lt 1024 && "$name" != "dns" ]]; then
        print_warning "Port $port is a privileged port (< 1024)"
    fi
    
    # Check if port is already in use
    if ss -tuln | grep -q ":${port} "; then
        print_warning "Port $port appears to be already in use"
    fi
    
    # Check for conflicts with other configured ports
    for key in "${!PORT_MAP[@]}"; do
        if [[ "${PORT_MAP[$key]}" == "$port" ]]; then
            print_error "Port $port is already assigned to $key"
            return 1
        fi
    done
    
    return 0
}

prompt_port() {
    local name="$1"
    local default="$2"
    local description="$3"
    local port
    
    while true; do
        if [[ "$AUTO_YES" == true ]]; then
            port="$default"
        else
            read -r -p "$(echo -e "${CYAN}Enter port for $description [$default]: ${NC}")" port
            port=${port:-$default}
        fi
        
        if validate_port "$port" "$name"; then
            PORT_MAP["$name"]="$port"
            print_success "$description port set to: $port"
            break
        else
            if [[ "$AUTO_YES" == true ]]; then
                print_error "Cannot use default port $default, exiting"
                exit 1
            fi
            print_warning "Please enter a valid port number"
        fi
    done
}

configure_ports() {
    print_header "PORT CONFIGURATION"
    
    print_info "Configure custom ports for service obfuscation."
    print_info "Using non-standard ports helps prevent automated attacks."
    echo ""
    
    # SSH Port
    prompt_port "ssh" "$DEFAULT_SSH_PORT" "SSH"
    
    # k3s API Port
    prompt_port "k3s_api" "$DEFAULT_K3S_API_PORT" "k3s Kubernetes API"
    
    echo ""
    print_header "PORT CONFIGURATION SUMMARY"
    printf "%-25s %s\n" "Service" "Port"
    printf "%-25s %s\n" "-------------------------" "-----"
    for key in "${!PORT_MAP[@]}"; do
        printf "%-25s %s\n" "$key" "${PORT_MAP[$key]}"
    done
    echo ""
    
    if ! confirm "Proceed with these port settings?"; then
        print_info "Restarting port configuration..."
        PORT_MAP=()
        configure_ports
    fi
    
    save_port_config
}

save_port_config() {
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would save port configuration to $PORT_CONFIG_FILE"
        return
    fi
    
    print_step "Saving port configuration..."
    
    cat > "$PORT_CONFIG_FILE" << EOF
# Server Port Configuration
# Generated by $SCRIPT_NAME on $(date)
# 
# This file contains the custom port mappings for all services.
# Do not edit manually unless you know what you're doing.

SSH_PORT=${PORT_MAP[ssh]}
K3S_API_PORT=${PORT_MAP[k3s_api]}
EOF
    
    chmod 600 "$PORT_CONFIG_FILE"
    print_success "Port configuration saved to $PORT_CONFIG_FILE"
    log "Port configuration saved"
}

load_port_config() {
    if [[ -f "$PORT_CONFIG_FILE" ]]; then
        print_info "Loading existing port configuration from $PORT_CONFIG_FILE"
        source "$PORT_CONFIG_FILE"
        PORT_MAP[ssh]="${SSH_PORT:-$DEFAULT_SSH_PORT}"
        PORT_MAP[k3s_api]="${K3S_API_PORT:-$DEFAULT_K3S_API_PORT}"
        return 0
    fi
    return 1
}

# =============================================================================
# SSH HARDENING FUNCTIONS
# =============================================================================

setup_ssh_key() {
    local ssh_dir="/root/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    
    print_step "Setting up SSH key authentication..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would configure SSH keys"
        return
    fi
    
    # Create .ssh directory if it doesn't exist
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # If SSH key was provided via command line
    if [[ -n "$SSH_PUBLIC_KEY" ]]; then
        echo "$SSH_PUBLIC_KEY" >> "$auth_keys"
        print_success "Added provided SSH public key"
    elif [[ "$AUTO_YES" != true ]]; then
        # Prompt for SSH key
        echo ""
        print_warning "SSH key authentication will be REQUIRED after hardening!"
        print_info "You need to add your SSH public key now."
        echo ""
        print_info "Your public key usually looks like:"
        print_info "  ssh-rsa AAAAB3NzaC1yc2E... user@hostname"
        print_info "  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user@hostname"
        echo ""
        
        read -r -p "$(echo -e "${CYAN}Paste your SSH public key (or press Enter to skip): ${NC}")" user_key
        
        if [[ -n "$user_key" ]]; then
            echo "$user_key" >> "$auth_keys"
            print_success "Added SSH public key"
        else
            print_warning "No SSH key provided. Make sure you have one configured!"
            if ! confirm "Continue without adding an SSH key? (You may lose access!)"; then
                print_error "Aborting. Please run again with an SSH key."
                exit 1
            fi
        fi
    fi
    
    # Set proper permissions
    if [[ -f "$auth_keys" ]]; then
        chmod 600 "$auth_keys"
    fi
    
    log "SSH key setup completed"
}

harden_ssh() {
    print_header "SSH HARDENING"
    
    local sshd_config="/etc/ssh/sshd_config"
    local ssh_port="${PORT_MAP[ssh]}"
    
    print_step "Hardening SSH configuration..."
    
    # Setup SSH key first
    setup_ssh_key
    
    # Backup original config
    backup_file "$sshd_config"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would modify $sshd_config with:"
        print_info "  - Port: $ssh_port"
        print_info "  - PermitRootLogin: prohibit-password"
        print_info "  - PasswordAuthentication: no"
        print_info "  - PubkeyAuthentication: yes"
        print_info "  - MaxAuthTries: 3"
        print_info "  - LoginGraceTime: 20"
        return
    fi
    
    # Create hardened sshd_config
    print_step "Applying SSH hardening settings..."
    
    # Modify SSH port
    sed -i "s/^#\?Port .*/Port $ssh_port/" "$sshd_config"
    if ! grep -q "^Port " "$sshd_config"; then
        echo "Port $ssh_port" >> "$sshd_config"
    fi
    
    # Disable root login with password (allow with key)
    sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/" "$sshd_config"
    if ! grep -q "^PermitRootLogin " "$sshd_config"; then
        echo "PermitRootLogin prohibit-password" >> "$sshd_config"
    fi
    
    # Disable password authentication
    sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" "$sshd_config"
    if ! grep -q "^PasswordAuthentication " "$sshd_config"; then
        echo "PasswordAuthentication no" >> "$sshd_config"
    fi
    
    # Enable public key authentication
    sed -i "s/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/" "$sshd_config"
    if ! grep -q "^PubkeyAuthentication " "$sshd_config"; then
        echo "PubkeyAuthentication yes" >> "$sshd_config"
    fi
    
    # Limit authentication attempts
    sed -i "s/^#\?MaxAuthTries .*/MaxAuthTries 3/" "$sshd_config"
    if ! grep -q "^MaxAuthTries " "$sshd_config"; then
        echo "MaxAuthTries 3" >> "$sshd_config"
    fi
    
    # Reduce login grace time
    sed -i "s/^#\?LoginGraceTime .*/LoginGraceTime 20/" "$sshd_config"
    if ! grep -q "^LoginGraceTime " "$sshd_config"; then
        echo "LoginGraceTime 20" >> "$sshd_config"
    fi
    
    # Disable empty passwords
    sed -i "s/^#\?PermitEmptyPasswords .*/PermitEmptyPasswords no/" "$sshd_config"
    if ! grep -q "^PermitEmptyPasswords " "$sshd_config"; then
        echo "PermitEmptyPasswords no" >> "$sshd_config"
    fi
    
    # Disable X11 forwarding
    sed -i "s/^#\?X11Forwarding .*/X11Forwarding no/" "$sshd_config"
    if ! grep -q "^X11Forwarding " "$sshd_config"; then
        echo "X11Forwarding no" >> "$sshd_config"
    fi
    
    # Validate configuration
    print_step "Validating SSH configuration..."
    if sshd -t; then
        print_success "SSH configuration is valid"
    else
        print_error "SSH configuration validation failed!"
        print_info "Restoring backup..."
        cp "${sshd_config}.backup."* "$sshd_config" 2>/dev/null || true
        exit 1
    fi
    
    # Restart SSH service
    print_step "Restarting SSH service..."
    systemctl restart sshd
    print_success "SSH service restarted"
    
    print_success "SSH hardening completed"
    print_warning "Remember: SSH is now on port $ssh_port with key-only authentication!"
    
    log "SSH hardening completed - Port: $ssh_port"
}

# =============================================================================
# DOCKER INSTALLATION
# =============================================================================

install_docker() {
    print_header "DOCKER INSTALLATION"
    
    if command_exists docker; then
        print_info "Docker is already installed"
        docker --version
        if ! confirm "Reinstall Docker?"; then
            return
        fi
    fi
    
    print_step "Installing Docker CE..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install Docker CE"
        return
    fi
    
    # Update package index
    run_cmd "apt-get update"
    
    # Install prerequisites
    run_cmd "apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release"
    
    # Add Docker's official GPG key
    print_step "Adding Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up the repository
    print_step "Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    run_cmd "apt-get update"
    run_cmd "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    
    # Configure Docker daemon
    print_step "Configuring Docker daemon..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true
}
EOF
    
    # Start and enable Docker
    run_cmd "systemctl enable docker"
    run_cmd "systemctl start docker"
    
    # Verify installation
    if docker run --rm hello-world &>/dev/null; then
        print_success "Docker installed and working"
    else
        print_warning "Docker installed but test container failed"
    fi
    
    docker --version
    log "Docker installation completed"
}

# =============================================================================
# K3S INSTALLATION
# =============================================================================

install_k3s() {
    print_header "K3S INSTALLATION"
    
    local k3s_port="${PORT_MAP[k3s_api]}"
    
    if command_exists k3s; then
        print_info "k3s is already installed"
        k3s --version
        if ! confirm "Reinstall k3s?"; then
            return
        fi
    fi
    
    print_step "Installing k3s (Lightweight Kubernetes)..."
    print_info "Using custom API port: $k3s_port"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install k3s with API port $k3s_port"
        return
    fi
    
    # Install k3s with enhanced security settings
    # --https-listen-port: Custom API server port
    # --disable=traefik: Remove default ingress controller
    # --write-kubeconfig-mode: Restrict kubeconfig permissions
    # --tls-san: Add additional TLS subject alternative names
    # --kube-apiserver-arg: Additional API server security arguments
    # --kubelet-arg: Additional kubelet security arguments
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
        --https-listen-port=$k3s_port \
        --disable=traefik \
        --write-kubeconfig-mode=600 \
        --tls-san=$(hostname -I | awk '{print $1}') \
        --kube-apiserver-arg=--enable-admission-plugins=NodeRestriction,PodSecurityPolicy \
        --kube-apiserver-arg=--audit-log-path=/var/log/k3s-audit.log \
        --kube-apiserver-arg=--audit-log-maxage=30 \
        --kube-apiserver-arg=--audit-log-maxbackup=10 \
        --kube-apiserver-arg=--audit-log-maxsize=100 \
        --kube-apiserver-arg=--service-account-lookup=true \
        --kube-apiserver-arg=--enable-aggregator-routing=false \
        --kubelet-arg=--protect-kernel-defaults=true \
        --kubelet-arg=--read-only-port=0 \
        --kubelet-arg=--streaming-connection-idle-timeout=30m" sh -
    
    # Wait for k3s to be ready
    print_step "Waiting for k3s to be ready..."
    sleep 15
    
    # Verify installation
    if k3s kubectl get nodes &>/dev/null; then
        print_success "k3s installed and running"
        k3s kubectl get nodes
    else
        print_warning "k3s installed but not fully ready yet"
    fi
    
    # Apply additional security configurations
    print_step "Applying additional k3s security configurations..."
    
    # Create audit log directory with proper permissions
    mkdir -p /var/log
    chmod 750 /var/log
    touch /var/log/k3s-audit.log
    chmod 600 /var/log/k3s-audit.log
    
    # Set up kubectl alias
    print_step "Setting up kubectl alias..."
    if ! grep -q "alias kubectl=" /root/.bashrc 2>/dev/null; then
        echo "alias kubectl='k3s kubectl'" >> /root/.bashrc
    fi
    
    # Export KUBECONFIG with restricted permissions
    if ! grep -q "KUBECONFIG=" /root/.bashrc 2>/dev/null; then
        echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /root/.bashrc
    fi
    
    # Apply basic network policies (deny all by default)
    print_step "Applying basic network policies..."
    cat << 'EOF' | k3s kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53
EOF
    
    # Apply Pod Security Standards
    print_step "Applying Pod Security Standards..."
    cat << 'EOF' | k3s kubectl apply -f -
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'MustRunAs'
    ranges:
    - min: 1
      max: 65535
  fsGroup:
    rule: 'MustRunAs'
    ranges:
    - min: 1
      max: 65535
EOF
    
    print_success "k3s installation and security hardening completed"
    print_info "Kubernetes API available on port $k3s_port"
    print_info "Audit logs: /var/log/k3s-audit.log"
    print_info "Network policies applied (default deny)"
    print_info "Pod Security Policy enabled"
    
    log "k3s installation completed with enhanced security - API Port: $k3s_port"
}

# =============================================================================
# SSHGUARD INSTALLATION
# =============================================================================

install_sshguard() {
    print_header "SSHGUARD INSTALLATION"
    
    if command_exists sshguard; then
        print_info "SSHGuard is already installed"
        if ! confirm "Reinstall SSHGuard?"; then
            return
        fi
    fi
    
    print_step "Installing SSHGuard..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install SSHGuard"
        return
    fi
    
    run_cmd "apt-get update"
    run_cmd "apt-get install -y sshguard"
    
    # Configure SSHGuard
    print_step "Configuring SSHGuard..."
    
    local sshguard_conf="/etc/sshguard/sshguard.conf"
    backup_file "$sshguard_conf"
    
    # Create or update SSHGuard configuration
    cat > "$sshguard_conf" << 'EOF'
# SSHGuard Configuration
# Generated by ubuntu-server-setup.sh

# Backend for blocking (ufw for Ubuntu)
BACKEND="/usr/libexec/sshguard/sshg-fw-ufw"

# Detection threshold: number of attacks before blocking
# 25 = 5 attacks with danger level 5 each (5*5=25)
THRESHOLD=25

# Block duration in seconds (starts at this, increases with repeat offenders)
# 600 = 10 minutes initial block
BLOCK_TIME=600

# Time to remember attacker (reset attack count after this time)
# 1800 = 30 minutes
DETECTION_TIME=1800

# Files to monitor for attacks
FILES="/var/log/auth.log"

# Whitelist file
WHITELIST_FILE=/etc/sshguard/whitelist

# Blacklist (persistent blocks)
BLACKLIST_FILE=10:/var/lib/sshguard/blacklist.db

# IPv6 subnet size to block (128 = single host)
IPV6_SUBNET=128

# IPv4 subnet size to block (32 = single host)
IPV4_SUBNET=32
EOF
    
    # Create whitelist file (add local network if needed)
    cat > /etc/sshguard/whitelist << EOF
# SSHGuard Whitelist
# Add IPs or networks that should never be blocked
# Examples:
# 192.168.1.0/24
# 10.0.0.0/8
127.0.0.0/8
::1/128
EOF
    
    # Ensure blacklist directory exists
    mkdir -p /var/lib/sshguard
    
    # Enable and start SSHGuard
    run_cmd "systemctl enable sshguard"
    run_cmd "systemctl restart sshguard"
    
    print_success "SSHGuard installed and configured"
    
    # Print helper commands
    echo ""
    print_info "SSHGuard Helper Commands:"
    print_info "  View blocked IPs:    sudo iptables -L sshguard -n"
    print_info "  Unban an IP:         sudo iptables -D sshguard -s <IP> -j DROP"
    print_info "  Check SSHGuard logs: sudo journalctl -u sshguard -f"
    print_info "  Whitelist file:      /etc/sshguard/whitelist"
    
    log "SSHGuard installation completed"
}

# =============================================================================
# PI-HOLE INSTALLATION
# =============================================================================

install_fail2ban() {
    print_header "FAIL2BAN INSTALLATION"

    if command_exists fail2ban-client; then
        print_info "Fail2Ban is already installed"
        if ! confirm "Reinstall Fail2Ban?"; then
            return
        fi
    fi

    print_step "Installing Fail2Ban..."

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install Fail2Ban"
        return
    fi

    # Install Fail2Ban
    run_cmd "apt-get update"
    run_cmd "apt-get install -y fail2ban"

    # Create custom jail configuration
    print_step "Configuring Fail2Ban jails..."

    local jail_local="/etc/fail2ban/jail.local"
    backup_file "$jail_local"

    cat > "$jail_local" << EOF
# Fail2Ban Configuration
# Generated by ubuntu-server-setup.sh

[DEFAULT]
# Ban hosts for one hour:
bantime = 3600

# Override /etc/fail2ban/jail.d/00-firewalld.conf:
banaction = ufw

# A host is banned if it has generated "maxretry" during the last "findtime" seconds.
findtime = 600
maxretry = 5

# "ignoreip" can be a list of IP addresses, CIDR masks or DNS hosts. Fail2Ban
# will not ban a host which matches an address in this list. Several addresses
# can be defined using space (and/or comma) separator.
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${PORT_MAP[ssh]}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = ${PORT_MAP[ssh]}
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 6
bantime = 3600

[dropbear]
enabled = false

[nginx-http-auth]
enabled = false

[nginx-noscript]
enabled = false

[nginx-badbots]
enabled = false

[nginx-noproxy]
enabled = false

[nginx-botsearch]
enabled = false

[nginx-req-limit]
enabled = false

[nginx-ddos]
enabled = false

[php-url-fopen]
enabled = false

[roundcube-auth]
enabled = false

[gssftpd]
enabled = false

[proftpd]
enabled = false

[pure-ftpd]
enabled = false

[wuftpd]
enabled = false

[vsftpd]
enabled = false

[postfix]
enabled = false

[postfix-sasl]
enabled = false

[dovecot]
enabled = false

[sieve]
enabled = false

[cyrus-imap]
enabled = false

[ucimap]
enabled = false

[solid-pop3d]
enabled = false

[exim]
enabled = false

[exim-spam]
enabled = false

[courier-auth]
enabled = false

[courier-smtp]
enabled = false

[courier-pop3]
enabled = false

[courier-imap]
enabled = false

[perdition]
enabled = false

[squirrelmail]
enabled = false

[cyrus-imap]
enabled = false

[uwimap-auth]
enabled = false

[saslauthd]
enabled = false

[openwebmail]
enabled = false

[horde]
enabled = false

[groupoffice]
enabled = false

[sogo-auth]
enabled = false

[open-xchange]
enabled = false

[roundcube-auth]
enabled = false

[incapsula]
enabled = false

[phpmyadmin-syslog]
enabled = false

[directadmin]
enabled = false

[portsentry]
enabled = false

[pass2allow-ftp]
enabled = false

[webmin-auth]
enabled = false

[froxlor-auth]
enabled = false

[ftpd]
enabled = false

[drupal-auth]
enabled = false

[wordpress]
enabled = false

[wordpress-hard]
enabled = false

[wordpress-brute]
enabled = false

[wordpress-bf]
enabled = false

[plesk-panel]
enabled = false

[plesk-proftpd]
enabled = false

[mod-security]
enabled = false

[apache-tcpwrapper]
enabled = false

[apache-overflows]
enabled = false

[apache-modsecurity]
enabled = false

[apache-noscript]
enabled = false

[apache-badbots]
enabled = false

[apache-botsearch]
enabled = false

[apache-ddos]
enabled = false

[apache-noproxy]
enabled = false

[apache-req-limit]
enabled = false

[apache-w00tw00t]
enabled = false

[apache-shellshock]
enabled = false

[openhab-auth]
enabled = false

[selinux-ssh]
enabled = false

[nginx-ddos]
enabled = false

[nginx-http-auth]
enabled = false

[nginx-noscript]
enabled = false

[nginx-badbots]
enabled = false

[nginx-noproxy]
enabled = false

[nginx-botsearch]
enabled = false

[nginx-req-limit]
enabled = false

[asterisk]
enabled = false

[freeswitch]
enabled = false

[mysqld-auth]
enabled = false

[named-refused]
enabled = false

[nsd]
enabled = false

[postfix]
enabled = false

[postfix-sasl]
enabled = false

[postfix-ddos]
enabled = false

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
banaction = ufw
bantime = 604800  ; 1 week
findtime = 86400   ; 1 day
maxretry = 5

[sendmail-auth]
enabled = false

[sendmail-reject]
enabled = false

[qmail-rbl]
enabled = false

[dovecot]
enabled = false

[squid]
enabled = false

[sshd]
enabled = true

[dropbear]
enabled = false

[selinux-ssh]
enabled = false

[nginx-ddos]
enabled = false

[nginx-http-auth]
enabled = false

[nginx-noscript]
enabled = false

[nginx-badbots]
enabled = false

[nginx-noproxy]
enabled = false

[nginx-botsearch]
enabled = false

[nginx-req-limit]
enabled = false
EOF

    # Enable and start Fail2Ban
    print_step "Enabling and starting Fail2Ban..."
    run_cmd "systemctl enable fail2ban"
    run_cmd "systemctl start fail2ban"

    # Wait a moment for Fail2Ban to start
    sleep 2

    # Verify Fail2Ban is working
    if fail2ban-client status > /dev/null 2>&1; then
        print_success "Fail2Ban installed and configured"
        echo ""
        print_info "Active jails:"
        fail2ban-client status | grep "Jail list:" | sed -E 's/^[^:]+:\s+//' | sed 's/,/\n  - /g' | sed 's/^/  - /'
        echo ""
        print_info "Fail2Ban Helper Commands:"
        print_info "  View status: sudo fail2ban-client status"
        print_info "  View banned IPs: sudo fail2ban-client status sshd"
        print_info "  Unban IP: sudo fail2ban-client set sshd unbanip <IP>"
        print_info "  Check logs: sudo journalctl -u fail2ban -f"
        print_info "  Configuration: /etc/fail2ban/jail.local"
    else
        print_warning "Fail2Ban installed but may not be fully operational"
    fi

    log "Fail2Ban installation completed"
}

# =============================================================================
# CERTBOT SSL CERTIFICATE SETUP
# =============================================================================

setup_certbot() {
    print_header "CERTBOT SSL CERTIFICATE SETUP"
    
    if [[ "$CERTBOT_SETUP" != true ]]; then
        print_info "SSL certificate setup skipped"
        return
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would set up SSL certificates for $CERTBOT_DOMAIN"
        return
    fi
    
    print_step "Installing Certbot..."
    
    # Install Certbot
    run_cmd "apt-get update"
    run_cmd "apt-get install -y certbot python3-certbot-nginx"
    
    # Get SSL certificate
    print_step "Obtaining SSL certificate for $CERTBOT_DOMAIN..."
    
    # Obtain certificate
    if certbot certonly --standalone -d "$CERTBOT_DOMAIN" --email "$CERTBOT_EMAIL" --agree-tos --non-interactive; then
        print_success "SSL certificate obtained successfully"
        
        # Configure automatic renewal
        print_step "Setting up automatic certificate renewal..."
        (crontab -l ; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        
        # Create renewal hook to restart services
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat > /etc/letsencrypt/renewal-hooks/deploy/restart-services << EOF
#!/bin/bash
# Restart services after certificate renewal
systemctl reload nginx 2>/dev/null || true
EOF
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/restart-services
        
        print_success "Certificate renewal configured"
        print_info "Certificate files are located in: /etc/letsencrypt/live/$CERTBOT_DOMAIN/"
        
    else
        print_error "Failed to obtain SSL certificate"
        print_info "You can try manually later with: certbot certonly --standalone -d $CERTBOT_DOMAIN"
    fi
    
    log "Certbot SSL setup completed for domain: $CERTBOT_DOMAIN"
}

# =============================================================================
# UFW FIREWALL CONFIGURATION
# =============================================================================

configure_ufw() {
    print_header "UFW FIREWALL CONFIGURATION"
    
    local ssh_port="${PORT_MAP[ssh]}"
    local k3s_port="${PORT_MAP[k3s_api]}"
    
    print_step "Configuring UFW firewall..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would configure UFW with:"
        print_info "  - Default deny incoming"
        print_info "  - Allow SSH on port $ssh_port"
        print_info "  - Allow k3s API on port $k3s_port"
        return
    fi
    
    # Install UFW if not present
    if ! command_exists ufw; then
        run_cmd "apt-get install -y ufw"
    fi
    
    # Reset UFW to defaults
    print_step "Resetting UFW to defaults..."
    ufw --force reset
    
    # Set default policies
    print_step "Setting default policies..."
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (IMPORTANT: do this first!)
    print_step "Allowing SSH on port $ssh_port..."
    ufw allow "$ssh_port/tcp" comment "SSH"
    
    # Allow k3s API
    print_step "Allowing k3s API on port $k3s_port..."
    ufw allow "$k3s_port/tcp" comment "k3s API"
    
    # Allow k3s internal communication (flannel)
    print_step "Allowing k3s internal networking..."
    ufw allow 8472/udp comment "k3s Flannel VXLAN"
    ufw allow 10250/tcp comment "k3s Kubelet"
    
    # Allow Docker networking (internal)
    print_step "Allowing Docker internal networking..."
    ufw allow in on docker0 comment "Docker bridge"
    
    # Enable UFW
    print_step "Enabling UFW..."
    echo "y" | ufw enable
    
    print_success "UFW firewall configured and enabled"
    echo ""
    print_info "UFW Status:"
    ufw status verbose
    
    log "UFW firewall configured"
}

# =============================================================================
# UNATTENDED UPGRADES CONFIGURATION
# =============================================================================

configure_unattended_upgrades() {
    print_header "UNATTENDED UPGRADES CONFIGURATION"
    
    print_step "Configuring automatic system updates..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would configure unattended upgrades"
        return
    fi
    
    # Install unattended-upgrades if not already installed
    if ! dpkg -l | grep -q unattended-upgrades; then
        print_step "Installing unattended-upgrades package..."
        run_cmd "apt-get update"
        run_cmd "apt-get install -y unattended-upgrades"
    fi
    
    # Preconfigure unattended-upgrades to automatically install updates
    print_step "Setting debconf selections..."
    echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
    
    # Enable unattended-upgrades
    print_step "Enabling unattended-upgrades service..."
    dpkg-reconfigure --frontend=noninteractive unattended-upgrades
    
    # Configure unattended-upgrades settings
    # Using conservative settings: enable updates but no automatic reboot
    print_step "Creating unattended-upgrades configuration..."
    backup_file "/etc/apt/apt.conf.d/50unattended-upgrades"
    
    cat > "/etc/apt/apt.conf.d/50unattended-upgrades" << EOF
// Unattended-Upgrade::Origins-URI "origin=Debian,codename=\${distro_codename},label=Debian";
// Unattended-Upgrade::Origins-URI "origin=Debian,codename=\${distro_codename},label=Debian-Security";
Unattended-Upgrade::Origins-URI "origin=Ubuntu,codename=\${distro_codename}";
Unattended-Upgrade::Origins-URI "origin=Ubuntu,codename=\${distro_codename}-security";
Unattended-Upgrade::Origins-URI "origin=Ubuntu,codename=\${distro_codename}-updates";

// Python regular expressions, matching packages to exclude from upgrading
Unattended-Upgrade::Package-Blacklist {
    // "vim";
    // "libc6";
    // "libc6-dev";
    // "libgcc.*";
    // "libstdc\+\+.*";
    // "gcc-.*";
    // ".*-dev$";
};

// This option allows you to control if on a unclean dpkg exit
// unattended-upgrades will automatically run
//   dpkg --force-confold --configure -a
// The default is true, to ensure updates keep getting installed
//Unattended-Upgrade::AutoFixInterruptedDpkg "false";

// Split the upgrade into the smallest possible chunks so that
// they can be interrupted with SIGTERM. This makes the upgrade
// a bit slower but it has the benefit that shutdown while a upgrade
// is running is possible (with a small delay)
//Unattended-Upgrade::MinimalSteps "true";

// Install all unattended-upgrades when the machine is shutting down
// instead of doing it in the background while the machine is running
// This will (obviously) make shutdown slower
//Unattended-Upgrade::InstallOnShutdown "true";

// Send email to this address for problems or packages upgrades
// If empty or unset then no email is sent, make sure that you
// have a working mail setup on your system. A package that provides
// 'mailx' must be installed. E.g. "user@example.com"
//Unattended-Upgrade::Mail "root";

// Set this value to "true" to get emails only on errors. Default
// is to always send a mail if Unattended-Upgrade::Mail is set
//Unattended-Upgrade::MailOnlyOnError "true";

// Do automatic removal of new unused dependencies after the upgrade
// (equivalent to apt-get autoremove)
//Unattended-Upgrade::Remove-Unused-Dependencies "false";

// Automatically reboot *WITHOUT CONFIRMATION* if
//  the file /var/run/reboot-required is found after the upgrade
//Unattended-Upgrade::Automatic-Reboot "false";

// If automatic reboot is enabled and needed, reboot at the specific
// time instead of immediately
//  Default: immediately if set to "now"; otherwise 02:00
//Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Use apt bandwidth limit feature, this example limits the download
// speed to 70kb/sec
//Acquire::http::Dl-Limit "70";

// Enable logging to syslog. Default is False
// Unattended-Upgrade::SyslogEnable "false";

// Log to syslog with facility and priority
// Unattended-Upgrade::SyslogFacility "daemon";
// Unattended-Upgrade::SyslogPriority "info";

// Controls behavior of verbose logging. Levels:
//
Unattended-Upgrade::Verbose "true";

// Automatically upgrade packages from these (origin:archive) pairs
// Note: This option will also cause Unattended-Upgrade::Origins-URI to be ignored.
//Unattended-Upgrade::Allowed-Origins {
//    "\${distro_id}:\${distro_codename}";
//    "\${distro_id}:\${distro_codename}-security";
//    "\${distro_id}:\${distro_codename}-updates";
//    "\${distro_id}:\${distro_codename}-proposed";
//    "\${distro_id}:\${distro_codename}-backports";
//};

// List of packages to not update (regexp are supported)
//Unattended-Upgrade::Package-Blacklist {
//    // "linux-image-generic";
//};

// This option controls whether the development release of Ubuntu will be
// upgraded automatically. Autoupgrading to a development version is
// almost never a good idea.
//Unattended-Upgrade::DevRelease "false";
EOF
    
    # Restart the unattended-upgrades service
    print_step "Restarting unattended-upgrades service..."
    systemctl restart unattended-upgrades
    
    print_success "Unattended upgrades configured and enabled"
    print_info "System will automatically install security updates"
    print_info "No automatic reboot configured (conservative settings)"
    
    log "Unattended upgrades configured"
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

generate_report() {
    print_header "GENERATING INSTALLATION REPORT"
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$REPORT_DIR/server-setup-${timestamp}.report"
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    
    print_step "Generating comprehensive report..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would generate report at $report_file"
        return
    fi
    
    # Ensure report directory exists
    mkdir -p "$REPORT_DIR"
    
    {
        echo "==============================================================================="
        echo "                    UBUNTU SERVER SETUP REPORT"
        echo "==============================================================================="
        echo ""
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Hostname:  $(hostname)"
        echo "Server IP: $server_ip"
        echo ""
        
        echo "==============================================================================="
        echo "                         PORT CONFIGURATION"
        echo "==============================================================================="
        echo ""
        echo "IMPORTANT: These are your custom service ports!"
        echo "Save this information securely."
        echo ""
        printf "%-30s %s\n" "Service" "Port"
        printf "%-30s %s\n" "------------------------------" "-------"
        printf "%-30s %s\n" "SSH" "${PORT_MAP[ssh]:-N/A}"
        printf "%-30s %s\n" "k3s Kubernetes API" "${PORT_MAP[k3s_api]:-N/A}"
        echo ""
        
        echo "==============================================================================="
        echo "                         CONNECTION INFORMATION"
        echo "==============================================================================="
        echo ""
        echo "SSH Connection:"
        echo "  ssh -p ${PORT_MAP[ssh]:-22} root@$server_ip"
        echo ""
        echo "Fail2Ban Status:"
        echo "  sudo fail2ban-client status"
        echo ""
        echo "Kubernetes (k3s):"
        echo "  kubectl --server=https://$server_ip:${PORT_MAP[k3s_api]:-6443} get nodes"
        echo "  KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes"
        echo ""
        
        echo "==============================================================================="
        echo "                         SERVICE STATUS"
        echo "==============================================================================="
        echo ""
        printf "%-25s %s\n" "Service" "Status"
        printf "%-25s %s\n" "-------------------------" "------------"
        
        for service in sshd docker k3s sshguard fail2ban ufw unattended-upgrades; do
            local status
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                status="✓ Active"
            elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
                status="○ Enabled (not running)"
            else
                status="✗ Not installed/inactive"
            fi
            printf "%-25s %s\n" "$service" "$status"
        done
        echo ""
        
        # Check Certbot/SSL status
        echo "Certbot SSL:"
        if command_exists certbot; then
            if [[ -d "/etc/letsencrypt/live/$CERTBOT_DOMAIN" ]]; then
                echo "  ✓ Configured for: $CERTBOT_DOMAIN"
                echo "  Certificate expiry: $(openssl x509 -enddate -noout -in /etc/letsencrypt/live/$CERTBOT_DOMAIN/cert.pem 2>/dev/null | cut -d= -f2 || echo 'Unknown')"
            else
                echo "  ○ Installed (no certificates)"
            fi
        else
            echo "  ✗ Not installed"
        fi
        echo ""
        
        echo "==============================================================================="
        echo "                         FIREWALL RULES (UFW)"
        echo "==============================================================================="
        echo ""
        ufw status verbose 2>/dev/null || echo "UFW not configured"
        echo ""
        
        echo "==============================================================================="
        echo "                         SYSTEM USERS"
        echo "==============================================================================="
        echo ""
        echo "Users with login shell (UID >= 1000):"
        echo ""
        printf "%-20s %-8s %-20s %s\n" "Username" "UID" "Shell" "Home"
        printf "%-20s %-8s %-20s %s\n" "--------------------" "--------" "--------------------" "--------------------"
        getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {printf "%-20s %-8s %-20s %s\n", $1, $3, $7, $6}'
        echo ""
        echo "System accounts with sudo access:"
        getent group sudo | cut -d: -f4
        echo ""
        
        echo "==============================================================================="
        echo "                         SYSTEM INFORMATION"
        echo "==============================================================================="
        echo ""
        echo "Operating System:"
        cat /etc/os-release | grep -E "^(NAME|VERSION)=" | sed 's/^/  /'
        echo ""
        echo "Kernel:"
        echo "  $(uname -r)"
        echo ""
        echo "CPU:"
        echo "  $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
        echo "  Cores: $(nproc)"
        echo ""
        echo "Memory:"
        free -h | grep -E "^(Mem|Swap)" | sed 's/^/  /'
        echo ""
        echo "Disk Usage:"
        df -h / | tail -1 | awk '{print "  Total: " $2 ", Used: " $3 " (" $5 "), Available: " $4}'
        echo ""
        echo "Network Interfaces:"
        ip -brief addr | sed 's/^/  /'
        echo ""
        
        echo "==============================================================================="
        echo "                         INSTALLED VERSIONS"
        echo "==============================================================================="
        echo ""
        echo "Docker:"
        docker --version 2>/dev/null | sed 's/^/  /' || echo "  Not installed"
        echo ""
        echo "k3s:"
        k3s --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  Not installed"
        echo ""
        echo "Fail2Ban:"
        fail2ban-client -V 2>/dev/null | sed 's/^/  /' || echo "  Not installed"
        echo ""
        
        echo "==============================================================================="
        echo "                         SSH CONFIGURATION"
        echo "==============================================================================="
        echo ""
        echo "SSH Port: ${PORT_MAP[ssh]:-22}"
        echo "Root Login: $(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo 'N/A')"
        echo "Password Auth: $(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo 'N/A')"
        echo ""
        echo "SSH Host Key Fingerprints:"
        for key in /etc/ssh/ssh_host_*_key.pub; do
            ssh-keygen -lf "$key" 2>/dev/null | sed 's/^/  /'
        done
        echo ""
        
        echo "==============================================================================="
        echo "                         FAIL2BAN HELPER COMMANDS"
        echo "==============================================================================="
        echo ""
        echo "View active jails:"
        echo "  sudo fail2ban-client status"
        echo ""
        echo "View banned IPs in SSH jail:"
        echo "  sudo fail2ban-client status sshd"
        echo ""
        echo "Unban a specific IP:"
        echo "  sudo fail2ban-client set sshd unbanip <IP_ADDRESS>"
        echo ""
        echo "View Fail2Ban logs:"
        echo "  sudo journalctl -u fail2ban -f"
        echo ""
        echo "Check jail configuration:"
        echo "  sudo fail2ban-client get sshd maxretry"
        echo "  sudo fail2ban-client get sshd bantime"
        echo ""
        
        echo "==============================================================================="
        echo "                         POST-INSTALLATION TASKS"
        echo "==============================================================================="
        echo ""
        echo "IMMEDIATE TASKS (Do these now to verify everything works):"
        echo ""
        echo "1. TEST SSH CONNECTION:"
        echo "   - Open a NEW terminal window"
        echo "   - Connect using: ssh -p ${PORT_MAP[ssh]:-22} root@$server_ip"
        echo "   - If it fails, you may be locked out! Check the report for details."
        echo ""
        echo "2. SAVE THIS REPORT SECURELY:"
        echo "   - Copy this report to a safe location (USB drive, secure email, etc.)"
        echo "   - The report contains all your custom port configurations"
        echo "   - Without it, you may forget the SSH port and lose access"
        echo ""
        echo "3. VERIFY FAIL2BAN IS WORKING:"
        echo "   - Check status: sudo fail2ban-client status"
        echo "   - Should show 'sshd' jail active"
        echo "   - Test with failed SSH attempts (from another machine)"
        echo ""
        echo "4. TEST KUBERNETES (K3S):"
        echo "   - Run: k3s kubectl get nodes"
        echo "   - Should show your server as 'Ready'"
        echo "   - Test deployment: k3s kubectl run test --image=nginx --port=80"
        echo ""
        echo "ONGOING MAINTENANCE TASKS:"
        echo ""
        echo "6. MONITOR FAIL2BAN:"
        echo "   - Check status: sudo fail2ban-client status"
        echo "   - View banned IPs: sudo fail2ban-client status sshd"
        echo "   - View logs: sudo journalctl -u fail2ban -f"
        echo "   - Unban legitimate IPs if needed"
        echo ""
        echo "7. BACKUP CONFIGURATIONS:"
        echo "   - Port config: /etc/server-ports.conf"
        echo "   - SSH config: /etc/ssh/sshd_config"
        echo "   - Fail2Ban: /etc/fail2ban/jail.local"
        echo "   - k3s: /etc/rancher/k3s/k3s.yaml"
        echo ""
        echo "8. UPDATE SERVICES:"
        echo "   - Docker: docker system prune -a (clean unused images)"
        echo "   - k3s: k3s kubectl get nodes (check cluster health)"
        echo "   - Fail2Ban: sudo fail2ban-client reload (reload configuration)"
        echo "   - Unattended upgrades: Check /var/log/unattended-upgrades/"
        echo "   - System: apt update && apt upgrade (manual updates)"
        echo ""
        echo "9. MONITOR SYSTEM HEALTH:"
        echo "   - Check services: systemctl status <service>"
        echo "   - View logs: journalctl -u <service>"
        echo "   - Disk usage: df -h"
        echo "   - Memory: free -h"
        echo ""
        echo "10. SECURITY AUDIT:"
        echo "    - Review UFW rules: sudo ufw status verbose"
        echo "    - Check Fail2Ban status: sudo fail2ban-client status"
        echo "    - Check for failed SSH attempts: sudo journalctl -u ssh"
        echo "    - Verify SSH key fingerprints match known hosts"
        echo "    - Check SSL certificate expiry: sudo certbot certificates"
        echo ""
        
        echo "==============================================================================="
        echo "                         IMPORTANT NOTES"
        echo "==============================================================================="
        echo ""
        echo "1. SAVE THIS REPORT SECURELY - It contains your custom port configuration"
        echo ""
        echo "2. SSH Access:"
        echo "   - Port has been changed to ${PORT_MAP[ssh]:-22}"
        echo "   - Password authentication is DISABLED"
        echo "   - Use SSH keys only: ssh -p ${PORT_MAP[ssh]:-22} root@$server_ip"
        echo ""
        echo "3. Fail2Ban:"
        echo "   - Intrusion prevention system is active"
        echo "   - Check status: sudo fail2ban-client status"
        echo "   - Configuration: /etc/fail2ban/jail.local"
        echo ""
        echo "4. Kubernetes (k3s):"
        echo "   - kubeconfig: /etc/rancher/k3s/k3s.yaml"
        echo "   - Use 'k3s kubectl' or set KUBECONFIG environment variable"
        echo ""
        echo "5. Firewall:"
        echo "   - UFW is enabled with minimal open ports"
        echo "   - Check status: sudo ufw status verbose"
        echo ""
        echo "6. Automatic Updates:"
        echo "   - Unattended-upgrades is configured and enabled"
        echo "   - Security updates will install automatically"
        echo "   - No automatic reboot (conservative settings)"
        echo "   - Monitor logs: /var/log/unattended-upgrades/"
        echo ""
        echo "==============================================================================="
        echo "                         END OF REPORT"
        echo "==============================================================================="
        
    } > "$report_file"
    
    chmod 600 "$report_file"
    
    print_success "Report saved to: $report_file"
    
    # Also display to console
    echo ""
    cat "$report_file"
    
    log "Report generated: $report_file"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--report-only)
                REPORT_ONLY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --ssh-key)
                SSH_PUBLIC_KEY="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Display banner
    echo -e "${CYAN}"
    echo "    ╔══════════════════════════════════════════════════════════════════════════╗"
    echo "    ║           Ubuntu Server Setup Script v${SCRIPT_VERSION}                  ║"
    echo "    ║                                                                          ║"
    echo "    ║  Docker • k3s (Secured) • SSHGuard • Fail2Ban • Certbot • UFW • SSH      ║"
    echo "    ║  Hardening • Unattended Upgrades                                         ║"
    echo "    ╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    # Check prerequisites
    check_root
    check_ubuntu
    
    # Run setup wizard (unless in report-only mode)
    if [[ "$REPORT_ONLY" != true ]]; then
        setup_wizard
    fi
    
    # Initialize log file
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE"
        log "=== Starting Ubuntu Server Setup ==="
    fi
    
    # Report only mode
    if [[ "$REPORT_ONLY" == true ]]; then
        if load_port_config; then
            generate_report
        else
            print_error "No port configuration found. Run full setup first."
            exit 1
        fi
        exit 0
    fi
    
    # Configure ports
    if ! load_port_config; then
        configure_ports
    else
        print_info "Loaded existing port configuration"
        echo ""
        printf "%-25s %s\n" "Service" "Port"
        printf "%-25s %s\n" "-------------------------" "-----"
        for key in "${!PORT_MAP[@]}"; do
            printf "%-25s %s\n" "$key" "${PORT_MAP[$key]}"
        done
        echo ""
        if confirm "Use existing port configuration?"; then
            print_success "Using existing configuration"
        else
            PORT_MAP=()
            configure_ports
        fi
    fi
    
    # Pre-installation system validation
    if [[ "$DRY_RUN" != true ]]; then
        validate_system_state "pre_install"
    fi
    
    # Update system
    print_header "SYSTEM UPDATE"
    print_step "Updating system packages..."
    if [[ "$DRY_RUN" != true ]]; then
        apt-get update
        apt-get upgrade -y
    else
        print_info "[DRY-RUN] Would update system packages"
    fi
    print_success "System updated"
    
    # Configure unattended upgrades
    configure_unattended_upgrades
    
    # Install services
    install_docker
    install_k3s
    install_sshguard
    install_fail2ban
    
    # Setup SSL certificates if configured
    setup_certbot
    
    # Configure firewall (before SSH hardening to ensure access)
    configure_ufw
    
    # Harden SSH (do this last to avoid lockout)
    harden_ssh
    
    # Post-installation system validation
    if [[ "$DRY_RUN" != true ]]; then
        validate_system_state "post_install"
    fi
    
    # Generate report
    generate_report
    
    # Final message
    print_header "SETUP COMPLETE"
    print_success "Ubuntu server setup completed successfully!"
    echo ""
    print_warning "IMPORTANT REMINDERS:"
    echo ""
    print_info "1. SSH port is now: ${PORT_MAP[ssh]}"
    print_info "2. Password authentication is DISABLED"
    print_info "3. Use: ssh -p ${PORT_MAP[ssh]} root@$(hostname -I | awk '{print $1}')"
    echo ""
    print_info "The detailed report has been saved. Keep it secure!"
    print_info "If any issues occur, check for error files:"
    print_info "  - Error details: $ERROR_FILE"
    print_info "  - Debug info: $DEBUG_FILE"
    echo ""
    print_header "POST-INSTALLATION TASKS"
    echo ""
    print_warning "IMMEDIATE TASKS (Do these now to verify everything works):"
    echo ""
    print_info "1. TEST SSH CONNECTION:"
    print_info "   - Open a NEW terminal window"
    print_info "   - Connect using: ssh -p ${PORT_MAP[ssh]} root@$(hostname -I | awk '{print $1}')"
    print_info "   - If it fails, you may be locked out! Check the report for details."
    echo ""
    print_info "2. SAVE THIS REPORT SECURELY:"
    print_info "   - Copy this report to a safe location (USB drive, secure email, etc.)"
    print_info "   - The report contains all your custom port configurations"
    print_info "   - Without it, you may forget the SSH port and lose access"
    echo ""
    print_info "3. VERIFY FAIL2BAN IS WORKING:"
    print_info "   - Check status: sudo fail2ban-client status"
    print_info "   - Should show 'sshd' jail active"
    print_info "   - Test with failed SSH attempts (from another machine)"
    echo ""
    print_info "4. TEST KUBERNETES (K3S):"
    print_info "   - Run: k3s kubectl get nodes"
    print_info "   - Should show your server as 'Ready'"
    print_info "   - Test deployment: k3s kubectl run test --image=nginx --port=80"
    echo ""
    print_warning "ONGOING MAINTENANCE TASKS:"
    echo ""
    print_info "6. MONITOR FAIL2BAN:"
    print_info "   - Check status: sudo fail2ban-client status"
    print_info "   - View banned IPs: sudo fail2ban-client status sshd"
    print_info "   - View logs: sudo journalctl -u fail2ban -f"
    print_info "   - Unban legitimate IPs if needed"
    echo ""
    print_info "7. BACKUP CONFIGURATIONS:"
    print_info "   - Port config: /etc/server-ports.conf"
    print_info "   - SSH config: /etc/ssh/sshd_config"
    print_info "   - Fail2Ban: /etc/fail2ban/jail.local"
    print_info "   - k3s: /etc/rancher/k3s/k3s.yaml"
    echo ""
    print_info "8. UPDATE SERVICES:"
    print_info "   - Docker: docker system prune -a (clean unused images)"
    print_info "   - k3s: k3s kubectl get nodes (check cluster health)"
    print_info "   - Fail2Ban: sudo fail2ban-client reload (reload configuration)"
    print_info "   - Unattended upgrades: Check /var/log/unattended-upgrades/"
    print_info "   - System: apt update && apt upgrade (manual updates)"
    echo ""
    print_info "9. MONITOR SYSTEM HEALTH:"
    print_info "   - Check services: systemctl status <service>"
    print_info "   - View logs: journalctl -u <service>"
    print_info "   - Disk usage: df -h"
    print_info "   - Memory: free -h"
    echo ""
    print_info "10. SECURITY AUDIT:"
    print_info "    - Review UFW rules: sudo ufw status verbose"
    print_info "    - Check Fail2Ban status: sudo fail2ban-client status"
    print_info "    - Check for failed SSH attempts: sudo journalctl -u ssh"
    print_info "    - Verify SSH key fingerprints match known hosts"
    print_info "    - Check SSL certificate expiry: sudo certbot certificates"
    echo ""
    
    if [[ "$DRY_RUN" != true ]]; then
        log "=== Ubuntu Server Setup Completed ==="
    fi
}

# Run main function
main "$@"



#
# TOD INTEGRATE Lynis
#

