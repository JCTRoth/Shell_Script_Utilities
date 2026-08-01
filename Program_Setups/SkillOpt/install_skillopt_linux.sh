#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

# Install Python 3.10+ and pip if missing
if ! command -v python3 &> /dev/null; then
    echo "Python3 is not installed. Installing..."
    if command -v dnf &> /dev/null; then
        dnf install python3 python3-pip -y
    elif command -v apt &> /dev/null; then
        apt update && apt install python3 python3-pip -y
    else
        echo "Unsupported package manager. Please install Python 3.10+ and pip manually."
        exit 1
    fi
fi

# Check Python version
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
if [ "$(printf '%s\n3.10' "$PYTHON_VERSION" | sort -V | head -n1)" != "3.10" ]; then
    echo "Python 3.10+ is required. Found: $PYTHON_VERSION"
    echo "Upgrade Python or install a newer version manually."
    exit 1
fi

# Install SkillOpt
echo "Installing SkillOpt..."
python3 -m pip install --upgrade pip
python3 -m pip install skillopt

# Verify installation
if python3 -c "import skillopt; print('SkillOpt installed successfully!')"; then
    echo "SkillOpt is ready to use."
else
    echo "Installation failed. Check logs for errors."
    exit 1
fi