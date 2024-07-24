# Android Report Generator

This script collects detailed system information from a connected Android device using ADB (Android Debug Bridge). \
The collected data includes system properties, battery status, CPU information, screen details, storage size, RAM and process information, audio information, installed packages, and logs.

## Prerequisites

- ADB must be installed on your system.
- USB debugging must be enabled on the connected Android device.
- A USB cable to connect the device to your computer.

## Usage

1. **Ensure ADB is installed**: Make sure you have ADB installed on your system. If not, follow the [official guide](https://developer.android.com/studio/command-line/adb) to install ADB.

2. **Enable USB Debugging on the device**: 
   - Go to `Settings` > `About phone`.
   - Tap `Build number` seven times to unlock Developer options.
   - Go to `Settings` > `Developer options`.
   - Enable `USB debugging`.

3. **Connect the device**: Use a USB cable to connect your Android device to the computer.

4. **Run the script**: Execute the script in your terminal.

   ```bash
   ./Generate_Android_System_Report.sh
   ```

## Output

The script generates a timestamped folder named after the device model and current timestamp, e.g., `Pixel_4_2024-07-24_14-30-00`. Inside this folder, it creates the following files:

1. `system_report.txt`: Contains detailed system information including device model, manufacturer, Android version, build number, SDK version, hardware, CPU architecture, serial number, battery status, CPU info, screen info, internal storage size, RAM and process info, audio info, user-installed packages, and system properties.

2. `logcat.log`: Contains the logcat output, which logs system messages, including stack traces when the device throws an error.

3. `dumpsys.log`: Contains the complete output of the `dumpsys` command, providing detailed information about the system services.

## Example

### System Report

The system report includes various sections:

- **Device Information**: Model, manufacturer, Android version, build number, SDK version, hardware, CPU architecture, serial number.
- **Battery Status**: Level, status, health, charge counter, voltage, temperature.
- **CPU Info**: Model, architecture, total cores, max and min frequencies.
- **Screen Info**: Resolution and density.
- **Internal Storage Size**: Available storage information.
- **RAM and Process Info**: Current memory usage and top processes.
- **Audio Info**: Audio stream and mixer information.
- **Installed Packages**: List of user-installed packages.
- **System Properties**: All system properties retrieved via `getprop`.

### Logcat Output

The logcat output captures real-time system messages, errors, and debugging information, useful for troubleshooting and development.

### Dumpsys Output

The dumpsys output provides detailed information about the system services running on the device, useful for in-depth system analysis.

## Notes

- The script will check if ADB is installed and if a device is connected before proceeding with the information collection.
- Ensure the connected device has USB debugging enabled and is authorized for ADB commands.