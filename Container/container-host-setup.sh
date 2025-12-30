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

# Wizard configuration variables
CERTBOT_EMAIL=""
CERTBOT_DOMAIN=""
CERTBOT_SETUP=false
ORCHESTRATOR_CHOICE="k3s"  # Options: k3s, swarm

# Admin user configuration (enhanced security - no direct root SSH)
ADMIN_USERNAME=""
ADMIN_PASSWORD=""
ADMIN_SSH_KEY=""
RECOVERY_ADMIN_USERNAME="recovery_admin"
RECOVERY_ADMIN_PASSWORD=""
RECOVERY_ADMIN_SSH_KEY=""

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

            # Check if required ports are available (skip if services already installed)
            # This allows re-running the script without failing on port conflicts
            local port_check_failed=false
            for port in "${PORT_MAP[@]}"; do
                if ss -tuln | grep -q ":${port}\b"; then
                    # Port is in use - this is OK if the service is already installed
                    if [[ -f /etc/systemd/system/k3s.service ]] || [[ -f /etc/systemd/system/docker.service ]]; then
                        # Services appear to be installed, skip port check
                        print_info "Port $port in use (service likely already installed - continuing)"
                    else
                        # Port in use but services not installed - this is a problem
                        print_error "Port $port is already in use by another service"
                        port_check_failed=true
                    fi
                fi
            done
            
            if [[ "$port_check_failed" == true ]]; then
                return 1
            fi
            ;;

        "post_install")
            log "Validating system state after installation"

            # Check if critical services are running
            local critical_services=("docker" "ufw")
            
            # Check SSH service (CRITICAL - must be running)
            if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
                : # SSH is running
            else
                print_error "CRITICAL: SSH service is not running!"
                print_error "This will make your server inaccessible!"
                print_error "Check the SSH hardening section above for recovery steps."
                return 1  # Fail validation
            fi
            
            # Add orchestration service based on choice
            if [[ "${ORCHESTRATOR_CHOICE:-k3s}" == "k3s" ]]; then
                critical_services+=("k3s")
            fi
            
            for service in "${critical_services[@]}"; do
                if ! systemctl is-active --quiet "$service" 2>/dev/null; then
                    print_warning "Service $service is not running"
                fi
            done
            
            # Additional check for Docker Swarm
            if [[ "${ORCHESTRATOR_CHOICE:-k3s}" == "swarm" ]]; then
                if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
                    print_warning "Docker Swarm is not active"
                fi
            fi

            # Note: SSH port check is skipped here because SSH hardening happens after this validation
            print_info "SSH hardening will be applied as the final step"
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
    print_color "$YELLOW" "         ⚠ WARNING: $1"
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
    -h, --help               Show this help message and exit
    -v, --version            Show version information and exit
    -y, --yes                Auto-confirm all prompts (use default values)
    -n, --dry-run            Show what would be done without making changes
    -r, --report-only        Generate report without installing anything
    --verbose                Enable verbose output
    --admin-user <username>  Admin username for SSH access (required in auto mode)
    --admin-password <password>  Admin password for sudo (required in auto mode)
    --admin-key <key>        SSH public key for admin user (required in auto mode)
    --recovery-key <key>     SSH public key for recovery admin (optional)
    --ssh-key <key>          DEPRECATED: Use --admin-key instead

${BOLD}EXAMPLES:${NC}
    # Interactive setup
    sudo $SCRIPT_NAME

    # Non-interactive setup with defaults
    sudo $SCRIPT_NAME --yes --admin-user containeruser --admin-password "mypassword" --admin-key "ssh-ed25519 AAAA..."

    # Dry run to see what would be installed
    sudo $SCRIPT_NAME --dry-run

    # Generate report only
    sudo $SCRIPT_NAME --report-only

    # Full automated setup with admin and recovery accounts
    sudo $SCRIPT_NAME --yes --admin-user containeruser --admin-password "mypassword" --admin-key "ssh-ed25519 AAAA..." --recovery-key "ssh-rsa BBBB..."

${BOLD}SERVICES INSTALLED:${NC}
    • Container Platform: k3s (Kubernetes + containerd) OR Docker CE + Swarm
    • Nginx (Web server & reverse proxy for containers)
    • SSHGuard (Brute-force protection)
    • Fail2Ban (Intrusion prevention system)
    • Certbot (SSL certificates via Nginx)
    • UFW (Uncomplicated Firewall)
    • Unattended Upgrades (Automatic security updates)
    • htop (System monitoring)

${BOLD}SECURITY MODEL:${NC}
    • Direct root SSH login is DISABLED (PermitRootLogin no)
    • Admin user required with SSH key authentication and password for sudo
    • Root access via sudo elevation (requires admin password)
    • Optional recovery admin for failsafe access

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
# DOCKER NON-ROOT USER HELPER
# =============================================================================
# Reference: https://docs.docker.com/engine/install/linux-postinstall/

show_docker_nonroot_help() {
    cat << 'EOF'

================================================================================
                    DOCKER WITHOUT SUDO - COMPREHENSIVE GUIDE
================================================================================

This script configures Docker to run without sudo by adding admin users to the
docker group. This guide explains how it works, the security implications, and
how to troubleshoot issues.

1. HOW DOCKER WITHOUT SUDO WORKS
================================================================================

The Docker daemon runs as root and binds to a Unix socket at /var/run/docker.sock

Default Socket Permissions:
  - Owner: root:root
  - Permission: 660 (rw-rw----)
  
To run docker commands without sudo, the socket needs to be accessible to users.
This is achieved by:
  
  a) Creating a docker group
  b) Making the socket owned by root:docker (done by Docker automatically)
  c) Adding users to the docker group
  
When a user is in the docker group, they can access the socket and interact with
the Docker daemon without using sudo.

Socket Location:
  - /var/run/docker.sock (Unix socket for local connections)

2. SECURITY IMPLICATIONS
================================================================================

⚠️  WARNING: Docker group membership grants root-level privileges! ⚠️

Why? Because users in the docker group can:
  - Run ANY container with ANY privileges
  - Mount host volumes with unrestricted access
  - Access the Docker API without authentication
  - Effectively escalate to root without password

Example attack vector:
  docker run -v /etc:/etc -it ubuntu bash
  # User now has access to /etc on the host as root!

ONLY add trusted users to the docker group.
Reference: https://docs.docker.com/engine/security/#docker-daemon-attack-surface

3. SETUP PROCESS (Done by this script)
================================================================================

Step 1: Create docker group
  $ sudo groupadd docker

Step 2: Add user to docker group
  $ sudo usermod -aG docker <username>

Step 3: Verify group membership
  $ groups <username>
  # Should show: ... docker ...

Step 4: Activate group membership
  - Option A: Logout and login again
  - Option B: Run in current session: newgrp docker
  - Option C: Start new shell: su - <username>

Step 5: Verify docker access
  $ docker run hello-world
  # Should work without sudo

4. ACTIVATING DOCKER GROUP MEMBERSHIP
================================================================================

After this script completes, the user is added to the docker group, but
the change won't take effect until the group membership is re-evaluated.

Option 1: Log out and log back in (recommended)
  $ exit  # Exit SSH session
  # Log back in with SSH

Option 2: Activate in current session
  $ newgrp docker
  # Shell subprocess with docker group membership
  $ docker ps  # Should work now
  $ exit       # Return to original shell

Option 3: Use sudo to run as user with docker group
  $ sudo -u <username> newgrp docker
  $ docker ps

5. TROUBLESHOOTING PERMISSION ERRORS
================================================================================

Problem: "Got permission denied while trying to connect to the Docker daemon"
Error: "permission denied while trying to connect to Docker daemon socket"

Cause: User is not in docker group or membership hasn't been activated.

Solution:

  a) Verify user is in docker group:
    $ id <username>
    # Should show "groups=...,docker"

  b) Activate group membership if needed:
    $ newgrp docker
    $ docker ps

  c) Logout and login again:
    $ exit
    # SSH back in and try again

  d) Check socket permissions:
    $ ls -la /var/run/docker.sock
    # Should show: srw-rw---- 1 root docker

Problem: "WARNING: Error loading config file: ~/.docker/config.json permission denied"

Cause: ~/.docker directory has wrong permissions from previous sudo usage.

Solution:

  Option 1: Remove the directory (will be recreated):
    $ rm -r ~/.docker

  Option 2: Fix permissions:
    $ sudo chown "$USER":"$USER" ~/.docker -R
    $ sudo chmod g+rwx ~/.docker -R

6. VERIFY INSTALLATION
================================================================================

Test that docker works without sudo:

  $ docker run hello-world
  
  # Output should include:
  # "Hello from Docker!
  #  This message shows that your installation appears to be working correctly."

Check docker daemon socket:

  $ ls -la /var/run/docker.sock
  # Should show: srw-rw---- 1 root docker

Check group membership:

  $ groups $USER
  # Should include: docker

7. BEST PRACTICES
================================================================================

Security:
  ✓ Only add trusted users to docker group
  ✓ Consider using Rootless Docker for untrusted environments
  ✓ Review running containers regularly
  ✓ Use strong container image sources

Monitoring:
  ✓ Monitor docker socket access
  ✓ Check docker logs: journalctl -u docker
  ✓ Review running containers: docker ps

Maintenance:
  ✓ Keep Docker and images updated
  ✓ Remove unused images: docker image prune
  ✓ Remove unused containers: docker container prune
  ✓ Monitor disk usage: docker system df

8. REFERENCES
================================================================================

Official Documentation:
  https://docs.docker.com/engine/install/linux-postinstall/

Docker Security:
  https://docs.docker.com/engine/security/

Rootless Docker (alternative approach):
  https://docs.docker.com/engine/security/rootless/

Linux Post-Installation:
  https://docs.docker.com/engine/install/linux-postinstall/

================================================================================
EOF
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
        ORCHESTRATOR_CHOICE="k3s"
        if [[ -z "$ADMIN_USERNAME" ]]; then
            print_error "Admin username required in auto-yes mode. Use --admin-user option."
            exit 1
        fi
        if [[ -z "$ADMIN_PASSWORD" ]]; then
            print_error "Admin password required in auto-yes mode. Use --admin-password option."
            exit 1
        fi
        return
    fi
    
    # Admin User Configuration
    echo ""
    print_step "Admin User Configuration"
    echo ""
    print_error "⚠️  CRITICAL SECURITY WARNING ⚠️"
    print_error "Direct root SSH login will be DISABLED after setup!"
    print_error "You MUST have SSH keys ready - no password access will be possible!"
    echo ""
    print_warning "SECURITY: Direct root SSH login will be DISABLED!"
    print_info "You need to create a non-root admin user for server management."
    print_info "This user will have sudo access for elevated operations."
    print_info "SSH key authentication is REQUIRED - prepare your public key now."
    echo ""
    
    while true; do
        read -r -p "$(echo -e "${CYAN}Enter username for non-root admin user: ${NC}")" admin_name
        if [[ -z "$admin_name" ]]; then
            print_warning "Admin username is required."
        elif [[ "$admin_name" == "root" ]]; then
            print_warning "Cannot use 'root' as admin username. Choose a different name."
        elif [[ ! "$admin_name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            print_warning "Invalid username. Use lowercase letters, numbers, underscore, or hyphen."
        elif [[ ${#admin_name} -gt 32 ]]; then
            print_warning "Username too long. Maximum 32 characters."
        else
            ADMIN_USERNAME="$admin_name"
            print_success "Admin username set: $ADMIN_USERNAME"
            break
        fi
    done
    
    # Admin Password
    echo ""
    print_info "Set a strong password for the admin user."
    print_info "This password will be required for sudo operations."
    echo ""
    
    while true; do
        read -r -s -p "$(echo -e "${CYAN}Enter password for $ADMIN_USERNAME: ${NC}")" admin_pass
        echo ""
        read -r -s -p "$(echo -e "${CYAN}Confirm password: ${NC}")" admin_pass_confirm
        echo ""
        
        if [[ -z "$admin_pass" ]]; then
            print_warning "Password cannot be empty."
        elif [[ "$admin_pass" != "$admin_pass_confirm" ]]; then
            print_warning "Passwords do not match. Try again."
        elif [[ ${#admin_pass} -lt 8 ]]; then
            print_warning "Password must be at least 8 characters long."
        else
            ADMIN_PASSWORD="$admin_pass"
            print_success "Admin password set"
            break
        fi
    done
    
    # Orchestrator Choice
    echo ""
    print_step "Container Platform Selection"
    echo ""
    print_info "Choose your container platform (mutually exclusive installations):"
    print_info "1) k3s (Lightweight Kubernetes) - Uses containerd runtime"
    print_info "2) Docker Swarm - Uses Docker CE runtime + Swarm orchestration"
    echo ""
    print_info "k3s is recommended for most users. Both provide container orchestration."
    echo ""
    
    while true; do
        read -r -p "$(echo -e "${CYAN}Select orchestration platform [1-2] (default: 1): ${NC}")" orchestrator_choice
        case "${orchestrator_choice:-1}" in
            1|k3s|kubernetes)
                ORCHESTRATOR_CHOICE="k3s"
                print_success "Selected: k3s (Lightweight Kubernetes)"
                break
                ;;
            2|swarm|docker-swarm)
                ORCHESTRATOR_CHOICE="swarm"
                print_success "Selected: Docker Swarm"
                break
                ;;
            *)
                print_warning "Invalid choice. Please select 1 or 2."
                ;;
        esac
    done
    
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
        
        # Validate no port conflicts
        if [[ "${PORT_MAP[ssh]}" == "${PORT_MAP[k3s_api]}" ]]; then
            print_error "Port conflict detected in $PORT_CONFIG_FILE!"
            print_error "SSH and k3s API cannot use the same port (${PORT_MAP[ssh]})"
            print_error ""
            print_error "Fixing automatically: Setting k3s API to default port 6443"
            PORT_MAP[k3s_api]="$DEFAULT_K3S_API_PORT"
            
            # Update the config file
            sed -i "s/^K3S_API_PORT=.*/K3S_API_PORT=${DEFAULT_K3S_API_PORT}/" "$PORT_CONFIG_FILE"
            print_success "Port conflict resolved. k3s API port set to ${DEFAULT_K3S_API_PORT}"
        fi
        
        return 0
    fi
    return 1
}

# =============================================================================
# SSH HARDENING FUNCTIONS
# =============================================================================

setup_ssh_key() {
    # Note: Primary SSH key setup is now handled in setup_admin_user()
    # This function preserves any existing root SSH keys for migration purposes
    # but root login will be disabled via PermitRootLogin no
    
    local ssh_dir="/root/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    
    print_step "Checking existing root SSH configuration..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would check for existing root SSH keys"
        return
    fi
    
    # Ensure .ssh directory exists (for existing keys)
    if [[ -d "$ssh_dir" ]]; then
        chmod 700 "$ssh_dir"
    fi
    
    # Preserve existing keys but warn that root login is disabled
    if [[ -f "$auth_keys" ]] && [[ -s "$auth_keys" ]]; then
        chmod 600 "$auth_keys"
        print_warning "Existing root SSH keys found. Note: Direct root SSH login will be DISABLED."
        print_info "Use the admin user ($ADMIN_USERNAME) and 'sudo -i' for root access."
    fi
    
    log "Root SSH key check completed - root login will be disabled"
}

# =============================================================================
# ADMIN USER SETUP FUNCTIONS
# =============================================================================

setup_admin_user() {
    print_header "ADMIN USER SETUP"
    
    if [[ -z "$ADMIN_USERNAME" ]]; then
        print_error "Admin username not configured!"
        exit 1
    fi
    
    local admin_user="$ADMIN_USERNAME"
    local ssh_dir="/home/$admin_user/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    
    print_step "Creating container admin user: $admin_user"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create admin user: $admin_user"
        print_info "[DRY-RUN] Would add user to docker group"
        print_info "[DRY-RUN] Would configure sudo access"
        print_info "[DRY-RUN] Would set up SSH key authentication"
        return
    fi
    
    # Check if user already exists
    if id "$admin_user" &>/dev/null; then
        print_warning "User $admin_user already exists"
    else
        # Create user with home directory
        useradd -m -s /bin/bash "$admin_user"
        print_success "Created user: $admin_user"
        
        # Set password for sudo access
        if [[ -n "$ADMIN_PASSWORD" ]]; then
            echo "$admin_user:$ADMIN_PASSWORD" | chpasswd
            print_success "Set password for $admin_user"
        fi
    fi
    
    # Add user to docker group for container management (non-root docker access)
    # ========================================================================
    # Security Note: Docker group membership grants root-level privileges
    # because the docker socket is owned by root and accessible by the group.
    # See: https://docs.docker.com/engine/security/#docker-daemon-attack-surface
    # 
    # How it works:
    # - Docker daemon binds to /var/run/docker.sock (Unix socket)
    # - Socket is owned by root:docker
    # - Users in docker group can interact with the socket
    # - This effectively grants root access without requiring password
    # 
    # Usage:
    # - Members can run: docker ps, docker run, etc. without sudo
    # - Must log out and back in (or use 'newgrp docker') to activate
    # ========================================================================
    
    if getent group docker &>/dev/null; then
        usermod -aG docker "$admin_user"
        print_success "Added $admin_user to docker group (non-root docker access)"
    else
        print_warning "Docker group does not exist. Please run install_docker first."
    fi
    
    # Add user to sudo group
    usermod -aG sudo "$admin_user"
    print_success "Added $admin_user to sudo group"
    
    # Configure passwordless sudo for the admin user (optional, more secure with password)
    # For now, we'll require password for sudo - user can configure passwordless if desired
    
    # Create .ssh directory
    mkdir -p "$ssh_dir"
    chown "$admin_user:$admin_user" "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Add SSH key
    if [[ -n "$ADMIN_SSH_KEY" ]]; then
        echo "$ADMIN_SSH_KEY" >> "$auth_keys"
        print_success "Added SSH public key for $admin_user"
    elif [[ "$AUTO_YES" != true ]]; then
        echo ""
        print_warning "SSH key authentication is REQUIRED for $admin_user!"
        print_info "Direct root login will be DISABLED."
        print_info "You MUST add your SSH public key now."
        echo ""
        
        read -r -p "$(echo -e "${CYAN}Paste SSH public key for $admin_user: ${NC}")" user_key
        
        if [[ -n "$user_key" ]]; then
            echo "$user_key" >> "$auth_keys"
            ADMIN_SSH_KEY="$user_key"
            print_success "Added SSH public key"
        else
            print_error "SSH key is REQUIRED. Cannot proceed without it."
            print_error "Direct root login will be disabled - you need an admin user key!"
            exit 1
        fi
    else
        print_error "Admin SSH key required in auto-yes mode. Use --admin-key option."
        exit 1
    fi
    
    # Set proper permissions on authorized_keys
    if [[ -f "$auth_keys" ]]; then
        chown "$admin_user:$admin_user" "$auth_keys"
        chmod 600 "$auth_keys"
    fi
    
    # Fix permission issues from previous sudo usage with docker CLI
    # ================================================================
    # If user ran 'docker' commands with sudo before being added to docker group,
    # the ~/.docker directory may have incorrect permissions.
    # See: https://docs.docker.com/engine/install/linux-postinstall/
    print_step "Docker config permissions for $admin_user (from previous sudo usage)..."
    
    local docker_config="/home/$admin_user/.docker"
    if [[ -d "$docker_config" ]]; then
        # Fix ownership and permissions
        chown "$admin_user:$admin_user" "$docker_config" -R
        chmod g+rwx "$docker_config" -R
        print_success "Fixed Docker config permissions"
    fi
    
    # Print docker setup instructions
    echo ""
    print_header "DOCKER NON-ROOT USER SETUP FOR $admin_user"
    print_info "Docker group has been added. To activate docker access:"
    print_info ""
    print_info "OPTION 1: Logout and login again"
    print_info "  - Exit SSH session"
    print_info "  - Log back in to activate group membership"
    print_info ""
    print_info "OPTION 2: Activate immediately in current session"
    print_info "  - Run: newgrp docker"
    print_info ""
    print_info "VERIFY: Test docker access"
    print_info "  - Run: docker run hello-world"
    print_info ""
    print_warning "SECURITY WARNING:"
    print_warning "Adding user to docker group grants root-level privileges!"
    print_warning "Only add trusted users. Members can escalate to root."
    print_info ""
    print_info "Reference: https://docs.docker.com/engine/install/linux-postinstall/"
    echo ""
    
    log "Admin user $admin_user setup completed with docker group access configured"
    print_success "Admin user $admin_user configured successfully"
}

setup_recovery_admin() {
    print_header "RECOVERY ADMIN SETUP"
    
    local recovery_user="$RECOVERY_ADMIN_USERNAME"
    local ssh_dir="/home/$recovery_user/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    
    print_step "Creating recovery admin user: $recovery_user"
    print_info "This is a failsafe account in case the primary admin is compromised."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create recovery admin: $recovery_user"
        print_info "[DRY-RUN] Would configure sudo access"
        print_info "[DRY-RUN] Would set up SSH key authentication"
        return
    fi
    
    if [[ "$AUTO_YES" == true ]] && [[ -z "$RECOVERY_ADMIN_SSH_KEY" ]]; then
        print_warning "Skipping recovery admin in auto-yes mode (no key provided)"
        return
    fi
    
    # Check if user already exists
    if id "$recovery_user" &>/dev/null; then
        print_warning "User $recovery_user already exists"
    else
        # Create user with home directory, no password (SSH key only)
        useradd -m -s /bin/bash "$recovery_user"
        print_success "Created recovery user: $recovery_user"
    fi
    
    # Add user to docker group for container management
    if getent group docker &>/dev/null; then
        usermod -aG docker "$recovery_user"
        print_success "Added $recovery_user to docker group"
    fi
    
    # Add user to sudo group
    usermod -aG sudo "$recovery_user"
    print_success "Added $recovery_user to sudo group"
    
    # Create .ssh directory
    mkdir -p "$ssh_dir"
    chown "$recovery_user:$recovery_user" "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Add SSH key
    if [[ -n "$RECOVERY_ADMIN_SSH_KEY" ]]; then
        echo "$RECOVERY_ADMIN_SSH_KEY" >> "$auth_keys"
        print_success "Added SSH public key for $recovery_user"
    elif [[ "$AUTO_YES" != true ]]; then
        echo ""
        print_info "Recovery admin provides a backup access method."
        print_info "Use a DIFFERENT SSH key than your primary admin."
        print_info "Store this key securely offline."
        echo ""
        
        if confirm "Do you want to set up a recovery admin account?"; then
            read -r -p "$(echo -e "${CYAN}Paste SSH public key for recovery admin: ${NC}")" recovery_key
            
            if [[ -n "$recovery_key" ]]; then
                echo "$recovery_key" >> "$auth_keys"
                RECOVERY_ADMIN_SSH_KEY="$recovery_key"
                print_success "Added recovery SSH public key"
            else
                print_warning "No recovery key provided. Skipping recovery admin setup."
                # Remove the user if no key provided
                userdel -r "$recovery_user" 2>/dev/null || true
                return
            fi
        else
            print_info "Skipping recovery admin setup"
            # Remove the user if not wanted
            userdel -r "$recovery_user" 2>/dev/null || true
            return
        fi
    fi
    
    # Set proper permissions on authorized_keys
    if [[ -f "$auth_keys" ]]; then
        chown "$recovery_user:$recovery_user" "$auth_keys"
        chmod 600 "$auth_keys"
    fi
    
    log "Recovery admin $recovery_user setup completed"
    print_success "Recovery admin $recovery_user configured successfully"
}

harden_ssh() {
    print_header "SSH HARDENING"
    
    local sshd_config="/etc/ssh/sshd_config"
    local ssh_port="${PORT_MAP[ssh]}"
    
    print_step "Hardening SSH configuration..."
    
    # Check for existing root SSH keys (migration purposes only)
    setup_ssh_key
    
    # Backup original config
    backup_file "$sshd_config"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would modify $sshd_config with:"
        print_info "  - Port: $ssh_port"
        print_info "  - PermitRootLogin: no (DISABLED - use admin user + sudo)"
        print_info "  - PasswordAuthentication: no"
        print_info "  - PubkeyAuthentication: yes"
        print_info "  - MaxAuthTries: 3"
        print_info "  - LoginGraceTime: 20"
        return
    fi
    
    # Create hardened sshd_config
    print_step "Applying SSH hardening settings..."
    
    # Modify SSH port - remove all existing Port lines first to avoid duplicates
    sed -i '/^Port /d' "$sshd_config"
    sed -i '/^#Port /d' "$sshd_config"
    # Add the new port at the beginning of the file
    sed -i "1i Port $ssh_port" "$sshd_config"
    
    # SECURITY: Completely disable root SSH login
    # Root access is only available via sudo elevation from admin user
    sed -i '/^PermitRootLogin /d' "$sshd_config"
    sed -i '/^#PermitRootLogin /d' "$sshd_config"
    echo "PermitRootLogin no" >> "$sshd_config"
    print_success "Direct root SSH login DISABLED (use admin user + sudo)"
    
    # Disable password authentication
    sed -i '/^PasswordAuthentication /d' "$sshd_config"
    sed -i '/^#PasswordAuthentication /d' "$sshd_config"
    echo "PasswordAuthentication no" >> "$sshd_config"
    
    # Enable public key authentication
    sed -i '/^PubkeyAuthentication /d' "$sshd_config"
    sed -i '/^#PubkeyAuthentication /d' "$sshd_config"
    echo "PubkeyAuthentication yes" >> "$sshd_config"
    
    # Limit authentication attempts
    sed -i '/^MaxAuthTries /d' "$sshd_config"
    sed -i '/^#MaxAuthTries /d' "$sshd_config"
    echo "MaxAuthTries 3" >> "$sshd_config"
    
    # Reduce login grace time
    sed -i '/^LoginGraceTime /d' "$sshd_config"
    sed -i '/^#LoginGraceTime /d' "$sshd_config"
    echo "LoginGraceTime 20" >> "$sshd_config"
    
    # Disable empty passwords
    sed -i '/^PermitEmptyPasswords /d' "$sshd_config"
    sed -i '/^#PermitEmptyPasswords /d' "$sshd_config"
    echo "PermitEmptyPasswords no" >> "$sshd_config"
    
    # Disable X11 forwarding
    sed -i '/^X11Forwarding /d' "$sshd_config"
    sed -i '/^#X11Forwarding /d' "$sshd_config"
    echo "X11Forwarding no" >> "$sshd_config"
    
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
    
    # Restart SSH service (try different service names)
    print_step "Restarting SSH service..."
    
    # Ubuntu 24.04+ uses systemd socket activation by default
    # This overrides the Port setting in sshd_config, so we need to disable it
    print_step "Disabling systemd socket activation (to apply custom SSH port)..."
    if systemctl is-active --quiet ssh.socket 2>/dev/null; then
        systemctl stop ssh.socket 2>/dev/null || true
        systemctl disable ssh.socket 2>/dev/null || true
        print_success "SSH socket activation disabled"
    fi
    
    # Remove socket dependency from SSH service
    if grep -q "Requires=ssh.socket" /etc/systemd/system/ssh.service 2>/dev/null || \
       grep -q "Requires=ssh.socket" /usr/lib/systemd/system/ssh.service 2>/dev/null; then
        print_step "Removing socket dependency from SSH service..."
        mkdir -p /etc/systemd/system
        cp /usr/lib/systemd/system/ssh.service /etc/systemd/system/ssh.service 2>/dev/null || true
        sed -i '/Requires=ssh.socket/d' /etc/systemd/system/ssh.service
        systemctl daemon-reload
        print_success "Socket dependency removed"
    fi
    
    # Try different SSH service names and restart methods
    # Try ssh first (Ubuntu), then sshd (some systems), then service command
    local ssh_restarted=false
    
    if systemctl restart ssh 2>/dev/null; then
        print_success "SSH service (ssh) restarted"
        ssh_restarted=true
    elif systemctl restart sshd 2>/dev/null; then
        print_success "SSH service (sshd) restarted"
        ssh_restarted=true
    elif service ssh restart 2>/dev/null; then
        print_success "SSH service restarted via service command"
        ssh_restarted=true
    fi
    
    # Verify SSH is actually running
    sleep 2
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        print_success "SSH service is confirmed running"
    else
        print_error "CRITICAL: SSH service failed to start!"
        print_error "Your server may become inaccessible!"
        print_error ""
        print_error "IMMEDIATE RECOVERY STEPS:"
        print_error "1. Access server via console/VNC/KVM"
        print_error "2. Check SSH configuration: nano /etc/ssh/sshd_config"
        print_error "3. Test SSH config: sshd -t"
        print_error "4. Start SSH manually: systemctl start ssh"
        print_error "5. If that fails: systemctl start sshd"
        print_error ""
        print_error "The script will continue, but SSH access may not work!"
        print_warning "SAVE THIS MESSAGE - You may need console access to fix SSH!"
        
        # Don't exit - let the script complete so other services can be configured
        # But log this critical error prominently
        log "CRITICAL ERROR: SSH service failed to start after hardening"
    fi
    
    print_success "SSH hardening completed"
    
    # Verify SSH is listening on new port
    print_step "Verifying SSH is listening on port $ssh_port..."
    local retry_count=0
    local max_retries=10
    local ssh_verified=false
    
    while [[ $retry_count -lt $max_retries ]]; do
        if ss -tuln | grep -q ":${ssh_port}\b"; then
            print_success "✓ SSH is listening on port $ssh_port"
            ssh_verified=true
            break
        fi
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            sleep 1
        fi
    done
    
    if [[ "$ssh_verified" != true ]]; then
        print_error "SSH is not listening on port $ssh_port after 10 seconds"
        print_warning "Current SSH listeners:"
        ss -tuln | grep :ssh || ss -tuln | grep :22
        print_info "You may need to manually restart SSH: systemctl restart sshd"
    fi
    
    print_warning "═══════════════════════════════════════════════════════════════"
    print_warning "  CRITICAL: ROOT SSH LOGIN IS NOW DISABLED!"
    print_warning "═══════════════════════════════════════════════════════════════"
    print_warning "Connect as admin user: ssh -p $ssh_port $ADMIN_USERNAME@<server-ip>"
    print_warning "Elevate to root with: sudo -i"
    print_warning "═══════════════════════════════════════════════════════════════"
    
    log "SSH hardening completed - Port: $ssh_port, Root login: disabled, Admin user: $ADMIN_USERNAME"
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
    
    # Create docker group if it doesn't exist
    # Note: Most package managers create this automatically
    print_step "Ensuring docker group exists..."
    if ! getent group docker &>/dev/null; then
        groupadd docker
        print_success "Created docker group"
    else
        print_info "Docker group already exists"
    fi
    
    # Verify installation
    if docker run --rm hello-world &>/dev/null; then
        print_success "Docker installed and working"
    else
        print_warning "Docker installed but test container failed"
    fi
    
    # Print important security and usage information
    echo ""
    print_header "DOCKER NON-ROOT USER ACCESS"
    print_warning "SECURITY NOTE: The docker group grants root-level privileges!"
    print_info "Users in the docker group can escalate to root without a password."
    print_info "Only add trusted users to this group."
    print_info ""
    print_info "Reference: https://docs.docker.com/engine/security/#docker-daemon-attack-surface"
    echo ""
    print_info "To enable non-root docker access for users:"
    print_info "  1. User must be added to docker group (done during admin setup)"
    print_info "  2. User must log out and log back in to activate group membership"
    print_info "  3. Or activate immediately: newgrp docker"
    print_info ""
    print_info "Verify docker access: docker run hello-world"
    print_info ""
    print_info "Fix permission issues from previous sudo usage:"
    print_info "  - Remove ~/.docker: rm -r ~/.docker"
    print_info "  - Or fix permissions: sudo chown \$USER:\$USER ~/.docker -R && chmod g+rwx ~/.docker -R"
    echo ""
    
    docker --version
    log "Docker installation completed with docker group configured"
}

# =============================================================================
# K3S INSTALLATION
# =============================================================================

install_k3s() {
    print_header "K3S INSTALLATION"
    
    local k3s_port="${PORT_MAP[k3s_api]}"
    local ssh_port="${PORT_MAP[ssh]}"
    
    # Critical: Check for port conflicts
    if [[ "$k3s_port" == "$ssh_port" ]]; then
        print_error "CRITICAL: k3s port ($k3s_port) conflicts with SSH port ($ssh_port)!"
        print_error "This is likely due to a configuration error."
        print_error ""
        print_error "RECOVERY STEPS:"
        print_error "1. Check port configuration: cat /etc/server-ports.conf"
        print_error "2. Fix the k3s API port (should be 6443 or custom port != SSH port)"
        print_error "3. Edit: sudo nano /etc/server-ports.conf"
        print_error "4. Set: K3S_API_PORT=6443 (or another available port)"
        print_error "5. Re-run this script"
        print_error ""
        log "ERROR: k3s installation failed - port conflict with SSH ($k3s_port)"
        return 1
    fi
    
    if command_exists k3s; then
        print_info "k3s is already installed"
        k3s --version
        if ! confirm "Reinstall k3s?"; then
            return
        fi
    fi
    
    print_step "Installing k3s (Lightweight Kubernetes)..."
    print_info "Using custom API port: $k3s_port"
    print_info "SSH port: $ssh_port (must be different from k3s port)"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install k3s with API port $k3s_port"
        return
    fi
    
    # Install k3s with enhanced security settings
    # --https-listen-port: Custom API server port
    # --disable=traefik: Remove default ingress controller (we use Nginx)
    # --write-kubeconfig-mode: Restrict kubeconfig permissions
    # --tls-san: Add additional TLS subject alternative names
    # --kube-apiserver-arg: Additional API server security arguments
    # --kubelet-arg: Additional kubelet security arguments
    # Note: PodSecurityPolicy removed in k8s 1.25+, using Pod Security Admission instead
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
        --https-listen-port=$k3s_port \
        --disable=traefik \
        --write-kubeconfig-mode=600 \
        --tls-san=$(hostname -I | awk '{print $1}') \
        --kube-apiserver-arg=--enable-admission-plugins=NodeRestriction \
        --kube-apiserver-arg=--audit-log-path=/var/log/k3s-audit.log \
        --kube-apiserver-arg=--audit-log-maxage=30 \
        --kube-apiserver-arg=--audit-log-maxbackup=10 \
        --kube-apiserver-arg=--audit-log-maxsize=100 \
        --kube-apiserver-arg=--service-account-lookup=true \
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
    
    # Apply Pod Security Standards using Pod Security Admission (replaces deprecated PodSecurityPolicy)
    # PSA uses namespace labels instead of cluster-wide policies
    print_step "Applying Pod Security Standards (Pod Security Admission)..."
    
    # Label the default namespace with restricted security standard
    k3s kubectl label --overwrite namespace default \
        pod-security.kubernetes.io/enforce=restricted \
        pod-security.kubernetes.io/enforce-version=latest \
        pod-security.kubernetes.io/warn=restricted \
        pod-security.kubernetes.io/warn-version=latest \
        pod-security.kubernetes.io/audit=restricted \
        pod-security.kubernetes.io/audit-version=latest
    
    print_success "k3s installation and security hardening completed"
    print_info "Kubernetes API available on port $k3s_port"
    print_info "Audit logs: /var/log/k3s-audit.log"
    print_info "Network policies applied (default deny)"
    print_info "Pod Security Admission enabled (restricted profile)"
    
    log "k3s installation completed with enhanced security - API Port: $k3s_port"
}

# =============================================================================
# DOCKER SWARM SETUP
# =============================================================================

setup_docker_swarm() {
    print_header "DOCKER SWARM SETUP"
    
    # Check if already in swarm mode
    if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
        print_info "Docker Swarm is already initialized"
        docker node ls 2>/dev/null || print_info "Swarm status: $(docker info --format '{{.Swarm.LocalNodeState}}')"
        if ! confirm "Reinitialize Docker Swarm?"; then
            return
        fi
        
        # Leave existing swarm
        print_step "Leaving existing swarm..."
        if [[ "$DRY_RUN" != true ]]; then
            run_cmd "docker swarm leave --force" "Leave existing swarm"
        else
            print_info "[DRY-RUN] Would leave existing swarm"
        fi
    fi
    
    print_step "Initializing Docker Swarm..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would initialize Docker Swarm cluster"
        print_info "[DRY-RUN] Would configure Swarm security settings"
        return
    fi
    
    # Get primary network interface IP
    local primary_ip
    primary_ip=$(hostname -I | awk '{print $1}')
    
    # Initialize swarm with security settings
    print_info "Initializing swarm on IP: $primary_ip"
    run_cmd "docker swarm init --advertise-addr $primary_ip --data-path-port 4789" "Initialize Docker Swarm"
    
    # Configure swarm security settings
    print_step "Configuring Swarm security settings..."
    
    # Set up swarm network with encryption
    print_step "Creating encrypted overlay network..."
    run_cmd "docker network create --driver overlay --opt encrypted secure-network" "Create encrypted overlay network"
    
    # Create a basic service constraint for security
    print_step "Applying Swarm security configurations..."
    
    # Update swarm with security settings
    run_cmd "docker swarm update --cert-expiry 2160h --dispatcher-heartbeat 30s" "Update Swarm security settings"
    
    # Create manager-only network for sensitive services
    run_cmd "docker network create --driver overlay --attachable --opt encrypted manager-network" "Create manager network"
    
    # Display swarm status and join token
    print_success "Docker Swarm initialized successfully"
    print_info "Swarm Manager IP: $primary_ip"
    print_info "Encrypted networks created: secure-network, manager-network"
    
    # Show join token for workers (useful for adding nodes later)
    echo ""
    print_info "To add worker nodes to this swarm, run the following command on the worker nodes:"
    echo ""
    docker swarm join-token worker | grep -A1 "docker swarm join"
    echo ""
    
    print_info "To add manager nodes to this swarm, run:"
    echo ""
    docker swarm join-token manager | grep -A1 "docker swarm join"
    echo ""
    
    # Create basic monitoring stack
    print_step "Setting up basic Swarm monitoring..."
    
    # Create monitoring directory
    mkdir -p /opt/swarm-monitoring
    
    # Create a basic monitoring service (Portainer for Swarm management)
    cat > /opt/swarm-monitoring/portainer-stack.yml << 'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - manager-network
    deploy:
      placement:
        constraints: [node.role == manager]
      restart_policy:
        condition: on-failure

volumes:
  portainer_data:

networks:
  manager-network:
    external: true
EOF
    
    # Deploy monitoring stack
    print_step "Deploying Swarm management interface..."
    run_cmd "docker stack deploy -c /opt/swarm-monitoring/portainer-stack.yml monitoring" "Deploy Portainer management interface"
    
    # Show swarm status
    print_step "Swarm cluster status:"
    docker node ls
    docker network ls | grep -E "(overlay|swarm)"
    
    print_success "Docker Swarm setup completed"
    print_info "Swarm management interface available on port 9000"
    print_info "Encrypted overlay networks configured"
    print_info "Security settings applied"
    
    log "Docker Swarm initialization completed - Manager IP: $primary_ip"
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
# NGINX INSTALLATION
# =============================================================================

install_nginx() {
    print_header "NGINX INSTALLATION"
    
    if command_exists nginx; then
        print_info "Nginx is already installed"
        nginx -v
        if ! confirm "Reinstall Nginx?"; then
            return
        fi
    fi
    
    print_step "Installing Nginx..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install Nginx"
        return
    fi
    
    # Install Nginx
    run_cmd "apt-get update"
    run_cmd "apt-get install -y nginx"
    
    # Create default landing page to ensure port 80 is responsive
    print_step "Configuring Nginx default site..."
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Server Ready</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 2rem;
        }
        h1 { font-size: 3rem; margin: 0; }
        p { font-size: 1.2rem; margin: 1rem 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>✓ Server is Ready</h1>
        <p>Nginx is running and ready to serve containers</p>
        <p><small>Configure your container routing in Nginx</small></p>
    </div>
</body>
</html>
EOF
    
    # Configure Nginx for container routing (basic template)
    print_step "Creating Nginx configuration template..."
    cat > /etc/nginx/sites-available/container-router << 'EOF'
# Nginx Container Router Configuration
# This file is a template for routing to container services

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    # Default location - landing page
    location / {
        root /var/www/html;
        index index.html;
    }
    
    # Example: Route to container on port 8080
    # Uncomment and modify as needed:
    # location /myapp {
    #     proxy_pass http://localhost:8080;
    #     proxy_set_header Host $host;
    #     proxy_set_header X-Real-IP $remote_addr;
    #     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #     proxy_set_header X-Forwarded-Proto $scheme;
    # }
    
    # Health check endpoint for monitoring
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Enable the configuration
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/container-router /etc/nginx/sites-enabled/
    
    # Test Nginx configuration
    print_step "Testing Nginx configuration..."
    if nginx -t; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration validation failed!"
        return 1
    fi
    
    # Start and enable Nginx
    run_cmd "systemctl enable nginx"
    run_cmd "systemctl restart nginx"
    
    # Verify Nginx is running
    if systemctl is-active --quiet nginx; then
        print_success "Nginx installed and running on port 80"
    else
        print_warning "Nginx installed but not running"
    fi
    
    print_success "Nginx installation completed"
    print_info "Default page available at http://$(hostname -I | awk '{print $1}')"
    print_info "Configuration: /etc/nginx/sites-available/container-router"
    
    log "Nginx installation completed"
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
    
    # Install Certbot with Nginx plugin
    run_cmd "apt-get update"
    run_cmd "apt-get install -y certbot python3-certbot-nginx"
    
    # Get SSL certificate
    print_step "Obtaining SSL certificate for $CERTBOT_DOMAIN..."
    
    # Get server IP for validation
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    print_info "Note: Domain must point to this server IP ($server_ip) and port 80 must be accessible"
    
    # Check if domain resolves to this server
    local domain_ip
    domain_ip=$(dig +short "$CERTBOT_DOMAIN" | head -1)
    if [[ -z "$domain_ip" ]]; then
        print_warning "Domain $CERTBOT_DOMAIN does not resolve to any IP address"
        print_warning "DNS may not be configured yet. Certificate obtaining will fail."
        print_warning "Update DNS to point to $server_ip, then run:"
        print_warning "  sudo certbot --nginx -d $CERTBOT_DOMAIN"
        print_warning "Skipping certificate obtaining for now..."
        return
    elif [[ "$domain_ip" != "$server_ip" ]]; then
        print_warning "Domain $CERTBOT_DOMAIN resolves to $domain_ip, not this server ($server_ip)"
        print_warning "Certificate obtaining will likely fail. Update DNS first, then run:"
        print_warning "  sudo certbot --nginx -d $CERTBOT_DOMAIN"
        print_warning "Skipping certificate obtaining for now..."
        return
    fi
    
    # Ensure Nginx is running for Certbot validation
    if ! systemctl is-active --quiet nginx; then
        print_warning "Nginx is not running. Starting Nginx for certificate validation..."
        systemctl start nginx || print_error "Failed to start Nginx"
    fi
    
    # Create Nginx configuration for the domain
    print_step "Creating Nginx configuration for $CERTBOT_DOMAIN..."
    cat > /etc/nginx/sites-available/$CERTBOT_DOMAIN << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $CERTBOT_DOMAIN;
    
    root /var/www/html;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Allow Let's Encrypt validation
    location ~ /.well-known {
        allow all;
    }
}
EOF
    
    # Enable the domain configuration
    ln -sf /etc/nginx/sites-available/$CERTBOT_DOMAIN /etc/nginx/sites-enabled/
    
    # Test and reload Nginx
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        print_success "Nginx configured for $CERTBOT_DOMAIN"
    else
        print_warning "Nginx configuration test failed"
    fi
    
    # Obtain certificate using Nginx plugin (automatically configures SSL)
    if certbot --nginx -d "$CERTBOT_DOMAIN" --email "$CERTBOT_EMAIL" --agree-tos --non-interactive --redirect; then
        print_success "SSL certificate obtained successfully"
        
        # Configure automatic renewal
        print_step "Setting up automatic certificate renewal..."
        (crontab -l 2>/dev/null || true; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        
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
        print_success "Nginx automatically configured with SSL for $CERTBOT_DOMAIN"
        print_info "HTTPS is now available at: https://$CERTBOT_DOMAIN"
        
    else
        print_error "Failed to obtain SSL certificate for $CERTBOT_DOMAIN"
        print_warning "This is normal if:"
        print_warning "  - DNS is not yet updated to point to this server"
        print_warning "  - Port 80 is blocked by upstream firewall"
        print_warning "  - Domain is behind a CDN or proxy"
        echo ""
        print_info "You can try manually later with:"
        print_info "  sudo certbot --nginx -d $CERTBOT_DOMAIN --email $CERTBOT_EMAIL"
        print_info "Or use DNS challenge if port 80 is blocked:"
        print_info "  sudo certbot certonly --manual --preferred-challenges dns -d $CERTBOT_DOMAIN"
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
        echo "SECURITY MODEL: Root SSH login is DISABLED"
        echo "Use the admin user and sudo for root access."
        echo ""
        echo "Admin User:      ${ADMIN_USERNAME:-not configured}"
        if [[ -n "$RECOVERY_ADMIN_SSH_KEY" ]]; then
            echo "Recovery Admin:  $RECOVERY_ADMIN_USERNAME"
        fi
        echo ""
        echo "SSH Connection:"
        echo "  ssh -p ${PORT_MAP[ssh]:-22} ${ADMIN_USERNAME:-admin}@$server_ip"
        echo ""
        echo "Get Root Shell:"
        echo "  sudo -i"
        echo ""
        echo "Fail2Ban Status:"
        echo "  sudo fail2ban-client status"
        echo ""
        
        if [[ "${ORCHESTRATOR_CHOICE:-k3s}" == "k3s" ]]; then
            echo "Kubernetes (k3s):"
            echo "  kubectl --server=https://$server_ip:${PORT_MAP[k3s_api]:-6443} get nodes"
            echo "  KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes"
        elif [[ "${ORCHESTRATOR_CHOICE}" == "swarm" ]]; then
            echo "Docker Swarm:"
            echo "  docker node ls"
            echo "  docker service ls"
            echo "  docker stack ls"
            echo "  Management UI: http://$server_ip:9000 (Portainer)"
        fi
        echo ""
        
        echo "==============================================================================="
        echo "                         SERVICE STATUS"
        echo "==============================================================================="
        echo ""
        printf "%-25s %s\n" "Service" "Status"
        printf "%-25s %s\n" "-------------------------" "------------"
        
        for service in sshd nginx docker k3s sshguard fail2ban ufw unattended-upgrades; do
            local status
            if [[ "$service" == "sshd" ]]; then
                # Special handling for SSH service (try both names)
                if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
                    status="✓ Active"
                elif systemctl is-enabled --quiet sshd 2>/dev/null || systemctl is-enabled --quiet ssh 2>/dev/null; then
                    status="○ Enabled (not running)"
                else
                    status="✗ CRITICAL - Not running!"
                fi
            elif systemctl is-active --quiet "$service" 2>/dev/null; then
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
        echo "Container Orchestration:"
        echo "  Selected: ${ORCHESTRATOR_CHOICE:-k3s}"
        if [[ "${ORCHESTRATOR_CHOICE:-k3s}" == "k3s" ]]; then
            k3s --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  k3s: Not installed"
        elif [[ "${ORCHESTRATOR_CHOICE}" == "swarm" ]]; then
            docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | sed 's/^/  Docker Swarm: /' || echo "  Docker Swarm: Not active"
            docker node ls 2>/dev/null | wc -l | awk '{print "  Swarm nodes: " $1}' 2>/dev/null || echo "  Swarm nodes: 0"
        fi
        echo ""
        echo "htop (System Monitor):"
        htop --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  Not installed"
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
        
        # Check if SSH is working and add critical warning if not
        if ! systemctl is-active --quiet sshd 2>/dev/null && ! systemctl is-active --quiet ssh 2>/dev/null; then
            echo "🚨 CRITICAL WARNING: SSH SERVICE IS NOT RUNNING! 🚨"
            echo "   Your server may be inaccessible via SSH!"
            echo "   You may need console access to fix this."
            echo "   See SSH recovery steps in the troubleshooting section below."
            echo ""
        fi
        
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
            --admin-user)
                ADMIN_USERNAME="$2"
                shift 2
                ;;
            --admin-password)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --admin-key)
                ADMIN_SSH_KEY="$2"
                shift 2
                ;;
            --recovery-key)
                RECOVERY_ADMIN_SSH_KEY="$2"
                shift 2
                ;;
            --ssh-key)
                # DEPRECATED: kept for backwards compatibility
                print_warning "--ssh-key is deprecated. Use --admin-key instead."
                ADMIN_SSH_KEY="$2"
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
    echo "    ║  Docker • k3s/Swarm • SSHGuard • Fail2Ban • Certbot • UFW • SSH          ║"
    echo "    ║  Hardening • Unattended Upgrades • htop                                  ║"
    echo "    ╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # CRITICAL SECURITY WARNING
    echo ""
    print_error "╔══════════════════════════════════════════════════════════════════════════════╗"
    print_error "║                        ⚠️  SECURITY WARNING ⚠️                               ║"
    print_error "║                                                                              ║"
    print_error "║  This script DISABLES direct root SSH login for security!                    ║"
    print_error "║  You MUST have SSH keys ready before running in non-interactive mode.        ║"
    print_error "║                                                                              ║"
    print_error "║  Required for auto mode: --admin-user <name> --admin-key <key>               ║"
    print_error "║  Interactive mode will prompt for SSH key.                                   ║"
    print_error "║                                                                              ║"
    print_error "║  WITHOUT SSH KEYS: You will be LOCKED OUT of your server!                    ║"
    print_error "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
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
    
    # System updates and essential packages
    print_header "SYSTEM UPDATE & ESSENTIAL PACKAGES"
    print_step "Updating package cache..."
    if [[ "$DRY_RUN" != true ]]; then
        run_cmd "apt-get update" "Update package cache"
    else
        print_info "[DRY-RUN] Would update package cache"
    fi
    
    print_step "Upgrading system packages..."
    if [[ "$DRY_RUN" != true ]]; then
        run_cmd "apt-get upgrade -y" "Upgrade system packages"
    else
        print_info "[DRY-RUN] Would upgrade system packages"
    fi
    
    print_step "Installing essential packages (htop, curl, wget, etc.)..."
    if [[ "$DRY_RUN" != true ]]; then
        run_cmd "apt-get install -y htop curl wget apt-transport-https ca-certificates gnupg lsb-release software-properties-common unzip" "Install essential packages"
    else
        print_info "[DRY-RUN] Would install essential packages (htop, curl, wget, etc.)"
    fi
    
    print_step "Removing unnecessary packages..."
    if [[ "$DRY_RUN" != true ]]; then
        run_cmd "apt-get autoremove -y" "Remove unnecessary packages"
        run_cmd "apt-get autoclean" "Clean package cache"
    else
        print_info "[DRY-RUN] Would remove unnecessary packages and clean cache"
    fi
    
    print_success "System updated and essential packages installed"
    
    # Configure unattended upgrades
    configure_unattended_upgrades
    
    # Install container runtime and orchestration platform based on choice
    case "$ORCHESTRATOR_CHOICE" in
        "k3s")
            print_info "Installing k3s (Kubernetes) with containerd runtime..."
            install_k3s
            ;;
        "swarm")
            print_info "Installing Docker CE + Docker Swarm..."
            install_docker
            setup_docker_swarm
            ;;
        *)
            print_error "Unknown orchestrator choice: $ORCHESTRATOR_CHOICE"
            exit 1
            ;;
    esac
    
    install_sshguard
    install_fail2ban
    
    # Install Nginx for container routing and Certbot SSL validation
    install_nginx
    
    # Setup SSL certificates if configured
    setup_certbot
    
    # Setup admin users (MUST be done before SSH hardening)
    # Admin user is required since we disable root SSH login
    setup_admin_user
    setup_recovery_admin
    
    # Configure firewall (must allow SSH port before hardening)
    configure_ufw
    
    # Generate report (before SSH hardening so root can still access if issues)
    generate_report
    
    # Post-installation system validation (before SSH hardening)
    if [[ "$DRY_RUN" != true ]]; then
        validate_system_state "post_install"
    fi
    
    # Harden SSH (ABSOLUTE LAST STEP - disables root login)
    # This is done at the very end after everything is verified working
    # Root login is disabled - use admin user + sudo from this point forward
    print_header "FINAL STEP: SSH HARDENING"
    print_warning "About to disable root SSH login and switch to port ${PORT_MAP[ssh]}"
    print_warning "Admin user ${ADMIN_USERNAME} must have working SSH key authentication"
    echo ""
    harden_ssh
    
    # Final message
    print_header "SETUP COMPLETE"
    print_success "Ubuntu server setup completed successfully!"
    echo ""
    print_warning "IMPORTANT REMINDERS:"
    echo ""
    print_warning "SECURITY MODEL:"
    print_info "- Direct root SSH login is DISABLED"
    print_info "- SSH port is now: ${PORT_MAP[ssh]}"
    print_info "- Password authentication is DISABLED"
    print_info "- Admin user: $ADMIN_USERNAME"
    echo ""
    print_success "Connect using: ssh -p ${PORT_MAP[ssh]} $ADMIN_USERNAME@$(hostname -I | awk '{print $1}')"
    print_success "Elevate to root: sudo -i"
    echo ""
    print_info "The detailed report has been saved. Keep it secure!"
    print_info "If any issues occur, check for error files:"
    print_info "  - Error details: $ERROR_FILE"
    print_info "  - Debug info: $DEBUG_FILE"
    echo ""
    print_header "POST-INSTALLATION TASKS"
    echo ""
    print_warning "CRITICAL: TEST SSH CONNECTION IMMEDIATELY!"
    echo ""
    print_info "1. TEST SSH CONNECTION (Do this NOW from a new terminal):"
    print_info "   - Open a NEW terminal window (keep this one open!)"
    print_info "   - Connect: ssh -p ${PORT_MAP[ssh]} $ADMIN_USERNAME@$(hostname -I | awk '{print $1}')"
    print_info "   - Test sudo: sudo whoami (should output 'root')"
    print_info "   - Elevate to root: sudo -i"
    print_info "   - If connection fails, DO NOT close this terminal!"
    echo ""
    print_info "2. SAVE THESE DETAILS SECURELY:"
    print_info "   - SSH Port: ${PORT_MAP[ssh]}"
    print_info "   - Admin User: $ADMIN_USERNAME"
    if [[ -n "$RECOVERY_ADMIN_SSH_KEY" ]]; then
        print_info "   - Recovery Admin: $RECOVERY_ADMIN_USERNAME"
    fi
    print_info "   - Copy the report to a secure location (USB drive, password manager, etc.)"
    echo ""
    print_info "3. VERIFY FAIL2BAN IS WORKING:"
    print_info "   - Check status: sudo fail2ban-client status"
    print_info "   - Should show 'sshd' jail active"
    print_info "   - Test with failed SSH attempts (from another machine)"
    echo ""
    if [[ "$ORCHESTRATOR_CHOICE" == "k3s" ]]; then
        print_info "4. TEST KUBERNETES (K3S):"
        print_info "   - Run: sudo k3s kubectl get nodes"
        print_info "   - Should show your server as 'Ready'"
        print_info "   - Test deployment: sudo k3s kubectl run test --image=nginx --port=80"
    else
        print_info "4. TEST DOCKER SWARM:"
        print_info "   - Run: docker node ls"
        print_info "   - Should show your server as 'Leader'"
        print_info "   - Test service: docker service create --name test nginx"
    fi
    echo ""
    print_warning "ROOT ACCESS SECURITY MODEL:"
    echo ""
    print_info "5. HOW TO ACCESS ROOT:"
    print_info "   - Direct root SSH is DISABLED (PermitRootLogin no)"
    print_info "   - SSH in as: $ADMIN_USERNAME"
    print_info "   - Run single command as root: sudo <command>"
    print_info "   - Get root shell: sudo -i"
    print_info "   - Switch to root (from admin): sudo su -"
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
    if [[ "$ORCHESTRATOR_CHOICE" == "k3s" ]]; then
        print_info "   - k3s: /etc/rancher/k3s/k3s.yaml"
    fi
    echo ""
    print_info "8. UPDATE SERVICES:"
    print_info "   - Docker: docker system prune -a (clean unused images)"
    if [[ "$ORCHESTRATOR_CHOICE" == "k3s" ]]; then
        print_info "   - k3s: sudo k3s kubectl get nodes (check cluster health)"
    else
        print_info "   - Swarm: docker node ls (check cluster health)"
    fi
    print_info "   - Fail2Ban: sudo fail2ban-client reload (reload configuration)"
    print_info "   - Unattended upgrades: Check /var/log/unattended-upgrades/"
    print_info "   - System: sudo apt update && sudo apt upgrade (manual updates)"
    echo ""
    print_info "9. MONITOR SYSTEM HEALTH:"
    print_info "   - Check services: sudo systemctl status <service>"
    print_info "   - View logs: sudo journalctl -u <service>"
    print_info "   - Disk usage: df -h"
    print_info "   - Memory: free -h"
    print_info "   - System overview: htop"
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

