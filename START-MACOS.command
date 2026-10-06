#!/bin/zsh
# Offline UI preview: no PowerShell, server, or dependencies required.
# Resolve the package location even when Finder launches from another directory.
SCRIPT_DIR="${0:A:h}"
open "$SCRIPT_DIR/preview/index.html"
