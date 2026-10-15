# Project instructions

- Writing: keep user's voice, conversational, stick closely to what user said without making things up, but fix small grammar mistakes. Don't embellish or add sentences the user didn't say. Rephrasing and light cleanup is fine, but the content should come from the user.
- Never use em dashes (—). Use regular dashes (-) instead.

## Project structure

- `README.md` - Tips content
- `GLOBAL-AGENTS.md` - Global AGENTS.md for all projects. Symlinked from `~/.gemini/AGENTS.md`.
- `scripts/context-bar.sh` - Status line script for Antigravity CLI. Symlinked from `~/.gemini/antigravity-cli/statusline.sh` so edits here take effect immediately.
- `scripts/color-preview.sh` - Preview color themes for the status line script

## Official documentation

The official Antigravity CLI documentation is at `https://antigravity.google/docs/`. Use Playwright to browse it when researching features or verifying claims.

## Filing issues on the official repo

File issues on `google-antigravity/antigravity-cli` using host `gh` (not through a container).

Use `DX:` prefix for developer experience issues. Before filing, check the user's past submitted issues on the repo to match the style. Checking issues and duplicates are read-only calls on a public repo - use a safeclaw container per the global CLAUDE.md rules. Only use host `gh` for the actual write operation (creating the issue).
