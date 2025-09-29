#!/bin/bash

# Package List Installer Script
# Enhanced version with proper error handling and validation
# Author: Improved version
# Version: 2.0

set -euo pipefail

#==============================================================================
# Configuration and Constants
#==============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LISTS_DIR="${SCRIPT_DIR}/lists"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#==============================================================================
# Utility Functions
#==============================================================================

# Print colored output
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

print_error() {
    print_color "$RED" "ERROR: $*" >&2
}

print_success() {
    print_color "$GREEN" "SUCCESS: $*"
}

print_warning() {
    print_color "$YELLOW" "WARNING: $*"
}

print_info() {
    print_color "$BLUE" "INFO: $*"
}

# Show help information
show_help() {
    cat << EOF
$SCRIPT_NAME - Package List Installer

USAGE:
    $SCRIPT_NAME [OPTIONS] LIST_FILE

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show script version
    -y, --yes               Automatic yes to prompts (non-interactive)
    -n, --dry-run          Show what would be installed without installing
    -s, --simulate         Simulate installation (alias for --dry-run)
    -u, --update           Update package cache before installation
    -l, --list-available    List available package lists
    -V, --verbose          Enable verbose output

ARGUMENTS:
    LIST_FILE               Path to package list file

DESCRIPTION:
    This script installs packages from a package list file.
    It validates the list file, checks package availability,
    and provides detailed feedback during installation.

EXAMPLES:
    $SCRIPT_NAME developer.list              # Install packages from developer.list
    $SCRIPT_NAME --dry-run server.list       # Show what would be installed
    $SCRIPT_NAME --update --yes app.list     # Update cache and install automatically
    $SCRIPT_NAME lists/python.list           # Install from specific path

PACKAGE LIST FORMAT:
    Each line should contain one package name.
    Empty lines and lines starting with # are ignored.

EOF
}

# Show script version
show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# List available package lists
list_available_lists() {
    print_info "Available package lists in $LISTS_DIR:"
    if [[ -d "$LISTS_DIR" ]]; then
        find "$LISTS_DIR" -name "*.list" -type f -printf "  %f\n" | sort
    else
        print_warning "Lists directory not found: $LISTS_DIR"
    fi
}

# Validate package list file
validate_list_file() {
    local list_file="$1"
    
    # Check if file exists
    if [[ ! -f "$list_file" ]]; then
        print_error "Package list file not found: $list_file"
        print_info "Available lists:"
        list_available_lists
        return 1
    fi
    
    # Check if file is readable
    if [[ ! -r "$list_file" ]]; then
        print_error "Cannot read package list file: $list_file"
        return 1
    fi
    
    # Check if file is not empty
    if [[ ! -s "$list_file" ]]; then
        print_warning "Package list file is empty: $list_file"
        return 1
    fi
    
    return 0
}

# Parse package list file
parse_package_list() {
    local list_file="$1"
    local -a packages=()
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Trim whitespace
        line=$(echo "$line" | xargs)
        
        # Validate package name format
        if [[ "$line" =~ ^[a-zA-Z0-9][a-zA-Z0-9+._-]*$ ]]; then
            packages+=("$line")
        else
            print_warning "Skipping invalid package name: $line"
        fi
    done < "$list_file"
    
    printf '%s\n' "${packages[@]}"
}

# Check package availability
check_packages_availability() {
    local -a packages=("$@")
    local -a available=()
    local -a unavailable=()
    
    print_info "Checking package availability..."
    
    for package in "${packages[@]}"; do
        if apt-cache policy "$package" 2>/dev/null | grep -q "Candidate:" && \
           [[ "$(apt-cache policy "$package" 2>/dev/null | grep "Candidate:" | awk '{print $2}')" != "(none)" ]]; then
            available+=("$package")
        else
            unavailable+=("$package")
        fi
    done
    
    if [[ ${#unavailable[@]} -gt 0 ]]; then
        print_warning "The following packages are not available:"
        printf '  %s\n' "${unavailable[@]}"
        echo
    fi
    
    if [[ ${#available[@]} -eq 0 ]]; then
        print_error "No packages are available for installation"
        return 1
    fi
    
    printf '%s\n' "${available[@]}"
}

# Show installation summary
show_installation_summary() {
    local -a packages=("$@")
    
    print_info "Installation Summary:"
    echo "  Packages to install: ${#packages[@]}"
    echo "  Package list:"
    printf '    %s\n' "${packages[@]}"
    echo
}

# Install packages
install_packages() {
    local -a packages=("$@")
    local auto_yes="$1"
    local dry_run="$2"
    local verbose="$3"
    
    # Remove flags from packages array
    packages=("${@:4}")
    
    if [[ "$dry_run" == true ]]; then
        print_info "DRY RUN - The following packages would be installed:"
        printf '  %s\n' "${packages[@]}"
        return 0
    fi
    
    # Build apt-get command
    local apt_cmd="apt-get install"
    
    if [[ "$auto_yes" == true ]]; then
        apt_cmd+=" -y"
    fi
    
    if [[ "$verbose" == true ]]; then
        apt_cmd+=" -V"
    fi
    
    # Install packages
    print_info "Starting package installation..."
    
    if sudo $apt_cmd "${packages[@]}"; then
        print_success "All packages installed successfully!"
        return 0
    else
        print_error "Some packages failed to install"
        return 1
    fi
}

# Get package statistics
show_package_stats() {
    local list_file="$1"
    local -a packages
    readarray -t packages < <(parse_package_list "$list_file")
    
    print_info "Package List Statistics:"
    echo "  File: $list_file"
    echo "  Total packages: ${#packages[@]}"
    echo "  File size: $(wc -c < "$list_file") bytes"
    echo "  Last modified: $(stat -c %y "$list_file")"
}

#==============================================================================
# Main Functions
#==============================================================================

# Parse command line arguments
parse_arguments() {
    local auto_yes=false
    local dry_run=false
    local update_cache=false
    local verbose=false
    local list_file=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -y|--yes)
                auto_yes=true
                shift
                ;;
            -n|--dry-run|-s|--simulate)
                dry_run=true
                shift
                ;;
            -u|--update)
                update_cache=true
                shift
                ;;
            -l|--list-available)
                list_available_lists
                exit 0
                ;;
            -V|--verbose)
                verbose=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                print_info "Use --help for usage information"
                exit 1
                ;;
            *)
                if [[ -z "$list_file" ]]; then
                    list_file="$1"
                else
                    print_error "Multiple file arguments provided"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$list_file" ]]; then
        print_error "No package list file specified"
        print_info "Use --help for usage information"
        exit 1
    fi
    
    # If input is just a filename, prepend lists directory
    if [[ "$list_file" == *.list && "$list_file" != */* ]]; then
        list_file="${LISTS_DIR}/${list_file}"
    fi
    
    echo "$auto_yes" "$dry_run" "$update_cache" "$verbose" "$list_file"
}

# Main function
main() {
    print_info "$SCRIPT_NAME v$SCRIPT_VERSION - Package List Installer"
    echo
    
    # Check if apt is available
    if ! command -v apt-get &> /dev/null; then
        print_error "This script requires apt package manager"
        exit 1
    fi
    
    # Parse arguments
    read -r auto_yes dry_run update_cache verbose list_file <<< "$(parse_arguments "$@")"
    
    # Validate list file
    if ! validate_list_file "$list_file"; then
        exit 1
    fi
    
    # Show package statistics
    show_package_stats "$list_file"
    echo
    
    # Parse package list
    local -a packages
    readarray -t packages < <(parse_package_list "$list_file")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        print_warning "No valid packages found in list file"
        exit 1
    fi
    
    # Update package cache if requested
    if [[ "$update_cache" == true ]]; then
        print_info "Updating package cache..."
        if ! sudo apt-get update; then
            print_warning "Failed to update package cache, continuing anyway..."
        fi
        echo
    fi
    
    # Check package availability
    local -a available_packages
    readarray -t available_packages < <(check_packages_availability "${packages[@]}")
    
    if [[ ${#available_packages[@]} -eq 0 ]]; then
        exit 1
    fi
    
    # Show installation summary
    show_installation_summary "${available_packages[@]}"
    
    # Confirm installation (unless auto-yes or dry-run)
    if [[ "$auto_yes" != true && "$dry_run" != true ]]; then
        echo -n "Do you want to proceed with the installation? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled by user"
            exit 0
        fi
        echo
    fi
    
    # Install packages
    if install_packages "$auto_yes" "$dry_run" "$verbose" "${available_packages[@]}"; then
        print_success "Package installation completed successfully!"
    else
        print_error "Package installation failed"
        exit 1
    fi
}

#==============================================================================
# Script Entry Point
#==============================================================================

# Handle Ctrl+C gracefully
trap 'echo; print_info "Operation cancelled by user"; exit 0' INT

# Run main function with all arguments
main "$@"
