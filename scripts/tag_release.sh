#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 5 ]]; then
  cat <<'EOF'
Usage:
  scripts/tag_release.sh <ios|macos> <marketing_version> <build_number> [commit] [--push]

Examples:
  scripts/tag_release.sh ios 1.0.0 202603051104
  scripts/tag_release.sh macos 1.0.0 202603061530 5eb916d --push
EOF
  exit 1
fi

platform="$1"
marketing_version="$2"
build_number="$3"
commit="${4:-HEAD}"
push_flag="${5:-}"

if [[ "${commit}" == "--push" ]]; then
  commit="HEAD"
  push_flag="--push"
fi

if [[ "${platform}" != "ios" && "${platform}" != "macos" ]]; then
  echo "Error: platform must be 'ios' or 'macos'" >&2
  exit 1
fi

if ! [[ "${marketing_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: marketing_version must look like X.Y.Z (example: 1.0.0)" >&2
  exit 1
fi

if ! [[ "${build_number}" =~ ^[0-9]+$ ]]; then
  echo "Error: build_number must be numeric" >&2
  exit 1
fi

if ! git rev-parse --verify "${commit}^{commit}" >/dev/null 2>&1; then
  echo "Error: commit '${commit}' not found" >&2
  exit 1
fi

tag="${platform}/v${marketing_version}-b${build_number}"

if git rev-parse --verify "refs/tags/${tag}" >/dev/null 2>&1; then
  echo "Error: tag '${tag}' already exists" >&2
  exit 1
fi

platform_label="$(printf "%s" "${platform}" | tr '[:lower:]' '[:upper:]')"
message="${platform_label} ${marketing_version} (${build_number})"

git tag -a "${tag}" "${commit}" -m "${message}"
echo "Created tag: ${tag} -> ${commit}"

if [[ "${push_flag}" == "--push" ]]; then
  git push origin "${tag}"
  echo "Pushed tag: ${tag}"
else
  echo "Tag created locally. Push with: git push origin ${tag}"
fi
