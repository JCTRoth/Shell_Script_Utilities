#!/usr/bin/env bash
###############################################################################
# install-ocrmypdf.sh — Installation wizard for OCRmyPDF (Fedora / Ubuntu)
#
# * Must be run as root (sudo).
# * First run : full wizard — base install, then language-pack selection.
# * Later runs: jumps straight to the language-pack selection.
#   (State marker: /var/lib/ocrmypdf-installer/base-installed
#    Use --full to force the complete wizard again.)
###############################################################################

set -euo pipefail

STATE_DIR="/var/lib/ocrmypdf-installer"
STATE_FILE="${STATE_DIR}/base-installed"

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
title() { printf '\n== %s ==\n' "$*"; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
[[ ${EUID} -eq 0 ]] || die "This installer must be run as root. Try:  sudo bash $0"

# ---------------------------------------------------------------------------
# Distribution detection
# ---------------------------------------------------------------------------
[[ -r /etc/os-release ]] || die "Cannot detect the distribution (/etc/os-release missing)."
. /etc/os-release

DISTRO=""
case "${ID}" in
    fedora) DISTRO=fedora ;;
    ubuntu) DISTRO=ubuntu ;;
    *)  case " ${ID_LIKE:-} " in
            *" fedora "*)              DISTRO=fedora ;;
            *" ubuntu "*|*" debian "*) DISTRO=ubuntu ;;
            *) die "Unsupported distribution '${ID}'. Only Fedora and Ubuntu are supported." ;;
        esac ;;
esac

# ---------------------------------------------------------------------------
# Package helpers
# ---------------------------------------------------------------------------
pkg_install() {
    if [[ ${DISTRO} == fedora ]]; then
        dnf install -y "$@"
    else
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    fi
}

# ISO 639-3 code -> distro package name
# ("chi_sim" -> tesseract-langpack-chi_sim on Fedora, tesseract-ocr-chi-sim on Ubuntu)
lang_pkg() {
    if [[ ${DISTRO} == fedora ]]; then
        printf 'tesseract-langpack-%s' "$1"
    else
        printf 'tesseract-ocr-%s' "${1//_/-}"
    fi
}

# ---------------------------------------------------------------------------
# Available language packs (codes as used by Tesseract)
# ---------------------------------------------------------------------------
LANG_CODES=(
    eng deu fra spa ita por nld pol rus tur
    swe dan nor fin ces slk hun ron bul ukr
    ell chi_sim chi_tra jpn kor ara heb hin tha vie
)
LANG_NAMES=(
    "English" "German" "French" "Spanish" "Italian" "Portuguese" "Dutch"
    "Polish" "Russian" "Turkish" "Swedish" "Danish" "Norwegian" "Finnish"
    "Czech" "Slovak" "Hungarian" "Romanian" "Bulgarian" "Ukrainian" "Greek"
    "Chinese (Simplified)" "Chinese (Traditional)" "Japanese" "Korean"
    "Arabic" "Hebrew" "Hindi" "Thai" "Vietnamese"
)

# ---------------------------------------------------------------------------
# Wizard step 1/3 — welcome
# ---------------------------------------------------------------------------
step_welcome() {
    title "OCRmyPDF installation wizard — step 1/3"
    cat <<EOF
Detected system : ${PRETTY_NAME:-${ID}}
Package backend : $([[ ${DISTRO} == fedora ]] && echo dnf || echo apt)

This wizard will:
  1. install ocrmypdf and tesseract,
  2. let you pick the OCR language packs,
  3. finish with a usage example.

Rerun the script for language-pack installation.
EOF
    local a
    read -rp "Continue? [Y/n] " a || a=n
    [[ ${a,,} == n* ]] && die "Aborted by user."
    return 0
}

# ---------------------------------------------------------------------------
# Wizard step 2/3 — base installation
# ---------------------------------------------------------------------------
step_base_install() {
    title "Step 2/3 — installing ocrmypdf and tesseract"
    local base_pkgs
    if [[ ${DISTRO} == fedora ]]; then
        base_pkgs=(ocrmypdf tesseract)
    else
        base_pkgs=(ocrmypdf tesseract-ocr)
        echo "Running apt-get update ..."
        apt-get update -qq
    fi
    echo "Installing: ${base_pkgs[*]}"
    if ! pkg_install "${base_pkgs[@]}"; then
        [[ ${DISTRO} == ubuntu ]] && \
            echo "Hint: the 'universe' repository must be enabled:  add-apt-repository universe" >&2
        die "Base installation failed."
    fi
    command -v ocrmypdf >/dev/null 2>&1 || die "ocrmypdf not found after installation."
    echo "OK — $(ocrmypdf --version 2>/dev/null | head -n1) installed."
}

# ---------------------------------------------------------------------------
# Wizard step 3/3 — language-pack selection (also the entry point on re-runs)
# ---------------------------------------------------------------------------
step_languages() {
    title "Step 3/3 — language-pack selection"
    command -v tesseract >/dev/null 2>&1 || die "tesseract not found — run the full wizard first (--full)."

    local installed=""
    installed="$(tesseract --list-langs 2>/dev/null | sed 1d || true)"

    echo "Available packs (* = already installed):"
    echo
    local i mark
    for i in "${!LANG_CODES[@]}"; do
        mark=" "
        if grep -qx "${LANG_CODES[$i]}" <<<"${installed}"; then mark="*"; fi
        printf ' %2d) %-8s %-21s%s' "$((i+1))" "${LANG_CODES[$i]}" "${LANG_NAMES[$i]}" "$mark"
        if (( (i+1) % 2 == 0 )); then printf '\n'; else printf '  '; fi
    done
    (( ${#LANG_CODES[@]} % 2 )) && printf '\n'
    echo

    local line tok code j
    local pkgs=()
    while true; do
        read -rp "Select numbers or codes (space-separated), ENTER/q to finish: " line || line=q
        [[ -z ${line} || ${line,,} == q ]] && break
        pkgs=()
        for tok in ${line}; do
            code=""
            if [[ ${tok} =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= ${#LANG_CODES[@]} )); then
                code="${LANG_CODES[$((tok-1))]}"
            else
                for j in "${!LANG_CODES[@]}"; do
                    [[ ${LANG_CODES[$j]} == "${tok,,}" ]] && { code="${LANG_CODES[$j]}"; break; }
                done
            fi
            if [[ -n ${code} ]]; then
                pkgs+=("$(lang_pkg "${code}")")
            else
                echo "  ! unknown selection: '${tok}' (skipped)"
            fi
        done
        if (( ${#pkgs[@]} )); then
            echo "Installing: ${pkgs[*]}"
            pkg_install "${pkgs[@]}" || echo "  ! some packs could not be installed"
        fi
    done

    echo
    echo "Currently installed OCR languages:"
    tesseract --list-langs 2>/dev/null | sed 's/^/  /'
}

# ---------------------------------------------------------------------------
# Final step — usage example
# ---------------------------------------------------------------------------
step_example() {
    title "Done — how to use ocrmypdf"
    cat <<'EOF'
Make a scanned PDF searchable (German text):

  ocrmypdf -l deu "/home/jonas/Dokumente/Jonas/Mietvertrag_Bensheim_Dammstrasse_78.pdf" \
                  "/home/jonas/Dokumente/Jonas/Mietvertrag_Bensheim_Dammstrasse_78_OCR.pdf"

Two languages at once (German + English):

  ocrmypdf -l deu+eng input.pdf output.pdf

Handy options:
  --deskew            straighten crooked scans
  --clean             remove scan noise before OCR
  --sidecar text.txt  additionally export the recognized text
  --force-ocr         OCR even pages that already contain a text layer

List all installed OCR languages:

  tesseract --list-langs
EOF
}

# ---------------------------------------------------------------------------
# Main flow: full wizard on first run, language selection on later runs
# ---------------------------------------------------------------------------
main() {
    local force_full=0
    [[ "${1:-}" == "--full" ]] && force_full=1

    if (( force_full == 0 )) && [[ -f ${STATE_FILE} ]] && command -v ocrmypdf >/dev/null 2>&1; then
        title "OCRmyPDF installation wizard"
        echo "Existing installation detected (state file: ${STATE_FILE})."
        echo "Skipping the base installation — going straight to the language packs."
        echo "(Run with --full to repeat the complete wizard.)"
        step_languages
    else
        step_welcome
        step_base_install
        mkdir -p "${STATE_DIR}"
        touch "${STATE_FILE}"
        step_languages
    fi
    step_example
}

main "$@"