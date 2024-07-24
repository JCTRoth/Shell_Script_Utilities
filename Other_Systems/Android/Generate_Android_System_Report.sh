#!/bin/bash

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    echo "ADB command not found. Please install ADB and try again."
    exit 1
fi

# Check if a device is connected
if ! adb get-state &> /dev/null; then
    echo "No device connected. Please connect a device and enable USB debugging."
    exit 1
fi

# Create a timestamp for the report
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

# Get the device model to use in the folder name
device_model=$(adb shell getprop ro.product.model | tr -d '\r')
folder_name="${device_model}_${timestamp}"

# Create directory for the report
mkdir -p "$folder_name"

# Output file paths
report_file="$folder_name/system_report.txt"
logcat_file="$folder_name/logcat.log"
dumpsys_file="$folder_name/dumpsys.log"

echo "Collecting system information..."

# Collect information
{
    echo "--------------------------------------------------"
    echo "Android System Report"
    echo "--------------------------------------------------"
    echo ""
    echo "Date and Time: $(date +"%Y-%m-%d %H:%M:%S")"

    echo ""
    echo "Device Model:"
    adb shell getprop ro.product.model

    echo ""
    echo "Manufacturer:"
    adb shell getprop ro.product.manufacturer

    echo ""
    echo "Android Version:"
    adb shell getprop ro.build.version.release

    echo ""
    echo "Build Number:"
    adb shell getprop ro.build.display.id

    echo ""
    echo "SDK Version:"
    adb shell getprop ro.build.version.sdk

    echo ""
    echo "Hardware:"
    adb shell getprop ro.hardware

    echo ""
    echo "CPU Architecture:"
    adb shell getprop ro.product.cpu.abi

    echo ""
    echo "Serial Number:"
    adb shell getprop ro.serialno

    echo ""
    echo "Battery Status:"
    battery_info=$(adb shell dumpsys battery)

    # Extract relevant fields
    battery_level=$(echo "$battery_info" | grep 'level:' | awk '{print $2}')
    battery_status=$(echo "$battery_info" | grep 'status:' | awk '{print $2}')
    battery_health=$(echo "$battery_info" | grep 'health:' | awk '{print $2}')
    battery_charge_counter=$(echo "$battery_info" | grep 'charge counter:' | awk '{print $3}')
    battery_voltage=$(echo "$battery_info" | grep 'voltage:' | awk '{print $2}')
    battery_temperature=$(echo "$battery_info" | grep 'temperature:' | awk '{print $2}')

    # Interpretation of battery status
    case $battery_status in
        1) status_description="Unknown" ;;
        2) status_description="Charging" ;;
        3) status_description="Discharging" ;;
        4) status_description="Not charging" ;;
        5) status_description="Full" ;;
        *) status_description="Unknown status code" ;;
    esac

    # Interpretation of battery health
    case $battery_health in
        1) health_description="Unknown" ;;
        2) health_description="Good" ;;
        3) health_description="Overheat" ;;
        4) health_description="Dead" ;;
        5) health_description="Over voltage" ;;
        6) health_description="Unspecified failure" ;;
        7) health_description="Cold" ;;
        *) health_description="Unknown health code" ;;
    esac

    # Convert temperature from tenths of a degree Celsius to Celsius
    battery_temperature_celsius=$(echo "scale=1; $battery_temperature / 10" | bc)

    echo "Battery Level: ${battery_level}%"
    echo "Battery Status: $status_description (Code: $battery_status)"
    echo "Battery Health: $health_description (Code: $battery_health)"
    echo "Battery Charge Counter: ${battery_charge_counter} μAh"
    echo "Battery Voltage: ${battery_voltage} mV"
    echo "Battery Temperature: ${battery_temperature_celsius}°C"

    echo ""
    echo "CPU Info:"
    cpuinfo=$(adb shell cat /proc/cpuinfo)

    # Calculate total number of cores
    total_cores=$(echo "$cpuinfo" | grep -c '^Processor')

    # Gather and combine core information
    cpu_model=$(echo "$cpuinfo" | grep 'Hardware' | head -n 1 | sed 's/Hardware\t: //')
    cpu_cores=$(echo "$cpuinfo" | grep 'processor' | wc -l)
    cpu_architecture=$(adb shell getprop ro.product.cpu.abi)

    # Get CPU frequency
    cpu_max_freq=$(adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
    cpu_min_freq=$(adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq)
    cpu_max_freq_ghz=$(echo "scale=2; $cpu_max_freq / 1000000" | bc)
    cpu_min_freq_ghz=$(echo "scale=2; $cpu_min_freq / 1000000" | bc)

    echo "CPU Model: $cpu_model"
    echo "CPU Architecture: $cpu_architecture"
    echo "Total Cores: $cpu_cores"
    echo "CPU Max Frequency: ${cpu_max_freq_ghz} GHz"
    echo "CPU Min Frequency: ${cpu_min_freq_ghz} GHz"

    echo ""
    echo "Screen Info:"
    screen_resolution=$(adb shell wm size | awk '{print $3}')
    screen_density=$(adb shell wm density | awk '{print $3}')
    echo "Screen Resolution: $screen_resolution"
    echo "Screen Density: $screen_density dpi"

    echo ""
    echo "Internal Storage Size:"
    adb shell df -h | grep '/data'

    echo ""
    echo "RAM and Process Info:"
    adb shell top -b -n 1 -m 30

    echo ""
    echo "Audio Info:"
    adb shell dumpsys media.audio_flinger | grep -E 'Stream|Mixer' | sed 's/Stream\s*: //'

    echo ""
    echo "User Installed Packages:"
    adb shell pm list packages -3

    echo ""
    echo -e "\nSystem Properties:"
    adb shell getprop

} > "$report_file"

echo "System report saved to $report_file"

echo "Collecting logcat output..."

# Capture logcat output
adb logcat -d > "$logcat_file"

echo "Logcat saved to $logcat_file"

echo "Collecting dumpsys..."

# save dumpsys
adb shell dumpsys > "$dumpsys_file"

echo "Dumpsys file saved to $dumpsys_file"

echo "System information collection complete."
