# Testing

Automated unit, edge-case, and live `tmux` end-to-end tests for [`scripts/context-bar.sh`](./scripts/context-bar.sh) live in [`scripts/test-context-bar.sh`](./scripts/test-context-bar.sh).

## Running the Tests

```bash
# Run unit and edge-case tests (<1s, 18 assertions)
./scripts/test-context-bar.sh

# Run unit tests + live tmux end-to-end verification with agy (20 assertions)
./scripts/test-context-bar.sh --tmux
```

## Covered Test Cases

### 1. Unit & Edge-Case Tests (`./scripts/test-context-bar.sh`)

1. **Baseline `.cwd` when no `session_id` is present**: Uses `.cwd` (initial launch directory) and reads `.vcs.branch` from the status line JSON payload.
2. **Double-encoded `Cwd` in `transcript.jsonl`**: Unwraps JSON-encoded string values (e.g., `"\"/tmp/.../repo-a\""` stored under `.tool_calls[].args.Cwd`) and detects the git branch in the new directory even when launched from a non-git directory.
3. **Multiple `run_command` calls in a single step**: Picks the last `run_command` `Cwd` in chronological order and reports uncommitted file state (`*dirty.txt`) and the active branch.
4. **Non-`run_command` tool calls and text mentions**: Ignores `view_file` calls and plain-text mentions of `"run_command"` in assistant responses.
5. **Empty `Cwd` (`""` or `"\"\""`)**: If a subsequent `run_command` has an empty `Cwd`, falls back cleanly to `.cwd` (initial launch directory) rather than staying stuck on an older `Cwd` or resolving to `/`.
6. **Missing or `null` `Cwd`**: Falls back to `.cwd` and never renders `📁null`.
7. **Relative `Cwd` (`.` or `subdir/`)**: Resolves relative paths against `.cwd` and canonicalizes via `pwd` (never rendering `📁.`).
8. **Deleted or non-existent `Cwd`**: Falls back to `.cwd` if the directory from the last command was subsequently deleted.
9. **Directory names with spaces**: Preserves spaces (`my project dir`) across directory resolution and `git` checks.
10. **Corrupted or partial trailing JSON line**: Uses `jq -R -r 'fromjson? | ...'` so mid-write or truncated JSONL lines never fail status line rendering.
11. **Moving from a git repo into a non-git folder**: Clears the git branch indicator instead of leaking `.vcs.branch` from the launch repository.
12. **Token clamping (`>100%`) and narrow terminal wrapping**: Clamps token percentages above `100%` to `100%`, formats `200k` / `1M` limits, and wraps segments across lines on narrow terminals (`COLUMNS=55`).

### 2. Live `tmux` End-to-End Test (`./scripts/test-context-bar.sh --tmux`)

13. **Live `agy` TUI session inside `tmux`**:
    - Launches `agy` inside a headless `tmux` session (`100x28`) starting in `$HOME`.
    - Captures the rendered TUI pane and verifies the initial status line displays `📁<home-basename>`.
    - Sends a prompt instructing the agent to run `pwd` in `scripts/`.
    - Captures the rendered TUI pane after `run_command` completes and verifies the status line dynamically updates to `📁scripts`.
