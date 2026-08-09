#!/usr/bin/env bash
set -e

export PATH="$HOME/.local/bin:$PATH"

if ! command -v codex >/dev/null 2>&1; then
  curl -fsSL https://chatgpt.com/codex/install.sh | sh
fi

"$HOME/.local/bin/codex" login --device-auth
