#!/usr/bin/env bash
# Build every kustomization in the repo. A kustomization that doesn't build
# here is one Argo CD would refuse to sync, so this is the cheap version of
# that feedback: no cluster, no network.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command -v kustomize >/dev/null || {
  echo "kustomize not on PATH" >&2
  exit 1
}

# The default load restrictor stays on: nothing here reads files from outside
# its own directory, and leaving it on means CI rejects a kustomization that
# starts to.
failed=()
built=0
skipped=0

while IFS= read -r kustomization; do
  dir="$(dirname "$kustomization")"

  if grep -qE '^kind:[[:space:]]*Component[[:space:]]*$' "$kustomization"; then
    echo "==> $dir (component, skipped)"
    skipped=$((skipped + 1))
    continue
  fi

  echo "==> $dir"

  if kustomize build "$dir" >/dev/null; then
    built=$((built + 1))
  else
    failed+=("$dir")
  fi
done < <(
  find . -type f \( -name kustomization.yaml -o -name kustomization.yml \) \
    -not -path './.git/*' | sort
)

if ((${#failed[@]})); then
  echo >&2
  echo "kustomize build failed for:" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi

echo
echo "built $built kustomizations, skipped $skipped components"
