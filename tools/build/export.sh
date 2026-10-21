#!/usr/bin/env bash
# Builds the release executables of SmartOnion from the committed export presets (export_presets.cfg).
#
#   build/steam/content/windows/SmartOnion.exe        one file (PCK embedded) + build_info.txt
#   build/steam/content/linux/SmartOnion.x86_64       one file (PCK embedded) + build_info.txt
#
# With --steam the GodotSteam plug-in is fetched (tools/steam/fetch_godotsteam.sh) and its libraries
# (steam_api64.dll / libsteam_api.so + libgodotsteam.*) are exported next to the executables. Without it the
# plug-in is hidden for the export (a copy in addons/godotsteam is put back afterwards), so a plain build never
# contains Valve's libraries. The content folders are exactly what tools/steam/upload.sh uploads (SteamPipe
# ContentRoot) and are emptied before each export of their platform. Each holds a build_info.txt (version, app_id, steam
# yes/no, git hash ...) that tools/steam/upload.sh checks against project.godot, so a stale or mixed build is not uploaded.
#
# What is checked: the templates are installed (tools/build/install_templates.sh), the editor is 4.7.2, the
# version of the Windows exe metadata matches application/config/version, every export is non-empty and
# error-free, the packed files (CREDITS.md in, tests/tools/docs out, Steam plug-in in or out - see
# tools/build/verify_pack.gd) and, on the Linux binary, a headless smoke run (4 bots, 1 wave, seed 5: exit 0 and
# "errors":0). Without --steam the archives for non-Steam distribution are written to build/dist/.
#
# Usage: tools/build/export.sh [--steam] [--platform windows|linux|all] [--skip-smoke] [--no-dist]
#                              [--godot BIN] [--help]

set -euo pipefail

EXPECTED_GODOT="4.7.2.stable"
PRODUCT="SmartOnion"
PRESET_WINDOWS="Windows Desktop"
PRESET_LINUX="Linux"
SMOKE_TIMEOUT_S=900

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${script_dir}/../.." && pwd)"
build_dir="${root}/build"
content_root="${build_dir}/steam/content"
dist_dir="${build_dir}/dist"
log_dir="${build_dir}/logs"
stash_dir="${build_dir}/.stash"
addon_dir="${root}/addons/godotsteam"

usage() {
	cat <<EOF
Exports the release builds of ${PRODUCT} (Windows x86_64 + Linux x86_64) into build/steam/content/<platform>/.

Usage: $(basename "$0") [options]
  --steam               fetch GodotSteam and export its Steam libraries next to the executables (the build for
                        tools/steam/upload.sh). Without it the plug-in is left out and archives for non-Steam
                        distribution are made in build/dist/.
  --platform NAME       windows, linux or all (default all).
  --skip-smoke          do not run the headless smoke test on the exported Linux binary.
  --no-dist             do not write the build/dist archives (they are not made for --steam builds anyway: Valve's
                        libraries must only go to Steam).
  --godot BIN           the Godot ${EXPECTED_GODOT} editor binary (default: \$GODOT, else godot from the PATH).
  -h, --help            this text.

Needs: Godot ${EXPECTED_GODOT} with its export templates (tools/build/install_templates.sh), git (optional,
for build_info.txt), zip and tar (build/dist only), curl + unzip (--steam, to fetch GodotSteam).
Set the version in project.godot (application/config/version) and in export_presets.cfg (Windows
file_version / product_version = <version>.0); the company name and copyright there are placeholders.
EOF
}

die() {
	echo "export: ERROR: $*" >&2
	exit 1
}

log() {
	echo "export: $*"
}

warn() {
	echo "export: WARNING: $*" >&2
}

steam=0
platform="all"
skip_smoke=0
make_dist=1
godot_bin="${GODOT:-godot}"

while [ $# -gt 0 ]; do
	case "$1" in
		--steam)
			steam=1
			shift
			;;
		--platform)
			[ $# -ge 2 ] || die "--platform needs windows, linux or all"
			platform="$2"
			shift 2
			;;
		--platform=*)
			platform="${1#--platform=}"
			shift
			;;
		--skip-smoke)
			skip_smoke=1
			shift
			;;
		--no-dist)
			make_dist=0
			shift
			;;
		--godot)
			[ $# -ge 2 ] || die "--godot needs a path"
			godot_bin="$2"
			shift 2
			;;
		--godot=*)
			godot_bin="${1#--godot=}"
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

platforms=()
case "${platform}" in
	windows) platforms=(windows) ;;
	linux) platforms=(linux) ;;
	all) platforms=(windows linux) ;;
	*) die "--platform must be windows, linux or all (got '${platform}')" ;;
esac
want_platform() {
	local p
	for p in "${platforms[@]}"; do
		[ "$p" = "$1" ] && return 0
	done
	return 1
}

# --- Project facts -----------------------------------------------------------------------------------------
[ -f "${root}/project.godot" ] || die "no project.godot in ${root}"
[ -f "${root}/export_presets.cfg" ] || die "export_presets.cfg is missing in ${root} (it is committed - restore it with git)"

version="$(sed -n 's/^config\/version="\([^"]*\)".*/\1/p' "${root}/project.godot" | head -n 1)"
[ -n "${version}" ] || die "project.godot has no application/config/version (config/version=\"0.9.0\" in [application])"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "application/config/version must look like 1.2.3, got '${version}'"
# The Steamworks app id compiled into the build (smartonion/steam/app_id); the game falls back to Valve's test app 480 without it.
app_id="$(sed -n 's/^steam\/app_id=\([0-9]*\).*/\1/p' "${root}/project.godot" | head -n 1)"
app_id="${app_id:-480}"

preset_value() {
	# preset_value KEY: the value of KEY (quotes stripped) in the Windows preset options of export_presets.cfg.
	sed -n "s|^$1=\"\\(.*\\)\"\$|\\1|p" "${root}/export_presets.cfg" | head -n 1
}
if want_platform windows; then
	for key in application/file_version application/product_version; do
		have="$(preset_value "${key}")"
		[ "${have}" = "${version}.0" ] \
			|| die "export_presets.cfg: ${key} is '${have}' but application/config/version is ${version} - set it to ${version}.0"
	done
	if grep -q '^application/\(company_name\|copyright\)=".*TODO' "${root}/export_presets.cfg"; then
		warn "export_presets.cfg: application/company_name / application/copyright are still the TODO placeholders (shown in the exe's Properties dialog)"
	fi
fi

# --- Godot editor and templates ----------------------------------------------------------------------------
command -v "${godot_bin}" > /dev/null 2>&1 || die "Godot not found ('${godot_bin}'): install ${EXPECTED_GODOT}, or pass --godot BIN / set GODOT"
godot_version="$("${godot_bin}" --version 2> /dev/null | head -n 1 | tr -d '\r')"
case "${godot_version}" in
	"${EXPECTED_GODOT}".*) ;;
	*) die "the editor is Godot '${godot_version}' but the export templates are ${EXPECTED_GODOT}: use the ${EXPECTED_GODOT} editor (--godot BIN)" ;;
esac

templates_root="${GODOT_EXPORT_TEMPLATES_DIR:-}"
if [ -z "${templates_root}" ]; then
	case "$(uname -s)" in
		Linux*) templates_root="${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}/godot/export_templates" ;;
		Darwin*) templates_root="${HOME:?HOME is not set}/Library/Application Support/Godot/export_templates" ;;
		MINGW* | MSYS* | CYGWIN*) templates_root="${APPDATA:-}/Godot/export_templates" ;;
		*) templates_root="" ;;
	esac
fi
templates_dir="${templates_root}/${EXPECTED_GODOT}"
required_templates=()
want_platform windows && required_templates+=(windows_release_x86_64.exe)
want_platform linux && required_templates+=(linux_release.x86_64)
for t in "${required_templates[@]}"; do
	[ -s "${templates_dir}/${t}" ] \
		|| die "export template ${t} is not installed in ${templates_dir} - run tools/build/install_templates.sh"
done

# --- The GodotSteam plug-in: in for --steam, out otherwise -------------------------------------------------
reimport=0
stashed=0
restore_addon() {
	if [ "${stashed}" -eq 1 ] && [ -d "${stash_dir}/godotsteam" ] && [ ! -e "${addon_dir}" ]; then
		mkdir -p "${root}/addons"
		mv "${stash_dir}/godotsteam" "${addon_dir}"
		stashed=0
		reimport=1
	fi
}
cleanup() {
	local rc=$?
	restore_addon
	if [ "${reimport}" -eq 1 ]; then
		# The import of the plug-in-less project dropped the extension from .godot/extension_list.cfg.
		"${godot_bin}" --headless --path "${root}" --import > /dev/null 2>&1 || true
	fi
	exit "${rc}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "${build_dir}" "${log_dir}"
# build/ holds 100+ MB executables and archives: Godot must not scan it as project content.
: > "${build_dir}/.gdignore"

# A plug-in left in build/.stash by an interrupted run (the shell was killed before it could put it back).
if [ -d "${stash_dir}/godotsteam" ]; then
	[ ! -e "${addon_dir}" ] || die "both addons/godotsteam and build/.stash/godotsteam exist - delete build/.stash/godotsteam"
	stashed=1
	restore_addon
	log "restored addons/godotsteam from an interrupted earlier build"
fi

if [ "${steam}" -eq 1 ]; then
	log "fetching the GodotSteam plug-in"
	"${root}/tools/steam/fetch_godotsteam.sh" --dest "${root}" || die "tools/steam/fetch_godotsteam.sh failed"
	[ -f "${addon_dir}/godotsteam.gdextension" ] || die "addons/godotsteam/godotsteam.gdextension is missing after the fetch"
	if [ "${app_id}" = "480" ]; then
		warn "steam/app_id in project.godot is 480 (Valve's test app): tools/steam/upload.sh refuses it without --allow-test-app." \
			"The id is baked into the exported game, so after you set the real id run this export again"
	fi
elif [ -e "${addon_dir}" ]; then
	log "build without --steam: hiding addons/godotsteam during the export (put back afterwards)"
	mkdir -p "${stash_dir}"
	mv "${addon_dir}" "${stash_dir}/godotsteam"
	stashed=1
fi

# --- Import --------------------------------------------------------------------------------------------------
log "importing the project (${godot_version})"
"${godot_bin}" --headless --path "${root}" --import > "${log_dir}/import.log" 2>&1 \
	|| { tail -n 30 "${log_dir}/import.log" >&2; die "the project import failed (full log: ${log_dir}/import.log)"; }
# The import above matches the plug-in's current state; putting it back (restore_addon) asks for a new one.
reimport=0

# --- Helpers -------------------------------------------------------------------------------------------------
human_size() {
	wc -c < "$1" | awk '{ s = $1; split("B KB MB GB", u, " "); i = 1; while (s >= 1024 && i < 4) { s /= 1024; i++ } printf "%.1f %s", s, u[i] }'
}

git_info() {
	if command -v git > /dev/null 2>&1 && git -C "${root}" rev-parse --git-dir > /dev/null 2>&1; then
		local hash dirty=""
		hash="$(git -C "${root}" rev-parse --short=10 HEAD 2> /dev/null || echo unknown)"
		[ -z "$(git -C "${root}" status --porcelain 2> /dev/null)" ] || dirty="-dirty"
		echo "${hash}${dirty}"
	else
		echo "unknown"
	fi
}

# Files that must sit next to the executable of a --steam build (and must not in a plain one).
steam_libs() {
	case "$1" in
		windows) echo "steam_api64.dll libgodotsteam.windows.template_release.x86_64.dll" ;;
		linux) echo "libsteam_api.so libgodotsteam.linux.template_release.x86_64.so" ;;
	esac
}

export_platform() {
	local plat="$1" preset exe_name out_dir out log_file
	case "${plat}" in
		windows) preset="${PRESET_WINDOWS}"; exe_name="${PRODUCT}.exe" ;;
		linux) preset="${PRESET_LINUX}"; exe_name="${PRODUCT}.x86_64" ;;
	esac
	out_dir="${content_root}/${plat}"
	out="${out_dir}/${exe_name}"
	log_file="${log_dir}/export-${plat}.log"

	# Only ever delete inside build/steam/content/<platform>.
	[ -n "${plat}" ] && [ "${out_dir}" = "${root}/build/steam/content/${plat}" ] || die "internal error: unexpected content path ${out_dir}"
	rm -rf "${out_dir}"
	mkdir -p "${out_dir}"

	log "exporting '${preset}' -> build/steam/content/${plat}/${exe_name}"
	if ! "${godot_bin}" --headless --path "${root}" --export-release "${preset}" "${out}" > "${log_file}" 2>&1; then
		sed 's/\x1b\[[0-9;]*m//g' "${log_file}" | grep -vE 'savepack \| Storing|first_scan_filesystem' | tail -n 30 >&2
		die "exporting '${preset}' failed (full log: ${log_file})"
	fi
	local errors
	errors="$(sed 's/\x1b\[[0-9;]*m//g' "${log_file}" | grep -E '^(SCRIPT )?ERROR:' || true)"
	if [ -n "${errors}" ]; then
		echo "${errors}" >&2
		die "the export of '${preset}' logged errors (full log: ${log_file})"
	fi
	[ -s "${out}" ] || die "the export of '${preset}' produced no ${out} (see ${log_file})"

	local lib
	for lib in $(steam_libs "${plat}"); do
		if [ "${steam}" -eq 1 ]; then
			[ -s "${out_dir}/${lib}" ] || die "--steam build: ${lib} was not exported next to ${exe_name} (is the plug-in registered? see ${log_file})"
		fi
	done
	if [ "${steam}" -eq 0 ]; then
		if find "${out_dir}" -iname '*steam*' | grep -q .; then
			die "a build without --steam contains Steam files in ${out_dir} - the plug-in was not hidden"
		fi
	fi

	{
		echo "product=${PRODUCT}"
		echo "version=${version}"
		echo "platform=${plat}"
		echo "git=$(git_info)"
		echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		echo "steam=$([ "${steam}" -eq 1 ] && echo yes || echo no)"
		echo "app_id=${app_id}"
		echo "godot=${godot_version}"
	} > "${out_dir}/build_info.txt"
	if [ "${plat}" = "linux" ]; then
		chmod +x "${out}"
	fi
	log "  ${exe_name}: $(human_size "${out}")"
}

verify_pack() {
	local plat="$1" exe_name args=() home="${build_dir}/run_home"
	case "${plat}" in
		windows) exe_name="${PRODUCT}.exe" ;;
		linux) exe_name="${PRODUCT}.x86_64" ;;
	esac
	if [ "${steam}" -eq 1 ]; then
		args=(--steam)
	fi
	# The release template cannot run an outside script, so the editor binary opens the embedded PCK (it is
	# the exe itself) as the project and runs the check against it (own user folders: nothing of a player's).
	if ! XDG_DATA_HOME="${home}/data" XDG_CONFIG_HOME="${home}/config" XDG_CACHE_HOME="${home}/cache" \
		"${godot_bin}" --headless --main-pack "${content_root}/${plat}/${exe_name}" -s "${script_dir}/verify_pack.gd" -- ${args[@]+"${args[@]}"} \
		> "${log_dir}/verify-${plat}.log" 2>&1; then
		tail -n 30 "${log_dir}/verify-${plat}.log" >&2
		die "the packed files of the ${plat} build are wrong (see ${log_dir}/verify-${plat}.log)"
	fi
	rm -rf "${home}"
	log "  pack check ${plat}: $(grep -m1 '^PACK_OK' "${log_dir}/verify-${plat}.log" || echo ok)"
}

smoke_linux() {
	local exe="${content_root}/linux/${PRODUCT}.x86_64" log_file="${log_dir}/smoke-linux.log" rc=0 home="${build_dir}/smoke_home"
	rm -rf "${home}"
	mkdir -p "${home}"
	log "smoke test of the exported Linux binary (--headless -- --smoke --waves=1 --seed=5)"
	# Own user data folders: the smoke run must never touch a real player profile / settings.
	(
		cd "${content_root}/linux"
		XDG_DATA_HOME="${home}/data" XDG_CONFIG_HOME="${home}/config" XDG_CACHE_HOME="${home}/cache" \
			timeout "${SMOKE_TIMEOUT_S}" "${exe}" --headless -- --smoke --waves=1 --seed=5
	) > "${log_file}" 2>&1 || rc=$?
	rm -rf "${home}"
	if [ "${rc}" -ne 0 ]; then
		tail -n 25 "${log_file}" | cut -c1-300 >&2
		die "the exported Linux binary failed the smoke run (exit ${rc}, see ${log_file})"
	fi
	local result
	result="$(grep -m1 '^SMOKE_RESULT ' "${log_file}" || true)"
	[ -n "${result}" ] || die "the smoke run printed no SMOKE_RESULT (see ${log_file})"
	case "${result}" in
		*'"errors":0'*) ;;
		*) die "the smoke run reported errors: $(echo "${result}" | grep -o '"errors":[0-9]*') (see ${log_file})" ;;
	esac
	case "${result}" in
		*'"result":"completed"'*) ;;
		*) die "the smoke run did not complete: $(echo "${result}" | grep -o '"result":"[^"]*"') (see ${log_file})" ;;
	esac
	if [ "${steam}" -eq 1 ] && grep -qiE 'cannot open shared object|error.*(libgodotsteam|libsteam_api|godotsteam\.gdextension)|GDExtension.*(failed|error)' "${log_file}"; then
		grep -iE 'cannot open shared object|libgodotsteam|libsteam_api|gdextension' "${log_file}" | head -n 5 >&2
		die "the Steam extension did not load in the exported Linux binary (see ${log_file})"
	fi
	log "  smoke ok: exit 0, \"errors\":0, $(echo "${result}" | grep -o '"kills":[0-9]*' | head -n 1), $(echo "${result}" | grep -o '"game_time":[0-9.]*' | head -n 1)"
}

make_dist() {
	local plat="$1" name stage
	name="${PRODUCT}-${version}-${plat}"
	stage="$(mktemp -d "${TMPDIR:-/tmp}/smartonion-dist.XXXXXX")"
	ln -s "${content_root}/${plat}" "${stage}/${name}"
	mkdir -p "${dist_dir}"
	case "${plat}" in
		windows)
			command -v zip > /dev/null 2>&1 || { rm -rf "${stage}"; die "zip is needed for build/dist (or pass --no-dist)"; }
			rm -f "${dist_dir}/${name}.zip"
			(cd "${stage}" && zip -q -r "${dist_dir}/${name}.zip" "${name}")
			log "  dist/${name}.zip: $(human_size "${dist_dir}/${name}.zip")"
			;;
		linux)
			command -v tar > /dev/null 2>&1 || { rm -rf "${stage}"; die "tar is needed for build/dist (or pass --no-dist)"; }
			rm -f "${dist_dir}/${name}.tar.gz"
			tar -C "${stage}" -h -czf "${dist_dir}/${name}.tar.gz" "${name}"
			log "  dist/${name}.tar.gz: $(human_size "${dist_dir}/${name}.tar.gz")"
			;;
	esac
	rm -rf "${stage}"
}

# --- Run ---------------------------------------------------------------------------------------------------
steam_label=""
if [ "${steam}" -eq 1 ]; then
	steam_label=", with Steam"
fi
log "${PRODUCT} ${version} (${platform}${steam_label})"
for plat in "${platforms[@]}"; do
	export_platform "${plat}"
done
for plat in "${platforms[@]}"; do
	verify_pack "${plat}"
done
if want_platform linux; then
	if [ "${skip_smoke}" -eq 1 ]; then
		log "smoke test skipped (--skip-smoke)"
	elif [ "$(uname -s)" != "Linux" ]; then
		log "smoke test skipped: the exported Linux binary cannot run on this host ($(uname -s))"
	else
		smoke_linux
	fi
else
	log "smoke test skipped: the headless smoke runs on the Linux binary and this run builds only ${platform}"
fi
if [ "${steam}" -eq 1 ]; then
	log "no build/dist archives for a --steam build (Valve's libraries are for the Steam depot only)"
elif [ "${make_dist}" -eq 1 ]; then
	log "archives for non-Steam distribution"
	for plat in "${platforms[@]}"; do
		make_dist "${plat}"
	done
fi
log "done: build/steam/content/{$(IFS=,; echo "${platforms[*]}")}/ - $(for plat in "${platforms[@]}"; do du -sh "${content_root}/${plat}" | cut -f1 | tr '\n' ' '; done)"
