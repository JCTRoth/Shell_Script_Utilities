#!/bin/bash

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if ! command -v brew &> /dev/null; then
        echo "Homebrew installation failed. Please install manually from https://brew.sh/"
        exit 1
    fi
    # Add Homebrew to PATH for this session
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Check if Python 3.10+ is installed
if ! command -v python3 &> /dev/null; then
    echo "Python3 not found. Installing Python 3.11 via Homebrew..."
    brew install python@3.11
fi

# Check Python version
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
if [ "$(printf '%s\n3.10' "$PYTHON_VERSION" | sort -V | head -n1)" != "3.10" ]; then
    echo "Python 3.10+ is required. Found: $PYTHON_VERSION"
    exit 1
fi

# Install SkillOpt
echo "Installing SkillOpt..."
python3 -m pip install --upgrade pip
python3 -m pip install skillopt
python3 -m pip install typing-extensions

# Verify installation
if python3 -c "import skillopt; print('SkillOpt installed successfully!')"; then
    echo "SkillOpt is ready to use."
else
    echo "Installation failed. Check logs for errors."
    exit 1
fi