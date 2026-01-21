#!/bin/bash
set -e

CONFIG_DIR="$HOME/.config/gh-account-switcher"
CONFIG_FILE="$CONFIG_DIR/config"
GITCONFIGS_DIR="$CONFIG_DIR/gitconfigs"
INSTALL_DIR="$HOME/.local/bin"
WRAPPER_SCRIPT="$CONFIG_DIR/switch.sh"
CLI_SCRIPT="$INSTALL_DIR/gh-account-switcher"

echo "Installing GitHub Account Switcher..."

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$GITCONFIGS_DIR"

# Copy wrapper script to config dir (sourced by shell)
cp "$(dirname "$0")/switch.sh" "$WRAPPER_SCRIPT"

# Copy CLI script
cp "$(dirname "$0")/cli.sh" "$CLI_SCRIPT"
chmod +x "$CLI_SCRIPT"

# Remove old CLI name if exists
[ -f "$INSTALL_DIR/gh-account-switcher-cli" ] && rm -f "$INSTALL_DIR/gh-account-switcher-cli"

# Copy config if doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$(dirname "$0")/config.example" "$CONFIG_FILE"
    echo "Created default config at $CONFIG_FILE"
else
    echo "Config already exists at $CONFIG_FILE"
fi

# Add to shell rc
RC_FILE="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
    RC_FILE="$HOME/.zshrc"
fi

SOURCE_LINE="source \"$WRAPPER_SCRIPT\""
# Check for old or new source line
if grep -q "gh-account-switcher" "$RC_FILE" 2>/dev/null; then
    # Update old source line to new path if needed
    if ! grep -q "$WRAPPER_SCRIPT" "$RC_FILE" 2>/dev/null; then
        sed -i "s|source.*gh-account-switcher.*|$SOURCE_LINE|g" "$RC_FILE"
        echo "Updated source line in $RC_FILE"
    else
        echo "Already configured in $RC_FILE"
    fi
else
    echo "" >> "$RC_FILE"
    echo "# GitHub Account Switcher" >> "$RC_FILE"
    echo "$SOURCE_LINE" >> "$RC_FILE"
    echo "Added to $RC_FILE"
fi

# Clean up old files
[ -L "$CONFIG_DIR/override" ] && rm -f "$CONFIG_DIR/override"
[ -f "$INSTALL_DIR/gh-account-switcher-cli" ] && rm -f "$INSTALL_DIR/gh-account-switcher-cli"

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Run: gh-account-switcher setup"
echo "2. Reload shell: source $RC_FILE"
echo ""
echo "Usage:"
echo "  gh-account-switcher status  # Show current account"
echo "  gh-account-switcher list    # List all accounts"
echo "  gh-account-switcher setup   # Interactive setup"
