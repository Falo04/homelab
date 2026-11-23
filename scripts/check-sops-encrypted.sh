#!/usr/bin/env bash
# pre-commit hook: refuse a *.sops.yaml that isn't encrypted. Catches the file
# that was created or decrypted for editing and never encrypted again; gitleaks
# can miss those, since most of their values don't look like keys.
set -euo pipefail

failed=0
for file in "$@"; do
  if ! grep -q '^sops:' "$file"; then
    echo "$file: not SOPS-encrypted, run: sops encrypt -i $file" >&2
    failed=1
  fi
done
exit "$failed"
