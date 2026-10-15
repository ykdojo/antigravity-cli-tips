Title: Created a custom status line for Antigravity CLI
Flair: Resources & Guides

---

I created a custom status line for Antigravity CLI and wanted to share it here. It shows the model, current directory, git branch, uncommitted file count, sync status with origin, and a visual progress bar for token usage:

```
Gemini 4 Argon (Medium) | 📁antigravity-cli-tips | 🔀main (scripts/color-preview.sh uncommitted, synced 14m ago) | █▄░░░░░░░░ 15% of 1M tokens
```

To set this up:

1. Copy the script to your Antigravity CLI config directory:
   ```bash
   mkdir -p ~/.gemini/antigravity-cli
   curl -o ~/.gemini/antigravity-cli/statusline.sh https://raw.githubusercontent.com/ykdojo/antigravity-cli-tips/main/scripts/context-bar.sh
   chmod +x ~/.gemini/antigravity-cli/statusline.sh
   ```

2. Add the following to your `~/.gemini/antigravity-cli/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.gemini/antigravity-cli/statusline.sh"
     }
   }
   ```

The script supports 10 color themes (orange, blue, teal, green, lavender, rose, gold, slate, cyan, or gray). Edit the `COLOR` variable at the top of the script to change it.

It also adapts to narrow terminals by wrapping at natural breakpoints instead of getting cut off:

```
Gemini 4 Argon (Medium) | 📁antigravity-cli-tips
 | 🔀main (scripts/context-bar.sh uncommitted, synced 11m ago)
 | ░░░░░░░░░░ 0% of 1M tokens
```

Source: https://github.com/ykdojo/antigravity-cli-tips
