#!/bin/bash
# GitHub Account Switcher

CONFIG_FILE="$HOME/.config/gh-account-switcher/config"
CONFIG_DIR="$HOME/.config/gh-account-switcher"
GITCONFIGS_DIR="$CONFIG_DIR/gitconfigs"

# Source switcher functions
if [ -f "$CONFIG_DIR/switch.sh" ]; then
    source "$CONFIG_DIR/switch.sh"
else
    echo "Error: gh-account-switcher not installed"
    echo "Run install.sh from the repository"
    exit 1
fi

# Show help
show_help() {
    echo "gh-account-switcher - Automatic GitHub account switching"
    echo ""
    echo "Usage: gh-account-switcher <command>"
    echo ""
    echo "Commands:"
    echo "  setup       Interactive setup wizard"
    echo "  init        Configure git rules from config"
    echo "  status      Show current account and sync gh CLI"
    echo "  sync        Sync gh CLI to expected account"
    echo "  list        List configured accounts"
    echo "  set <name>  Override account for current directory"
    echo "  unset       Remove override"
    echo "  help        Show this help"
}

# List all configured accounts
list_accounts() {
    echo "Configured accounts:"
    for account_name in "${!ACCOUNT_MAP[@]}"; do
        local username="${ACCOUNT_MAP[$account_name]}"
        local name="${NAME_MAP[$account_name]:-N/A}"
        local email="${EMAIL_MAP[$account_name]:-N/A}"
        local marker=""
        [ "$account_name" = "$DEFAULT_ACCOUNT" ] && marker=" (default)"

        printf "  %-15s %-20s %s%s\n" "$account_name" "$username" "$name" "$marker"
        printf "  %-15s %s\n" "" "$email"
        echo ""
    done
}

# Validate account exists
validate_account() {
    local account_name="$1"
    if [ -z "${ACCOUNT_MAP[$account_name]}" ]; then
        echo "Error: Account '$account_name' not found"
        echo ""
        list_accounts
        return 1
    fi
    return 0
}

# Check if shell wrappers are configured
check_shell_integration() {
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        if [ -f "$rc_file" ] && grep -q "gh-account-switcher" "$rc_file" 2>/dev/null; then
            return 0
        fi
    done
    echo "Warning: Shell wrappers not active. Run: source ~/.config/gh-account-switcher/switch.sh"
    echo ""
}

# Get the currently active gh CLI account username
get_active_gh_account() {
    # Parse gh auth status to find the active account
    # Output format includes: "✓ Logged in to github.com account <username>"
    local status_output
    status_output=$(/usr/bin/gh auth status 2>&1)

    # Extract the active account (line with checkmark)
    echo "$status_output" | grep -oP '✓ Logged in to github.com account \K[^ ]+' | head -1
}

# Show current status
show_status() {
    local expected_account=$(get_account)
    local expected_username="${ACCOUNT_MAP[$expected_account]}"
    local name="${NAME_MAP[$expected_account]:-N/A}"
    local email="${EMAIL_MAP[$expected_account]:-N/A}"

    # Get actual gh CLI state
    local actual_username=$(get_active_gh_account)

    echo "Current account: $expected_account ($expected_username)"
    echo "Git authorship: $name <$email>"

    if [ -f .gh-account ]; then
        echo "Override: active in $(pwd)"
    fi

    # Check if gh CLI is synced with expected account
    if [ -z "$actual_username" ]; then
        echo "gh CLI: unable to determine (run 'gh auth status')"
    elif [ "$actual_username" = "$expected_username" ]; then
        echo "gh CLI: synced"
    else
        echo "gh CLI: was $actual_username, syncing to $expected_username..."
        if switch_account "$expected_account"; then
            echo "gh CLI: synced to $expected_username"
        else
            echo "gh CLI: sync failed (check 'gh auth status')"
        fi
    fi

    echo ""
    # Check shell integration
    check_shell_integration
}

# Sync gh CLI to expected account (for scripts or explicit sync)
sync_to_expected() {
    local expected_account=$(get_account)
    local expected_username="${ACCOUNT_MAP[$expected_account]}"

    if [ -z "$expected_username" ]; then
        echo "Error: Could not determine expected account"
        return 1
    fi

    local actual_username=$(get_active_gh_account)

    if [ "$actual_username" = "$expected_username" ]; then
        echo "Already synced: $expected_account ($expected_username)"
        return 0
    fi

    echo "Syncing to: $expected_account ($expected_username)..."
    if switch_account "$expected_account"; then
        echo "Synced successfully"
        return 0
    else
        echo "Sync failed"
        return 1
    fi
}

# Set manual override
set_account() {
    local account_name="$1"

    if [ -z "$account_name" ]; then
        echo "Error: Please specify an account name"
        echo "Usage: gh-account-switcher set <account>"
        echo ""
        list_accounts
        exit 1
    fi

    validate_account "$account_name" || exit 1

    echo "$account_name" > .gh-account
    switch_account "$account_name" >/dev/null 2>&1

    echo "Set account to: $account_name (${ACCOUNT_MAP[$account_name]})"
    echo "Git authorship: ${NAME_MAP[$account_name]} <${EMAIL_MAP[$account_name]}>"
}

# Unset manual override
unset_account() {
    if [ -f .gh-account ]; then
        rm .gh-account
        local account=$(get_account)
        switch_account "$account" >/dev/null 2>&1
        echo "Removed override, using: $account (${ACCOUNT_MAP[$account]})"
    else
        echo "No manual override set in $(pwd)"
    fi
}

# Interactive setup wizard
setup_wizard() {
    echo "=== GitHub Account Switcher Setup ==="
    echo ""

    # Step 1: Get existing gh accounts
    echo "Step 1: GitHub CLI accounts"
    local gh_accounts=$(/usr/bin/gh auth status 2>&1 | grep "Logged in" | sed 's/.*account //' | sed 's/ .*//')

    if [ -z "$gh_accounts" ]; then
        echo "Error: No GitHub accounts found in gh CLI"
        echo "Please authenticate first: gh auth login"
        exit 1
    fi

    echo "Found accounts: $gh_accounts"
    echo ""

    # Use temp file - only overwrite config when complete
    local temp_config=$(mktemp)
    trap "rm -f '$temp_config'" EXIT

    # Step 2: Configure each account
    echo "Step 2: Configure each account"
    echo ""

    local configured_accounts=""
    for username in $gh_accounts; do
        echo "Configuring: $username"
        read -p "  Account name (e.g., personal): " account_name

        # Allow empty to skip
        if [ -z "$account_name" ]; then
            echo "  Skipped"
            continue
        fi

        # Validate account name
        if [[ ! "$account_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo "  Error: Account name must be alphanumeric"
            continue
        fi

        read -p "  Display name: " display_name
        read -p "  Email: " email

        if [ -z "$display_name" ] || [ -z "$email" ]; then
            echo "  Error: Display name and email are required"
            continue
        fi

        echo "ACCOUNT_$account_name=$username|$display_name|$email" >> "$temp_config"
        configured_accounts="$configured_accounts $account_name"
        echo "  Added: $account_name"
        echo ""
    done

    if [ -z "$configured_accounts" ]; then
        echo "Error: No accounts configured. Setup cancelled."
        exit 1
    fi

    # Step 3: Ask for default account
    echo "Step 3: Default account"
    echo "Configured:$configured_accounts"
    read -p "Default account name: " default_account

    if [ -z "$default_account" ]; then
        echo "Error: Default account required. Setup cancelled."
        exit 1
    fi

    if ! grep -q "ACCOUNT_$default_account=" "$temp_config"; then
        echo "Error: Account '$default_account' not found. Setup cancelled."
        exit 1
    fi

    # Add default account at the top of temp config
    local final_config=$(mktemp)
    echo "DEFAULT_ACCOUNT=$default_account" > "$final_config"
    echo "" >> "$final_config"
    cat "$temp_config" >> "$final_config"
    mv "$final_config" "$temp_config"

    echo "Set default: $default_account"
    echo ""

    # Step 4: Ask for directory mappings
    echo "Step 4: Directory mappings (optional, empty to finish)"
    echo ""

    while true; do
        read -p "Directory (e.g., ~/personal): " directory
        [ -z "$directory" ] && break

        read -p "Account name: " account_name

        if ! grep -q "ACCOUNT_$account_name=" "$temp_config"; then
            echo "  Error: Account '$account_name' not found"
            continue
        fi

        echo "$directory=$account_name" >> "$temp_config"
        echo "  Added: $directory -> $account_name"
    done

    # Backup existing config and save new one
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%s)"
    fi
    cp "$temp_config" "$CONFIG_FILE"

    echo ""
    echo "Step 5: Applying configuration..."

    # Re-read config and generate
    read_config
    generate_gitconfigs
    setup_git_includes

    echo ""
    echo "=== Setup Complete ==="
    echo ""
    echo "Config saved to: $CONFIG_FILE"
    echo ""
    echo "Reload shell: source ~/.bashrc"
}

# Generate gitconfig files (init command)
init_gitconfigs() {
    echo "Generating git configuration files..."

    read_config
    generate_gitconfigs

    local count=${#ACCOUNT_MAP[@]}
    echo "Generated $count gitconfig file(s) in $GITCONFIGS_DIR"
    echo ""

    # Setup directory-based git includes
    setup_git_includes

    echo ""
    echo "Git is now configured for automatic directory-based switching."
    echo "gh CLI wrappers handle automatic switching on each command."
    echo ""
    echo "To activate gh CLI wrappers, run: source ~/.bashrc"
    echo "Or open a new terminal."
}

# Setup git includeIf rules in ~/.gitconfig based on directory patterns
setup_git_includes() {
    local gitconfig="$HOME/.gitconfig"
    local temp_file=$(mktemp)

    # Get default account info
    local default_name="${NAME_MAP[$DEFAULT_ACCOUNT]}"
    local default_email="${EMAIL_MAP[$DEFAULT_ACCOUNT]}"

    if [ -z "$default_name" ] || [ -z "$default_email" ]; then
        echo "Error: Default account '$DEFAULT_ACCOUNT' missing name or email"
        return 1
    fi

    # Remove existing gh-account-switcher sections from gitconfig
    if [ -f "$gitconfig" ]; then
        # Remove:
        # 1. Comment blocks starting with "# GitHub Account Switcher"
        # 2. includeIf sections that reference our gitconfigs
        # 3. include sections that reference our override file
        awk '
            /^# GitHub Account Switcher/ { skip=1; next }
            /^\[includeIf.*gitdir:.*personal/ { skip=1; next }
            /^\[include\]/ { maybe_skip=1; hold=$0; next }
            maybe_skip && /gh-account-switcher/ { maybe_skip=0; next }
            maybe_skip { print hold; maybe_skip=0 }
            /^\[/ && skip { skip=0 }
            /gh-account-switcher\/gitconfigs/ { next }
            /gh-account-switcher\/override/ { next }
            !skip { print }
        ' "$gitconfig" > "$temp_file"

        # Clean up any empty lines at end
        sed -i ':a;/^[[:space:]]*$/{$d;N;ba}' "$temp_file" 2>/dev/null || true
    else
        touch "$temp_file"
    fi

    # Update or add [user] section with default account
    if grep -q "^\[user\]" "$temp_file"; then
        # Update existing [user] section
        awk -v name="$default_name" -v email="$default_email" '
            /^\[user\]/ { in_user=1; print; next }
            in_user && /^[[:space:]]*(name|email)[[:space:]]*=/ { next }
            in_user && /^\[/ {
                print "\tname = " name
                print "\temail = " email
                in_user=0
            }
            { print }
            END {
                if (in_user) {
                    print "\tname = " name
                    print "\temail = " email
                }
            }
        ' "$temp_file" > "${temp_file}.2"
        mv "${temp_file}.2" "$temp_file"
    else
        # Add [user] section at the beginning
        {
            echo "[user]"
            echo "	name = $default_name"
            echo "	email = $default_email"
            echo ""
            cat "$temp_file"
        } > "${temp_file}.2"
        mv "${temp_file}.2" "$temp_file"
    fi

    # Add gh-account-switcher includeIf section
    {
        cat "$temp_file"
        echo ""
        echo "# GitHub Account Switcher - directory-based git authorship"
        echo "# Default account: $DEFAULT_ACCOUNT ($default_name <$default_email>)"

        # Sort patterns by length (shortest first) so more specific patterns override
        local sorted_patterns
        sorted_patterns=$(printf '%s\n' "${!PATTERN_MAP[@]}" | awk '{print length, $0}' | sort -n | cut -d' ' -f2-)

        for pattern in $sorted_patterns; do
            local account="${PATTERN_MAP[$pattern]}"

            # Skip if this is the default account (already set in [user])
            [ "$account" = "$DEFAULT_ACCOUNT" ] && continue

            # Expand ~ to full path for the includeIf
            local expanded_pattern="${pattern/#\~/$HOME}"

            # Ensure pattern ends with / for gitdir matching
            [[ "$expanded_pattern" != */ ]] && expanded_pattern="${expanded_pattern}/"

            local gitconfig_path="~/.config/gh-account-switcher/gitconfigs/$account"

            echo "# $pattern -> $account"
            echo "[includeIf \"gitdir:$expanded_pattern\"]"
            echo "	path = $gitconfig_path"
        done
    } > "$gitconfig"

    rm -f "$temp_file"

    echo "Configured git includeIf rules:"
    echo "  Default: $DEFAULT_ACCOUNT ($default_name <$default_email>)"
    for pattern in $sorted_patterns; do
        local account="${PATTERN_MAP[$pattern]}"
        [ "$account" = "$DEFAULT_ACCOUNT" ] && continue
        echo "  $pattern -> $account (${NAME_MAP[$account]} <${EMAIL_MAP[$account]}>)"
    done
}

# Main command dispatcher
case "${1:-help}" in
    setup)
        setup_wizard
        ;;
    init)
        init_gitconfigs
        ;;
    status)
        show_status
        ;;
    sync)
        sync_to_expected
        ;;
    list)
        list_accounts
        ;;
    set)
        set_account "$2"
        ;;
    unset)
        unset_account
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        show_help
        exit 1
        ;;
esac
