# gh-account-switcher

Automatically switch GitHub accounts based on directory. Never commit with the wrong account again.

## The Problem

You have multiple GitHub accounts (personal, work) and constantly forget to switch. You commit as your personal account to work repos, or push work code with personal credentials.

## The Solution

Configure once, forget forever:
- **Git author** switches automatically based on repo location
- **gh CLI** switches automatically before each command
- Works across multiple terminals without conflicts

## Quick Start

```bash
git clone https://github.com/yourusername/gh-account-switcher.git
cd gh-account-switcher
./install.sh
gh-account-switcher setup
source ~/.bashrc
```

## Configuration

Edit `~/.config/gh-account-switcher/config`:

```bash
DEFAULT_ACCOUNT=work

ACCOUNT_personal=personal-username|Your Name|you@personal.com
ACCOUNT_work=work-username|Your Name|you@company.com

~/personal=personal
~/=work
```

Then run `gh-account-switcher init` to apply.

## How It Works

| What | How | When |
|------|-----|------|
| Git author | Native `includeIf` in `~/.gitconfig` | Inside any git repo |
| gh CLI auth | Shell wrapper syncs before command | Every `git`/`gh` command |

**Note:** Git author switching only works inside actual git repositories under the configured path, not in the directory itself. This is how git's `includeIf` works - it activates when you're inside a repo whose location matches the pattern.

## Commands

```bash
gh-account-switcher setup   # Interactive configuration
gh-account-switcher init    # Apply config to git
gh-account-switcher status  # Show current account
gh-account-switcher list    # List all accounts
```

## Verify It Works

```bash
# Check wrappers are active
type git  # Should show: git is a function

# Test in different directories
cd ~/personal/repo && git config user.email  # personal email
cd ~/work/repo && git config user.email      # work email
```

## Requirements

- Bash 4.0+ or Zsh
- `gh` CLI with accounts authenticated (`gh auth login`)

## License

MIT
