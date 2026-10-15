#!/bin/bash

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
# Preview colors with: bash scripts/color-preview.sh
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'  # explicit gray for default text
C_BAR_EMPTY='\033[38;5;238m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

input=$(cat)

# Extract model and directory
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
initial_cwd=$(echo "$input" | jq -r '.cwd // empty')
cwd="$initial_cwd"

# Prefer the latest run_command Cwd from the session transcript (falls back to .cwd if empty)
session_id=$(echo "$input" | jq -r '.session_id // empty')
if [[ -n "$session_id" ]]; then
    transcript="$HOME/.gemini/antigravity-cli/brain/$session_id/.system_generated/logs/transcript.jsonl"
    if [[ ! -f "$transcript" ]]; then
        transcript=$(echo "$input" | jq -r '.transcript_path // empty')
    fi
    if [[ -n "$transcript" && -f "$transcript" ]]; then
        last_cwd=$(jq -r '.tool_calls[]? | select(.name == "run_command") | (.args.Cwd | (fromjson? // .))' "$transcript" 2>/dev/null | tail -n 1)
        last_cwd="${last_cwd/#\~/$HOME}"
        if [[ -n "$last_cwd" && -d "$last_cwd" ]]; then
            cwd="$last_cwd"
        fi
    fi
fi
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch (only use .vcs.branch from JSON if cwd hasn't changed from launch directory)
branch=""
if [[ "$cwd" == "$initial_cwd" ]]; then
    branch=$(echo "$input" | jq -r '.vcs.branch // empty')
fi
if [[ -z "$branch" && -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
fi

git_status=""
if [[ -n "$branch" && -n "$cwd" && -d "$cwd" ]]; then
    # Count uncommitted files
    file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

    # Check sync status with upstream
    sync_status=""
    upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
    if [[ -n "$upstream" ]]; then
        # Get last fetch time
        fetch_head="$cwd/.git/FETCH_HEAD"
        fetch_ago=""
        if [[ -f "$fetch_head" ]]; then
            fetch_time=$(stat -f %m "$fetch_head" 2>/dev/null || stat -c %Y "$fetch_head" 2>/dev/null)
            if [[ -n "$fetch_time" ]]; then
                now=$(date +%s)
                diff=$((now - fetch_time))
                if [[ $diff -lt 60 ]]; then
                    fetch_ago="<1m ago"
                elif [[ $diff -lt 3600 ]]; then
                    fetch_ago="$((diff / 60))m ago"
                elif [[ $diff -lt 86400 ]]; then
                    fetch_ago="$((diff / 3600))h ago"
                else
                    fetch_ago="$((diff / 86400))d ago"
                fi
            fi
        fi

        counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
        ahead=$(echo "$counts" | cut -f1)
        behind=$(echo "$counts" | cut -f2)
        if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
            if [[ -n "$fetch_ago" ]]; then
                sync_status="synced ${fetch_ago}"
            else
                sync_status="synced"
            fi
        elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
            sync_status="${ahead} ahead"
        elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
            sync_status="${behind} behind"
        else
            sync_status="${ahead} ahead, ${behind} behind"
        fi
    else
        sync_status="no upstream"
    fi

    # Build git status string
    if [[ "$file_count" -eq 0 ]]; then
        git_status="(0 files uncommitted, ${sync_status})"
    elif [[ "$file_count" -eq 1 ]]; then
        single_file=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | head -1 | sed 's/^...//')
        git_status="(${single_file} uncommitted, ${sync_status})"
    else
        git_status="(${file_count} files uncommitted, ${sync_status})"
    fi
fi

# Get context usage from JSON
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 1048576')
max_k=$((max_context / 1000))
if [[ $max_k -ge 1000 ]]; then
    max_display="$((max_k / 1000))M"
else
    max_display="${max_k}k"
fi

pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[[ -z "$pct" || "$pct" == "null" ]] && pct=0
[[ $pct -gt 100 ]] && pct=100

bar_width=10
bar=""
for ((i=0; i<bar_width; i++)); do
    bar_start=$((i * 10))
    progress=$((pct - bar_start))
    if [[ $progress -ge 8 ]]; then
        bar+="${C_ACCENT}█${C_RESET}"
    elif [[ $progress -ge 3 ]]; then
        bar+="${C_ACCENT}▄${C_RESET}"
    else
        bar+="${C_BAR_EMPTY}░${C_RESET}"
    fi
done

ctx="${bar} ${C_GRAY}${pct}% of ${max_display} tokens"

# Get terminal width from JSON
term_width=$(echo "$input" | jq -r '.terminal_width // 120')

# Build segments: each has a colored version and a plain version for measuring
seg_colored=()
seg_plain=()

seg_colored+=("${C_ACCENT}${model}${C_GRAY}")
seg_plain+=("${model}")

seg_colored+=(" | 📁${dir}")
seg_plain+=(" | 📁${dir}")

if [[ -n "$branch" ]]; then
    seg_colored+=(" | 🔀${branch} ${git_status}")
    seg_plain+=(" | 🔀${branch} ${git_status}")
fi

seg_colored+=(" | ${ctx}${C_RESET}")
seg_plain+=(" | xxxxxxxxxx ${pct}% of ${max_display} tokens")

# Build lines, wrapping at word boundaries when a segment won't fit
line=""
line_len=0
first=1
for (( s=0; s<${#seg_colored[@]}; s++ )); do
    p="${seg_plain[$s]}"
    # Account for double-width emojis
    p_len=${#p}
    [[ "$p" == *📁* ]] && (( p_len++ ))
    [[ "$p" == *🔀* ]] && (( p_len++ ))

    if (( first || line_len + p_len <= term_width )); then
        line+="${seg_colored[$s]}"
        (( line_len += p_len ))
        first=0
    else
        printf '%b\n' "$line"
        line="${seg_colored[$s]}"
        line_len=$p_len
    fi
done
printf '%b\n' "$line"
