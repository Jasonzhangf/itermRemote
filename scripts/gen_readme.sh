#!/usr/bin/env bash
set -euo pipefail

# Repo-wide README generator.
#
# Policy:
# - Each module README.md is generated as:
#     README_MANUAL.md (optional) + AUTO-GEN section
# - AUTO-GEN section includes a best-effort file list.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

modules=(
  "$repo_root/apps/host_daemon"
  "$repo_root/apps/host_console"
  "$repo_root/apps/android_client"
  "$repo_root/examples/host_test_app"
  "$repo_root/packages/cloudplayplus_core"
  "$repo_root/packages/iterm2_host"
  "$repo_root/packages/itermremote_protocol"
  "$repo_root/packages/itermremote_blocks"
  "$repo_root/plugins/flutter-webrtc"
  "$repo_root/src/modules/observability"
)

autogen_header=$'---\n## AUTO-GEN (以下内容由脚本生成，禁止手工修改)\n---\n'

relpath() {
  # macOS doesn't ship with GNU realpath by default.
  python3 - <<PY
import os
print(os.path.relpath("$1", "$repo_root"))
PY
}

for m in "${modules[@]}"; do
  if [[ ! -d "$m" ]]; then
    continue
  fi

  manual="$m/README_MANUAL.md"
  out="$m/README.md"

  tmp="$(mktemp)"

  if [[ -f "$manual" ]]; then
    cat "$manual" > "$tmp"
    echo >> "$tmp"
  else
    echo "# $(basename "$m")" > "$tmp"
    echo >> "$tmp"
    echo "(MANUAL section missing: create README_MANUAL.md to add human notes.)" >> "$tmp"
    echo >> "$tmp"
  fi

  printf "%s" "$autogen_header" >> "$tmp"
  echo >> "$tmp"
  echo "### Module Path" >> "$tmp"
  echo "\`$(relpath "$m")\`" >> "$tmp"
  echo >> "$tmp"

  if [[ -f "$m/pubspec.yaml" ]]; then
    echo "### pubspec.yaml" >> "$tmp"
    echo "\`pubspec.yaml\`" >> "$tmp"
    echo >> "$tmp"
  fi

  echo "### Files" >> "$tmp"
  echo >> "$tmp"
  echo "\`\`\`" >> "$tmp"
  (
    cd "$m"
    find . -maxdepth 2 -type f \
      ! -path "./.dart_tool/*" \
      ! -path "./build/*" \
      ! -path "./Pods/*" \
      ! -path "./DerivedData/*" \
      ! -name "README.md" \
      ! -name "README_MANUAL.md" \
      ! -name "*.iml" \
      ! -name ".metadata" \
      | sed 's|^\./||' \
      | sort
  ) >> "$tmp"
  echo "\`\`\`" >> "$tmp"

  mkdir -p "$(dirname "$out")"
  mv "$tmp" "$out"
done

# Top-level INDEX.md is kept short and hand-written.
# We only ensure it exists.
if [[ ! -f "$repo_root/INDEX.md" ]]; then
  cat > "$repo_root/INDEX.md" << 'EOT'
# Repo Documentation Index

- AGENTS: `AGENTS.md`
EOT
fi
