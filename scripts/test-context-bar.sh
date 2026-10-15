#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_BAR="$SCRIPT_DIR/context-bar.sh"

pass_count=0
fail_count=0

strip_ansi() {
    python3 -c 'import re, sys; sys.stdout.write(re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", sys.stdin.read()))'
}

assert_contains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  [PASS] $name"
        ((pass_count++)) || true
    else
        echo "  [FAIL] $name"
        echo "         Expected to contain: $needle"
        echo "         Actual output:       $haystack"
        ((fail_count++)) || true
    fi
}

assert_not_contains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  [PASS] $name"
        ((pass_count++)) || true
    else
        echo "  [FAIL] $name"
        echo "         Expected NOT to contain: $needle"
        echo "         Actual output:           $haystack"
        ((fail_count++)) || true
    fi
}

TMPDIR_ROOT="$(mktemp -d -t context-bar-tests.XXXXXX)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

LAUNCH_DIR="$TMPDIR_ROOT/launch-dir"
SUB_DIR="$LAUNCH_DIR/sub-project"
SPACE_DIR="$TMPDIR_ROOT/my spaced project"
NON_GIT_DIR="$TMPDIR_ROOT/non-git-folder"
GIT_REPO_A="$TMPDIR_ROOT/repo-alpha"
GIT_REPO_B="$TMPDIR_ROOT/repo-beta"
TRANSCRIPT="$TMPDIR_ROOT/transcript.jsonl"

mkdir -p "$LAUNCH_DIR" "$SUB_DIR" "$SPACE_DIR" "$NON_GIT_DIR" "$GIT_REPO_A" "$GIT_REPO_B"

# Initialize Git Repo A (branch: main, 0 uncommitted, no upstream)
git -C "$GIT_REPO_A" init -q -b main
git -C "$GIT_REPO_A" config user.email "test@example.com"
git -C "$GIT_REPO_A" config user.name "Test User"
echo "hello" > "$GIT_REPO_A/README.md"
git -C "$GIT_REPO_A" add README.md
git -C "$GIT_REPO_A" commit -q -m "initial"

# Initialize Git Repo B (branch: feat-x, 1 uncommitted file)
git -C "$GIT_REPO_B" init -q -b feat-x
git -C "$GIT_REPO_B" config user.email "test@example.com"
git -C "$GIT_REPO_B" config user.name "Test User"
echo "init" > "$GIT_REPO_B/app.py"
git -C "$GIT_REPO_B" add app.py
git -C "$GIT_REPO_B" commit -q -m "initial"
echo "dirty" >> "$GIT_REPO_B/app.py"

run_bar() {
    local json="$1"
    printf '%s\n' "$json" | bash "$CONTEXT_BAR" | strip_ansi
}

echo "=== Running context-bar.sh Automated Unit & Edge-Case Tests ==="

# 1. Baseline: no session_id / no transcript yet -> uses .cwd
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"context_window\":{\"context_window_size\":1048576,\"used_percentage\":5},\"terminal_width\":160}")
assert_contains "1. Baseline .cwd when no session_id is present" "$out" "📁launch-dir"

# 2. Double-encoded JSON string Cwd in transcript (standard Antigravity transcript format)
cat > "$TRANSCRIPT" <<EOF
{"step_index":1,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"$GIT_REPO_A\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"context_window\":{\"context_window_size\":1048576,\"used_percentage\":5},\"terminal_width\":160}")
assert_contains "2a. Double-encoded Cwd updates directory" "$out" "📁repo-alpha"
assert_contains "2b. Detects git branch in new Cwd when launched from non-git dir" "$out" "🔀main (0 files uncommitted, no upstream)"

# 3. Multiple run_command calls in one step & across steps -> picks the very last one
cat >> "$TRANSCRIPT" <<EOF
{"step_index":2,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"$GIT_REPO_A\""}},{"name":"run_command","args":{"Cwd":"\"$GIT_REPO_B\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "3a. Picks last run_command within multi-call step" "$out" "📁repo-beta"
assert_contains "3b. Shows single uncommitted filename and new branch" "$out" "🔀feat-x (app.py uncommitted, no upstream)"

# 4. Assistant text or other tools mentioning "run_command" do not override Cwd
cat >> "$TRANSCRIPT" <<EOF
{"step_index":3,"content":"I used run_command earlier.","tool_calls":[{"name":"view_file","args":{"AbsolutePath":"\"$LAUNCH_DIR/file.txt\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "4. Ignores non-run_command steps and text mentions" "$out" "📁repo-beta"

# 5. Trailing empty Cwd ("") falls back to initial launch directory (.cwd)
cat >> "$TRANSCRIPT" <<EOF
{"step_index":4,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "5. Trailing empty Cwd (\"\") falls back to launch .cwd" "$out" "📁launch-dir"

# 6. Trailing null/missing Cwd falls back to initial launch directory (.cwd), never "null"
cat >> "$TRANSCRIPT" <<EOF
{"step_index":5,"tool_calls":[{"name":"run_command","args":{"CommandLine":"\"pwd\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "6a. Missing/null Cwd falls back to launch .cwd" "$out" "📁launch-dir"
assert_not_contains "6b. Missing/null Cwd never renders 📁null" "$out" "📁null"

# 7. Relative Cwd ("." and "sub-project") and trailing slash normalization
cat > "$TRANSCRIPT" <<EOF
{"step_index":1,"tool_calls":[{"name":"run_command","args":{"Cwd":"\".\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "7a. Relative Cwd '.' resolves to launch directory name (not 📁.)" "$out" "📁launch-dir"

cat > "$TRANSCRIPT" <<EOF
{"step_index":1,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"sub-project/\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "7b. Relative subdirectory Cwd with trailing slash resolves cleanly" "$out" "📁sub-project"

# 8. Deleted / non-existent Cwd directory falls back to .cwd
cat > "$TRANSCRIPT" <<EOF
{"step_index":1,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"$TMPDIR_ROOT/does-not-exist\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "8. Deleted or non-existent Cwd falls back to .cwd" "$out" "📁launch-dir"

# 9. Directory name with spaces
cat > "$TRANSCRIPT" <<EOF
{"step_index":1,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"$SPACE_DIR\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "9. Directory name with spaces is preserved" "$out" "📁my spaced project"

# 10. Truncated / corrupted trailing JSON line in transcript.jsonl does not break parsing
cat > "$TRANSCRIPT" <<EOF
{"step_index":1,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"$GIT_REPO_A\""}}]}
{"step_index":2,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"/truncated-json-line
EOF
out=$(run_bar "{\"cwd\":\"$LAUNCH_DIR\",\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "10. Corrupted trailing JSON line is skipped gracefully" "$out" "📁repo-alpha"

# 11. Moving from a git repo (.vcs.branch="main") to a non-git folder does not leak .vcs.branch
cat > "$TRANSCRIPT" <<EOF
{"step_index":1,"tool_calls":[{"name":"run_command","args":{"Cwd":"\"$NON_GIT_DIR\""}}]}
EOF
out=$(run_bar "{\"cwd\":\"$GIT_REPO_A\",\"vcs\":{\"branch\":\"main\"},\"session_id\":\"test-session\",\"transcript_path\":\"$TRANSCRIPT\",\"model\":{\"display_name\":\"Gemini 4 Argon\"},\"terminal_width\":160}")
assert_contains "11a. Shows non-git folder name" "$out" "📁non-git-folder"
assert_not_contains "11b. Does not leak launch repo .vcs.branch into non-git folder" "$out" "🔀"

# 12. Narrow terminal wrapping & float/clamped percentage formatting
out=$(run_bar "{\"cwd\":\"$GIT_REPO_A\",\"vcs\":{\"branch\":\"main\"},\"model\":{\"display_name\":\"Gemini 4 Argon (Medium)\"},\"context_window\":{\"context_window_size\":200000,\"used_percentage\":104.7},\"terminal_width\":55}")
line_count=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
assert_contains "12a. Clamps >100% token usage to 100% and formats 200k" "$out" "100% of 200k tokens"
if [[ "$line_count" -ge 2 ]]; then
    echo "  [PASS] 12b. Wraps output across multiple lines ($line_count lines) on narrow terminal (width=55)"
    ((pass_count++)) || true
else
    echo "  [FAIL] 12b. Expected wrapped lines >= 2, got $line_count"
    ((fail_count++)) || true
fi

if [[ "${1:-}" == "--tmux" ]]; then
    echo ""
    echo "=== Running Live tmux End-to-End Integration Test ==="
    export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
    TMUX_SESSION="ctxbar-e2e-$$"
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$TMUX_SESSION" -x 140 -y 35 -c "$HOME" "$HOME/.local/bin/agy --dangerously-skip-permissions"
    sleep 4
    init_pane=$(tmux capture-pane -t "$TMUX_SESSION" -p)
    assert_contains "13a. Live tmux initial launch in ~ shows 📁$(basename "$HOME")" "$init_pane" "📁$(basename "$HOME")"

    tmux send-keys -t "$TMUX_SESSION" -l "/no-email Run pwd in $SCRIPT_DIR and reply with just OK."
    sleep 0.4
    tmux send-keys -t "$TMUX_SESSION" Enter

    updated=0
    for _ in {1..20}; do
        sleep 1
        pane=$(tmux capture-pane -t "$TMUX_SESSION" -p)
        if [[ "$pane" == *"📁scripts"* ]]; then
            updated=1
            break
        fi
    done
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    if [[ "$updated" -eq 1 ]]; then
        echo "  [PASS] 13b. Live tmux status bar updated to 📁scripts after run_command"
        ((pass_count++)) || true
    else
        echo "  [FAIL] 13b. Live tmux status bar did not update to 📁scripts"
        ((fail_count++)) || true
    fi
fi

echo ""
echo "Summary: $pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
