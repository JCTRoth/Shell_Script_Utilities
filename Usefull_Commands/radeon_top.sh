#!/bin/bash
radeontop -d - -l 1 | grep -oE "gpu [0-9.]+%|vram [0-9.]+% [0-9.]+mb" | tr '\n' ' '