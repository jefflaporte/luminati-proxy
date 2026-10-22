#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build-image-optimized.sh <amd64|arm64> [--no-chrome] [--dry-run] [--check] [--] [buildx options...]

Build and load one optimized image locally for the requested architecture.
By default, AMD64 includes Puppeteer's Chrome and ARM64 includes Debian Chromium.
SSL analysis and the HAR viewer remain included with --no-chrome. Requires Docker
with Buildx; no host npm.

  --no-chrome Omit the browser and GUI libraries; Browser action unavailable.
  --dry-run   Print the command without contacting Docker or building an image.
  --check     Run Dockerfile checks without executing build steps or loading an image.
  --help      Show this help.

Environment:
  LPM_VERSION   Published npm version (default: this checkout's package.json).
  NODE_VERSION  Node image version (default: the original Dockerfile's pinned version).
  IMAGE_TAG     Local image tag (default: luminati-proxy:<LPM_VERSION>-optimized,
                or luminati-proxy:<LPM_VERSION>-optimized-no-chrome with --no-chrome).

Examples:
  scripts/build-image-optimized.sh arm64 --dry-run
  scripts/build-image-optimized.sh amd64 --check
  scripts/build-image-optimized.sh arm64 --no-chrome
  scripts/build-image-optimized.sh arm64 -- --no-cache
  IMAGE_TAG=luminati-proxy:comparison-arm64 scripts/build-image-optimized.sh arm64

This installs the published npm package, as the upstream Dockerfile does. Local
application source changes are not included. The architecture argument is
required, and --platform must not be supplied through extra Buildx options.
EOF
}

dry_run=false
check_only=false
with_chrome=true
architecture=""
while (($#)); do
    case "$1" in
        --no-chrome) with_chrome=false; shift ;;
        --dry-run) dry_run=true; shift ;;
        --check) check_only=true; shift ;;
        --help|-h) usage; exit 0 ;;
        amd64|arm64)
            if [[ -n "$architecture" ]]; then
                printf 'Specify exactly one architecture: amd64 or arm64.\n' >&2
                exit 2
            fi
            architecture="$1"; shift ;;
        --) shift; break ;;
        *) break ;;
    esac
done

if [[ -z "$architecture" ]]; then
    printf 'Architecture is required: amd64 or arm64.\n' >&2
    usage >&2
    exit 2
fi

for option in "$@"; do
    case "$option" in
        --platform|--platform=*)
            printf 'Select the platform using the architecture argument, not --platform.\n' >&2
            exit 2 ;;
    esac
done

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lpm_version="${LPM_VERSION:-$(sed -n 's/^  "version": "\([^"]*\)".*/\1/p' "$repo_root/package.json")}"
node_version="${NODE_VERSION:-}"
if [[ -z "$node_version" ]]; then
    # Follow the original container's exact Node pin, rather than a supported range.
    node_version="$(sed -nE \
        's/^[[:space:]]*FROM[[:space:]]+node:([0-9]+\.[0-9]+\.[0-9]+)-bookworm[[:space:]]*$/\1/p' \
        "$repo_root/Dockerfile")"
fi

if [[ -z "$lpm_version" ]]; then
    printf 'Unable to read package.json version; set LPM_VERSION explicitly.\n' >&2
    exit 1
fi

if [[ -z "$node_version" || "$node_version" == *$'\n'* ]]; then
    printf 'Unable to read one pinned Node version from Dockerfile; set NODE_VERSION explicitly.\n' >&2
    exit 1
fi

image_suffix=optimized
if [[ "$with_chrome" == false ]]; then
    image_suffix+=-no-chrome
fi
image_tag="${IMAGE_TAG:-luminati-proxy:${lpm_version}-${image_suffix}}"
build_command=(docker buildx build
    --platform "linux/$architecture"
    --file "$repo_root/Dockerfile.optimized"
    --build-arg "LPM_VERSION=$lpm_version"
    --build-arg "NODE_VERSION=$node_version"
    --build-arg "WITH_CHROME=$with_chrome")

if [[ "$check_only" == true ]]; then
    build_command+=(--check)
else
    build_command+=(--load --tag "$image_tag")
fi
build_command+=("$@" "$repo_root")

printf 'Command:'
printf ' %q' "${build_command[@]}"
printf '\n'

if [[ "$dry_run" == true ]]; then
    exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
    printf 'Docker is required. Install Docker with the Buildx plugin first.\n' >&2
    exit 1
fi

exec "${build_command[@]}"
