#!/bin/bash

# =========================================
# Professional-Style Auto Brightener Script
# Refactored + Filename cleaned (no extra dots)
# =========================================

# -------------------------
# Default Parameters
# -------------------------
INPUT_DIR=""
OUTPUT_DIR=""
BRIGHTNESS_FACTOR=1.0
TARGET_BRIGHT=55
BRIGHTNESS_BUFFER=5
THRESHOLD_SKIP=30
MIN_GAMMA=1.0
MAX_GAMMA=1.6
MAX_DESAT=20

# -------------------------
# Parse Flag-Style Arguments
# -------------------------
for arg in "$@"; do
    case $arg in
        --input_dir=*) INPUT_DIR="${arg#*=}" ;;
        --output_dir=*) OUTPUT_DIR="${arg#*=}" ;;
        --brightness_factor=*) BRIGHTNESS_FACTOR="${arg#*=}" ;;
        --threshold=*) TARGET_BRIGHT="${arg#*=}" ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# -------------------------
# Default Folders
# -------------------------
[ -z "$INPUT_DIR" ] && INPUT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="$INPUT_DIR/brightened"
mkdir -p "$OUTPUT_DIR"

echo "Input folder: $INPUT_DIR"
echo "Output folder: $OUTPUT_DIR"
echo "Brightness factor: $BRIGHTNESS_FACTOR"
echo "Target brightness: $TARGET_BRIGHT"
echo "--------------------------------------"

# -------------------------
# Functions
# -------------------------

# Calculate average brightness of image in Lab Lightness
calc_brightness() {
    local img="$1"
    convert "$img" -colorspace Lab -channel L -format "%[fx:100*mean]" info:
}

# Compute dynamic adjustment parameters based on image brightness
compute_adjustments() {
    local brightness="$1"

    # Gamma (global lightness adjustment)
    local gamma=$(echo "scale=2; 1 + (($TARGET_BRIGHT - $brightness)/100)*$BRIGHTNESS_FACTOR" | bc)
    gamma=$(echo "$gamma" | awk -v min="$MIN_GAMMA" -v max="$MAX_GAMMA" '{if($1<min) $1=min; if($1>max) $1=max; print $1}')

    # Modulate (brightness scaling)
    local modulate=$(echo "scale=0; (100 + (120-100)*(($TARGET_BRIGHT-$brightness)/$TARGET_BRIGHT))*$BRIGHTNESS_FACTOR" | bc)

    # Level adjustment (low and high thresholds)
    local level_low=$(echo "scale=2; 0 + (5*(($TARGET_BRIGHT-$brightness)/$TARGET_BRIGHT))*$BRIGHTNESS_FACTOR" | bc)
    local level_high=$(echo "scale=2; 100 - (5*(($TARGET_BRIGHT-$brightness)/$TARGET_BRIGHT))*$BRIGHTNESS_FACTOR" | bc)

    # Sigmoidal contrast (soft contrast curve to preserve highlights)
    local sigmoidal=$(echo "scale=1; (1 + (3-1)*(($TARGET_BRIGHT-$brightness)/$TARGET_BRIGHT))*$BRIGHTNESS_FACTOR" | bc)

    # Optional desaturation for very strong brightening
    local desat=$(echo "scale=0; 100 - (($gamma-1)*$MAX_DESAT/($MAX_GAMMA-1))" | bc)
    (( $(echo "$desat<0" | bc -l) )) && desat=0

    echo "$gamma $modulate $level_low $level_high $sigmoidal $desat"
}

# Apply brightening with gradient shadow/midtone mask
apply_brightening() {
    local img="$1"
    local output_file="$2"
    local gamma="$3"
    local modulate="$4"
    local level_low="$5"
    local level_high="$6"
    local sigmoidal="$7"
    local desat="$8"

    # Temporary shadow/midtone mask
    local shadow_mask="${OUTPUT_DIR}/$(basename "${img%.*}")_mask.png"

    # Create mask: dark areas emphasized, blurred for smooth transition
    convert "$img" -colorspace Lab -channel L -separate +channel -level 0%,50% -blur 0x2 "$shadow_mask"

    # Apply adjustments: gamma, modulate, levels, desaturation, and sigmoidal contrast
    convert "$img" \
        \( +clone -colorspace Lab -channel L -gamma "$gamma" \
           -modulate "$modulate","$desat",100 \
           -level ${level_low}%,${level_high}% +channel -colorspace sRGB \
        \) \
        "$shadow_mask" -compose CopyOpacity -composite \
        -sigmoidal-contrast ${sigmoidal}x50% \
        "$output_file"

    # Remove temporary mask
    rm "$shadow_mask"
}

# -------------------------
# Main Processing Loop
# -------------------------
for img in "$INPUT_DIR"/*.{jpg,jpeg,png}; do
    [ -e "$img" ] || continue
    filename=$(basename "$img")
    name="${filename%.*}"
    ext="${filename##*.}"

    # Calculate average brightness
    brightness=$(calc_brightness "$img")
    echo "Image: $filename -> Average brightness: $brightness"

    # Skip extremely dark images
    if (( $(echo "$brightness < $THRESHOLD_SKIP" | bc -l) )); then
        echo "   → Skipped (too dark)"
        continue
    fi

    # Copy images already bright enough
    if (( $(echo "$brightness >= ($TARGET_BRIGHT+$BRIGHTNESS_BUFFER)" | bc -l) )); then
        echo "   → Bright enough, copying"
        cp "$img" "$OUTPUT_DIR/$filename"
        continue
    fi

    # Compute adjustments for slightly dark images
    read gamma modulate level_low level_high sigmoidal desat <<< $(compute_adjustments "$brightness")

    # -------------------------
    # Encode adjustments in filename WITHOUT extra dots
    # Multiply floats to make integers
    # -------------------------
    gamma_int=$(printf "%.0f" $(echo "$gamma*10" | bc))
    modulate_int=$(printf "%.0f" "$modulate")
    level_low_int=$(printf "%.0f" "$level_low")
    level_high_int=$(printf "%.0f" "$level_high")
    sigmoidal_int=$(printf "%.0f" $(echo "$sigmoidal*10" | bc))

    adj_str="_G${gamma_int}_M${modulate_int}_L${level_low_int}-${level_high_int}_S${sigmoidal_int}"
    output_file="$OUTPUT_DIR/${name}${adj_str}.$ext"

    echo "   → Brightening: $adj_str, desaturation=${desat}%"

    # Apply the brightening adjustments
    apply_brightening "$img" "$output_file" "$gamma" "$modulate" "$level_low" "$level_high" "$sigmoidal" "$desat"

done

echo "--------------------------------------"
echo "Done! Processed images are in: $OUTPUT_DIR"

