#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
platform=""
skip_rebuild=0
keep_staging=0
output_dir="$repo_root/dist"

usage() {
  cat <<'EOF'
Usage: ./scripts/release-unix.sh [options]

Options:
  --platform <linux-x64|macos-arm64|macos-x64>
  --skip-rebuild
  --keep-staging
  --output-directory <path>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      [[ $# -ge 2 ]] || { echo "Missing value for --platform" >&2; exit 2; }
      platform="$2"
      shift 2
      ;;
    --skip-rebuild) skip_rebuild=1; shift ;;
    --keep-staging) keep_staging=1; shift ;;
    --output-directory)
      [[ $# -ge 2 ]] || { echo "Missing value for --output-directory" >&2; exit 2; }
      output_dir="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
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
    echo "Platform $platform cannot be released on host OS $host_os" >&2
    exit 2
    ;;
esac

case "$platform" in
  linux-x64)
    build_dir="$repo_root/build/linux-x64-vcpkg"
    test_preset="linux-x64-tests"
    triplet="x64-linux"
    ;;
  macos-arm64)
    build_dir="$repo_root/build/macos-arm64-vcpkg"
    test_preset="macos-arm64-tests"
    triplet="arm64-osx"
    ;;
  macos-x64)
    build_dir="$repo_root/build/macos-x64-vcpkg"
    test_preset="macos-x64-tests"
    triplet="x64-osx"
    ;;
  *) echo "Unsupported platform name: $platform" >&2; exit 2 ;;
esac

: "${VCPKG_ROOT:?VCPKG_ROOT must point to a bootstrapped vcpkg installation}"
for command_name in cmake ninja tar; do
  command -v "$command_name" >/dev/null || { echo "$command_name was not found" >&2; exit 1; }
done

build_args=(--platform "$platform")
if [[ $skip_rebuild -eq 0 ]]; then
  build_args+=(--rebuild)
fi
"$script_dir/build-unix.sh" "${build_args[@]}"

cd "$repo_root"
ctest --preset "$test_preset"

exe="$build_dir/econv"
version_output="$("$exe" --version)"
[[ "$version_output" =~ ^econv[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]] || {
  echo "Could not determine version: $version_output" >&2
  exit 1
}
version="${BASH_REMATCH[1]}"

cmake_version="$(sed -nE 's/^[[:space:]]*project\(econv VERSION ([^[:space:]]+) LANGUAGES CXX\).*/\1/p' CMakeLists.txt)"
vcpkg_version="$(sed -nE 's/^[[:space:]]*"version-string"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' vcpkg.json)"
if [[ "$version" != "$cmake_version" || "$version" != "$vcpkg_version" ]]; then
  echo "Version mismatch: exe=$version, CMake=$cmake_version, vcpkg=$vcpkg_version" >&2
  exit 1
fi

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
package_name="econv-$version-$platform"
staging_dir="$output_dir/$package_name"
archive_path="$output_dir/$package_name.tar.gz"
checksum_path="$archive_path.sha256"

rm -rf "$staging_dir"
rm -f "$archive_path" "$checksum_path"
mkdir -p "$staging_dir"

cp "$exe" "$staging_dir/econv"
chmod +x "$staging_dir/econv"
cp README.md "$staging_dir/README.md"
cp LICENSE "$staging_dir/LICENSE.txt"
cp THIRD-PARTY-NOTICES.md "$staging_dir/THIRD-PARTY-NOTICES.md"

installed_root="$build_dir/vcpkg_installed/$triplet"
uchardet_license="$installed_root/share/uchardet/copyright"
libiconv_license="$installed_root/share/libiconv/copyright"
[[ -f "$uchardet_license" ]] || { echo "Missing license: $uchardet_license" >&2; exit 1; }
[[ -f "$libiconv_license" ]] || { echo "Missing license: $libiconv_license" >&2; exit 1; }
{
  printf '%s\n\n' 'THIRD-PARTY LICENSES' '===================='
  printf '%s\n%s\n%s\n' 'uchardet 0.0.8' 'Source: https://gitlab.freedesktop.org/uchardet/uchardet' '----------------'
  cat "$uchardet_license"
  printf '\n\n%s\n%s\n%s\n' 'GNU libiconv 1.19' 'Source: https://git.savannah.gnu.org/git/libiconv.git' '-----------------'
  cat "$libiconv_license"
} > "$staging_dir/THIRD-PARTY-LICENSES.txt"

cat > "$staging_dir/REQUIREMENTS.txt" <<EOF
econv $version - $platform

This package contains a native executable for $platform.
The uchardet and GNU libiconv libraries are linked by the platform build.
EOF

"$staging_dir/econv" --version
tar -C "$output_dir" -czf "$archive_path" "$package_name"

if command -v sha256sum >/dev/null; then
  archive_hash="$(sha256sum "$archive_path" | awk '{print $1}')"
else
  archive_hash="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
fi
printf '%s  %s\n' "$archive_hash" "$(basename "$archive_path")" > "$checksum_path"

archive_entries="$(tar -tzf "$archive_path")"
for required in econv LICENSE.txt THIRD-PARTY-NOTICES.md THIRD-PARTY-LICENSES.txt REQUIREMENTS.txt; do
  grep -Fxq "$package_name/$required" <<< "$archive_entries" || {
    echo "Archive validation failed; missing: $required" >&2
    exit 1
  }
done

if [[ $keep_staging -eq 0 ]]; then
  rm -rf "$staging_dir"
fi

echo "Release package created: $archive_path"
echo "SHA-256: $archive_hash"
echo "Checksum file: $checksum_path"
