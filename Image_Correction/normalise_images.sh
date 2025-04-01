#!/bin/bash

# Initialize variables for input and output directories, and modulate values
input_dir="."
output_dir="processed_images"
brightness=101
saturation=105
hue=101

# Parse command-line options for input and output directories, and modulate values
while getopts "i:o:b:s:h:" opt; do
    case "$opt" in
        i) input_dir="$OPTARG" ;;  # Input directory
        o) output_dir="$OPTARG" ;;  # Output directory
        b) brightness="$OPTARG" ;;  # Brightness value
        s) saturation="$OPTARG" ;;  # Saturation value
        h) hue="$OPTARG" ;;  # Hue value
        *) echo "Usage: $0 [-i input_dir] [-o output_dir] [-b brightness] [-s saturation] [-h hue]"; exit 1 ;;
    esac
done

# Ensure the input directory exists
if [ ! -d "$input_dir" ]; then
    echo "Error: Input directory '$input_dir' does not exist."
    exit 1
fi

# Create the output directory if it doesn't exist
mkdir -p "$output_dir"

# Count the number of .jpg and .jpeg files in the input directory
total_files=$(ls "$input_dir"/*.jpg "$input_dir"/*.jpeg 2>/dev/null | wc -l)

# Output how many files will be processed
echo "Total files to process in '$input_dir': $total_files"

# Initialize counters
total_images=0
processed_images=0

# Process each image file in the input directory
for img in "$input_dir"/*.jpg "$input_dir"/*.jpeg; do
    if [ -f "$img" ]; then
        ((total_images++))
        
        # Every 20 files, print a log
        if (( total_images % 20 == 0 )); then
            echo "Processed $total_images files so far..."
        fi

        # Ensure all modulate values are set correctly
        if [ -z "$brightness" ] || [ -z "$saturation" ] || [ -z "$hue" ]; then
            echo "Error: One or more modulate values are missing. Using defaults."
            brightness=101
            saturation=105
            hue=101
        fi

        # Normalize the image (adjust brightness and contrast) and increase saturation by the specified values
        convert "$img" -normalize -modulate "$brightness","$saturation","$hue" "$output_dir/$(basename "$img")"
        
        if [ $? -eq 0 ]; then
            ((processed_images++))
        else
            echo "Error processing image: $img"
        fi
    fi
done

# Output summary
echo "Total images processed: $total_images"
echo "Images successfully processed: $processed_images"
