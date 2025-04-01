# Image Processing Scripts

## Normalize Images

### Overview

This script processes `.jpg` and `.jpeg` images by normalizing brightness and contrast, and optionally enhancing saturation and adjusting hue based on user-defined parameters. The processed images are saved to a specified output directory.

### Requirements

- **ImageMagick**: Install using:
  - **macOS**: `brew install imagemagick`
  - **Ubuntu**: `sudo apt install imagemagick`

### Usage

Run the script with optional input and output directory arguments, along with optional modulate parameters:

```
./process_images.sh [-i input_dir] [-o output_dir] [-b brightness] [-s saturation] [-h hue]
```

#### Options:
- `-i <input_dir>`: Input directory for images (defaults to the current directory).
- `-o <output_dir>`: Output directory for processed images (defaults to `processed_images`).
- `-b <brightness>`: Brightness percentage (defaults to `101`, meaning no change).
- `-s <saturation>`: Saturation percentage (defaults to `105`, meaning 5% increase).
- `-h <hue>`: Hue percentage (defaults to `101`, meaning no change).

#### Examples:

1. **Default behavior** (process images with default settings):
   ```bash
   ./process_images.sh
   ```

2. **Custom input and output directories**:
   ```bash
   ./process_images.sh -i /path/to/input -o /path/to/output
   ```

3. **Custom brightness, saturation, and hue values**:
   ```bash
   ./process_images.sh -i /path/to/input -o /path/to/output -b 110 -s 120 -h 100
   ```

### Description

- The script processes `.jpg` and `.jpeg` files in the input directory.
- It applies `-normalize` to adjust brightness and contrast automatically.
- It enhances saturation by 5% (`default -s 105`) and adjusts hue as specified by the user.
- The processed images are saved in the output directory with the same filenames.
- Progress is logged every 20 images processed.

### Notes

- **Normalization**: The `-normalize` option automatically adjusts the image's brightness and contrast to balance the color levels.
- **Modulate**: The `-modulate` option adjusts brightness, saturation, and hue. The default values are `101, 105, 101`, which means no change in brightness, a 5% increase in saturation, and no change in hue.
- The script ensures the input directory exists and creates the output directory if necessary.
- Errors in processing individual images will not stop the script.