#!/bin/bash
# ============================================================================
# ocr_gui.sh — Graphical convenience wrapper for OCRmyPDF
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION — resolved once in main(), exposed as globals
# ============================================================================
SCRIPT_DIR=""      # directory of this script
SETTINGS_FILE=""    # path to JSON settings file

# ============================================================================
# DEBUG LOGGING — prints timestamped messages to stderr (visible in terminal)
# ============================================================================

debug_log() {
    echo "[$(date '+%H:%M:%S')] $1" >&2
}

# ============================================================================
# HELPER — clean exit with optional GUI error
# ============================================================================
die() {
    local msg="$1"
    local gui="${2:-yes}"
    debug_log "FATAL: $msg"
    if [[ "$gui" == "yes" ]] && command -v zenity &>/dev/null; then
        zenity --error --text="$msg" --width=350 2>/dev/null || true
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
    "naming_replace"
    "naming_suffix_OCR"
    "naming_index_number"
)
ALL_SETTINGS_LABELS=(
    "Text handling mode"
    "Naming: Replace original file"
    "Naming: _OCR suffix"
    "Naming: Index number"
)
ALL_SETTINGS_DEFAULTS=(
    "--skip-text"
    ""
    ""
    ""
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
    debug_log "DIALOG: mode selection"
    local mode
    mode=$(zenity --list --radiolist --title="OCRmyPDF Convenience Center" \
        --column="Pick" --column="Action" \
        TRUE  "Process single PDF file" \
        FALSE "Process a whole folder" \
        FALSE "Settings" \
        --width=500 --height=350 2>/dev/null)
    debug_log "USER: mode selected = '${mode:-<cancel>}'"
    echo "$mode"
}

# File picker — returns path, empty = cancelled
select_pdf_file() {
    debug_log "DIALOG: file picker"
    local path
    path=$(zenity --file-selection --title="Select a PDF file" \
        --file-filter="*.pdf" 2>/dev/null)
    debug_log "USER: file selected = '${path:-<back>}'"
    echo "$path"
}

# Directory picker — returns path, empty = cancelled
select_folder() {
    debug_log "DIALOG: folder picker"
    local path
    path=$(zenity --file-selection --directory --title="Select a folder with PDFs" 2>/dev/null)
    debug_log "USER: folder selected = '${path:-<back>}'"
    echo "$path"
}

# Language checklist — returns pipe-separated codes, empty = cancelled
select_languages() {
    debug_log "LANG: detecting installed tesseract languages"
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
        debug_log "LANG: no languages detected, using fallback deu+eng"
        langs=(TRUE deu FALSE eng)
    fi
    debug_log "LANG: checklist built with ${#langs[@]} languages"

    debug_log "DIALOG: language selection"
    local chosen
    chosen=$(zenity --list --checklist \
        --title="Installed OCR Languages" \
        --text="Select one or more languages:" \
        --column="Pick" --column="Code" \
        --ok-label="Next" --cancel-label="Back" \
        "${langs[@]}" \
        --width=400 --height=420 2>/dev/null)
    debug_log "USER: languages selected = '${chosen:-<back>}'"
    echo "$chosen"
}

# Text-mode selection: radiolist + optional "remember" question
# Returns the ocrmypdf flag: "--skip-text" or "--force-ocr"
select_text_mode() {
    local saved
    saved=$(get_setting "text_mode") || true
    if [[ -n "$saved" ]]; then
        debug_log "TEXT: using saved setting '$saved'"
        echo "$saved"
        return 0
    fi

    debug_log "DIALOG: text mode selection"
    local result
    result=$(zenity --list --checklist \
        --title="Handling existing text" \
        --text="Should PDFs that already contain a text layer be skipped?\nSelect one mode and optionally tick 'Remember'." \
        --column="Pick" --column="Option" \
        TRUE  "Skip existing text (--skip-text, faster)" \
        FALSE "Force OCR and rebuild text (--force-ocr)" \
        FALSE "Remember this setting" \
        --width=550 --height=300 2>/dev/null) || true

    # Cancel/Back → empty string signals "go back"
    if [[ -z "$result" ]]; then
        debug_log "USER: text mode = <back>"
        echo "" && return 0
    fi

    # Parse the pipe-separated checklist result
    local -a selected
    IFS='|' read -ra selected <<< "$result"

    local mode=""
    local remember=false
    local item
    for item in "${selected[@]}"; do
        case "$item" in
            *"--skip-text"*) mode="--skip-text" ;;
            *"--force-ocr"*) mode="--force-ocr" ;;
            *"Remember"*)    remember=true ;;
        esac
    done

    # Validate: exactly one mode must be selected
    if [[ -z "$mode" ]]; then
        debug_log "TEXT: no mode selected"
        zenity --error --text="You must select a mode (--skip-text or --force-ocr)." 2>/dev/null
        echo "" && return 0
    fi

    debug_log "USER: text mode = '$mode', remember = $remember"

    if $remember; then
        debug_log "TEXT: saving setting '$mode'"
        save_setting "text_mode" "$mode"
    fi

    echo "$mode"
}

# Output naming dialog (with optional "remember" question)
# Returns: "replace" | "suffix_OCR" | "index_number"
select_naming_mode() {
    # Check which naming toggle is saved (Settings checkboxes)
    if [[ -n "$(get_setting "naming_replace" || true)" ]]; then
        debug_log "NAMING: using saved 'replace'"
        echo "replace"
        return 0
    fi
    if [[ -n "$(get_setting "naming_suffix_OCR" || true)" ]]; then
        debug_log "NAMING: using saved 'suffix_OCR'"
        echo "suffix_OCR"
        return 0
    fi
    if [[ -n "$(get_setting "naming_index_number" || true)" ]]; then
        debug_log "NAMING: using saved 'index_number'"
        echo "index_number"
        return 0
    fi

    debug_log "DIALOG: naming mode selection"
    local mode
    mode=$(zenity --list --radiolist --title="Output file naming" \
        --text="How should the OCR result be saved?" \
        --column="Pick" --column="Mode" \
        TRUE  "Replace original file" \
        FALSE "Add _OCR suffix (filename_OCR.pdf)" \
        FALSE "Index number (filename_1.pdf, filename_2.pdf...)" \
        --width=580 --height=270 2>/dev/null) || true

    # Cancel/Back → empty string
    if [[ -z "$mode" ]]; then
        debug_log "USER: naming mode = <back>"
        echo "" && return 0
    fi

    local code
    case "$mode" in
        *"Replace"*)  code="replace" ;;
        *"_OCR"*)     code="suffix_OCR" ;;
        *"Index"*)    code="index_number" ;;
        *)            code="suffix_OCR" ;;
    esac
    debug_log "USER: naming mode = '$code'"

    # Ask whether to remember this choice
    if zenity --question --title="Remember setting" \
        --text="Remember '$code' for future runs?\n\nYou can change this later in Settings." \
        --ok-label="Remember" --cancel-label="No" \
        --width=400 2>/dev/null; then
        debug_log "NAMING: saving setting '$code'"
        # Clear previous naming settings, save the chosen one as a toggle
        remove_setting "naming_replace" 2>/dev/null || true
        remove_setting "naming_suffix_OCR" 2>/dev/null || true
        remove_setting "naming_index_number" 2>/dev/null || true
        save_setting "naming_${code}" "true"
    fi

    echo "$code"
}

# Compute output path based on naming mode and (for index_number) next free index
get_output_path() {
    local src="$1"
    local naming_mode="$2"

    local dir; dir=$(dirname "$src")
    local name; name=$(basename "$src")
    name="${name%.*}"

    case "$naming_mode" in
        "replace")
            echo "$src"
            ;;
        "suffix_OCR")
            echo "${dir}/${name}_OCR.pdf"
            ;;
        "index_number")
            local max_idx=0
            local f bname suffix num
            for f in "${dir}/${name}"_*.pdf; do
                if [[ -f "$f" ]]; then
                    bname=$(basename "$f" .pdf)
                    suffix="${bname##*_}"
                    if [[ "$suffix" =~ ^[0-9]+$ ]]; then
                        num=10#$suffix
                        [[ $num -gt $max_idx ]] && max_idx=$num
                    fi
                fi
            done
            echo "${dir}/${name}_$((max_idx + 1)).pdf"
            ;;
    esac
}

# Settings-management window — single checklist for ALL settings.
# Naming entries silently enforce single selection (no popup).
show_settings() {
    debug_log "DIALOG: settings window"

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
            local display_val="${saved_map[$key]}"
            [[ "$display_val" == --* ]] && display_val=" $display_val"
            args+=(TRUE "$label" "$display_val")
            debug_log "SETTINGS: $key = '${saved_map[$key]}' (saved)"
        else
            local hint="$default"
            [[ -z "$hint" ]] && hint="off"
            args+=(FALSE "$label" "$hint")
            debug_log "SETTINGS: $key = $hint (not saved)"
        fi
    done

    local result
    local cancelled=false
    result=$(zenity --list --checklist \
        --title="OCR Settings" \
        --text="Checked settings are remembered and applied automatically.\nUnchecked settings will prompt you each time.\n\nNaming modes: only one stays active when you Save." \
        --column="Active" --column="Setting" --column="Value" \
        --ok-label="Save" --cancel-label="Back" \
        "${args[@]}" \
        --width=700 --height=420 2>/dev/null) || cancelled=true

    if $cancelled; then
        debug_log "USER: settings = <back>"
        return
    fi
    debug_log "USER: settings saved, checked = '${result}'"

    # Map labels back to keys
    local -A checked_keys=()
    local -a checked_labels=()
    IFS='|' read -ra checked_labels <<< "$result"
    for label in "${checked_labels[@]}"; do
        for i in "${!ALL_SETTINGS_LABELS[@]}"; do
            if [[ "${ALL_SETTINGS_LABELS[$i]}" == "$label" ]]; then
                checked_keys["${ALL_SETTINGS_KEYS[$i]}"]=1
                break
            fi
        done
    done

    # Apply changes: save checked settings, remove unchecked ones
    # For naming entries: silently keep only the last-checked one
    local last_naming=""
    for i in "${!ALL_SETTINGS_KEYS[@]}"; do
        local key="${ALL_SETTINGS_KEYS[$i]}"
        local was_saved=false
        [[ -n "${saved_map[$key]+set}" ]] && was_saved=true
        local is_checked=false
        [[ -n "${checked_keys[$key]+set}" ]] && is_checked=true

        if $is_checked && ! $was_saved; then
            save_setting "$key" "${ALL_SETTINGS_DEFAULTS[$i]}"
            debug_log "SETTINGS: enabling $key"
        elif ! $is_checked && $was_saved; then
            remove_setting "$key"
            debug_log "SETTINGS: disabling $key"
        fi
        # Track last naming entry that was checked
        if $is_checked && [[ "$key" == naming_* ]]; then
            last_naming="$key"
        fi
    done

    # Silently remove any other naming entries except the last checked one
    local naming_cleaned=false
    if [[ -n "$last_naming" ]]; then
        for key in naming_replace naming_suffix_OCR naming_index_number; do
            if [[ "$key" != "$last_naming" && -n "$(get_setting "$key" || true)" ]]; then
                remove_setting "$key"
                debug_log "SETTINGS: auto-removed $key (only $last_naming kept)"
                naming_cleaned=true
            fi
        done
    fi

    if $naming_cleaned; then
        debug_log "SETTINGS: naming group cleaned"
    fi

    zenity --info --title="Settings" \
        --text="Settings updated." --width=300 2>/dev/null
}

# ============================================================================
# CORE — OCR processing
# ============================================================================

# Process a single PDF. Parameters are explicit (no globals).
process_ocr() {
    local src="$1"          # source PDF path
    local dest="$2"         # output PDF path
    local lang_param="$3"   # e.g. "deu+eng"
    local text_mode="$4"    # "--skip-text" or "--force-ocr"

    debug_log "OCR: start src='$src' dest='$dest' lang='$lang_param' mode='$text_mode'"

    local dir; dir=$(dirname "$src")
    local name; name=$(basename "$src")
    name="${name%.*}"

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
        debug_log "OCR: FAILED (exit $rc)"
        echo "[!] OCRmyPDF error at ${name}.pdf:" >&2
        cat "$tmp_err" >&2

        rm -f "$dest"       # remove partial output
    else
        debug_log "OCR: success — output = '$dest'"
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
    local naming_mode="$4"

    debug_log "RUN: single file — target='$target'"

    # Validate extension
    if [[ ! "${target,,}" =~ \.pdf$ ]]; then
        die "The selected file is not a PDF document." yes
    fi

    local outfile; outfile=$(get_output_path "$target" "$naming_mode")
    debug_log "RUN: output = '$outfile'"

    # Run OCR in a pipefail-safe way
    local zen_exit=0
    set +e
    process_ocr "$target" "$outfile" "$lang_param" "$text_mode" \
        | zenity --progress --title="OCR running" \
                 --text="Initializing document..." \
                 --pulsate --auto-close 2>/dev/null
    # Capture immediately — any command ([[, echo, etc.) resets PIPESTATUS!
    zen_exit=${PIPESTATUS[1]-0}
    set -e
    if [[ $zen_exit -ne 0 ]]; then
        debug_log "USER: progress cancelled"
        zenity --warning --title="OCR Aborted" \
            --text="The process was aborted." --width=300 2>/dev/null || true
        return 0    # go back to file selection
    fi

    local ret=0
    if [[ -f "$outfile" ]]; then
        debug_log "RESULT: output file exists '$outfile'"
        zenity --question --title="OCR Success" \
            --text="✓ File successfully OCRed!\n\nInput:  $(basename "$target")\nOutput: $(basename "$outfile")\nLanguage: $lang_param\nMode: $text_mode\n\nOCR another file?" \
            --ok-label="OCR another file" --cancel-label="Exit" \
            --width=480 2>/dev/null || ret=$?
    else
        debug_log "RESULT: no output file — OCR failed"
        zenity --question --title="OCR Failed" \
            --text="✗ Processing failed!\n\nFile: $(basename "$target")\nLanguage: $lang_param\n\nSee error messages above in the terminal.\n\nTry another file?" \
            --ok-label="OCR another file" --cancel-label="Exit" \
            --width=480 2>/dev/null || ret=$?
    fi

    debug_log "NAV: user clicked $([ $ret -eq 0 ] && echo 'OCR another file' || echo 'Exit')"
    return $ret
}

# ============================================================================
# EXECUTION — batch folder
# ============================================================================

run_folder() {
    local folder="$1"
    local lang_param="$2"
    local text_mode="$3"
    local naming_mode="$4"

    debug_log "RUN: batch folder — folder='$folder'"

    # Determine the exclude pattern based on naming mode
    local exclude_expr
    if [[ "$naming_mode" == "suffix_OCR" ]]; then
        # Skip already-processed _OCR.pdf files
        exclude_expr=! -iname "*_OCR.pdf"
    else
        # For replace and index_number, no automatic skip pattern
        exclude_expr="-true"
    fi

    # Gather non-processed PDFs
    local -a files=()
    mapfile -d $'\0' files < <(find "$folder" -maxdepth 1 \
        -iname "*.pdf" $exclude_expr -print0)
    debug_log "FIND: found ${#files[@]} unprocessed PDFs (exclude expr: $exclude_expr)"

    if [[ ${#files[@]} -eq 0 ]]; then
        debug_log "FIND: no new PDFs"
        zenity --info --title="Folder OCR" \
            --text="No new PDF files found in the folder.\n(Already processed _OCR.pdf files were skipped)." \
            --width=450 2>/dev/null
        return 0
    fi

    local total=${#files[@]}
    # Temp file to pass error count from subshell to parent
    local tmp_err_count; tmp_err_count=$(mktemp)
    echo 0 > "$tmp_err_count"

    # Run batch in a pipefail-safe way
    local zen_exit=0
    set +e
    (
        trap 'exit 1' SIGPIPE   # user closes progress bar

        local count=0
        local had_errors=0
        for f in "${files[@]}"; do
            count=$((count + 1))
            local pct=$((count * 100 / total))
            local dest; dest=$(get_output_path "$f" "$naming_mode")

            process_ocr "$f" "$dest" "$lang_param" "$text_mode" \
                || had_errors=$((had_errors + 1))

            echo "$pct"
        done
        echo "$had_errors" > "$tmp_err_count"
    ) | zenity --progress --title="Batch OCR active" \
                --text="Processing folder contents..." \
                --percentage=0 --auto-close 2>/dev/null
    # Capture immediately — any command resets PIPESTATUS!
    zen_exit=${PIPESTATUS[1]-0}
    set -e

    local had_errors=$(cat "$tmp_err_count")
    rm -f "$tmp_err_count"

    local ret=0
    if [[ $zen_exit -ne 0 ]]; then
        debug_log "USER: batch progress cancelled"
        zenity --warning --title="Batch OCR" \
            --text="The process was aborted prematurely.\nAlready processed files have been saved." \
            --width=450 2>/dev/null || true
        return 0    # go back to folder selection
    elif [[ $had_errors -gt 0 ]]; then
        debug_log "RESULT: batch finished with errors (${had_errors}/${total} failed)"
        zenity --question --title="Batch OCR - Errors" \
            --text="Warning: Folder processing finished with errors!\n\nProcessed: ${total} files\nFailed:    ${had_errors} files\n\nSee error messages above in the terminal.\n\nOCR another folder?" \
            --ok-label="OCR another folder" --cancel-label="Exit" \
            --width=500 2>/dev/null || ret=$?
    else
        debug_log "RESULT: batch success (${total} files)"
        zenity --question --title="Batch OCR Complete" \
            --text="Completed: Folder processing done!\n\nAll ${total} PDFs have been made searchable.\n\nOCR another folder?" \
            --ok-label="OCR another folder" --cancel-label="Exit" \
            --width=480 2>/dev/null || ret=$?
    fi

    debug_log "NAV: user clicked $([ $ret -eq 0 ] && echo 'OCR another folder' || echo 'Exit')"
    return $ret
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # ---- Resolve paths early ----
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    SETTINGS_FILE="${SCRIPT_DIR}/ocr_settings.json"

    debug_log "=== SCRIPT START ==="
    debug_log "CONFIG: SCRIPT_DIR=$SCRIPT_DIR"
    debug_log "CONFIG: SETTINGS_FILE=$SETTINGS_FILE"

    # ---- System check ----
    for cmd in zenity ocrmypdf tesseract; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: '$cmd' is not installed."
            if [[ "$cmd" != "zenity" ]]; then
                zenity --error --text="Error: '$cmd' is not installed. Please use the installation script." 2>/dev/null
            fi
            exit 1
        fi
        debug_log "CHECK: $cmd = $(command -v "$cmd")"
    done

    # ---- Navigable workflow (cancel on any screen = back one step) ----
    local mode target_path lang_choice lang_param text_mode naming_mode

    while true; do   # 1 — Mode selection (cancel here exits)
        mode=$(select_mode) || true
        [[ -z "$mode" ]] && {
            debug_log "NAV: mode = <exit>"
            exit 0
        }
        debug_log "NAV: mode = '$mode'"

        if [[ "$mode" == "Settings" ]]; then
            show_settings
            debug_log "NAV: returning from settings to mode selection"
            continue    # ← back to mode selection
        fi

        # 2 — File / folder selection (cancel → back to mode)
        while true; do
            if [[ "$mode" == "Process single PDF file" ]]; then
                target_path=$(select_pdf_file) || true
            else
                target_path=$(select_folder) || true
            fi
            [[ -z "$target_path" ]] && {
                debug_log "NAV: back to mode selection"
                break    # ← back
            }
            debug_log "NAV: target = '$target_path'"

            # 3 — Language selection (cancel/back → back to file/folder)
            while true; do
                lang_choice=$(select_languages) || true
                [[ -z "$lang_choice" ]] && {
                    debug_log "NAV: back to file/folder selection"
                    break  # ← back
                }
                debug_log "NAV: languages = '$lang_choice'"

                lang_param=$(echo "$lang_choice" | tr '|' '+')
                if [[ -z "$lang_param" ]]; then
                    debug_log "LANG: empty after join — shouldn't happen"
                    zenity --error --text="You must select at least one language!" 2>/dev/null
                    continue
                fi
                debug_log "LANG: param = '$lang_param'"

                # 4 — Text mode (cancel → back to languages)
                while true; do
                    text_mode=$(select_text_mode)
                    [[ -z "$text_mode" ]] && {
                        debug_log "NAV: back to language selection"
                        break  # ← back
                    }
                    debug_log "NAV: text mode = '$text_mode'"

                    # 5 — Naming mode (cancel → back to text mode)
                    while true; do
                        naming_mode=$(select_naming_mode)
                        [[ -z "$naming_mode" ]] && {
                            debug_log "NAV: back to text mode"
                            break  # ← back
                        }
                        debug_log "NAV: naming mode = '$naming_mode'"

                        # 6 — Dispatch
                        if [[ -f "$target_path" ]]; then
                            debug_log "DISPATCH: single file"
                            run_single_file "$target_path" "$lang_param" "$text_mode" "$naming_mode" && {
                                debug_log "NAV: continue → file selection"
                                continue 4
                            }
                            debug_log "NAV: exit"
                        elif [[ -d "$target_path" ]]; then
                            debug_log "DISPATCH: batch folder"
                            run_folder "$target_path" "$lang_param" "$text_mode" "$naming_mode" && {
                                debug_log "NAV: continue → folder selection"
                                continue 4
                            }
                            debug_log "NAV: exit"
                        fi
                        exit 0
                    done
                done
            done
        done
    done
}

main "$@"