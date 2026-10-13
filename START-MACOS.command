#!/bin/zsh
# Open the included offline draft. Finder may start this from a different directory.
SCRIPT_DIR="${0:A:h}"
PREVIEW_FILE="$SCRIPT_DIR/preview/index.html"
if [[ ! -f "$PREVIEW_FILE" || ! -f "$SCRIPT_DIR/preview/data.js" || ! -f "$SCRIPT_DIR/preview/flow.js" ]]; then
  print -u2 'The preview is incomplete. Download and extract the whole Lenovo_update folder, then try again.'
  read '?Press Return to close.'
  exit 1
fi
/usr/bin/open "$PREVIEW_FILE"
