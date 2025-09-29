#!/bin/bash

# Package List Manager - Add Packages Script
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
$SCRIPT_NAME - Package List Manager (Add Packages)

USAGE:
    $SCRIPT_NAME [OPTIONS] [LIST_FILE]

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show script version
    -i, --interactive       Interactive mode (default)
    -c, --create            Create new list if it doesn't exist
    -l, --list-available    List available package lists

ARGUMENTS:
    LIST_FILE               Path to package list file (optional in interactive mode)

DESCRIPTION:
    This script allows you to add packages to existing package lists.
    It validates package availability before adding them to the list.
    Supports both interactive and command-line modes.

EXAMPLES:
    $SCRIPT_NAME                                    # Interactive mode
    $SCRIPT_NAME developer.list                     # Add to specific list
    $SCRIPT_NAME --create my_new_list.list         # Create new list
    $SCRIPT_NAME --list-available                   # Show available lists

EOF
}

# Show script version
show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# Check if package exists in repositories
check_package_exists() {
    local package="$1"
    
    # Use apt-cache policy to check if package exists
    if apt-cache policy "$package" 2>/dev/null | grep -q "Candidate:"; then
        local candidate=$(apt-cache policy "$package" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        if [[ "$candidate" != "(none)" ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Check if package is already in list
package_in_list() {
    local package="$1"
    local list_file="$2"
    
    if [[ -f "$list_file" ]] && grep -q "^${package}$" "$list_file"; then
        return 0
    fi
    return 1
}

# Add package to list
add_package_to_list() {
    local package="$1"
    local list_file="$2"
    
    # Check if package already exists in list
    if package_in_list "$package" "$list_file"; then
        print_warning "Package '$package' already exists in list"
        return 1
    fi
    
    # Check if package exists in repositories
    print_info "Checking package availability: $package"
    if check_package_exists "$package"; then
        echo "$package" >> "$list_file"
        print_success "Added '$package' to $list_file"
        return 0
    else
        print_error "Package '$package' not found in repositories"
        return 1
    fi
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

# Interactive package selection
interactive_add_packages() {
    local list_file="$1"
    local package
    
    print_info "Interactive package addition mode"
    print_info "Target list: $list_file"
    print_info "Enter package names (one per line). Type 'quit', 'exit', or press Ctrl+C to finish."
    echo
    
    while true; do
        echo -n "Enter package name: "
        read -r package
        
        # Check for exit conditions
        if [[ "$package" == "quit" || "$package" == "exit" || -z "$package" ]]; then
            break
        fi
        
        # Validate package name (basic validation)
        if [[ ! "$package" =~ ^[a-zA-Z0-9][a-zA-Z0-9+._-]*$ ]]; then
            print_error "Invalid package name format: $package"
            continue
        fi
        
        # Add package to list
        add_package_to_list "$package" "$list_file"
        echo
    done
    
    print_info "Package addition completed."
}

# Get or create list file
get_list_file() {
    local list_input="$1"
    local create_new="$2"
    local list_file
    
    # If input is just a filename, prepend lists directory
    if [[ "$list_input" == *.list && "$list_input" != */* ]]; then
        list_file="${LISTS_DIR}/${list_input}"
    else
        list_file="$list_input"
    fi
    
    # Create lists directory if it doesn't exist
    mkdir -p "$LISTS_DIR"
    
    # Check if file exists or should be created
    if [[ ! -f "$list_file" ]]; then
        if [[ "$create_new" == true ]]; then
            touch "$list_file"
            print_success "Created new package list: $list_file"
        else
            print_error "Package list file not found: $list_file"
            print_info "Use --create flag to create a new list, or choose from available lists:"
            list_available_lists
            exit 1
        fi
    fi
    
    echo "$list_file"
}

# Interactive file selection
interactive_file_selection() {
    local list_file
    
    print_info "Available package lists:"
    list_available_lists
    echo
    
    while true; do
        echo -n "Enter list filename (or full path): "
        read -r list_input
        
        if [[ -z "$list_input" ]]; then
            print_error "Please enter a filename"
            continue
        fi
        
        # Ask if user wants to create new file if it doesn't exist
        list_file=$(get_list_file "$list_input" false 2>/dev/null) || {
            echo -n "File doesn't exist. Create new list? (y/N): "
            read -r create_response
            if [[ "$create_response" =~ ^[Yy]$ ]]; then
                list_file=$(get_list_file "$list_input" true)
                break
            else
                continue
            fi
        }
        break
    done
    
    echo "$list_file"
}

#==============================================================================
# Main Functions
#==============================================================================

# Parse command line arguments
parse_arguments() {
    local create_new=false
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
            -i|--interactive)
                # Interactive mode is default, but we'll accept this flag
                shift
                ;;
            -c|--create)
                create_new=true
                shift
                ;;
            -l|--list-available)
                list_available_lists
                exit 0
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
    
    # If no list file provided, use interactive selection
    if [[ -z "$list_file" ]]; then
        list_file=$(interactive_file_selection)
    else
        list_file=$(get_list_file "$list_file" "$create_new")
    fi
    
    echo "$list_file"
}

# Main function
main() {
    print_info "$SCRIPT_NAME v$SCRIPT_VERSION - Package List Manager"
    echo
    
    # Check if apt is available
    if ! command -v apt-cache &> /dev/null; then
        print_error "This script requires apt package manager"
        exit 1
    fi
    
    # Parse arguments and get list file
    local list_file
    list_file=$(parse_arguments "$@")
    
    # Show current list contents
    if [[ -s "$list_file" ]]; then
        print_info "Current packages in list:"
        cat "$list_file" | sed 's/^/  /'
        echo
    else
        print_info "List is empty or newly created"
        echo
    fi
    
    # Start interactive package addition
    interactive_add_packages "$list_file"
    
    # Show final list contents
    echo
    print_info "Final package list contents:"
    if [[ -s "$list_file" ]]; then
        cat "$list_file" | sed 's/^/  /'
        echo
        print_success "Package list saved to: $list_file"
    else
        print_info "No packages were added to the list"
    fi
}

#==============================================================================
# Script Entry Point
#==============================================================================

# Handle Ctrl+C gracefully
trap 'echo; print_info "Operation cancelled by user"; exit 0' INT

# Run main function with all arguments
main "$@"

