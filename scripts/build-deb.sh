#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <ghostty-version> <output-directory>" >&2
}

if [[ ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

version="$1"
output_dir="$2"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid Ghostty version: $version" >&2
  exit 2
fi

arch="$(dpkg --print-architecture)"
case "$arch" in
  amd64) zig_arch="x86_64" ;;
  arm64) zig_arch="aarch64" ;;
  *)
    echo "unsupported Debian architecture: $arch" >&2
    exit 2
    ;;
esac

for command_name in curl jq minisign tar sha256sum dpkg-deb dpkg-shlibdeps file; do
  command -v "$command_name" >/dev/null || {
    echo "required command is missing: $command_name" >&2
    exit 1
  }
done

pkg_config_modules=(gtk4 libadwaita-1 gtk4-layer-shell-0)
for module in "${pkg_config_modules[@]}"; do
  pkg-config --exists "$module" || {
    echo "required pkg-config module is missing: $module" >&2
    exit 1
  }
done

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

source_url="https://release.files.ghostty.org/${version}/ghostty-${version}.tar.gz"
signature_url="${source_url}.minisig"
source_archive="$work_dir/ghostty-${version}.tar.gz"
signature_file="${source_archive}.minisig"
public_key="RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV"

curl --http1.1 --fail --location --retry 3 --output "$source_archive" "$source_url"
curl --http1.1 --fail --location --retry 3 --output "$signature_file" "$signature_url"
minisign -Vm "$source_archive" -x "$signature_file" -P "$public_key"
source_sha256="$(sha256sum "$source_archive" | awk '{print $1}')"

tar -xzf "$source_archive" -C "$work_dir"
source_dir="$(find "$work_dir" -mindepth 1 -maxdepth 1 -type d -name 'ghostty-*' -print -quit)"
[[ -n "$source_dir" && -f "$source_dir/build.zig.zon" ]] || {
  echo "could not locate the extracted Ghostty source" >&2
  exit 1
}

zig_version="$(
  sed -n 's/.*minimum_zig_version = "\([^"]*\)".*/\1/p' \
    "$source_dir/build.zig.zon" | head -n 1
)"
[[ -n "$zig_version" ]] || {
  echo "could not determine the required Zig version" >&2
  exit 1
}

zig_platform="${zig_arch}-linux"
zig_index="$work_dir/zig-index.json"
curl --fail --location --retry 3 --output "$zig_index" \
  https://ziglang.org/download/index.json
zig_url="$(jq -er --arg version "$zig_version" --arg platform "$zig_platform" \
  '.[$version][$platform].tarball' "$zig_index")"
zig_sha256="$(jq -er --arg version "$zig_version" --arg platform "$zig_platform" \
  '.[$version][$platform].shasum' "$zig_index")"
zig_archive="$work_dir/zig.tar.xz"
curl --fail --location --retry 3 --output "$zig_archive" "$zig_url"
printf '%s  %s\n' "$zig_sha256" "$zig_archive" | sha256sum -c -

zig_root="$work_dir/zig"
mkdir -p "$zig_root"
tar -xJf "$zig_archive" --strip-components=1 -C "$zig_root"
zig="$zig_root/zig"
export PATH="$zig_root:$PATH"

local_cache="$work_dir/local-cache"
cd "$source_dir"

staging="$work_dir/staging"
ZIG_GLOBAL_CACHE_DIR="$work_dir/global-cache" \
ZIG_LOCAL_CACHE_DIR="$local_cache" \
DESTDIR="$staging" \
  "$zig" build \
    --prefix /usr \
    -Doptimize=ReleaseFast \
    -Dcpu=baseline \
    -Demit-docs \
    -Dstrip \
    -Dversion-string="$version" \
    -fsys=fontconfig \
    -fsys=gtk4-layer-shell \
    -Dinstalled-exe-path=/usr/bin/ghostty

# Package the terminal application; libghostty-vt development files are separate products.
rm -rf "$staging/usr/include" "$staging/usr/lib" "$staging/usr/share/pkgconfig"
# Debian's ncurses-term already owns this entry; xterm-ghostty is ours.
rm "$staging/usr/share/terminfo/g/ghostty"
rmdir "$staging/usr/share/terminfo/g"
mv "$staging/usr/share/zsh/site-functions" "$staging/usr/share/zsh/vendor-completions"

install -D -m 0644 "$source_dir/LICENSE" \
  "$staging/usr/share/doc/ghostty/copyright"
cat > "$work_dir/changelog.Debian" <<EOF
ghostty (${version}-1) stable; urgency=medium

  * Build Ghostty ${version} from the upstream signed source tarball.

 -- mora1n <55047233+mora1n@users.noreply.github.com>  $(date -R)
EOF
gzip -n -c "$work_dir/changelog.Debian" \
  > "$staging/usr/share/doc/ghostty/changelog.Debian.gz"

readarray -d '' elf_files < <(
  find "$staging" -type f \( -perm /111 -o -name '*.so*' \) -print0
)
(( ${#elf_files[@]} > 0 )) || {
  echo "no ELF files found in the staged installation" >&2
  exit 1
}

mkdir -p debian
printf 'Source: ghostty\n\nPackage: ghostty\nArchitecture: any\n' > debian/control
shlib_output="$(dpkg-shlibdeps -O "${elf_files[@]}")"
depends="$(printf '%s\n' "$shlib_output" |
  sed -n 's/^shlibs:Depends=//p' | tail -n 1)"
[[ -n "$depends" ]] || {
  echo "dpkg-shlibdeps did not produce runtime dependencies" >&2
  exit 1
}

installed_size="$(du -ks "$staging" | awk '{print $1}')"
package_version="${version}-1"
mkdir -p "$staging/DEBIAN"
cat > "$staging/DEBIAN/control" <<EOF
Package: ghostty
Version: ${package_version}
Section: utils
Priority: optional
Architecture: ${arch}
Maintainer: mora1n <55047233+mora1n@users.noreply.github.com>
Homepage: https://ghostty.org/
Installed-Size: ${installed_size}
Depends: ${depends}
Provides: x-terminal-emulator
Description: Fast, feature-rich, and cross-platform terminal emulator
 Ghostty is a terminal emulator with a native GTK interface and GPU
 acceleration. This is an unofficial Debian package.
EOF

package_path="$output_dir/ghostty_${package_version}_${arch}.deb"
dpkg-deb --build --root-owner-group "$staging" "$package_path"
dpkg-deb --info "$package_path" >/dev/null
dpkg-deb --contents "$package_path" >/dev/null

jq -n \
  --arg version "$version" \
  --arg architecture "$arch" \
  --arg source_url "$source_url" \
  --arg source_sha256 "$source_sha256" \
  --arg zig_version "$zig_version" \
  '{
    ghostty_version: $version,
    debian_version: ($version + "-1"),
    architecture: $architecture,
    source_url: $source_url,
    source_sha256: $source_sha256,
    zig_version: $zig_version,
    base_distribution: "debian:13"
  }' > "$output_dir/build-metadata.json"

echo "built $package_path"
