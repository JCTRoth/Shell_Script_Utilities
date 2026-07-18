#!/bin/bash
# ============================================================================
# ocr_gui.sh — Graphical convenience wrapper for OCRmyPDF
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION — resolved once in main(), exposed as globals
# ============================================================================
SCRIPT_DIR=""      # directory of this script
LOG_FILE=""         # path to error log
SETTINGS_FILE=""    # path to JSON settings file

# ============================================================================
# HELPER — clean exit with optional GUI error
# ============================================================================
die() {
    local msg="$1"
    local gui="${2:-yes}"
    if [[ "$gui" == "yes" ]] && command -v zenity &>/dev/null; then
        zenity --error --text="$msg" --width=350 2>/dev/null
    fi
    echo "Error: $msg" >&2
    exit 1
}

# ============================================================================
# SETTINGS REGISTRY — every known setting with its display label and default
# ============================================================================
# When you add a new setting, append to each array at the same index.
ALL_SETTINGS_KEYS=(
    "text_mode"
)
ALL_SETTINGS_LABELS=(
    "Text handling mode"
)
ALL_SETTINGS_DEFAULTS=(
    "--skip-text"
)

# ============================================================================
# SETTINGS MANAGEMENT (JSON via python3)
# ============================================================================

# Read a stored setting; returns empty string + non-zero if missing
get_setting() {
    local key="$1"
    python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        s = json.load(f)
    val = s.get('$key', '')
    if val == '':
        sys.exit(1)
    print(val)
except:
    sys.exit(1)
" 2>/dev/null
}

# Store a string setting
save_setting() {
    local key="$1"
    local value="$2"
    python3 -c "
import json
try:
    with open('$SETTINGS_FILE') as f:
        s = json.load(f)
except:
    s = {}
s['$key'] = '$value'
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(s, f, indent=2)
" 2>/dev/null
}

# Delete a single setting
remove_setting() {
    local key="$1"
    python3 -c "
import json
try:
    with open('$SETTINGS_FILE') as f:
        s = json.load(f)
    s.pop('$key', None)
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(s, f, indent=2)
except:
    pass
" 2>/dev/null
}

# ============================================================================
# UI — Dialogs (all handle cancellation by returning empty / calling exit)
# ============================================================================

# Main radio list: "Process single file" | "Process folder" | "Settings"
select_mode() {
    zenity --list --radiolist --title="OCRmyPDF Convenience Center" \
        --column="Pick" --column="Action" \
        TRUE  "Process single PDF file" \
        FALSE "Process a whole folder" \
        FALSE "Settings" \
        --width=450 --height=280 2>/dev/null
}

# File picker — returns path, empty = cancelled
select_pdf_file() {
    zenity --file-selection --title="Select a PDF file" \
        --file-filter="PDF Documents | *.pdf *.PDF" 2>/dev/null
}

# Directory picker — returns path, empty = cancelled
select_folder() {
    zenity --file-selection --directory --title="Select a folder with PDFs" 2>/dev/null
}

# Language checklist — returns pipe-separated codes, empty = cancelled
select_languages() {
    local -a langs=()
    local first=TRUE

    while read -r lang; do
        if [[ ! "$lang" =~ ^(osd|pdf|snum)$ && -n "$lang" ]]; then
            langs+=("$first" "$lang")
            first=FALSE
        fi
    done < <(tesseract --list-langs 2>/dev/null | tail -n +2)

    # Fallback if no languages are detected
    if [[ ${#langs[@]} -eq 0 ]]; then
        langs=(TRUE deu FALSE eng)
    fi

    zenity --list --checklist \
        --title="Installed OCR Languages" \
        --text="Select one or more languages:" \
        --column="Pick" --column="Code" \
        "${langs[@]}" \
        --width=350 --height=350 2>/dev/null
}

# Text-mode dialog (with "remember" checkbox) or auto-apply saved setting
# Returns the ocrmypdf flag: "--skip-text" or "--force-ocr"
select_text_mode() {
    local saved
    saved=$(get_setting "text_mode")
    if [[ -n "$saved" ]]; then
        echo "$saved"
        return 0
    fi

    local choice
    choice=$(zenity --forms --title="Handling existing text" \
        --text="Should PDFs that already contain a text layer be skipped?\n\n\
--skip-text = Skip existing text (faster)\n\
--force-ocr = Force OCR and rebuild text" \
        --add-combo="Mode" --combo-values="--skip-text|--force-ocr" \
        --add-checkbox="Remember this setting" \
        --width=500 2>/dev/null)

    # Cancel/close → signal "go back" (empty output, non-zero exit)
    [[ $? -ne 0 || -z "$choice" ]] && return 1

    # Parse "mode|true/false"
    local mode remember
    mode="${choice%%|*}"
    remember="${choice##*|}"
    mode=$(echo "$mode" | awk '{print $1}')

    if [[ "$remember" == "true" ]]; then
        save_setting "text_mode" "$mode"
    fi

    echo "$mode"
}

# Settings-management window — shows ALL known settings as checkboxes.
# Checked = setting is saved (and will be auto-applied).  Unchecked = not saved.
show_settings() {
    # Load currently saved keys into a quick lookup set
    local -A saved_map=()
    if [[ -f "$SETTINGS_FILE" ]]; then
        while IFS='|' read -r k v; do
            [[ -n "$k" ]] && saved_map["$k"]="$v"
        done < <(python3 -c "
import json
try:
    with open('$SETTINGS_FILE') as f:
        s = json.load(f)
    for k, v in s.items():
        print(f'{k}|{v}')
except:
    pass
" 2>/dev/null)
    fi

    # Build checklist: one row per known setting
    local -a args=()
    local i
    for i in "${!ALL_SETTINGS_KEYS[@]}"; do
        local key="${ALL_SETTINGS_KEYS[$i]}"
        local label="${ALL_SETTINGS_LABELS[$i]}"
        local default="${ALL_SETTINGS_DEFAULTS[$i]}"

        if [[ -n "${saved_map[$key]+set}" ]]; then
            # Saved → show checked with actual value
            args+=(TRUE "$label" "${saved_map[$key]}")
        else
            # Not saved → show unchecked with default (greyed out hint)
            args+=(FALSE "$label" "(default: $default)")
        fi
    done

    local result
    result=$(zenity --list --checklist \
        --title="OCR Settings" \
        --text="Checked settings are remembered and applied automatically.\nUnchecked settings will prompt you each time.\n\nTo change a saved value: uncheck it, save, then run the workflow again." \
        --column="Active" --column="Setting" --column="Value" \
        "${args[@]}" \
        --width=650 --height=300 2>/dev/null)
    [[ $? -ne 0 ]] && return   # cancelled

    # result contains pipe-separated LABELS (not keys!) that are still checked.
    # We need to map labels back to keys to determine what changed.
    local -a checked_labels=()
    IFS='|' read -ra checked_labels <<< "$result"

    # Build a set of checked keys for O(1) lookup
    local -A checked_keys=()
    for label in "${checked_labels[@]}"; do
        for i in "${!ALL_SETTINGS_LABELS[@]}"; do
            if [[ "${ALL_SETTINGS_LABELS[$i]}" == "$label" ]]; then
                checked_keys["${ALL_SETTINGS_KEYS[$i]}"]=1
                break
            fi
        done
    done

    # Apply changes: save newly-checked settings, remove unchecked ones
    local changed=false
    for i in "${!ALL_SETTINGS_KEYS[@]}"; do
        local key="${ALL_SETTINGS_KEYS[$i]}"
        local was_saved=false
        [[ -n "${saved_map[$key]+set}" ]] && was_saved=true
        local is_checked=false
        [[ -n "${checked_keys[$key]+set}" ]] && is_checked=true

        if $is_checked && ! $was_saved; then
            # Newly enabled → save with default
            save_setting "$key" "${ALL_SETTINGS_DEFAULTS[$i]}"
            changed=true
        elif ! $is_checked && $was_saved; then
            # Disabled → remove
            remove_setting "$key"
            changed=true
        fi
        # (both checked + saved, or both unchecked + unsaved → no-op)
    done

    if $changed; then
        zenity --info --title="Settings" \
            --text="Settings updated." --width=300 2>/dev/null
    fi
}

# ============================================================================
# CORE — OCR processing
# ============================================================================

# Process a single PDF. Parameters are explicit (no globals).
process_ocr() {
    local src="$1"          # source PDF path
    local lang_param="$2"   # e.g. "deu+eng"
    local text_mode="$3"    # "--skip-text" or "--force-ocr"
    local log_file="$4"     # error log path

    # Skip files that were already processed (*_OCR.pdf)
    local base="${src%.*}"
    [[ "$base" == *_OCR ]] && return 0

    local dir; dir=$(dirname "$src")
    local name; name=$(basename "$src")
    name="${name%.*}"                         # strip .pdf / .PDF
    local dest="${dir}/${name}_OCR.pdf"

    echo "# Processing: ${name}.pdf..."

    local tmp_err; tmp_err=$(mktemp)

    ocrmypdf -l "$lang_param" \
             "$text_mode" \
             --rotate-pages \
             --rotate-pages-threshold 12 \
             --deskew \
             --clean \
             --oversample 300 \
             --optimize 1 \
             --pdf-renderer sandwich \
             "$src" "$dest" > /dev/null 2> "$tmp_err"

    local rc=$?

    if [[ $rc -ne 0 ]]; then
        {
            echo ""
            echo "=== ERROR IN FILE: ${name}.pdf ==="
            echo "Timestamp: $(date)"
            cat "$tmp_err"
            echo "=================================================="
        } >> "$log_file"

        echo "[!] OCRmyPDF error at ${name}.pdf:" >&2
        cat "$tmp_err" >&2

        rm -f "$dest"       # remove partial output
    fi

    rm -f "$tmp_err"
    return $rc
}

# ============================================================================
# EXECUTION — single file
# ============================================================================

run_single_file() {
    local target="$1"
    local lang_param="$2"
    local text_mode="$3"

    # Validate extension
    if [[ ! "${target,,}" =~ \.pdf$ ]]; then
        die "The selected file is not a PDF document." yes
    fi

    process_ocr "$target" "$lang_param" "$text_mode" "$LOG_FILE" \
        | zenity --progress --title="OCR running" \
                 --text="Initializing document..." \
                 --pulsate --auto-close 2>/dev/null

    local zen_exit=$?
    if [[ $zen_exit -ne 0 ]]; then
        zenity --warning --title="OCR Aborted" \
            --text="The process was aborted." --width=300 2>/dev/null
        exit 1
    fi

    local outfile="${target%.*}_OCR.pdf"
    if [[ -f "$outfile" ]]; then
        zenity --info --title="OCR Success" \
            --text="Success!\nFile saved as:\n\n$outfile" \
            --width=450 2>/dev/null
    else
        local last_err
        last_err=$(tail -n 15 "$LOG_FILE" 2>/dev/null)
        [[ -z "$last_err" ]] && last_err="Process was aborted or terminated without error output."
        zenity --error --title="OCR Failed" \
            --text="Processing failed!\n\nDetails saved in: $LOG_FILE\n\nLast error:\n$last_err" \
            --width=500 2>/dev/null
    fi
}

# ============================================================================
# EXECUTION — batch folder
# ============================================================================

run_folder() {
    local folder="$1"
    local lang_param="$2"
    local text_mode="$3"

    # Gather non-processed PDFs
    local -a files=()
    mapfile -d $'\0' files < <(find "$folder" -maxdepth 1 \
        -iname "*.pdf" ! -iname "*_OCR.pdf" -print0)

    if [[ ${#files[@]} -eq 0 ]]; then
        zenity --info --title="Folder OCR" \
            --text="No new PDF files found in the folder.\n(Already processed _OCR.pdf files were skipped)." \
            --width=450 2>/dev/null
        return 0
    fi

    local total=${#files[@]}
    local had_errors=0

    (
        trap 'exit 1' SIGPIPE   # user closes progress bar

        local count=0
        for f in "${files[@]}"; do
            count=$((count + 1))
            local pct=$((count * 100 / total))

            process_ocr "$f" "$lang_param" "$text_mode" "$LOG_FILE" \
                || had_errors=$((had_errors + 1))

            echo "$pct"
        done
    ) | zenity --progress --title="Batch OCR active" \
                --text="Processing folder contents..." \
                --percentage=0 --auto-close 2>/dev/null

    local zen_exit=$?

    if [[ $zen_exit -ne 0 ]]; then
        zenity --warning --title="Batch OCR" \
            --text="The process was aborted prematurely.\nAlready processed files have been saved." \
            --width=450 2>/dev/null
    elif grep -q "ERROR IN FILE" "$LOG_FILE" 2>/dev/null; then
        zenity --warning --title="Batch OCR" \
            --text="Folder processing finished, but errors occurred!\n\nCheck: $LOG_FILE" \
            --width=450 2>/dev/null
    else
        zenity --info --title="Batch OCR" \
            --text="Folder processing successfully completed!\nAll PDFs have been made searchable." \
            --width=400 2>/dev/null
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # ---- Resolve paths early ----
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    SETTINGS_FILE="${SCRIPT_DIR}/ocr_settings.json"

    if [[ -d "$HOME/Schreibtisch" ]]; then
        LOG_FILE="$HOME/Schreibtisch/ocr_error.log"
    elif [[ -d "$HOME/Desktop" ]]; then
        LOG_FILE="$HOME/Desktop/ocr_error.log"
    else
        LOG_FILE="$SCRIPT_DIR/ocr_error.log"
    fi
    : > "$LOG_FILE"

    # ---- System check ----
    for cmd in zenity ocrmypdf tesseract; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: '$cmd' is not installed."
            if [[ "$cmd" != "zenity" ]]; then
                zenity --error --text="Error: '$cmd' is not installed. Please use the installation script." 2>/dev/null
            fi
            exit 1
        fi
    done

    # ---- Navigable workflow (cancel on any screen = back one step) ----
    local mode target_path lang_choice lang_param text_mode

    while true; do   # 1 — Mode selection (cancel here exits)
        mode=$(select_mode)
        [[ -z "$mode" ]] && exit 0

        if [[ "$mode" == "Settings" ]]; then
            show_settings
            exit 0
        fi

        # 2 — File / folder selection (cancel → back to mode)
        while true; do
            if [[ "$mode" == "Process single PDF file" ]]; then
                target_path=$(select_pdf_file)
            else
                target_path=$(select_folder)
            fi
            [[ -z "$target_path" ]] && break    # ← back

            # 3 — Language selection (cancel → back to file/folder)
            while true; do
                lang_choice=$(select_languages)
                [[ -z "$lang_choice" ]] && break  # ← back

                lang_param=$(echo "$lang_choice" | tr '|' '+')
                if [[ -z "$lang_param" ]]; then
                    zenity --error --text="You must select at least one language!" 2>/dev/null
                    continue
                fi

                # 4 — Text mode (cancel → back to languages)
                while true; do
                    text_mode=$(select_text_mode)
                    [[ -z "$text_mode" ]] && break  # ← back

                    # 5 — Dispatch & done
                    if [[ -f "$target_path" ]]; then
                        run_single_file "$target_path" "$lang_param" "$text_mode"
                    elif [[ -d "$target_path" ]]; then
                        run_folder "$target_path" "$lang_param" "$text_mode"
                    fi
                    exit 0
                done
            done
        done
    done
}

main "$@"