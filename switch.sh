#!/bin/bash
# GitHub Account Switcher
# Source this file to enable automatic account switching

CONFIG_FILE="$HOME/.config/gh-account-switcher/config"
CONFIG_DIR="$HOME/.config/gh-account-switcher"
GITCONFIGS_DIR="$CONFIG_DIR/gitconfigs"

# Associative arrays (requires bash 4.0+)
declare -A ACCOUNT_MAP
declare -A NAME_MAP
declare -A EMAIL_MAP
declare -A PATTERN_MAP
DEFAULT_ACCOUNT=""

# Read config file
read_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Config file not found at $CONFIG_FILE"
        echo "Create it or run: gh-account-switcher setup"
        return 1
    fi

    # Clear arrays
    ACCOUNT_MAP=()
    NAME_MAP=()
    EMAIL_MAP=()
    PATTERN_MAP=()
    DEFAULT_ACCOUNT=""

    # Parse config file line by line
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Store config values
        case "$key" in
            DEFAULT_ACCOUNT)
                DEFAULT_ACCOUNT="$value"
                ;;
            ACCOUNT_*)
                account_name="${key#ACCOUNT_}"
                # Parse pipe-delimited format: username|name|email
                IFS='|' read -r username name email <<< "$value"
                ACCOUNT_MAP["$account_name"]="$username"
                [ -n "$name" ] && NAME_MAP["$account_name"]="$name"
                [ -n "$email" ] && EMAIL_MAP["$account_name"]="$email"
                ;;
            *)
                # Directory patterns
                PATTERN_MAP["$key"]="$value"
                ;;
        esac
    done < "$CONFIG_FILE"
}

# Get account for current directory
get_account() {
    local current_dir=$(pwd)

    # Priority 1: Check for manual override file
    if [ -f ".gh-account" ]; then
        cat .gh-account
        return
    fi

    local account="$DEFAULT_ACCOUNT"

    # Priority 2: Check each pattern (sorted by length - most specific first)
    local pattern
    local sorted_patterns
    sorted_patterns=$(printf '%s\n' "${!PATTERN_MAP[@]}" | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-)

    for pattern in $sorted_patterns; do
        # Expand ~ to $HOME
        local expanded_pattern="${pattern/#\~/$HOME}"

        # Remove trailing slash from current_dir for comparison
        local normalized_dir="${current_dir%/}"

        # Check if current directory matches or is under pattern
        case "$expanded_pattern" in
            */)
                if [[ "$normalized_dir" == "$expanded_pattern"* ]]; then
                    account="${PATTERN_MAP[$pattern]}"
                    break
                fi
                ;;
            *\*)
                if [[ "$normalized_dir" == $expanded_pattern ]]; then
                    account="${PATTERN_MAP[$pattern]}"
                    break
                fi
                ;;
            *)
                if [[ "$normalized_dir" == "$expanded_pattern" ]] || \
                   [[ "$normalized_dir" == "$expanded_pattern/"* ]]; then
                    account="${PATTERN_MAP[$pattern]}"
                    break
                fi
                ;;
        esac
    done

    echo "$account"
}

# Switch GitHub CLI account (git uses native includeIf rules)
switch_account() {
    local account_name="$1"
    local username="${ACCOUNT_MAP[$account_name]}"

    if [ -z "$username" ]; then
        echo "Warning: Account '$account_name' not found in config" >&2
        return 1
    fi

    # Switch GitHub CLI account, capturing errors
    local switch_output
    local switch_exit_code
    switch_output=$(/usr/bin/gh auth switch -h github.com -u "$username" 2>&1)
    switch_exit_code=$?

    if [ $switch_exit_code -ne 0 ]; then
        echo "Error switching to '$username': $switch_output" >&2
        return 1
    fi
}

# Generate gitconfig files for all accounts
generate_gitconfigs() {
    mkdir -p "$GITCONFIGS_DIR"

    for account_name in "${!ACCOUNT_MAP[@]}"; do
        local name="${NAME_MAP[$account_name]}"
        local email="${EMAIL_MAP[$account_name]}"

        if [ -n "$name" ] && [ -n "$email" ]; then
            local gitconfig_file="$GITCONFIGS_DIR/$account_name"
            echo "[user]" > "$gitconfig_file"
            echo "    name = $name" >> "$gitconfig_file"
            echo "    email = $email" >> "$gitconfig_file"
        fi
    done
}

# Wrapper functions - ensure gh CLI is synced before commands
# Git: Author info uses native includeIf, but push/fetch use gh for authentication
git() {
    local account=$(get_account)
    switch_account "$account" >/dev/null 2>&1
    /usr/bin/git "$@"
}

gh() {
    local account=$(get_account)
    switch_account "$account" >/dev/null 2>&1
    /usr/bin/gh "$@"
}

# Initialize
read_config
