# Check if Python is installed
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Python not found. Installing Python 3.10+..."

    # Download and install Python (adjust URL if needed)
    $pythonUrl = "https://www.python.org/ftp/python/3.11.0/python-3.11.0-amd64.exe"
    $installerPath = "$env:TEMP\python_installer.exe"

    Invoke-WebRequest -Uri $pythonUrl -OutFile $installerPath
    Start-Process -Wait -FilePath $installerPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1"

    # Verify installation
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Error "Python installation failed. Please install manually from https://www.python.org/downloads/"
        exit 1
    }
}

# Check Python version
$pythonVersion = python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ([version]$pythonVersion -lt [version]"3.10") {
    Write-Error "SkillOpt requires Python 3.10+. Found: $pythonVersion"
    exit 1
}

# Install SkillOpt
Write-Host "Installing SkillOpt..."
python -m pip install --upgrade pip
python -m pip install skillopt

# Verify installation
try {
    python -c "import skillopt; print('SkillOpt installed successfully!')"
    Write-Host "SkillOpt is ready to use."
} catch {
    Write-Error "Installation failed. Check logs for errors."
    exit 1
}