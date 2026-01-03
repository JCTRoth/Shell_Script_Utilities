# Node.js Setup Script

This script installs Node.js from the official binaries on Linux systems.
It supports installing specific versions or the latest in a major version series, automatically detects the system architecture, and handles version conflicts.

## Features

- **Version Selection**: Install a specific Node.js version (e.g., `v18.17.0`) or the latest in a major series (e.g., `20` for the newest 20.x version).
- **Architecture Detection**: Automatically detects x86_64, ARM64, ARMv7, etc., and downloads the appropriate binary.
- **Conflict Resolution**: Removes existing Node.js installations if they differ from the requested version.
- **Symlinks**: Creates symbolic links for `node`, `npm`, `npx`, and `nodejs` commands in `/usr/local/bin`.
- **Verification**: Tests all installed binaries after installation.
- **Logging**: Logs all operations to `/var/log/node_install.log`.

## Usage

```bash
sudo ./setup_nodeJs.sh [version]
```

### Arguments

- `version`: Optional. Can be:
  - A full version string (e.g., `v18.17.0`)
  - A major version number (e.g., `20`) to install the latest in that series
  - If omitted, installs the latest LTS version

### Examples

```bash
# Install the latest LTS version
sudo ./setup_nodeJs.sh

# Install the latest in Node.js 20.x series
sudo ./setup_nodeJs.sh 20

# Install a specific version
sudo ./setup_nodeJs.sh v18.17.0
```

## What It Does

1. **Purge System Packages**: Removes any system-installed `nodejs` and `npm` packages to avoid conflicts.
2. **Version Resolution**: Determines the exact version to install based on input.
3. **Architecture Check**: Detects the system architecture and selects the correct binary.
4. **Download**: Fetches the Node.js tarball from `nodejs.org`.
5. **Extraction**: Extracts to `/opt/node-{version}-linux-{arch}/`.
6. **Cleanup**: Removes the downloaded tarball.
7. **Symlinks**: Creates symlinks in `/usr/local/bin` for easy access.
8. **Testing**: Verifies all commands work and logs versions.

## Installation Location

- **Binaries**: `/opt/node-{version}-linux-{arch}/bin/`
- **Symlinks**: `/usr/local/bin/` (points to the above)
- **Log File**: `/var/log/node_install.log`

## Troubleshooting

### Permission Denied
- Ensure you're running with `sudo`.
- Check that `/var/log`, `/opt`, and `/usr/local/bin` are writable by root.

### Download Fails
- Verify internet connection.
- Check if the requested version exists on [nodejs.org/dist/](https://nodejs.org/dist/).
- For major versions, ensure there are releases in that series.

### Architecture Not Supported
- The script supports x86_64, ARM64, and ARMv7.
- Unknown architectures fall back to x64 with a warning.

### jq Not Found
- Install `jq`: `sudo apt install jq` (on Debian/Ubuntu).

### Existing Installation Not Removed
- The script only removes installations with different versions.
- If the same version is requested, it overwrites the existing install.

## Uninstalling

To remove Node.js installed by this script:

```bash
sudo rm -rf /opt/node-*
sudo rm /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/nodejs
```

## License

This script is part of the Shell Script Utilities collection. See the main README for more information.</content>
<parameter name="filePath">/home/jonas/Git/Shell_Script_Utilities/Program_Setups/README.md