# Package List Management System

A comprehensive package management system for Ubuntu/Debian-based Linux distributions that helps you organize, manage, and install packages using curated lists.

## Features

- **Unified Management**: Single interface for all package list operations
- **Interactive Mode**: User-friendly menu system for easy navigation
- **Package Validation**: Automatic verification of package availability
- **Multiple Operations**: List, add, remove, install, search packages
- **Smart Detection**: Architecture and dependency detection
- **Backup/Restore**: Built-in backup and rollback capabilities
- **Colored Output**: Enhanced readability with color-coded messages
- **Dry Run Mode**: Preview operations before execution
- **Comprehensive Logging**: Detailed operation tracking

## File Structure

```
List_Installation/
├── package_manager.sh      # Main unified package manager
├── add_pack.sh            # Enhanced package addition script
├── install_list.sh        # Improved package installation script
├── lists/                 # Package list storage
│   ├── developer.list     # Development tools
│   ├── server.list        # Server packages
│   ├── python.list        # Python ecosystem
│   └── *.list             # Custom package lists
├── backups/               # Backup storage (auto-created)
└── README.md              # This documentation
```

## Installation

1. Clone or download the Shell_Script_Utilities repository
2. Navigate to the List_Installation directory:
   ```bash
   cd Shell_Script_Utilities/List_Installation
   ```
3. Make scripts executable (if not already):
   ```bash
   chmod +x *.sh
   ```

## Usage

### Main Package Manager

The unified package manager (`package_manager.sh`) provides all functionality in one script:

```bash
./package_manager.sh [GLOBAL_OPTIONS] COMMAND [COMMAND_OPTIONS] [ARGUMENTS]
```

#### Global Options
- `-h, --help`: Show help information
- `-v, --version`: Show script version
- `-V, --verbose`: Enable verbose output
- `-y, --yes`: Automatic yes to prompts
- `-n, --dry-run`: Preview operations without executing

#### Available Commands

##### 1. List Operations
```bash
# List all available package lists
./package_manager.sh list

# Show contents of specific list
./package_manager.sh list developer.list

# Show all lists with contents
./package_manager.sh list --all

# Show package counts only
./package_manager.sh list --count
```

##### 2. Add Packages
```bash
# Add specific packages to a list
./package_manager.sh add developer.list git vim curl

# Interactive package addition
./package_manager.sh add --interactive developer.list

# Create new list and add packages
./package_manager.sh add --create newlist.list package1 package2
```

##### 3. Remove Packages
```bash
# Remove specific packages
./package_manager.sh remove developer.list vim

# Interactive removal
./package_manager.sh remove --interactive developer.list

# Clear entire list
./package_manager.sh remove --all developer.list
```

##### 4. Install Packages
```bash
# Install packages from list
./package_manager.sh install developer.list

# Update cache and install automatically
./package_manager.sh install --update --yes server.list

# Simulate installation (preview)
./package_manager.sh install --simulate python.list
```

##### 5. Search Packages
```bash
# Search for packages across all lists
./package_manager.sh search nodejs

# Case-insensitive search
./package_manager.sh search --ignore-case PYTHON

# Show only list names containing matches
./package_manager.sh search --list-only docker
```

##### 6. Interactive Mode
```bash
# Start interactive menu system
./package_manager.sh interactive
```

### Individual Scripts

#### Enhanced Add Packages Script
```bash
# Interactive mode
./add_pack.sh

# Specify list file directly
./add_pack.sh developer.list

# Create new list
./add_pack.sh --create --interactive newlist.list
```

#### Enhanced Install Script
```bash
# Install from list
./install_list.sh developer.list

# Preview installation
./install_list.sh --dry-run server.list

# Update and install automatically
./install_list.sh --update --yes python.list
```

## Package List Format

Package lists are simple text files with one package per line:

```
# This is a comment
git
vim
curl
nodejs
python3-pip

# Another comment
docker.io
```

### Format Rules
- One package name per line
- Lines starting with `#` are comments
- Empty lines are ignored
- Package names are automatically validated

## Examples

### Example 1: Setting up a Development Environment
```bash
# Create a new development list
./package_manager.sh add --create dev-env.list git vim curl nodejs npm

# Preview what will be installed
./package_manager.sh install --simulate dev-env.list

# Install the packages
./package_manager.sh install --update dev-env.list
```

### Example 2: Managing Server Packages
```bash
# Add server packages interactively
./package_manager.sh add --interactive server.list

# List current packages
./package_manager.sh list server.list

# Install with automatic confirmation
./package_manager.sh install --yes server.list
```

### Example 3: Finding Packages
```bash
# Search for Docker-related packages
./package_manager.sh search docker

# Find all lists containing Python packages
./package_manager.sh search --ignore-case python
```

## Advanced Features

### Dry Run Mode
Preview operations without making changes:
```bash
./package_manager.sh --dry-run add developer.list new-package
./package_manager.sh --dry-run install server.list
```

### Verbose Output
Get detailed information about operations:
```bash
./package_manager.sh --verbose install developer.list
```

### Batch Operations
Combine multiple flags for powerful operations:
```bash
# Update cache, install automatically, with verbose output
./package_manager.sh --verbose --yes install --update server.list
```

## Safety Features

### Package Validation
- Automatically checks if packages exist in repositories
- Warns about unavailable packages
- Prevents installation of non-existent packages

### Confirmation Prompts
- Requests confirmation for destructive operations
- Can be bypassed with `--yes` flag for automation
- Provides clear operation summaries

### Error Handling
- Comprehensive error checking
- Graceful handling of failures
- Detailed error messages with suggestions

## Package List Examples

### Developer Tools
```bash
# lists/developer.list
git
micro
curl
wget
build-essential
nodejs
npm
python3-pip
docker.io
```

### Server Essentials
```bash
# lists/server.list
nginx
certbot
fail2ban
ufw
htop
```

### Python Development
```bash
# lists/python.list
python3
python3-pip
python3-venv
python3-dev
jupyter
pylint
black
```

## Troubleshooting

### Common Issues

#### Package Not Found
```
ERROR: Package 'example-package' not found in repositories
```
**Solution**: Update package cache or check package name:
```bash
sudo apt update
./package_manager.sh install --update your-list.list
```

#### Permission Denied
```
ERROR: This script must be run as root
```
**Solution**: Use sudo for installation operations:
```bash
sudo ./install_list.sh your-list.list
```

#### List File Not Found
```
ERROR: Package list file not found: missing.list
```
**Solution**: Create the list or use correct path:
```bash
./package_manager.sh add --create missing.list
./package_manager.sh list  # Show available lists
```

### Debug Mode
Enable verbose output for debugging:
```bash
./package_manager.sh --verbose --dry-run install your-list.list
```

## Best Practices

### Package Management
- Test with `--dry-run` before installation
- Update package cache regularly with `--update`
- Use version control for your package lists
- Create backups before major changes

### List Organization
- Use descriptive names: `web-dev.list`, `server-minimal.list`
- Group related packages together
- Add comments to document package purposes
- Keep lists focused and manageable