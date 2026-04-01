# packer

A lightweight shell tool to back up and restore your macOS development environment — dotfiles and Homebrew packages — with support for layered profiles.

## Why

Setting up a new Mac means reinstalling apps, copying config files, and remembering what you had. Packer solves this with a single command to snapshot your setup and another to restore it. Profiles let you separate personal configs from work-specific ones and selectively apply what you need.

## How It Works

Packer uses a **copy-based** sync strategy. `backup` copies files from your home directory into the data repo. `restore` copies them back. No symlinks, no magic — just `rsync`.

The tool itself (`packer` script) is separate from your data (`~/.packer/`), so you can version-control them independently.

## Architecture

```
<tool-repo>/                 # Tool repo — just the script
└── packer

~/.packer/                   # Data repo — your configs and Brewfiles
├── base/                    # Shared across all machines
│   ├── packer.conf          # List of dotfile paths to track
│   ├── Brewfile             # Homebrew packages
│   └── dotfiles/            # Backed-up config files
│       ├── .zshrc
│       ├── .gitconfig
│       ├── .config/nvim/
│       └── ...
├── work/                    # Company-specific overrides
│   ├── packer.conf
│   ├── Brewfile
│   └── dotfiles/
└── personal/                # Personal machine extras
    ├── packer.conf
    ├── Brewfile
    └── dotfiles/
```

## Quick Start

```bash
# 1. Clone or copy the packer script somewhere in your PATH
cp packer /usr/local/bin/  # or add the repo directory to PATH

# 2. Create your first profile
packer init base

# 3. Add dotfiles to track
packer add base .zshrc
packer add base .gitconfig
packer add base .config/nvim
packer add base .ssh/config

# 4. Back up everything
packer backup

# 5. Version-control your data
cd ~/.packer && git init && git add -A && git commit -m "Initial backup"
```

### Restoring on a New Machine

```bash
# 1. Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Clone your data repo
git clone <your-repo-url> ~/.packer

# 3. Get the packer script (from your tool repo or copy it)
# 4. Restore
packer restore base          # shared configs + brew packages
packer restore dots work     # overlay work-specific dotfiles
```

## Commands

### Backup

```bash
packer backup                    # Back up all profiles (dotfiles + Brewfile)
packer backup dots               # All profiles, dotfiles only
packer backup brew               # All profiles, Brewfile only
packer backup base               # Just the base profile
packer backup dots work          # Just work profile dotfiles
```

### Restore

```bash
packer restore                   # Restore all profiles (alphabetical order)
packer restore base work         # Restore base, then overlay work
packer restore dots base         # Dotfiles only from base
packer restore brew work         # Install only work's Brewfile packages
```

When restoring multiple profiles, they are applied **in the order specified**. Later profiles overwrite earlier ones for overlapping files. This is the layering mechanism — put shared configs in `base`, machine-specific overrides in `work` or `personal`.

### Diff

```bash
packer diff                      # Show all changes across all profiles
packer diff base                 # Changes in base profile only
```

Shows a colorized unified diff between backed-up files and their live counterparts in `~`.

### List

```bash
packer list                      # List all tracked paths across all profiles
packer list work                 # List only work profile paths
```

Shows each tracked path and whether it exists in `~` (HOME) and in the repo (REPO).

### Profiles

```bash
packer profiles                  # List all profiles with summary
packer init <name>               # Create a new empty profile
```

### Add / Remove

```bash
packer add <profile> <path>      # Start tracking a path
packer remove <profile> <path>   # Stop tracking a path
```

Paths can be absolute, relative to `~`, or use `~` notation:

```bash
packer add base .config/ghostty
packer add work ~/.ssh/config
packer add work /Users/$USER/.stCommitMsg
```

## Flags

| Flag | Description |
|---|---|
| `-f`, `--force` | Skip confirmation prompts (useful in scripts) |
| `-n`, `--dry-run` | Preview what would happen without making changes |
| `--data-dir <path>` | Override data directory (default: `~/.packer`) |

The data directory can also be set via the `PACKER_DATA_DIR` environment variable.

## Profile Config Format

Each profile's `packer.conf` is a simple text file — one path per line, relative to `$HOME`. Comments start with `#`.

```conf
# Shell
.zshrc
.zprofile
.zshenv

# Git
.gitconfig
.gitignore_global

# Editors
.config/nvim
.config/helix

# Terminals
.config/ghostty
.config/wezterm
```

## Layering Strategy

The recommended setup for a work machine:

| Profile | Contains |
|---|---|
| `base` | Editor configs, terminal configs, shell configs, general CLI tools |
| `work` | Company-specific git config, SSH config, internal brew taps, VPN tools |

For a personal machine:

| Profile | Contains |
|---|---|
| `base` | Same shared configs |
| `personal` | Personal git config, personal SSH keys config, hobby project tools |

Restore only what you need:

```bash
# Work laptop
packer restore base work

# Personal laptop
packer restore base personal
```

## Brewfile Management

`packer backup brew <profile>` runs `brew bundle dump` which captures **all** currently installed packages. When using multiple profiles, you'll want to manually curate each profile's Brewfile to contain only the packages belonging to that profile.

A typical split:

**base/Brewfile** — tools you use everywhere:
```ruby
brew "fzf"
brew "ripgrep"
brew "neovim"
brew "starship"
cask "ghostty"
```

**work/Brewfile** — company-specific:
```ruby
tap "company/internal"
brew "company-cli"
cask "company-vpn"
```

## Dependencies

- **bash** (v3.2+ — ships with macOS)
- **rsync** (ships with macOS)
- **diff** (ships with macOS)
- **brew** + **brew bundle** (for Homebrew sync)

No other dependencies. No Python, no Ruby, no Node.

## Tips

- Run `packer -n restore base work` before an actual restore to preview what will change
- Use `packer diff` after making config changes to see what's drifted since last backup
- Keep `~/.packer` as a git repo — commit after each `packer backup` to maintain history
- Add `alias packer="/path/to/packer"` to your `.zshrc` for convenience
- `.DS_Store` files are automatically excluded from all operations
