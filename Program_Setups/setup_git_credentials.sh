#!/usr/bin/env bash

set -euo pipefail

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Error: %s is required but not installed.\n' "$1" >&2
        exit 1
    fi
}

prompt_required() {
    local prompt="$1"
    local value=""

    while [ -z "$value" ]; do
        read -r -p "$prompt" value
        if [ -z "$value" ]; then
            printf 'This value cannot be empty.\n' >&2
        fi
    done

    printf '%s' "$value"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    local reply=""
    local suffix="[y/N]"

    case "$default" in
        Y|y) suffix="[Y/n]" ;;
    esac

    while true; do
        read -r -p "$prompt $suffix " reply
        reply="${reply:-$default}"

        case "$reply" in
            Y|y) return 0 ;;
            N|n) return 1 ;;
            *) printf 'Please answer y or n.\n' >&2 ;;
        esac
    done
}

show_public_key() {
    local key_file="$1"

    printf '\nSSH public key (%s):\n' "$key_file"
    cat "$key_file"
    printf '\n'
}

main() {
    require_command git
    require_command ssh-keygen

    printf '%s\n\n' 'Git credential setup'

    local git_name git_email
    git_name="$(prompt_required 'Git full name: ')"
    git_email="$(prompt_required 'Git email address: ')"

    git config --global user.name "$git_name"
    git config --global user.email "$git_email"

    printf '\nGit identity saved:\n'
    printf '  user.name  = %s\n' "$(git config --global --get user.name)"
    printf '  user.email = %s\n' "$(git config --global --get user.email)"

    local ssh_dir="$HOME/.ssh"
    local -a public_keys=()
    local key_file

    for key_file in "$ssh_dir"/*.pub; do
        [ -f "$key_file" ] && public_keys+=("$key_file")
    done

    if [ "${#public_keys[@]}" -gt 0 ]; then
        printf '\nExisting SSH public key(s) found:\n'
        for ((index = 0; index < ${#public_keys[@]}; index++)); do
            printf '  [%d] %s\n' "$((index + 1))" "${public_keys[$index]}"
        done

        local selected_index=0
        if [ "${#public_keys[@]}" -gt 1 ]; then
            local choice=""
            read -r -p "Choose a key to display [1-${#public_keys[@]}] (default: 1): " choice
            case "$choice" in
                ''|*[!0-9]*) selected_index=0 ;;
                *)
                    if [ "$choice" -ge 1 ] && [ "$choice" -le "${#public_keys[@]}" ]; then
                        selected_index=$((choice - 1))
                    fi
                    ;;
            esac
        fi

        show_public_key "${public_keys[$selected_index]}"
    else
        printf '\nNo SSH public key found in %s.\n' "$ssh_dir"

        if prompt_yes_no 'Generate a new ed25519 SSH key now?' 'Y'; then
            mkdir -p "$ssh_dir"
            chmod 700 "$ssh_dir"

            local key_name="id_ed25519"
            local key_path="$ssh_dir/$key_name"
            local key_comment="$git_email"
            local key_passphrase=""

            while [ -e "$key_path" ] || [ -e "$key_path.pub" ]; do
                printf 'Key file %s already exists.\n' "$key_path" >&2
                read -r -p 'Choose a different key file name [id_ed25519]: ' key_name
                key_name="${key_name:-id_ed25519}"
                key_path="$ssh_dir/$key_name"
            done

            read -r -p "SSH key comment [${git_email}]: " key_comment
            key_comment="${key_comment:-$git_email}"

            read -r -s -p 'SSH key passphrase (leave blank for none): ' key_passphrase
            printf '\n'

            ssh-keygen -t ed25519 -C "$key_comment" -f "$key_path" -N "$key_passphrase"

            printf '\nGenerated SSH key:\n'
            show_public_key "$key_path.pub"
        fi
    fi

    printf 'Done.\n'
}

main "$@"