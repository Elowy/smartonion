#!/usr/bin/env bash
# Installs the Godot export templates that tools/build/export.sh needs.
#
# The templates are the engine binaries a release build is made from. They must match the editor exactly
# (4.7.2.stable): the official Godot_v4.7.2-stable_export_templates.tpz (about 1.3 GB) is downloaded from the
# godot-builds GitHub release, its sha512 is checked BEFORE anything is unpacked, and only what the game ships
# on (Windows x86_64 + Linux x86_64, release and debug) is installed into the user's templates folder:
#   Linux    ${XDG_DATA_HOME:-~/.local/share}/godot/export_templates/4.7.2.stable/
#   macOS    ~/Library/Application Support/Godot/export_templates/4.7.2.stable/
#   Windows  %APPDATA%\Godot\export_templates\4.7.2.stable\   (Git Bash / MSYS2)
# Idempotent: when the version is already installed (checked by a stamp file and the template files) nothing
# is downloaded. The download lives in a temporary folder and is deleted again, also on failure.
#
# Usage: tools/build/install_templates.sh [--all] [--force] [--tpz FILE] [--dir DIR] [--help]

set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_CHANNEL="stable"
VERSION_DIR="${GODOT_VERSION}.${GODOT_CHANNEL}"
ASSET="Godot_v${GODOT_VERSION}-${GODOT_CHANNEL}_export_templates.tpz"
URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_CHANNEL}/${ASSET}"
SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
STAMP=".smartonion-templates"

# Unzip patterns of the default install (everything else in the archive is ignored). The glob also covers the
# *_console.exe variants (Windows console wrapper) but not the 32-bit / arm / web / mobile templates.
DEFAULT_PATTERNS=(
	"templates/version.txt"
	"templates/windows_*_x86_64*.exe"
	"templates/linux_*.x86_64"
)
# Templates export.sh needs; they must exist (and not be empty) after the install.
REQUIRED=(
	"version.txt"
	"windows_release_x86_64.exe"
	"windows_debug_x86_64.exe"
	"linux_release.x86_64"
	"linux_debug.x86_64"
)
# Free space (MB) needed in the temporary folder for the download, and in the templates folder for the result.
NEED_TMP_MB=1500
NEED_DEST_MB_DEFAULT=700
NEED_DEST_MB_ALL=3500

usage() {
	cat <<EOF
Installs the Godot ${VERSION_DIR} export templates (Windows x86_64 + Linux x86_64) for tools/build/export.sh.

Usage: $(basename "$0") [options]
  --all        install every template of the archive (web, mobile, macOS, 32-bit ...), about 3 GB on disk.
  --force      download and unpack again even if the templates are installed.
  --tpz FILE   use this already downloaded ${ASSET} instead of downloading it
               (its sha512 is still verified; the file is not deleted).
  --dir DIR    templates folder to install into (the version folder ${VERSION_DIR} is created inside).
               Default: the Godot editor's own folder (see above); the environment variable
               GODOT_EXPORT_TEMPLATES_DIR does the same.
  -h, --help   this text.

Environment: TMPDIR - where the 1.3 GB download is kept while it is verified (default /tmp).

Source:  ${URL}
sha512:  ${SHA512}
EOF
}

die() {
	echo "install_templates: $*" >&2
	exit 1
}

log() {
	echo "install_templates: $*"
}

all=0
force=0
tpz_file=""
dest_root="${GODOT_EXPORT_TEMPLATES_DIR:-}"

while [ $# -gt 0 ]; do
	case "$1" in
		--all)
			all=1
			shift
			;;
		--force)
			force=1
			shift
			;;
		--tpz)
			[ $# -ge 2 ] || die "--tpz needs a file"
			tpz_file="$2"
			shift 2
			;;
		--tpz=*)
			tpz_file="${1#--tpz=}"
			shift
			;;
		--dir)
			[ $# -ge 2 ] || die "--dir needs a directory"
			dest_root="$2"
			shift 2
			;;
		--dir=*)
			dest_root="${1#--dir=}"
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

if [ -z "${dest_root}" ]; then
	case "$(uname -s)" in
		Linux*) dest_root="${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}/godot/export_templates" ;;
		Darwin*) dest_root="${HOME:?HOME is not set}/Library/Application Support/Godot/export_templates" ;;
		MINGW* | MSYS* | CYGWIN*)
			[ -n "${APPDATA:-}" ] || die "APPDATA is not set - pass --dir"
			dest_root="${APPDATA}/Godot/export_templates"
			;;
		*) die "unknown platform $(uname -s) - pass --dir" ;;
	esac
fi
dest="${dest_root}/${VERSION_DIR}"
stamp_file="${dest}/${STAMP}"
want_mode="default"
[ "${all}" -eq 1 ] && want_mode="all"

installed() {
	[ -f "${stamp_file}" ] || return 1
	local stamp mode
	stamp="$(cat "${stamp_file}")"
	mode="${stamp##* }"
	[ "${stamp%% *}" = "${SHA512}" ] || return 1
	# An "all" install satisfies a default request, not the other way round.
	if [ "${want_mode}" = "all" ] && [ "${mode}" != "all" ]; then
		return 1
	fi
	local f
	for f in "${REQUIRED[@]}"; do
		[ -s "${dest}/${f}" ] || return 1
	done
	[ "$(tr -d '\r\n' < "${dest}/version.txt")" = "${VERSION_DIR}" ] || return 1
	return 0
}

if [ "${force}" -eq 0 ] && installed; then
	log "the ${VERSION_DIR} templates are already installed in ${dest}"
	exit 0
fi

sha512_of() {
	if command -v sha512sum > /dev/null 2>&1; then
		sha512sum "$1" | cut -d' ' -f1
	elif command -v shasum > /dev/null 2>&1; then
		shasum -a 512 "$1" | cut -d' ' -f1
	else
		die "need sha512sum or shasum to verify the download"
	fi
}

free_mb() {
	# Free megabytes on the filesystem holding $1 (walks up to the first existing parent).
	local p="$1"
	while [ ! -d "${p}" ] && [ "${p}" != "/" ] && [ "${p}" != "." ]; do
		p="$(dirname "${p}")"
	done
	df -Pk "${p}" | awk 'NR==2 { printf "%d", $4 / 1024 }'
}

need_dest_mb="${NEED_DEST_MB_DEFAULT}"
[ "${all}" -eq 1 ] && need_dest_mb="${NEED_DEST_MB_ALL}"
have_dest_mb="$(free_mb "${dest_root}")"
[ "${have_dest_mb}" -ge "${need_dest_mb}" ] \
	|| die "not enough disk space for the templates in ${dest_root}: ${have_dest_mb} MB free, ${need_dest_mb} MB needed"

work="$(mktemp -d "${TMPDIR:-/tmp}/godot-templates.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

if [ -z "${tpz_file}" ]; then
	have_tmp_mb="$(free_mb "${work}")"
	[ "${have_tmp_mb}" -ge "${NEED_TMP_MB}" ] \
		|| die "not enough disk space for the download in ${work}: ${have_tmp_mb} MB free, ${NEED_TMP_MB} MB needed (set TMPDIR to a bigger disk, or pass --tpz)"
	tpz_file="${work}/${ASSET}"
	log "downloading ${URL} (about 1.3 GB)"
	if command -v curl > /dev/null 2>&1; then
		progress="--silent"
		[ -t 2 ] && progress="--progress-bar"
		curl --fail --location "${progress}" --show-error --retry 3 --connect-timeout 30 --output "${tpz_file}" "${URL}" \
			|| die "download failed (curl). If the network blocks GitHub releases, download ${ASSET} by hand and pass --tpz"
	elif command -v wget > /dev/null 2>&1; then
		wget --quiet --tries=3 --timeout=60 --output-document="${tpz_file}" "${URL}" \
			|| die "download failed (wget). If the network blocks GitHub releases, download ${ASSET} by hand and pass --tpz"
	else
		die "need curl or wget to download ${ASSET}"
	fi
else
	[ -f "${tpz_file}" ] || die "--tpz file not found: ${tpz_file}"
fi

log "checking sha512 ..."
actual="$(sha512_of "${tpz_file}")"
if [ "${actual}" != "${SHA512}" ]; then
	die "sha512 mismatch for ${ASSET}: expected ${SHA512}, got ${actual} - nothing was installed"
fi
log "sha512 ok"

# Unpack into a staging folder next to the destination (same filesystem), then move the files in place.
mkdir -p "${dest_root}"
stage="$(mktemp -d "${dest_root}/.staging.XXXXXX")"
trap 'rm -rf "${work}" "${stage}"' EXIT

if command -v unzip > /dev/null 2>&1; then
	if [ "${all}" -eq 1 ]; then
		unzip -q -o "${tpz_file}" "templates/*" -d "${stage}" || die "unzip failed"
	else
		unzip -q -o "${tpz_file}" "${DEFAULT_PATTERNS[@]}" -d "${stage}" || die "unzip failed (is the disk full?)"
	fi
elif command -v python3 > /dev/null 2>&1; then
	# Fallback without unzip: the same whitelist, nothing else is read out of the archive.
	patterns=("templates/*")
	[ "${all}" -eq 1 ] || patterns=("${DEFAULT_PATTERNS[@]}")
	python3 -I - "${tpz_file}" "${stage}" "${patterns[@]}" <<'PY' || die "python3 extraction failed"
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
                while True:
                    chunk = src.read(1 << 20)
                    if not chunk:
                        break
                    dst.write(chunk)
PY
else
	die "need unzip or python3 to unpack ${ASSET}"
fi

for f in "${REQUIRED[@]}"; do
	[ -s "${stage}/templates/${f}" ] || die "the archive has no templates/${f} - unexpected layout, nothing was installed"
done
[ "$(tr -d '\r\n' < "${stage}/templates/version.txt")" = "${VERSION_DIR}" ] \
	|| die "the archive's version.txt says '$(tr -d '\r\n' < "${stage}/templates/version.txt")', expected ${VERSION_DIR}"

# The download is not needed any more: free the space before the files are moved (only a temporary copy).
if [ "${tpz_file}" = "${work}/${ASSET}" ]; then
	rm -f "${tpz_file}"
fi

mkdir -p "${dest}"
(
	shopt -s dotglob nullglob
	for f in "${stage}/templates/"*; do
		mv -f "${f}" "${dest}/"
	done
)
chmod +x "${dest}"/linux_*.x86_64 2> /dev/null || true
printf '%s %s' "${SHA512}" "${want_mode}" > "${stamp_file}"

log "installed the ${VERSION_DIR} templates (${want_mode}) in ${dest}"
