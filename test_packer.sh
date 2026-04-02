#!/bin/bash
#
# Test suite for packer
# Uses isolated temp directories — never touches real $HOME or ~/.packer-data
#
set -euo pipefail

PACKER="$(cd "$(dirname "$0")" && pwd)/packer"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Test harness ─────────────────────────────────────────────

setup() {
    TEST_DIR=$(mktemp -d)
    export HOME="$TEST_DIR/home"
    export PACKER_DATA_DIR="$TEST_DIR/data"
    mkdir -p "$HOME"
}

teardown() {
    rm -rf "$TEST_DIR"
    unset PACKER_DATA_DIR
}

run_packer() {
    "$PACKER" "$@"
}

assert_exit() {
    local expected="$1"
    shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    if [[ "$actual" -ne "$expected" ]]; then
        echo "  FAIL: expected exit $expected, got $actual"
        echo "  Command: $*"
        return 1
    fi
}

assert_file_exists() {
    if [[ ! -e "$1" ]]; then
        echo "  FAIL: expected file to exist: $1"
        return 1
    fi
}

assert_file_not_exists() {
    if [[ -e "$1" ]]; then
        echo "  FAIL: expected file NOT to exist: $1"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  FAIL: expected '$pattern' in $file"
        return 1
    fi
}

assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  FAIL: expected '$pattern' NOT in $file"
        return 1
    fi
}

assert_output_contains() {
    local output="$1"
    local pattern="$2"
    if ! echo "$output" | grep -q "$pattern"; then
        echo "  FAIL: expected output to contain '$pattern'"
        echo "  Got: $output"
        return 1
    fi
}

assert_files_equal() {
    if ! diff -q "$1" "$2" >/dev/null 2>&1; then
        echo "  FAIL: files differ: $1 vs $2"
        diff "$1" "$2" || true
        return 1
    fi
}

run_test() {
    local name="$1"
    local func="$2"
    ((TESTS_RUN++))
    setup
    local result=0
    if output=$($func 2>&1); then
        echo -e "  ${GREEN}✓${RESET} $name"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${RESET} $name"
        echo "$output" | sed 's/^/    /'
        ((TESTS_FAILED++))
    fi
    teardown
}

# ── Tests ────────────────────────────────────────────────────

test_help() {
    mkdir -p "$PACKER_DATA_DIR"
    local out
    out=$(run_packer help)
    assert_output_contains "$out" "packer — sync dotfiles"
    assert_output_contains "$out" "backup"
    assert_output_contains "$out" "restore"
    assert_output_contains "$out" "brew-dump"
    assert_output_contains "$out" "brew-diff"
    assert_output_contains "$out" "snapshots"
    assert_output_contains "$out" "rollback"
}

test_init_creates_profile() {
    run_packer -f init base
    assert_file_exists "$PACKER_DATA_DIR/base/packer.conf"
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles"
}

test_init_duplicate_profile() {
    run_packer -f init base
    local out
    out=$(run_packer -f init base)
    assert_output_contains "$out" "already exists"
}

test_profiles_empty() {
    mkdir -p "$PACKER_DATA_DIR"
    local out
    out=$(run_packer profiles 2>&1)
    assert_output_contains "$out" "No profiles found"
}

test_profiles_lists_profiles() {
    run_packer -f init alpha
    run_packer -f init beta
    local out
    out=$(run_packer profiles)
    assert_output_contains "$out" "alpha"
    assert_output_contains "$out" "beta"
}

test_add_path() {
    run_packer -f init base
    run_packer add base .zshrc
    assert_file_contains "$PACKER_DATA_DIR/base/packer.conf" "^.zshrc$"
}

test_add_duplicate_path() {
    run_packer -f init base
    run_packer add base .zshrc
    local out
    out=$(run_packer add base .zshrc)
    assert_output_contains "$out" "Already tracked"
}

test_add_normalizes_absolute_path() {
    run_packer -f init base
    run_packer add base "$HOME/.config/nvim"
    assert_file_contains "$PACKER_DATA_DIR/base/packer.conf" "^.config/nvim$"
}

test_add_normalizes_tilde_path() {
    run_packer -f init base
    run_packer add base "~/.gitconfig"
    assert_file_contains "$PACKER_DATA_DIR/base/packer.conf" "^.gitconfig$"
}

test_add_strips_trailing_slash() {
    run_packer -f init base
    run_packer add base ".config/nvim/"
    assert_file_contains "$PACKER_DATA_DIR/base/packer.conf" "^.config/nvim$"
}

test_remove_path() {
    run_packer -f init base
    run_packer add base .zshrc
    run_packer add base .gitconfig
    run_packer remove base .zshrc
    assert_file_not_contains "$PACKER_DATA_DIR/base/packer.conf" "^.zshrc$"
    assert_file_contains "$PACKER_DATA_DIR/base/packer.conf" "^.gitconfig$"
}

test_remove_nonexistent_fails() {
    run_packer -f init base
    assert_exit 1 run_packer remove base .nonexistent
}

test_add_missing_profile_fails() {
    mkdir -p "$PACKER_DATA_DIR"
    assert_exit 1 run_packer add nonexistent .zshrc
}

test_backup_dots_single_file() {
    run_packer -f init base
    echo "export FOO=bar" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    assert_files_equal "$HOME/.zshrc" "$PACKER_DATA_DIR/base/dotfiles/.zshrc"
}

test_backup_dots_directory() {
    run_packer -f init base
    mkdir -p "$HOME/.config/nvim"
    echo "set number" > "$HOME/.config/nvim/init.lua"
    echo "colorscheme blue" > "$HOME/.config/nvim/colors.lua"
    run_packer add base .config/nvim
    run_packer backup dots base
    assert_files_equal "$HOME/.config/nvim/init.lua" "$PACKER_DATA_DIR/base/dotfiles/.config/nvim/init.lua"
    assert_files_equal "$HOME/.config/nvim/colors.lua" "$PACKER_DATA_DIR/base/dotfiles/.config/nvim/colors.lua"
}

test_backup_dots_skips_missing() {
    run_packer -f init base
    run_packer add base .nonexistent
    local out
    out=$(run_packer backup dots base)
    assert_output_contains "$out" "Skipping"
}

test_backup_dots_excludes_ds_store() {
    run_packer -f init base
    mkdir -p "$HOME/.config/test"
    echo "content" > "$HOME/.config/test/file.txt"
    echo "ds" > "$HOME/.config/test/.DS_Store"
    run_packer add base .config/test
    run_packer backup dots base
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.config/test/file.txt"
    assert_file_not_exists "$PACKER_DATA_DIR/base/dotfiles/.config/test/.DS_Store"
}

test_backup_dots_all_profiles() {
    run_packer -f init base
    run_packer -f init work
    echo "base-content" > "$HOME/.zshrc"
    echo "work-content" > "$HOME/.workrc"
    run_packer add base .zshrc
    run_packer add work .workrc
    run_packer backup dots
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.zshrc"
    assert_file_exists "$PACKER_DATA_DIR/work/dotfiles/.workrc"
}

test_restore_dots_single_file() {
    run_packer -f init base
    echo "original" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    # Modify the live file
    echo "modified" > "$HOME/.zshrc"
    # Restore
    run_packer -f restore dots base
    local content
    content=$(cat "$HOME/.zshrc")
    [[ "$content" == "original" ]] || { echo "FAIL: expected 'original', got '$content'"; return 1; }
}

test_restore_dots_creates_snapshot() {
    run_packer -f init base
    echo "live-content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    echo "changed" > "$HOME/.zshrc"
    run_packer -f restore dots base
    # Snapshot should exist
    local snap_count
    snap_count=$(ls "$PACKER_DATA_DIR/.snapshots" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$snap_count" -ge 1 ]] || { echo "FAIL: expected snapshot, found $snap_count"; return 1; }
    # Snapshot should contain the "changed" version
    local snap_dir
    snap_dir=$(ls -d "$PACKER_DATA_DIR/.snapshots"/*/ | head -1)
    local snap_content
    snap_content=$(cat "$snap_dir/.zshrc")
    [[ "$snap_content" == "changed" ]] || { echo "FAIL: snapshot should contain 'changed', got '$snap_content'"; return 1; }
}

test_restore_dots_layering() {
    run_packer -f init base
    run_packer -f init work
    # Base has a .gitconfig
    mkdir -p "$PACKER_DATA_DIR/base/dotfiles"
    printf "[user]\n  name = Base User\n" > "$PACKER_DATA_DIR/base/dotfiles/.gitconfig"
    echo ".gitconfig" > "$PACKER_DATA_DIR/base/packer.conf"
    # Work overrides .gitconfig
    mkdir -p "$PACKER_DATA_DIR/work/dotfiles"
    printf "[user]\n  name = Work User\n" > "$PACKER_DATA_DIR/work/dotfiles/.gitconfig"
    echo ".gitconfig" > "$PACKER_DATA_DIR/work/packer.conf"
    # Restore base then work — work should win
    run_packer -f restore dots base work
    local content
    content=$(cat "$HOME/.gitconfig")
    assert_output_contains "$content" "Work User"
}

test_restore_dots_dry_run_no_changes() {
    run_packer -f init base
    echo "original" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    echo "modified" > "$HOME/.zshrc"
    run_packer -n restore dots base
    # File should still be "modified" (dry-run doesn't change anything)
    local content
    content=$(cat "$HOME/.zshrc")
    [[ "$content" == "modified" ]] || { echo "FAIL: dry-run should not modify files"; return 1; }
}

test_restore_dots_dry_run_no_snapshot() {
    run_packer -f init base
    echo "content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    run_packer -n restore dots base
    # No snapshot should be created during dry-run
    assert_file_not_exists "$PACKER_DATA_DIR/.snapshots"
}

test_diff_in_sync() {
    run_packer -f init base
    echo "content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    local out
    out=$(run_packer diff base)
    assert_output_contains "$out" "Everything is in sync"
}

test_diff_detects_changes() {
    run_packer -f init base
    echo "original" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    echo "modified" > "$HOME/.zshrc"
    local out
    out=$(run_packer diff base)
    assert_output_contains "$out" ".zshrc"
    # Should show the actual diff content
    assert_output_contains "$out" "modified"
}

test_diff_detects_missing_live_file() {
    run_packer -f init base
    echo "content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    rm "$HOME/.zshrc"
    local out
    out=$(run_packer diff base)
    assert_output_contains "$out" "missing but exists in repo"
}

test_diff_detects_not_backed_up() {
    run_packer -f init base
    echo "content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    # Don't backup — file exists in HOME but not in repo
    local out
    out=$(run_packer diff base)
    assert_output_contains "$out" "not backed up"
}

test_list_shows_paths() {
    run_packer -f init base
    echo "content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer add base .gitconfig
    local out
    out=$(run_packer list base)
    assert_output_contains "$out" ".zshrc"
    assert_output_contains "$out" ".gitconfig"
}

test_list_all_profiles() {
    run_packer -f init base
    run_packer -f init work
    run_packer add base .zshrc
    run_packer add work .workrc
    local out
    out=$(run_packer list)
    assert_output_contains "$out" "base"
    assert_output_contains "$out" "work"
    assert_output_contains "$out" ".zshrc"
    assert_output_contains "$out" ".workrc"
}

test_dry_run_backup_no_files_created() {
    run_packer -f init base
    echo "content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer -n backup dots base
    assert_file_not_exists "$PACKER_DATA_DIR/base/dotfiles/.zshrc"
}

test_snapshots_empty() {
    run_packer -f init base
    local out
    out=$(run_packer snapshots)
    assert_output_contains "$out" "No snapshots"
}

test_snapshots_lists_after_restore() {
    run_packer -f init base
    echo "content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    run_packer -f restore dots base
    local out
    out=$(run_packer snapshots)
    assert_output_contains "$out" "Snapshots"
    # Should show a timestamp-format entry
    assert_output_contains "$out" "file(s)"
}

test_rollback() {
    run_packer -f init base
    echo "original" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    # Modify, then restore (which snapshots "modified")
    echo "modified" > "$HOME/.zshrc"
    run_packer -f restore dots base
    # Now .zshrc is "original" (from backup). Rollback should bring back "modified"
    run_packer -f rollback
    local content
    content=$(cat "$HOME/.zshrc")
    [[ "$content" == "modified" ]] || { echo "FAIL: expected 'modified' after rollback, got '$content'"; return 1; }
}

test_rollback_no_snapshots_fails() {
    run_packer -f init base
    assert_exit 1 run_packer -f rollback
}

test_rollback_dry_run() {
    run_packer -f init base
    echo "content" > "$HOME/.zshrc"
    run_packer add base .zshrc
    run_packer backup dots base
    run_packer -f restore dots base
    echo "after-restore" > "$HOME/.zshrc"
    run_packer -n rollback
    local content
    content=$(cat "$HOME/.zshrc")
    [[ "$content" == "after-restore" ]] || { echo "FAIL: dry-run rollback should not modify files"; return 1; }
}

test_unknown_command_fails() {
    run_packer -f init base
    assert_exit 1 run_packer nonexistent
}

test_unknown_flag_fails() {
    assert_exit 1 run_packer --bad-flag help
}

test_config_parsing_skips_comments() {
    run_packer -f init base
    cat > "$PACKER_DATA_DIR/base/packer.conf" <<'EOF'
# This is a comment
.zshrc
   # Indented comment
.gitconfig
  .vimrc   # inline comment

EOF
    echo "z" > "$HOME/.zshrc"
    echo "g" > "$HOME/.gitconfig"
    echo "v" > "$HOME/.vimrc"
    run_packer backup dots base
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.zshrc"
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.gitconfig"
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.vimrc"
}

test_config_parsing_skips_blank_lines() {
    run_packer -f init base
    printf ".zshrc\n\n\n.gitconfig\n" > "$PACKER_DATA_DIR/base/packer.conf"
    echo "z" > "$HOME/.zshrc"
    echo "g" > "$HOME/.gitconfig"
    run_packer backup dots base
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.zshrc"
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.gitconfig"
}

test_backup_brew_skips_existing() {
    run_packer -f init base
    echo 'brew "fzf"' > "$PACKER_DATA_DIR/base/Brewfile"
    local out
    out=$(run_packer backup brew base)
    assert_output_contains "$out" "already exists"
    # Brewfile should be unchanged
    local content
    content=$(cat "$PACKER_DATA_DIR/base/Brewfile")
    [[ "$content" == 'brew "fzf"' ]] || { echo "FAIL: Brewfile was modified"; return 1; }
}

test_restore_nonexistent_profile_fails() {
    mkdir -p "$PACKER_DATA_DIR"
    assert_exit 1 run_packer -f restore dots nonexistent
}

test_init_missing_name_fails() {
    mkdir -p "$PACKER_DATA_DIR"
    assert_exit 1 run_packer -f init
}

test_add_missing_args_fails() {
    run_packer -f init base
    assert_exit 1 run_packer add base
}

test_remove_missing_args_fails() {
    run_packer -f init base
    assert_exit 1 run_packer remove base
}

test_backup_directory_sync_deletes_removed_files() {
    run_packer -f init base
    mkdir -p "$HOME/.config/test"
    echo "a" > "$HOME/.config/test/a.txt"
    echo "b" > "$HOME/.config/test/b.txt"
    run_packer add base .config/test
    run_packer backup dots base
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.config/test/b.txt"
    # Remove b.txt from live, backup again
    rm "$HOME/.config/test/b.txt"
    run_packer backup dots base
    # b.txt should be deleted from backup too (rsync --delete)
    assert_file_not_exists "$PACKER_DATA_DIR/base/dotfiles/.config/test/b.txt"
    assert_file_exists "$PACKER_DATA_DIR/base/dotfiles/.config/test/a.txt"
}

# ── Run all tests ────────────────────────────────────────────

echo -e "\n${BOLD}Running packer tests...${RESET}\n"

# Save real HOME to restore later
REAL_HOME="$HOME"

run_test "help shows usage" test_help
run_test "init creates profile directory and conf" test_init_creates_profile
run_test "init duplicate profile warns" test_init_duplicate_profile
run_test "profiles shows empty state" test_profiles_empty
run_test "profiles lists all profiles" test_profiles_lists_profiles
run_test "add appends path to conf" test_add_path
run_test "add duplicate path warns" test_add_duplicate_path
run_test "add normalizes absolute path" test_add_normalizes_absolute_path
run_test "add normalizes ~ path" test_add_normalizes_tilde_path
run_test "add strips trailing slash" test_add_strips_trailing_slash
run_test "remove deletes path from conf" test_remove_path
run_test "remove nonexistent path fails" test_remove_nonexistent_fails
run_test "add to missing profile fails" test_add_missing_profile_fails
run_test "backup dots copies single file" test_backup_dots_single_file
run_test "backup dots copies directory" test_backup_dots_directory
run_test "backup dots skips missing files" test_backup_dots_skips_missing
run_test "backup dots excludes .DS_Store" test_backup_dots_excludes_ds_store
run_test "backup dots all profiles" test_backup_dots_all_profiles
run_test "backup directory sync deletes removed files" test_backup_directory_sync_deletes_removed_files
run_test "restore dots restores file content" test_restore_dots_single_file
run_test "restore creates snapshot" test_restore_dots_creates_snapshot
run_test "restore layers profiles in order" test_restore_dots_layering
run_test "restore dry-run does not modify files" test_restore_dots_dry_run_no_changes
run_test "restore dry-run does not create snapshot" test_restore_dots_dry_run_no_snapshot
run_test "restore nonexistent profile fails" test_restore_nonexistent_profile_fails
run_test "diff reports in sync" test_diff_in_sync
run_test "diff detects file changes" test_diff_detects_changes
run_test "diff detects missing live file" test_diff_detects_missing_live_file
run_test "diff detects not backed up" test_diff_detects_not_backed_up
run_test "list shows tracked paths" test_list_shows_paths
run_test "list shows all profiles" test_list_all_profiles
run_test "dry-run backup creates no files" test_dry_run_backup_no_files_created
run_test "snapshots shows empty state" test_snapshots_empty
run_test "snapshots lists after restore" test_snapshots_lists_after_restore
run_test "rollback restores snapshot" test_rollback
run_test "rollback with no snapshots fails" test_rollback_no_snapshots_fails
run_test "rollback dry-run does not modify" test_rollback_dry_run
run_test "backup brew skips existing Brewfile" test_backup_brew_skips_existing
run_test "config parsing skips comments" test_config_parsing_skips_comments
run_test "config parsing skips blank lines" test_config_parsing_skips_blank_lines
run_test "unknown command fails" test_unknown_command_fails
run_test "unknown flag fails" test_unknown_flag_fails
run_test "init missing name fails" test_init_missing_name_fails
run_test "add missing args fails" test_add_missing_args_fails
run_test "remove missing args fails" test_remove_missing_args_fails

# Restore real HOME
export HOME="$REAL_HOME"

echo ""
echo -e "${BOLD}Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_RUN total${RESET}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
