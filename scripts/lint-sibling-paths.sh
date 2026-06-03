#!/usr/bin/env bash
# lint-sibling-paths: fail if any dependency points OUTSIDE this repo.
#
# The recurring deploy failure across agent-platform has been a shared thing
# (a Terraform module, a Cargo crate) referenced by a relative path to a
# *sibling directory* — which exists in the local monorepo-style checkout but
# NOT in an isolated single-repo CI checkout, so `terraform init` / `cargo build`
# fail. Shared deps must be published + pinned (git tag), never relative-sibling
# paths. This catches the mistake at commit/CI time instead of deploy time.
#
# Usage: lint-sibling-paths.sh [repo-dir]   (default: current dir)
# Exit 0 = clean; exit 1 = an escaping relative dependency was found.
set -euo pipefail

target="${1:-.}"
root="$(cd "$target" && git rev-parse --show-toplevel)"
violations=0

# Resolve $2 relative to the dir of file $1; flag if it escapes $root.
check() {
  local file="$1" raw="$2" kind="$3" abs
  abs="$(cd "$(dirname "$file")" && realpath -m "$raw")"
  case "$abs/" in
    "$root"/*) : ;;  # inside the repo — fine (e.g. a workspace member)
    *) echo "  ESCAPES REPO  ${file#$root/}  ($kind = \"$raw\")"; violations=$((violations + 1)) ;;
  esac
}

# Cargo path dependencies
while IFS= read -r f; do
  while IFS= read -r p; do
    [ -n "$p" ] && check "$f" "$p" "path"
  done < <(grep -oE 'path[[:space:]]*=[[:space:]]*"[^"]+"' "$f" | sed -E 's/.*"([^"]+)".*/\1/')
done < <(find "$root" -name Cargo.toml -not -path '*/target/*' -not -path '*/.git/*')

# Terraform module sources that are relative paths
while IFS= read -r f; do
  while IFS= read -r s; do
    case "$s" in
      ./*|../*) check "$f" "$s" "source" ;;
    esac
  done < <(grep -oE 'source[[:space:]]*=[[:space:]]*"[^"]+"' "$f" | sed -E 's/.*"([^"]+)".*/\1/')
done < <(find "$root" -name '*.tf' -not -path '*/.terraform/*' -not -path '*/.git/*')

if [ "$violations" -eq 0 ]; then
  echo "ok: no escaping relative dependencies in ${root##*/}"
else
  echo "FAIL: $violations escaping relative dependency(ies) — publish + pin them (git tag) instead of a sibling path."
  exit 1
fi
