#!/bin/bash

# Package List Manager - Unified Package Management System
# Comprehensive package list management with multiple operations
# Author: Enhanced version
# Version: 3.0

set -euo pipefail

#==============================================================================
# Configuration and Constants
#==============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="3.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LISTS_DIR="${SCRIPT_DIR}/lists"
readonly BACKUP_DIR="${SCRIPT_DIR}/backups"
readonly CONFIG_FILE="${SCRIPT_DIR}/.pkgmgr_config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Default configuration
VERBOSE=false
AUTO_YES=false
DRY_RUN=false

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

print_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        print_color "$CYAN" "VERBOSE: $*"
    fi
}

print_header() {
    print_color "$MAGENTA" "=== $* ==="
}

# Show main help information
show_help() {
    cat << EOF
$SCRIPT_NAME - Unified Package List Management System

USAGE:
    $SCRIPT_NAME [GLOBAL_OPTIONS] COMMAND [COMMAND_OPTIONS] [ARGUMENTS]

GLOBAL OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show script version
    -V, --verbose           Enable verbose output
    -y, --yes               Automatic yes to prompts
    -n, --dry-run          Show what would be done without doing it

COMMANDS:
    list                    List package lists and their contents
    add                     Add packages to a list
    remove                  Remove packages from a list
    install                 Install packages from a list
    search                  Search for packages in lists
    create                  Create a new package list
    delete                  Delete a package list
    backup                  Backup package lists
    restore                 Restore package lists from backup
    validate                Validate package lists
    merge                   Merge multiple package lists
    diff                    Compare package lists
    interactive             Start interactive menu mode

Use '$SCRIPT_NAME COMMAND --help' for specific command help.

EXAMPLES:
    $SCRIPT_NAME list                           # List all package lists
    $SCRIPT_NAME add developer.list git vim    # Add packages to list
    $SCRIPT_NAME install --update server.list  # Install with cache update
    $SCRIPT_NAME search nodejs                 # Search for nodejs in all lists
    $SCRIPT_NAME backup --all                  # Backup all lists
    $SCRIPT_NAME interactive                   # Start interactive mode

EOF
}

# Show command-specific help
show_command_help() {
    local command="$1"
    
    case "$command" in
        list)
            cat << EOF
$SCRIPT_NAME list - List package lists and their contents

USAGE:
    $SCRIPT_NAME list [OPTIONS] [LIST_NAME]

OPTIONS:
    -a, --all               Show all lists with contents
    -s, --summary           Show summary statistics
    -c, --count             Show package counts only

EXAMPLES:
    $SCRIPT_NAME list                   # List all available lists
    $SCRIPT_NAME list developer.list   # Show contents of specific list
    $SCRIPT_NAME list --all             # Show all lists with contents

EOF
            ;;
        add)
            cat << EOF
$SCRIPT_NAME add - Add packages to a list

USAGE:
    $SCRIPT_NAME add [OPTIONS] LIST_NAME PACKAGE1 [PACKAGE2 ...]

OPTIONS:
    -c, --create            Create list if it doesn't exist
    -i, --interactive       Interactive package entry mode
    -f, --from-file FILE    Add packages from another file

EXAMPLES:
    $SCRIPT_NAME add developer.list git vim    # Add specific packages
    $SCRIPT_NAME add --create new.list curl    # Create list and add package
    $SCRIPT_NAME add --interactive dev.list    # Interactive mode

EOF
            ;;
        remove)
            cat << EOF
$SCRIPT_NAME remove - Remove packages from a list

USAGE:
    $SCRIPT_NAME remove [OPTIONS] LIST_NAME PACKAGE1 [PACKAGE2 ...]

OPTIONS:
    -i, --interactive       Interactive package removal
    -a, --all               Remove all packages (clear list)

EXAMPLES:
    $SCRIPT_NAME remove developer.list vim     # Remove specific package
    $SCRIPT_NAME remove --interactive dev.list # Interactive removal

EOF
            ;;
        install)
            cat << EOF
$SCRIPT_NAME install - Install packages from a list

USAGE:
    $SCRIPT_NAME install [OPTIONS] LIST_NAME

OPTIONS:
    -u, --update            Update package cache first
    -s, --simulate          Simulate installation
    -f, --force             Force installation of unavailable packages

EXAMPLES:
    $SCRIPT_NAME install server.list           # Install packages
    $SCRIPT_NAME install --update --yes app.list # Update and install

EOF
            ;;
        search)
            cat << EOF
$SCRIPT_NAME search - Search for packages in lists

USAGE:
    $SCRIPT_NAME search [OPTIONS] PATTERN

OPTIONS:
    -i, --ignore-case       Case insensitive search
    -w, --whole-word        Match whole words only
    -l, --list-only         Show only list names

EXAMPLES:
    $SCRIPT_NAME search nodejs                 # Find nodejs in all lists
    $SCRIPT_NAME search --ignore-case PYTHON   # Case insensitive search

EOF
            ;;
        *)
            print_error "Unknown command: $command"
            print_info "Use '$SCRIPT_NAME --help' for available commands"
            ;;
    esac
}

# Initialize directories
init_dirs() {
    mkdir -p "$LISTS_DIR" "$BACKUP_DIR"
    print_verbose "Initialized directories: $LISTS_DIR, $BACKUP_DIR"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        print_verbose "Loaded configuration from $CONFIG_FILE"
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
# Package Manager Configuration
# Auto-generated on $(date)

VERBOSE=$VERBOSE
AUTO_YES=$AUTO_YES
DRY_RUN=$DRY_RUN
EOF
    print_verbose "Saved configuration to $CONFIG_FILE"
}

#==============================================================================
# Package Management Functions
#==============================================================================

# Check if package exists in repositories
check_package_exists() {
    local package="$1"
    
    if apt-cache policy "$package" 2>/dev/null | grep -q "Candidate:"; then
        local candidate=$(apt-cache policy "$package" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        [[ "$candidate" != "(none)" ]]
    else
        return 1
    fi
}

# Get list file path
get_list_path() {
    local list_name="$1"
    
    if [[ "$list_name" == *.list && "$list_name" != */* ]]; then
        echo "${LISTS_DIR}/${list_name}"
    else
        echo "$list_name"
    fi
}

# Validate list file
validate_list_file() {
    local list_file="$1"
    local create_if_missing="$2"
    
    if [[ ! -f "$list_file" ]]; then
        if [[ "$create_if_missing" == true ]]; then
            touch "$list_file"
            print_success "Created new package list: $list_file"
        else
            print_error "Package list not found: $list_file"
            return 1
        fi
    fi
    
    if [[ ! -r "$list_file" ]]; then
        print_error "Cannot read package list: $list_file"
        return 1
    fi
    
    return 0
}

# Parse package list
parse_package_list() {
    local list_file="$1"
    
    grep -v '^[[:space:]]*$' "$list_file" 2>/dev/null | \
    grep -v '^[[:space:]]*#' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    sort -u
}

#==============================================================================
# Command Implementations
#==============================================================================

# List command
cmd_list() {
    local show_all=false
    local show_summary=false
    local show_count=false
    local target_list=""
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                show_all=true
                shift
                ;;
            -s|--summary)
                show_summary=true
                shift
                ;;
            -c|--count)
                show_count=true
                shift
                ;;
            --help)
                show_command_help "list"
                return 0
                ;;
            -*)
                print_error "Unknown option for list command: $1"
                return 1
                ;;
            *)
                target_list="$1"
                shift
                ;;
        esac
    done
    
    if [[ -n "$target_list" ]]; then
        # Show specific list
        local list_file
        list_file=$(get_list_path "$target_list")
        
        if ! validate_list_file "$list_file" false; then
            return 1
        fi
        
        print_header "Package List: $(basename "$list_file")"
        local packages
        packages=$(parse_package_list "$list_file")
        
        if [[ -n "$packages" ]]; then
            echo "$packages" | nl -w2 -s'. '
            echo
            print_info "Total packages: $(echo "$packages" | wc -l)"
        else
            print_info "List is empty"
        fi
    else
        # Show all lists
        print_header "Available Package Lists"
        
        if [[ ! -d "$LISTS_DIR" ]] || [[ -z "$(ls -A "$LISTS_DIR"/*.list 2>/dev/null)" ]]; then
            print_info "No package lists found in $LISTS_DIR"
            return 0
        fi
        
        for list_file in "$LISTS_DIR"/*.list; do
            if [[ -f "$list_file" ]]; then
                local list_name
                list_name=$(basename "$list_file")
                local count
                count=$(parse_package_list "$list_file" | wc -l)
                
                if [[ "$show_count" == true ]]; then
                    printf "%-30s %3d packages\n" "$list_name" "$count"
                elif [[ "$show_all" == true ]]; then
                    print_info "$list_name ($count packages)"
                    parse_package_list "$list_file" | sed 's/^/  /'
                    echo
                else
                    printf "%-30s %3d packages\n" "$list_name" "$count"
                fi
            fi
        done
        
        if [[ "$show_summary" == true ]]; then
            echo
            local total_lists total_packages
            total_lists=$(find "$LISTS_DIR" -name "*.list" -type f | wc -l)
            total_packages=$(find "$LISTS_DIR" -name "*.list" -type f -exec cat {} \; | \
                           grep -v '^[[:space:]]*$' | grep -v '^[[:space:]]*#' | wc -l)
            
            print_header "Summary"
            echo "Total lists: $total_lists"
            echo "Total packages: $total_packages"
        fi
    fi
}

# Add command
cmd_add() {
    local create_list=false
    local interactive_mode=false
    local from_file=""
    local list_name=""
    local -a packages=()
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--create)
                create_list=true
                shift
                ;;
            -i|--interactive)
                interactive_mode=true
                shift
                ;;
            -f|--from-file)
                from_file="$2"
                shift 2
                ;;
            --help)
                show_command_help "add"
                return 0
                ;;
            -*)
                print_error "Unknown option for add command: $1"
                return 1
                ;;
            *)
                if [[ -z "$list_name" ]]; then
                    list_name="$1"
                else
                    packages+=("$1")
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$list_name" ]]; then
        print_error "List name is required"
        return 1
    fi
    
    local list_file
    list_file=$(get_list_path "$list_name")
    
    if ! validate_list_file "$list_file" "$create_list"; then
        return 1
    fi
    
    # Handle different input modes
    if [[ -n "$from_file" ]]; then
        # Add packages from another file
        if [[ ! -f "$from_file" ]]; then
            print_error "Source file not found: $from_file"
            return 1
        fi
        
        print_info "Adding packages from $from_file to $list_name"
        local source_packages
        source_packages=$(parse_package_list "$from_file")
        
        while IFS= read -r package; do
            if [[ -n "$package" ]] && ! grep -q "^${package}$" "$list_file"; then
                if check_package_exists "$package"; then
                    echo "$package" >> "$list_file"
                    print_success "Added: $package"
                else
                    print_warning "Package not found: $package"
                fi
            fi
        done <<< "$source_packages"
        
    elif [[ "$interactive_mode" == true ]]; then
        # Interactive mode
        print_info "Interactive mode - Enter packages (one per line, 'quit' to finish)"
        
        while true; do
            echo -n "Package name: "
            read -r package
            
            if [[ "$package" == "quit" || "$package" == "exit" || -z "$package" ]]; then
                break
            fi
            
            if grep -q "^${package}$" "$list_file"; then
                print_warning "Package already in list: $package"
                continue
            fi
            
            if check_package_exists "$package"; then
                echo "$package" >> "$list_file"
                print_success "Added: $package"
            else
                print_warning "Package not found: $package"
            fi
        done
        
    else
        # Command line packages
        if [[ ${#packages[@]} -eq 0 ]]; then
            print_error "No packages specified"
            return 1
        fi
        
        for package in "${packages[@]}"; do
            if grep -q "^${package}$" "$list_file"; then
                print_warning "Package already in list: $package"
                continue
            fi
            
            if [[ "$DRY_RUN" == true ]]; then
                print_info "Would add: $package"
            else
                if check_package_exists "$package"; then
                    echo "$package" >> "$list_file"
                    print_success "Added: $package"
                else
                    print_warning "Package not found: $package"
                fi
            fi
        done
    fi
    
    # Sort and remove duplicates
    if [[ "$DRY_RUN" != true ]] && [[ -f "$list_file" ]]; then
        sort -u "$list_file" -o "$list_file"
        print_verbose "Sorted and deduplicated list file"
    fi
}

# Remove command
cmd_remove() {
    local interactive_mode=false
    local remove_all=false
    local list_name=""
    local -a packages=()
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interactive)
                interactive_mode=true
                shift
                ;;
            -a|--all)
                remove_all=true
                shift
                ;;
            --help)
                show_command_help "remove"
                return 0
                ;;
            -*)
                print_error "Unknown option for remove command: $1"
                return 1
                ;;
            *)
                if [[ -z "$list_name" ]]; then
                    list_name="$1"
                else
                    packages+=("$1")
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$list_name" ]]; then
        print_error "List name is required"
        return 1
    fi
    
    local list_file
    list_file=$(get_list_path "$list_name")
    
    if ! validate_list_file "$list_file" false; then
        return 1
    fi
    
    if [[ "$remove_all" == true ]]; then
        if [[ "$AUTO_YES" != true ]]; then
            echo -n "Remove all packages from $list_name? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_info "Operation cancelled"
                return 0
            fi
        fi
        
        if [[ "$DRY_RUN" == true ]]; then
            print_info "Would remove all packages from $list_name"
        else
            > "$list_file"
            print_success "Removed all packages from $list_name"
        fi
        return 0
    fi
    
    if [[ "$interactive_mode" == true ]]; then
        # Interactive removal
        local current_packages
        current_packages=$(parse_package_list "$list_file")
        
        if [[ -z "$current_packages" ]]; then
            print_info "List is empty"
            return 0
        fi
        
        print_info "Current packages in $list_name:"
        echo "$current_packages" | nl -w2 -s'. '
        echo
        
        while true; do
            echo -n "Package to remove (name or number, 'quit' to finish): "
            read -r input
            
            if [[ "$input" == "quit" || "$input" == "exit" || -z "$input" ]]; then
                break
            fi
            
            local package=""
            if [[ "$input" =~ ^[0-9]+$ ]]; then
                package=$(echo "$current_packages" | sed -n "${input}p")
            else
                package="$input"
            fi
            
            if [[ -n "$package" ]] && grep -q "^${package}$" "$list_file"; then
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "Would remove: $package"
                else
                    sed -i "/^${package}$/d" "$list_file"
                    print_success "Removed: $package"
                fi
            else
                print_warning "Package not found in list: $package"
            fi
        done
    else
        # Command line removal
        if [[ ${#packages[@]} -eq 0 ]]; then
            print_error "No packages specified for removal"
            return 1
        fi
        
        for package in "${packages[@]}"; do
            if grep -q "^${package}$" "$list_file"; then
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "Would remove: $package"
                else
                    sed -i "/^${package}$/d" "$list_file"
                    print_success "Removed: $package"
                fi
            else
                print_warning "Package not in list: $package"
            fi
        done
    fi
}

# Install command
cmd_install() {
    local update_cache=false
    local simulate=false
    local force=false
    local list_name=""
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--update)
                update_cache=true
                shift
                ;;
            -s|--simulate)
                simulate=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            --help)
                show_command_help "install"
                return 0
                ;;
            -*)
                print_error "Unknown option for install command: $1"
                return 1
                ;;
            *)
                list_name="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$list_name" ]]; then
        print_error "List name is required"
        return 1
    fi
    
    local list_file
    list_file=$(get_list_path "$list_name")
    
    if ! validate_list_file "$list_file" false; then
        return 1
    fi
    
    local packages
    packages=$(parse_package_list "$list_file")
    
    if [[ -z "$packages" ]]; then
        print_info "No packages to install"
        return 0
    fi
    
    # Update cache if requested
    if [[ "$update_cache" == true ]]; then
        print_info "Updating package cache..."
        if [[ "$DRY_RUN" == true ]]; then
            print_info "Would update package cache"
        else
            sudo apt-get update
        fi
    fi
    
    # Check package availability
    local -a available=()
    local -a unavailable=()
    
    while IFS= read -r package; do
        if check_package_exists "$package"; then
            available+=("$package")
        else
            unavailable+=("$package")
        fi
    done <<< "$packages"
    
    if [[ ${#unavailable[@]} -gt 0 ]]; then
        print_warning "Unavailable packages:"
        printf '  %s\n' "${unavailable[@]}"
        
        if [[ "$force" != true ]]; then
            echo -n "Continue with available packages? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_info "Installation cancelled"
                return 0
            fi
        fi
    fi
    
    if [[ ${#available[@]} -eq 0 ]]; then
        print_error "No packages available for installation"
        return 1
    fi
    
    print_info "Installing ${#available[@]} packages..."
    
    if [[ "$simulate" == true || "$DRY_RUN" == true ]]; then
        print_info "Would install:"
        printf '  %s\n' "${available[@]}"
    else
        # Build install command
        local apt_cmd="apt-get install"
        if [[ "$AUTO_YES" == true ]]; then
            apt_cmd+=" -y"
        fi
        
        if sudo $apt_cmd "${available[@]}"; then
            print_success "Installation completed successfully!"
        else
            print_error "Installation failed"
            return 1
        fi
    fi
}

# Search command
cmd_search() {
    local ignore_case=false
    local whole_word=false
    local list_only=false
    local pattern=""
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--ignore-case)
                ignore_case=true
                shift
                ;;
            -w|--whole-word)
                whole_word=true
                shift
                ;;
            -l|--list-only)
                list_only=true
                shift
                ;;
            --help)
                show_command_help "search"
                return 0
                ;;
            -*)
                print_error "Unknown option for search command: $1"
                return 1
                ;;
            *)
                pattern="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$pattern" ]]; then
        print_error "Search pattern is required"
        return 1
    fi
    
    print_header "Searching for: $pattern"
    
    local grep_opts="-n"
    if [[ "$ignore_case" == true ]]; then
        grep_opts+="i"
    fi
    if [[ "$whole_word" == true ]]; then
        grep_opts+="w"
    fi
    
    local found=false
    
    for list_file in "$LISTS_DIR"/*.list; do
        if [[ -f "$list_file" ]]; then
            local matches
            matches=$(grep $grep_opts "$pattern" "$list_file" 2>/dev/null || true)
            
            if [[ -n "$matches" ]]; then
                found=true
                local list_name
                list_name=$(basename "$list_file")
                
                if [[ "$list_only" == true ]]; then
                    echo "$list_name"
                else
                    print_info "Found in $list_name:"
                    echo "$matches" | sed 's/^/  /'
                    echo
                fi
            fi
        fi
    done
    
    if [[ "$found" != true ]]; then
        print_info "No matches found for: $pattern"
    fi
}

# Backup command
cmd_backup() {
    local backup_all=false
    local backup_name=""
    local -a lists_to_backup=()
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                backup_all=true
                shift
                ;;
            -n|--name)
                backup_name="$2"
                shift 2
                ;;
            --help)
                cat << EOF
$SCRIPT_NAME backup - Backup package lists

USAGE:
    $SCRIPT_NAME backup [OPTIONS] [LIST_NAMES...]

OPTIONS:
    -a, --all               Backup all lists
    -n, --name NAME         Custom backup name

EXAMPLES:
    $SCRIPT_NAME backup --all              # Backup all lists
    $SCRIPT_NAME backup developer.list     # Backup specific list
    $SCRIPT_NAME backup --name mybackup --all # Named backup

EOF
                return 0
                ;;
            -*)
                print_error "Unknown option for backup command: $1"
                return 1
                ;;
            *)
                lists_to_backup+=("$1")
                shift
                ;;
        esac
    done
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Generate backup name if not provided
    if [[ -z "$backup_name" ]]; then
        backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    fi
    
    local backup_path="${BACKUP_DIR}/${backup_name}"
    mkdir -p "$backup_path"
    
    # Determine which lists to backup
    local -a target_lists=()
    if [[ "$backup_all" == true ]]; then
        while IFS= read -r -d '' list_file; do
            target_lists+=("$(basename "$list_file")")
        done < <(find "$LISTS_DIR" -name "*.list" -type f -print0 2>/dev/null)
    else
        target_lists=("${lists_to_backup[@]}")
    fi
    
    if [[ ${#target_lists[@]} -eq 0 ]]; then
        print_error "No lists to backup"
        return 1
    fi
    
    # Perform backup
    local backed_up=0
    for list_name in "${target_lists[@]}"; do
        local list_file
        list_file=$(get_list_path "$list_name")
        
        if [[ -f "$list_file" ]]; then
            cp "$list_file" "$backup_path/"
            print_success "Backed up: $list_name"
            ((backed_up++))
        else
            print_warning "List not found: $list_name"
        fi
    done
    
    if [[ $backed_up -gt 0 ]]; then
        # Create backup metadata
        cat > "${backup_path}/backup_info.txt" << EOF
Backup created: $(date)
Lists backed up: $backed_up
Backup location: $backup_path
EOF
        
        print_success "Backup completed: $backup_name"
        print_info "Location: $backup_path"
        print_info "Lists backed up: $backed_up"
    else
        rmdir "$backup_path" 2>/dev/null
        print_error "No lists were backed up"
        return 1
    fi
}

# Restore command
cmd_restore() {
    local backup_name=""
    local force=false
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force=true
                shift
                ;;
            --help)
                cat << EOF
$SCRIPT_NAME restore - Restore package lists from backup

USAGE:
    $SCRIPT_NAME restore [OPTIONS] BACKUP_NAME

OPTIONS:
    -f, --force             Overwrite existing lists

EXAMPLES:
    $SCRIPT_NAME restore backup_20231201_120000     # Restore specific backup
    $SCRIPT_NAME restore --force mybackup           # Force restore

EOF
                return 0
                ;;
            -*)
                print_error "Unknown option for restore command: $1"
                return 1
                ;;
            *)
                backup_name="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$backup_name" ]]; then
        print_error "Backup name is required"
        print_info "Available backups:"
        if [[ -d "$BACKUP_DIR" ]]; then
            ls -1 "$BACKUP_DIR" 2>/dev/null | sed 's/^/  /' || echo "  No backups found"
        else
            echo "  No backups found"
        fi
        return 1
    fi
    
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    if [[ ! -d "$backup_path" ]]; then
        print_error "Backup not found: $backup_name"
        return 1
    fi
    
    # Show backup info if available
    if [[ -f "${backup_path}/backup_info.txt" ]]; then
        print_info "Backup Information:"
        cat "${backup_path}/backup_info.txt" | sed 's/^/  /'
        echo
    fi
    
    # List files to restore
    local -a backup_files=()
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file")" != "backup_info.txt" ]]; then
            backup_files+=("$(basename "$file")")
        fi
    done < <(find "$backup_path" -name "*.list" -type f -print0 2>/dev/null)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        print_error "No list files found in backup"
        return 1
    fi
    
    print_info "Files to restore:"
    printf '  %s\n' "${backup_files[@]}"
    echo
    
    # Confirm restore
    if [[ "$AUTO_YES" != true ]]; then
        echo -n "Proceed with restore? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Restore cancelled"
            return 0
        fi
    fi
    
    # Perform restore
    local restored=0
    for file in "${backup_files[@]}"; do
        local source_file="${backup_path}/${file}"
        local target_file="${LISTS_DIR}/${file}"
        
        if [[ -f "$target_file" && "$force" != true ]]; then
            echo -n "Overwrite existing $file? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_info "Skipped: $file"
                continue
            fi
        fi
        
        if [[ "$DRY_RUN" == true ]]; then
            print_info "Would restore: $file"
        else
            cp "$source_file" "$target_file"
            print_success "Restored: $file"
        fi
        ((restored++))
    done
    
    print_success "Restore completed. Files restored: $restored"
}

# Validate command
cmd_validate() {
    local fix_issues=false
    local list_name=""
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--fix)
                fix_issues=true
                shift
                ;;
            --help)
                cat << EOF
$SCRIPT_NAME validate - Validate package lists

USAGE:
    $SCRIPT_NAME validate [OPTIONS] [LIST_NAME]

OPTIONS:
    -f, --fix               Fix issues automatically

EXAMPLES:
    $SCRIPT_NAME validate                   # Validate all lists
    $SCRIPT_NAME validate developer.list   # Validate specific list
    $SCRIPT_NAME validate --fix server.list # Fix issues

EOF
                return 0
                ;;
            -*)
                print_error "Unknown option for validate command: $1"
                return 1
                ;;
            *)
                list_name="$1"
                shift
                ;;
        esac
    done
    
    local -a lists_to_validate=()
    
    if [[ -n "$list_name" ]]; then
        lists_to_validate=("$list_name")
    else
        # Validate all lists
        while IFS= read -r -d '' list_file; do
            lists_to_validate+=("$(basename "$list_file")")
        done < <(find "$LISTS_DIR" -name "*.list" -type f -print0 2>/dev/null)
    fi
    
    if [[ ${#lists_to_validate[@]} -eq 0 ]]; then
        print_info "No lists to validate"
        return 0
    fi
    
    print_header "Package List Validation"
    
    local total_issues=0
    
    for list_name in "${lists_to_validate[@]}"; do
        local list_file
        list_file=$(get_list_path "$list_name")
        
        if [[ ! -f "$list_file" ]]; then
            print_warning "List not found: $list_name"
            continue
        fi
        
        print_info "Validating: $list_name"
        
        local -a issues=()
        local -a valid_packages=()
        local -a invalid_packages=()
        local -a duplicate_packages=()
        
        # Check for duplicates and validate packages
        local -A seen_packages=()
        
        while IFS= read -r line; do
            # Skip empty lines and comments
            if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            
            # Trim whitespace
            line=$(echo "$line" | xargs)
            
            # Check for duplicates
            if [[ -n "${seen_packages[$line]:-}" ]]; then
                duplicate_packages+=("$line")
                continue
            fi
            seen_packages["$line"]=1
            
            # Validate package name format
            if [[ ! "$line" =~ ^[a-zA-Z0-9][a-zA-Z0-9+._-]*$ ]]; then
                issues+=("Invalid package name format: $line")
                continue
            fi
            
            # Check package availability
            if check_package_exists "$line"; then
                valid_packages+=("$line")
            else
                invalid_packages+=("$line")
            fi
            
        done < "$list_file"
        
        # Report findings
        echo "  Valid packages: ${#valid_packages[@]}"
        echo "  Invalid packages: ${#invalid_packages[@]}"
        echo "  Duplicate packages: ${#duplicate_packages[@]}"
        echo "  Format issues: ${#issues[@]}"
        
        if [[ ${#invalid_packages[@]} -gt 0 ]]; then
            print_warning "Invalid packages found:"
            printf '    %s\n' "${invalid_packages[@]}"
            ((total_issues += ${#invalid_packages[@]}))
        fi
        
        if [[ ${#duplicate_packages[@]} -gt 0 ]]; then
            print_warning "Duplicate packages found:"
            printf '    %s\n' "${duplicate_packages[@]}"
            ((total_issues += ${#duplicate_packages[@]}))
        fi
        
        if [[ ${#issues[@]} -gt 0 ]]; then
            print_warning "Format issues found:"
            printf '    %s\n' "${issues[@]}"
            ((total_issues += ${#issues[@]}))
        fi
        
        # Fix issues if requested
        if [[ "$fix_issues" == true && ($total_issues -gt 0) ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                print_info "Would fix issues in: $list_name"
            else
                # Create backup before fixing
                cp "$list_file" "${list_file}.backup.$(date +%Y%m%d_%H%M%S)"
                
                # Write only valid, unique packages
                printf '%s\n' "${valid_packages[@]}" | sort -u > "$list_file"
                print_success "Fixed issues in: $list_name"
            fi
        fi
        
        echo
    done
    
    if [[ $total_issues -eq 0 ]]; then
        print_success "All package lists are valid!"
    else
        print_warning "Found $total_issues total issues"
        if [[ "$fix_issues" != true ]]; then
            print_info "Use --fix to automatically resolve issues"
        fi
    fi
}

# Create command
cmd_create() {
    local template=""
    local list_name=""
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--template)
                template="$2"
                shift 2
                ;;
            --help)
                cat << EOF
$SCRIPT_NAME create - Create a new package list

USAGE:
    $SCRIPT_NAME create [OPTIONS] LIST_NAME

OPTIONS:
    -t, --template TEMPLATE     Use template (basic, dev, server, python)

EXAMPLES:
    $SCRIPT_NAME create mylist.list            # Create empty list
    $SCRIPT_NAME create --template dev new.list # Create from template

EOF
                return 0
                ;;
            -*)
                print_error "Unknown option for create command: $1"
                return 1
                ;;
            *)
                list_name="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$list_name" ]]; then
        print_error "List name is required"
        return 1
    fi
    
    local list_file
    list_file=$(get_list_path "$list_name")
    
    if [[ -f "$list_file" ]]; then
        print_error "List already exists: $list_name"
        return 1
    fi
    
    # Create list from template or empty
    case "$template" in
        basic)
            cat > "$list_file" << 'EOF'
# Basic system tools
curl
wget
git
vim
htop
tree
EOF
            ;;
        dev|developer)
            cat > "$list_file" << 'EOF'
# Development tools
git
vim
curl
wget
build-essential
nodejs
npm
python3-pip
docker.io
code
EOF
            ;;
        server)
            cat > "$list_file" << 'EOF'
# Server essentials
nginx
mysql-server
php-fpm
certbot
fail2ban
ufw
htop
iotop
EOF
            ;;
        python)
            cat > "$list_file" << 'EOF'
# Python development
python3
python3-pip
python3-venv
python3-dev
jupyter
pylint
black
pytest
EOF
            ;;
        ""|empty)
            cat > "$list_file" << 'EOF'
# New package list
# Add package names below (one per line)

EOF
            ;;
        *)
            print_error "Unknown template: $template"
            print_info "Available templates: basic, dev, server, python"
            return 1
            ;;
    esac
    
    print_success "Created package list: $list_name"
    if [[ -n "$template" ]]; then
        print_info "Used template: $template"
    fi
    
    # Show contents
    print_info "List contents:"
    cat "$list_file" | sed 's/^/  /'
}

# Delete command
cmd_delete() {
    local force=false
    local -a lists_to_delete=()
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force=true
                shift
                ;;
            --help)
                cat << EOF
$SCRIPT_NAME delete - Delete package lists

USAGE:
    $SCRIPT_NAME delete [OPTIONS] LIST_NAME [LIST_NAME2...]

OPTIONS:
    -f, --force             Force deletion without confirmation

EXAMPLES:
    $SCRIPT_NAME delete old.list               # Delete with confirmation
    $SCRIPT_NAME delete --force temp.list      # Force delete

EOF
                return 0
                ;;
            -*)
                print_error "Unknown option for delete command: $1"
                return 1
                ;;
            *)
                lists_to_delete+=("$1")
                shift
                ;;
        esac
    done
    
    if [[ ${#lists_to_delete[@]} -eq 0 ]]; then
        print_error "No lists specified for deletion"
        return 1
    fi
    
    # Confirm deletion
    if [[ "$force" != true && "$AUTO_YES" != true ]]; then
        print_warning "The following lists will be deleted:"
        printf '  %s\n' "${lists_to_delete[@]}"
        echo
        echo -n "Are you sure? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Deletion cancelled"
            return 0
        fi
    fi
    
    # Delete lists
    local deleted=0
    for list_name in "${lists_to_delete[@]}"; do
        local list_file
        list_file=$(get_list_path "$list_name")
        
        if [[ -f "$list_file" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                print_info "Would delete: $list_name"
            else
                rm "$list_file"
                print_success "Deleted: $list_name"
            fi
            ((deleted++))
        else
            print_warning "List not found: $list_name"
        fi
    done
    
    print_info "Deleted $deleted lists"
}

# Merge command
cmd_merge() {
    local output_file=""
    local remove_duplicates=true
    local -a source_files=()
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            --keep-duplicates)
                remove_duplicates=false
                shift
                ;;
            --help)
                cat << EOF
$SCRIPT_NAME merge - Merge multiple package lists

USAGE:
    $SCRIPT_NAME merge [OPTIONS] -o OUTPUT_FILE LIST1 LIST2 [LIST3...]

OPTIONS:
    -o, --output FILE       Output file name
    --keep-duplicates       Keep duplicate packages

EXAMPLES:
    $SCRIPT_NAME merge -o combined.list dev.list server.list
    $SCRIPT_NAME merge --keep-duplicates -o all.list *.list

EOF
                return 0
                ;;
            -*)
                print_error "Unknown option for merge command: $1"
                return 1
                ;;
            *)
                source_files+=("$1")
                shift
                ;;
        esac
    done
    
    if [[ -z "$output_file" ]]; then
        print_error "Output file is required"
        return 1
    fi
    
    if [[ ${#source_files[@]} -lt 2 ]]; then
        print_error "At least 2 source files are required"
        return 1
    fi
    
    local output_path
    output_path=$(get_list_path "$output_file")
    
    if [[ -f "$output_path" ]]; then
        echo -n "Output file exists. Overwrite? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Merge cancelled"
            return 0
        fi
    fi
    
    # Merge files
    local temp_file=$(mktemp)
    
    for source_file in "${source_files[@]}"; do
        local source_path
        source_path=$(get_list_path "$source_file")
        
        if [[ -f "$source_path" ]]; then
            print_info "Merging: $source_file"
            parse_package_list "$source_path" >> "$temp_file"
        else
            print_warning "Source file not found: $source_file"
        fi
    done
    
    # Process merged content
    if [[ "$remove_duplicates" == true ]]; then
        sort -u "$temp_file" > "$output_path"
    else
        cp "$temp_file" "$output_path"
    fi
    
    rm "$temp_file"
    
    local total_packages
    total_packages=$(wc -l < "$output_path")
    
    print_success "Merged ${#source_files[@]} lists into $output_file"
    print_info "Total packages: $total_packages"
}

# Diff command
cmd_diff() {
    local file1=""
    local file2=""
    
    # Parse command arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                cat << EOF
$SCRIPT_NAME diff - Compare two package lists

USAGE:
    $SCRIPT_NAME diff LIST1 LIST2

EXAMPLES:
    $SCRIPT_NAME diff old.list new.list
    $SCRIPT_NAME diff server.list client.list

EOF
                return 0
                ;;
            -*)
                print_error "Unknown option for diff command: $1"
                return 1
                ;;
            *)
                if [[ -z "$file1" ]]; then
                    file1="$1"
                elif [[ -z "$file2" ]]; then
                    file2="$1"
                else
                    print_error "Too many arguments"
                    return 1
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$file1" || -z "$file2" ]]; then
        print_error "Two list files are required"
        return 1
    fi
    
    local path1 path2
    path1=$(get_list_path "$file1")
    path2=$(get_list_path "$file2")
    
    if [[ ! -f "$path1" ]]; then
        print_error "First file not found: $file1"
        return 1
    fi
    
    if [[ ! -f "$path2" ]]; then
        print_error "Second file not found: $file2"
        return 1
    fi
    
    print_header "Comparing $file1 vs $file2"
    
    local temp1 temp2
    temp1=$(mktemp)
    temp2=$(mktemp)
    
    parse_package_list "$path1" | sort > "$temp1"
    parse_package_list "$path2" | sort > "$temp2"
    
    # Find differences
    local only_in_1 only_in_2 common
    only_in_1=$(comm -23 "$temp1" "$temp2")
    only_in_2=$(comm -13 "$temp1" "$temp2")
    common=$(comm -12 "$temp1" "$temp2")
    
    print_info "Only in $file1 ($(echo "$only_in_1" | wc -w) packages):"
    if [[ -n "$only_in_1" ]]; then
        echo "$only_in_1" | sed 's/^/  /'
    else
        echo "  (none)"
    fi
    echo
    
    print_info "Only in $file2 ($(echo "$only_in_2" | wc -w) packages):"
    if [[ -n "$only_in_2" ]]; then
        echo "$only_in_2" | sed 's/^/  /'
    else
        echo "  (none)"
    fi
    echo
    
    print_info "Common packages ($(echo "$common" | wc -w) packages):"
    if [[ -n "$common" ]]; then
        echo "$common" | sed 's/^/  /'
    else
        echo "  (none)"
    fi
    
    rm "$temp1" "$temp2"
}

# Interactive menu
cmd_interactive() {
    while true; do
        clear
        print_header "Package List Manager - Interactive Mode"
        echo
        echo "1)  List package lists"
        echo "2)  Add packages to list"
        echo "3)  Remove packages from list"
        echo "4)  Install packages from list"
        echo "5)  Search packages"
        echo "6)  Create new list"
        echo "7)  Delete list"
        echo "8)  Backup lists"
        echo "9)  Restore lists"
        echo "10) Validate lists"
        echo "11) Merge lists"
        echo "12) Compare lists"
        echo "0)  Exit"
        echo
        echo -n "Choose an option [0-12]: "
        read -r choice
        
        case "$choice" in
            1)
                echo
                cmd_list --all
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            2)
                echo
                echo -n "List name: "
                read -r list_name
                if [[ -n "$list_name" ]]; then
                    cmd_add --interactive "$list_name"
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            3)
                echo
                echo -n "List name: "
                read -r list_name
                if [[ -n "$list_name" ]]; then
                    cmd_remove --interactive "$list_name"
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            4)
                echo
                cmd_list --count
                echo
                echo -n "List name to install: "
                read -r list_name
                if [[ -n "$list_name" ]]; then
                    cmd_install "$list_name"
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            5)
                echo
                echo -n "Search pattern: "
                read -r pattern
                if [[ -n "$pattern" ]]; then
                    cmd_search "$pattern"
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            6)
                echo
                echo -n "New list name: "
                read -r list_name
                if [[ -n "$list_name" ]]; then
                    echo -n "Use template? (basic/dev/server/python/empty): "
                    read -r template
                    if [[ -n "$template" && "$template" != "empty" ]]; then
                        cmd_create --template "$template" "$list_name"
                    else
                        cmd_create "$list_name"
                    fi
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            7)
                echo
                cmd_list --count
                echo
                echo -n "List name to delete: "
                read -r list_name
                if [[ -n "$list_name" ]]; then
                    cmd_delete "$list_name"
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            8)
                echo
                echo "1) Backup all lists"
                echo "2) Backup specific list"
                echo -n "Choice: "
                read -r backup_choice
                case "$backup_choice" in
                    1)
                        cmd_backup --all
                        ;;
                    2)
                        cmd_list --count
                        echo
                        echo -n "List name to backup: "
                        read -r list_name
                        if [[ -n "$list_name" ]]; then
                            cmd_backup "$list_name"
                        fi
                        ;;
                esac
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            9)
                echo
                if [[ -d "$BACKUP_DIR" ]]; then
                    echo "Available backups:"
                    ls -1 "$BACKUP_DIR" 2>/dev/null | sed 's/^/  /' || echo "  No backups found"
                else
                    echo "No backups found"
                fi
                echo
                echo -n "Backup name to restore: "
                read -r backup_name
                if [[ -n "$backup_name" ]]; then
                    cmd_restore "$backup_name"
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            10)
                echo
                echo "1) Validate all lists"
                echo "2) Validate specific list"
                echo -n "Choice: "
                read -r validate_choice
                case "$validate_choice" in
                    1)
                        cmd_validate
                        ;;
                    2)
                        cmd_list --count
                        echo
                        echo -n "List name to validate: "
                        read -r list_name
                        if [[ -n "$list_name" ]]; then
                            cmd_validate "$list_name"
                        fi
                        ;;
                esac
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            11)
                echo
                cmd_list --count
                echo
                echo -n "Output file name: "
                read -r output_file
                echo -n "Source files (space separated): "
                read -r source_files
                if [[ -n "$output_file" && -n "$source_files" ]]; then
                    cmd_merge --output "$output_file" $source_files
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            12)
                echo
                cmd_list --count
                echo
                echo -n "First list: "
                read -r list1
                echo -n "Second list: "
                read -r list2
                if [[ -n "$list1" && -n "$list2" ]]; then
                    cmd_diff "$list1" "$list2"
                fi
                echo
                echo -n "Press Enter to continue..."
                read -r
                ;;
            0)
                print_info "Goodbye!"
                break
                ;;
            *)
                print_error "Invalid choice: $choice"
                sleep 1
                ;;
        esac
    done
}

#==============================================================================
# Main Functions
#==============================================================================

# Parse global arguments
parse_global_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME version $SCRIPT_VERSION"
                exit 0
                ;;
            -V|--verbose)
                VERBOSE=true
                shift
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -*)
                print_error "Unknown global option: $1"
                exit 1
                ;;
            *)
                # This is the command
                echo "$@"
                return 0
                ;;
        esac
    done
    
    # No command provided
    echo ""
}

# Main function
main() {
    # Initialize
    init_dirs
    load_config
    
    # Parse global arguments
    local remaining_args
    remaining_args=$(parse_global_args "$@")
    
    if [[ -z "$remaining_args" ]]; then
        print_error "No command specified"
        print_info "Use '$SCRIPT_NAME --help' for usage information"
        exit 1
    fi
    
    # Extract command and its arguments
    set -- $remaining_args
    local command="$1"
    shift
    
    # Validate apt availability
    if [[ "$command" != "list" && "$command" != "search" ]]; then
        if ! command -v apt-get &> /dev/null; then
            print_error "This script requires apt package manager"
            exit 1
        fi
    fi
    
    # Execute command
    case "$command" in
        list)
            cmd_list "$@"
            ;;
        add)
            cmd_add "$@"
            ;;
        remove|rm)
            cmd_remove "$@"
            ;;
        install)
            cmd_install "$@"
            ;;
        search)
            cmd_search "$@"
            ;;
        backup)
            cmd_backup "$@"
            ;;
        restore)
            cmd_restore "$@"
            ;;
        validate)
            cmd_validate "$@"
            ;;
        merge)
            cmd_merge "$@"
            ;;
        diff)
            cmd_diff "$@"
            ;;
        create)
            cmd_create "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        interactive|menu)
            cmd_interactive "$@"
            ;;
        *)
            print_error "Unknown command: $command"
            print_info "Use '$SCRIPT_NAME --help' for available commands"
            exit 1
            ;;
    esac
    
    # Save configuration
    save_config
}

#==============================================================================
# Script Entry Point
#==============================================================================

# Handle Ctrl+C gracefully
trap 'echo; print_info "Operation cancelled by user"; exit 0' INT

# Run main function with all arguments
main "$@"