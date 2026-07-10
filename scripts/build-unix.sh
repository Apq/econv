#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
platform=""
rebuild=0

usage() {
  cat <<'EOF'
Usage: ./scripts/build-unix.sh [--platform <linux-x64|macos-arm64|macos-x64>] [--rebuild]

When --platform is omitted, the script detects the current operating system and architecture.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      [[ $# -ge 2 ]] || { echo "Missing value for --platform" >&2; exit 2; }
      platform="$2"
      shift 2
      ;;
    --rebuild)
      rebuild=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64|Linux/amd64) echo "linux-x64" ;;
    Darwin/arm64|Darwin/aarch64) echo "macos-arm64" ;;
    Darwin/x86_64|Darwin/amd64) echo "macos-x64" ;;
    *) echo "Unsupported platform: $os/$arch" >&2; return 1 ;;
  esac
}

if [[ -z "$platform" ]]; then
  platform="$(detect_platform)"
fi

host_os="$(uname -s)"
case "$platform/$host_os" in
  linux-x64/Linux|macos-arm64/Darwin|macos-x64/Darwin) ;;
  *)
    echo "Platform $platform cannot be built on host OS $host_os" >&2
    exit 2
    ;;
esac

case "$platform" in
  linux-x64)
    configure_preset="linux-x64-vcpkg"
    build_preset="linux-x64-release"
    build_dir="$repo_root/build/linux-x64-vcpkg"
    ;;
  macos-arm64)
    configure_preset="macos-arm64-vcpkg"
    build_preset="macos-arm64-release"
    build_dir="$repo_root/build/macos-arm64-vcpkg"
    ;;
  macos-x64)
    configure_preset="macos-x64-vcpkg"
    build_preset="macos-x64-release"
    build_dir="$repo_root/build/macos-x64-vcpkg"
    ;;
  *)
    echo "Unsupported platform name: $platform" >&2
    exit 2
    ;;
esac

: "${VCPKG_ROOT:?VCPKG_ROOT must point to a bootstrapped vcpkg installation}"
command -v cmake >/dev/null || { echo "cmake was not found" >&2; exit 1; }
command -v ninja >/dev/null || { echo "ninja was not found" >&2; exit 1; }

cd "$repo_root"
echo "Configuring $platform ($configure_preset)..."
cmake --preset "$configure_preset"

build_args=(--build --preset "$build_preset")
if [[ $rebuild -eq 1 ]]; then
  build_args+=(--clean-first)
fi
echo "Building $platform..."
cmake "${build_args[@]}"

exe="$build_dir/econv"
[[ -x "$exe" ]] || { echo "Build output not found: $exe" >&2; exit 1; }
echo "Build output: $exe"
"$exe" --version
