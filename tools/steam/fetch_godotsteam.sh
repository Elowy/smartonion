#!/usr/bin/env bash
# Fetches the GodotSteam GDExtension plug-in into addons/godotsteam/ (gitignored: it contains Valve's
# steam_api64.dll / libsteam_api.so, which must not be published in a source repository).
#
# Pinned to GodotSteam v4.23.2-gde (Godot 4.4+, Steamworks SDK 1.65, MIT). The zip is downloaded from the
# official Codeberg release, its sha256 is checked BEFORE anything is unpacked, and only the files the game
# needs for Windows 64-bit and Linux 64-bit are extracted:
#   addons/godotsteam/godotsteam.gdextension
#   addons/godotsteam/license.md
#   addons/godotsteam/win64/*     (libgodotsteam.windows.*.dll + steam_api64.dll)
#   addons/godotsteam/linux64/*   (libgodotsteam.linux.*.so + libsteam_api.so)
# The plug-in is optional: the game runs without it (no Steam features). Idempotent: running it again
# when the pinned version is installed does nothing (use --force to re-extract).
#
# Usage: tools/steam/fetch_godotsteam.sh [--dest PROJECT_DIR] [--zip FILE] [--force] [--help]

set -euo pipefail

VERSION="4.23.2"
TAG="v${VERSION}-gde"
ASSET="godotsteam-${VERSION}-gdextension-plugin-4.4.zip"
URL="https://codeberg.org/godotsteam/godotsteam/releases/download/${TAG}/${ASSET}"
SHA256="4f1db786924ad0e1de9b161d87276b1a0b7504332ceec2e9c6694be202c33da4"

# Entries unpacked from the zip (unzip patterns; everything else is ignored).
WANTED=(
	"addons/godotsteam/godotsteam.gdextension"
	"addons/godotsteam/license.md"
	"addons/godotsteam/win64/*"
	"addons/godotsteam/linux64/*"
)
# Files that must exist afterwards.
REQUIRED=(
	"godotsteam.gdextension"
	"win64/steam_api64.dll"
	"win64/libgodotsteam.windows.template_debug.x86_64.dll"
	"win64/libgodotsteam.windows.template_release.x86_64.dll"
	"linux64/libsteam_api.so"
	"linux64/libgodotsteam.linux.template_debug.x86_64.so"
	"linux64/libgodotsteam.linux.template_release.x86_64.so"
)
STAMP=".fetched"

usage() {
	cat <<EOF
Fetches GodotSteam ${TAG} (Windows 64-bit + Linux 64-bit only) into <PROJECT_DIR>/addons/godotsteam/.

Usage: $(basename "$0") [options]
  --dest DIR   project root to install into (default: the repository root of this script).
               The files land in DIR/addons/godotsteam/.
  --zip FILE   use this already downloaded ${ASSET} instead of downloading it
               (its sha256 is still verified).
  --force      extract again even if the pinned version is already installed.
  -h, --help   this text.

Source:  ${URL}
sha256:  ${SHA256}
EOF
}

die() {
	echo "fetch_godotsteam: $*" >&2
	exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="$(cd "${script_dir}/../.." && pwd)"
zip_file=""
force=0

while [ $# -gt 0 ]; do
	case "$1" in
		--dest)
			[ $# -ge 2 ] || die "--dest needs a directory"
			dest="$2"
			shift 2
			;;
		--dest=*)
			dest="${1#--dest=}"
			shift
			;;
		--zip)
			[ $# -ge 2 ] || die "--zip needs a file"
			zip_file="$2"
			shift 2
			;;
		--zip=*)
			zip_file="${1#--zip=}"
			shift
			;;
		--force)
			force=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			usage >&2
			die "unknown option: $1"
			;;
	esac
done

[ -d "${dest}" ] || die "--dest is not a directory: ${dest}"
dest="$(cd "${dest}" && pwd)"
addon_dir="${dest}/addons/godotsteam"
stamp_file="${addon_dir}/${STAMP}"

installed() {
	[ -f "${stamp_file}" ] && [ "$(cat "${stamp_file}")" = "${TAG} ${SHA256}" ] || return 1
	local f
	for f in "${REQUIRED[@]}"; do
		[ -f "${addon_dir}/${f}" ] || return 1
	done
	return 0
}

if [ "${force}" -eq 0 ] && installed; then
	echo "fetch_godotsteam: ${TAG} is already installed in ${addon_dir}"
	exit 0
fi

sha256_of() {
	if command -v sha256sum > /dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum > /dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		die "need sha256sum or shasum to verify the download"
	fi
}

work="$(mktemp -d "${TMPDIR:-/tmp}/godotsteam.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

if [ -z "${zip_file}" ]; then
	zip_file="${work}/${ASSET}"
	echo "fetch_godotsteam: downloading ${URL}"
	if command -v curl > /dev/null 2>&1; then
		curl --fail --location --silent --show-error --retry 3 --connect-timeout 30 --output "${zip_file}" "${URL}" \
			|| die "download failed (curl). If the network blocks Codeberg, download ${ASSET} by hand and pass --zip"
	elif command -v wget > /dev/null 2>&1; then
		wget --quiet --tries=3 --timeout=30 --output-document="${zip_file}" "${URL}" \
			|| die "download failed (wget). If the network blocks Codeberg, download ${ASSET} by hand and pass --zip"
	else
		die "need curl or wget to download ${ASSET}"
	fi
else
	[ -f "${zip_file}" ] || die "--zip file not found: ${zip_file}"
fi

actual="$(sha256_of "${zip_file}")"
if [ "${actual}" != "${SHA256}" ]; then
	die "sha256 mismatch for ${ASSET}: expected ${SHA256}, got ${actual} - nothing was extracted"
fi
echo "fetch_godotsteam: sha256 ok"

stage="${work}/stage"
mkdir -p "${stage}"
if command -v unzip > /dev/null 2>&1; then
	unzip -q -o "${zip_file}" "${WANTED[@]}" -d "${stage}" || die "unzip failed"
elif command -v python3 > /dev/null 2>&1; then
	# Fallback without unzip: the same whitelist, nothing else is read out of the archive.
	python3 -I - "${zip_file}" "${stage}" "${WANTED[@]}" <<'PY' || die "python3 extraction failed"
import fnmatch
import os
import sys
import zipfile

zip_path, stage, patterns = sys.argv[1], sys.argv[2], sys.argv[3:]
with zipfile.ZipFile(zip_path) as zf:
    for info in zf.infolist():
        name = info.filename
        if name.endswith("/") or ".." in name.split("/"):
            continue
        if any(fnmatch.fnmatchcase(name, pattern) for pattern in patterns):
            target = os.path.join(stage, name)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with zf.open(info) as src, open(target, "wb") as dst:
                dst.write(src.read())
PY
else
	die "need unzip or python3 to unpack ${ASSET}"
fi

for f in "${REQUIRED[@]}"; do
	[ -f "${stage}/addons/godotsteam/${f}" ] || die "the archive has no ${f} - unexpected layout, nothing was installed"
done

# Replace the previous install of the plug-in atomically-ish: stage first, then swap.
mkdir -p "${dest}/addons"
rm -rf "${addon_dir}"
mv "${stage}/addons/godotsteam" "${addon_dir}"
printf '%s' "${TAG} ${SHA256}" > "${stamp_file}"

echo "fetch_godotsteam: installed ${TAG} (Windows 64-bit + Linux 64-bit) in ${addon_dir}"
echo "fetch_godotsteam: run 'godot --headless --path ${dest} --import' once so Godot registers the extension"
