#!/usr/bin/env bash
# Uploads the Steam build to Steam with SteamPipe (steamcmd):
#   build/steam/content/windows/  ->  the Windows depot
#   build/steam/content/linux/    ->  the Linux depot (also the Steam Deck)
# Both folders are made by tools/build/export.sh --steam. The step-by-step guide for the owner is docs/STEAM_RELEASE.md.
#
# What it does: fills the templates in tools/steam/steampipe/*.vdf.in with the app id, depot ids, branch and
# description, writes them to build/steam/scripts/, checks the content folders, installs steamcmd into build/steamcmd/
# when it is missing (a Steam Guard / password prompt then comes from steamcmd itself), and runs
#   steamcmd +@ShutdownOnFailedCommand 1 +login <user> +run_app_build <app_build_<AppID>.vdf> +quit
# It never asks for, reads or stores a password. See --help.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_dir="${script_dir}/steampipe"

# Where steamcmd comes from (Valve's installer, the same URLs as the SteamCMD documentation).
STEAMCMD_URL_BASE="https://steamcdn-a.akamaihd.net/client/installer"
STEAMCMD_URL_FALLBACK_BASE="https://cdn.cloudflare.steamstatic.com/client/installer"
# Valve's test app (Spacewar). The game ships with it until the Steamworks registration; it cannot be uploaded to.
TEST_APP_ID="480"
# The files the content folders must have (the launch options in Steamworks name the executables).
EXE_WINDOWS="SmartOnion.exe"
EXE_LINUX="SmartOnion.x86_64"

usage() {
	cat <<EOF
Uploads the Steam build (build/steam/content/windows and .../linux) to Steam with SteamPipe.

Usage: $(basename "$0") [mode] [settings]

Modes (default: the real upload):
  --dry-run            Write the filled VDF scripts to build/steam/scripts/ and check the settings and the content
                       folders. No login, no network, steamcmd is not touched. Prints the steamcmd command it would run.
  --print-vdf          Like --dry-run, and print the filled VDF scripts.
  --preview            SteamPipe preview build ("Preview" "1"): logs in, checks everything and writes the logs and the
                       file manifest to build/steam/output/, but uploads nothing. Do this before the real upload.
  --install-steamcmd   Only download steamcmd into build/steamcmd/ (if missing) and start it once; then exit.

Settings (a flag, else the environment variable, else the default):
  --app-id N           APP_ID        default: smartonion/steam/app_id in project.godot (it must match that setting:
                                     the game restarts itself through Steam with that id)
  --depot-win N        DEPOT_WIN     Windows depot id (required)
  --depot-linux N      DEPOT_LINUX   Linux depot id (required)
  --user NAME          STEAM_USER    Steam build account (required except for --dry-run / --print-vdf)
  --branch NAME        STEAM_BRANCH  set the build live on this beta branch after the upload. Never "default": Steam
                                     only lets you set the default branch live in the app admin. Without it nothing
                                     is set live. The branch must exist already (Steamworks: Builds).
  --desc TEXT          BUILD_DESC    build description, shown on the Builds page (default: "v<version> <git hash>" of the
                                     content, read from its build_info.txt)
  --steamcmd PATH      STEAMCMD      an existing steamcmd (default: build/steamcmd/, installed on demand)
  --allow-test-app                   do not refuse app id ${TEST_APP_ID} (Valve's test app, the game's built-in default). Only
                                     useful with --dry-run: nobody can upload to it
  --root DIR                         project root (default: the repository of this script; for tests)
  -h, --help                         this text

It refuses (exit 1, every problem listed) when: a setting is missing or malformed; the app id is ${TEST_APP_ID}; --app-id
differs from project.godot; a content folder or its executable is missing; the Steam libraries are missing (Windows:
steam_api64.dll + libgodotsteam*.dll, Linux: libsteam_api.so + libgodotsteam*.so); a steam_appid.txt is in the content; or
a content folder's build_info.txt (written by tools/build/export.sh) is missing, is not a --steam export (steam=yes), has a
version other than application/config/version, has an app_id other than the one being uploaded (the id is baked into the
exported game: set the real id in project.godot, then export again), or differs from the other platform's in version or
git. It only warns when the git hash in build_info.txt is not the current HEAD or ends in -dirty.

Password and Steam Guard: this script has no password option and never stores one. The first time, steamcmd asks for
the password and the Steam Guard code in your terminal and then caches a login token in its own config folder
(config/config.vdf; a secret: never commit or share it, and the installed copy in build/steamcmd/ is gitignored).
Later runs only need --user. If the login is denied because of Steam Guard, run "steamcmd +set_steam_guard_code <code>"
with the code Steam e-mailed you (the same steamcmd the upload uses: build/steamcmd/steamcmd.sh on Linux / WSL,
build/steamcmd/steamcmd.exe under Git Bash, or the one given with --steamcmd), then try again.

Needs bash (on Windows: Git Bash or WSL), curl or wget, and on Linux the 32-bit C library for steamcmd
(Debian / Ubuntu: lib32gcc-s1). Build and upload the Linux depot from Linux or WSL (repository on the Linux file system):
Git Bash cannot keep the executable bit of SmartOnion.x86_64.

Examples:
  $(basename "$0") --dry-run --depot-win 2345671 --depot-linux 2345672
  $(basename "$0") --preview --user my_build_account --depot-win 2345671 --depot-linux 2345672
  STEAM_USER=my_build_account DEPOT_WIN=2345671 DEPOT_LINUX=2345672 $(basename "$0") --branch beta
EOF
}

# --- Small helpers ---------------------------------------------------------------------------

die() {
	echo "upload: $*" >&2
	exit 1
}

usage_error() {
	echo "upload: $*" >&2
	echo "Try '$(basename "$0") --help'." >&2
	exit 2
}

info() {
	echo "upload: $*"
}

warn() {
	echo "upload: warning: $*" >&2
}

# Literal replace-all (no regex, no & or backslash magic, whatever the value holds): subst TEXT KEY VALUE.
subst() {
	local text="$1" key="$2" value="$3" out=""
	while [[ "${text}" == *"${key}"* ]]; do
		out+="${text%%"${key}"*}${value}"
		text="${text#*"${key}"}"
	done
	printf '%s' "${out}${text}"
}

# A positive whole number without leading zeros, small enough for an app / depot id (32 bit).
is_uint() {
	[[ "$1" =~ ^[1-9][0-9]*$ ]] && [ "${#1}" -le 10 ] && [ "$1" -le 4294967295 ]
}

lower() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# A value of a project.godot setting (text after "key="), quotes and CR removed; empty when missing.
godot_setting() {
	local key="$1"
	[ -f "${project_file}" ] || return 0
	awk -v k="${key}=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "${project_file}" \
		| tr -d '\r' | sed -e 's/^"//' -e 's/"[[:space:]]*$//' -e 's/[[:space:]]*$//'
}

# A path in the form steamcmd wants (on Windows under Git Bash / MSYS: C:/dir/file).
native_path() {
	if command -v cygpath > /dev/null 2>&1; then
		cygpath -m "$1"
	else
		printf '%s' "$1"
	fi
}

# A string for a VDF value: one line, no double quote, backslashes doubled.
vdf_string() {
	local s
	s="$(printf '%s' "$1" | tr '\r\n\t' '   ')"
	s="$(subst "${s}" '"' "'")"
	subst "${s}" '\' '\\'
}

# Size in MiB of a folder, and its file count.
size_mib() {
	local kib
	kib="$(du -sk "$1" | cut -f1)"
	echo $(((kib + 1023) / 1024))
}

file_count() {
	find "$1" -type f | wc -l | tr -d ' '
}

# The first file in a tree matching a find -name / -iname pattern ("" when there is none).
first_match() {
	local dir="$1" flag="$2" pattern="$3"
	find "${dir}" -type f "${flag}" "${pattern}" 2> /dev/null | head -n 1 || true
}

host_os() {
	case "$(uname -s)" in
		Linux*) echo linux ;;
		Darwin*) echo macos ;;
		MINGW* | MSYS* | CYGWIN*) echo windows ;;
		*) echo other ;;
	esac
}

sha256_of() {
	if command -v sha256sum > /dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum > /dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		echo "(no sha256 tool)"
	fi
}

# --- Arguments ---------------------------------------------------------------------------------

mode="upload" # upload | dry-run | install-only
preview=0
print_vdf=0
allow_test_app=0
root=""
app_id_arg="${APP_ID:-}"
depot_win="${DEPOT_WIN:-}"
depot_linux="${DEPOT_LINUX:-}"
steam_user="${STEAM_USER:-}"
branch="${STEAM_BRANCH:-}"
desc="${BUILD_DESC:-}"
steamcmd_arg="${STEAMCMD:-}"

# "--opt=value" is "--opt value".
args=()
for a in "$@"; do
	case "${a}" in
		--*=*) args+=("${a%%=*}" "${a#*=}") ;;
		*) args+=("${a}") ;;
	esac
done
set -- ${args[@]+"${args[@]}"}

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) mode="dry-run"; shift ;;
		--print-vdf) mode="dry-run"; print_vdf=1; shift ;;
		--preview) preview=1; shift ;;
		--install-steamcmd) mode="install-only"; shift ;;
		--allow-test-app) allow_test_app=1; shift ;;
		--app-id | --depot-win | --depot-linux | --user | --branch | --desc | --steamcmd | --root)
			[ $# -ge 2 ] || usage_error "$1 needs a value"
			case "$1" in
				--app-id) app_id_arg="$2" ;;
				--depot-win) depot_win="$2" ;;
				--depot-linux) depot_linux="$2" ;;
				--user) steam_user="$2" ;;
				--branch) branch="$2" ;;
				--desc) desc="$2" ;;
				--steamcmd) steamcmd_arg="$2" ;;
				--root) root="$2" ;;
			esac
			shift 2
			;;
		-h | --help) usage; exit 0 ;;
		*) usage_error "unknown option: $1" ;;
	esac
done

if [ -z "${root}" ]; then
	root="$(cd "${script_dir}/../.." && pwd)"
else
	[ -d "${root}" ] || die "--root is not a directory: ${root}"
	root="$(cd "${root}" && pwd)"
fi
project_file="${root}/project.godot"
content_dir="${root}/build/steam/content"
scripts_dir="${root}/build/steam/scripts"
output_dir="${root}/build/steam/output"
steamcmd_dir="${root}/build/steamcmd"
os="$(host_os)"

# --- steamcmd ------------------------------------------------------------------------------------

default_steamcmd() {
	if [ "${os}" = "windows" ]; then
		echo "${steamcmd_dir}/steamcmd.exe"
	else
		echo "${steamcmd_dir}/steamcmd.sh"
	fi
}

download() {
	local url="$1" target="$2"
	if command -v curl > /dev/null 2>&1; then
		curl --fail --location --silent --show-error --retry 3 --connect-timeout 30 --output "${target}" "${url}"
	elif command -v wget > /dev/null 2>&1; then
		wget --quiet --tries=3 --timeout=30 --output-document="${target}" "${url}"
	else
		die "need curl or wget to download steamcmd"
	fi
}

# Downloads Valve's steamcmd installer into build/steamcmd/ (no checksum is published for it: the file is Valve's
# rolling installer, steamcmd then updates itself on its first start).
install_steamcmd() {
	local archive
	case "${os}" in
		linux) archive="steamcmd_linux.tar.gz" ;;
		macos) archive="steamcmd_osx.tar.gz" ;;
		windows) archive="steamcmd.zip" ;;
		*) die "no steamcmd installer is known for this system; install steamcmd yourself and pass --steamcmd PATH" ;;
	esac
	local work
	work="$(mktemp -d "${TMPDIR:-/tmp}/steamcmd.XXXXXX")"
	# shellcheck disable=SC2064
	trap "rm -rf '${work}'" EXIT
	info "downloading ${archive} from Valve (${STEAMCMD_URL_BASE})"
	download "${STEAMCMD_URL_BASE}/${archive}" "${work}/${archive}" \
		|| download "${STEAMCMD_URL_FALLBACK_BASE}/${archive}" "${work}/${archive}" \
		|| die "could not download ${archive}. Install steamcmd by hand and pass --steamcmd PATH"
	info "sha256 of the download: $(sha256_of "${work}/${archive}")"
	mkdir -p "${work}/unpacked"
	case "${archive}" in
		*.tar.gz) tar -xzf "${work}/${archive}" -C "${work}/unpacked" ;;
		*.zip)
			if command -v unzip > /dev/null 2>&1; then
				unzip -q -o "${work}/${archive}" -d "${work}/unpacked"
			elif command -v python3 > /dev/null 2>&1; then
				python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "${work}/${archive}" "${work}/unpacked"
			else
				die "need unzip or python3 to unpack ${archive}"
			fi
			;;
	esac
	mkdir -p "${steamcmd_dir}"
	cp -R "${work}/unpacked/." "${steamcmd_dir}/"
	chmod +x "${steamcmd_dir}/steamcmd.sh" 2> /dev/null || true
	[ -f "$(default_steamcmd)" ] || die "the installer did not contain $(basename "$(default_steamcmd)")"
	info "steamcmd installed in ${steamcmd_dir}"
}

# On Linux the steamcmd binary is a 32-bit program: without the 32-bit C library it does not start at all.
warn_if_no_32bit_loader() {
	[ "${os}" = "linux" ] || return 0
	local loader
	for loader in /lib/ld-linux.so.2 /lib32/ld-linux.so.2 /usr/lib32/ld-linux.so.2 /lib/i386-linux-gnu/ld-linux.so.2; do
		[ -e "${loader}" ] && return 0
	done
	warn "this system has no 32-bit C library, and steamcmd is a 32-bit program, so it cannot start. Install it first" \
		"(Debian / Ubuntu: sudo dpkg --add-architecture i386 && sudo apt update && sudo apt install lib32gcc-s1)."
}

# Sets steamcmd_bin to a steamcmd that exists, installing the default one when allowed.
steamcmd_bin=""
ensure_steamcmd() {
	if [ -n "${steamcmd_arg}" ]; then
		[ -f "${steamcmd_arg}" ] || die "--steamcmd / STEAMCMD is not a file: ${steamcmd_arg}"
		[ -x "${steamcmd_arg}" ] || die "--steamcmd / STEAMCMD is not executable: ${steamcmd_arg}"
		steamcmd_bin="${steamcmd_arg}"
		return 0
	fi
	steamcmd_bin="$(default_steamcmd)"
	if [ ! -x "${steamcmd_bin}" ]; then
		install_steamcmd
	fi
	warn_if_no_32bit_loader
}

# --- The one mode that needs nothing else ---------------------------------------------------------

if [ "${mode}" = "install-only" ]; then
	ensure_steamcmd
	info "starting steamcmd once so it can update itself: ${steamcmd_bin} +quit"
	status=0
	"${steamcmd_bin}" +quit || status=$?
	[ "${status}" -eq 0 ] || die "steamcmd did not run (exit code ${status}); see the messages above"
	info "steamcmd is ready (${steamcmd_bin})"
	exit 0
fi

# --- Settings ------------------------------------------------------------------------------------

problems=()
problem() {
	problems+=("$*")
}

[ -f "${project_file}" ] || problem "no project.godot in ${root}"

project_app_id="$(godot_setting "steam/app_id")"
project_version="$(godot_setting "config/version")"
version="${project_version:-dev}"
if [ -z "${project_app_id}" ]; then
	# The game itself falls back to 480 (SteamRemotePlayBackend.DEFAULT_APP_ID) when the setting is missing.
	project_app_id="${TEST_APP_ID}"
fi

app_id="${app_id_arg:-${project_app_id}}"
if ! is_uint "${app_id}"; then
	problem "the app id is not a positive number: '${app_id}' (--app-id / APP_ID / smartonion/steam/app_id in project.godot)"
elif [ "${app_id}" != "${project_app_id}" ]; then
	problem "the app id ${app_id} differs from smartonion/steam/app_id in project.godot (${project_app_id}). The game relaunches itself" \
		"through Steam with the project.godot value, so they must be the same: change project.godot, then export again"
fi
if [ "${app_id}" = "${TEST_APP_ID}" ] && [ "${allow_test_app}" -eq 0 ]; then
	problem "app id ${TEST_APP_ID} is Valve's test app (Spacewar) and the game's built-in default; it cannot be uploaded to. Put your Steamworks" \
		"app id into smartonion/steam/app_id in project.godot (docs/STEAM_RELEASE.md) and run tools/build/export.sh --steam again (the id is" \
		"baked into the exported game, so a build made with ${TEST_APP_ID} stays wrong), or pass --allow-test-app to try a dry run anyway"
fi

if ! is_uint "${depot_win}"; then
	problem "the Windows depot id is missing or not a positive number: '${depot_win}' (--depot-win / DEPOT_WIN)"
fi
if ! is_uint "${depot_linux}"; then
	problem "the Linux depot id is missing or not a positive number: '${depot_linux}' (--depot-linux / DEPOT_LINUX)"
fi
if is_uint "${depot_win}" && is_uint "${depot_linux}"; then
	[ "${depot_win}" != "${depot_linux}" ] || problem "the Windows and the Linux depot must have different ids (both are ${depot_win})"
	if [ "${depot_win}" = "${app_id}" ] || [ "${depot_linux}" = "${app_id}" ]; then
		problem "a depot id equals the app id ${app_id}: depot ids are separate numbers (Steamworks: SteamPipe > Depots)"
	fi
fi

if [ "${mode}" = "upload" ] && [ -z "${steam_user}" ]; then
	problem "no Steam build account: pass --user NAME or set STEAM_USER (a dedicated build account is recommended)"
fi
if [ -n "${steam_user}" ] && ! [[ "${steam_user}" =~ ^[A-Za-z0-9_.@+-]+$ ]]; then
	problem "the Steam account name '${steam_user}' has characters a Steam login name does not have"
fi

set_live=""
if [ -n "${branch}" ]; then
	branch_lower="$(lower "${branch}")"
	if [ "${branch_lower}" = "default" ] || [ "${branch_lower}" = "public" ]; then
		problem "the branch '${branch}' is the default branch: Steam does not let a build be set live on it automatically." \
			"Upload without --branch and set the build live on the Builds page of the Steamworks app admin"
	elif ! [[ "${branch}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
		problem "the branch name '${branch}' must be a single word of letters, digits, '_', '-' or '.' (Steamworks branch names have no spaces)"
	else
		set_live="${branch}"
	fi
fi
if [ "${preview}" -eq 1 ] && [ -n "${set_live}" ]; then
	info "a preview build uploads nothing, so --branch ${set_live} is not used"
	set_live=""
fi

# The commit of the checkout (build_info.txt of the content is compared with it; only a warning).
head_commit="$(git -C "${root}" rev-parse HEAD 2> /dev/null || true)"

# --- The content folders --------------------------------------------------------------------------

# The value of KEY in a build_info.txt (key=value lines, written by tools/build/export.sh), CR removed; "" when missing.
build_info_value() {
	local file="$1" key="$2"
	[ -f "${file}" ] || return 0
	tr -d '\r' < "${file}" \
		| awk -v k="${key}=" 'index($0, k) == 1 && !found { print substr($0, length(k) + 1); found = 1 }' \
		| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Is the content of one platform an export of THIS project, made for the app id that is uploaded? The app id and the
# version are compiled into the executables, so build_info.txt (written by export.sh next to them) is the only record.
check_build_info() {
	local name="$1" file="${content_dir}/$1/build_info.txt"
	local again="run tools/build/export.sh --steam again"
	if [ ! -f "${file}" ]; then
		problem "${name}: build_info.txt is missing in ${content_dir}/${name}: the content cannot be matched to this project (${again})"
		return 0
	fi
	local steam_flag b_version b_app_id b_git
	steam_flag="$(build_info_value "${file}" steam)"
	b_version="$(build_info_value "${file}" version)"
	b_app_id="$(build_info_value "${file}" app_id)"
	b_git="$(build_info_value "${file}" git)"
	[ "${steam_flag}" = "yes" ] \
		|| problem "${name}: build_info.txt says steam=${steam_flag:-(missing)}, so this is not a Steam export (${again})"
	if [ -z "${b_version}" ]; then
		problem "${name}: build_info.txt has no version (${again})"
	elif [ "${b_version}" != "${project_version}" ]; then
		problem "${name}: the content is version ${b_version}, but application/config/version in project.godot is '${project_version}' (${again})"
	fi
	if [ -z "${b_app_id}" ]; then
		problem "${name}: build_info.txt has no app_id (exported by an older export.sh; ${again})"
	elif [ "${b_app_id}" != "${app_id}" ]; then
		problem "${name}: the content was exported with app id ${b_app_id}, but the app id being uploaded is ${app_id}. The id is baked into" \
			"the game (it relaunches itself through Steam with it): set the real id in smartonion/steam/app_id in project.godot, then ${again}"
	fi
	case "${b_git}" in
		*-dirty) warn "${name}: the content was exported from a working tree with uncommitted changes (git ${b_git})" ;;
	esac
	local b_hash="${b_git%-dirty}"
	if [ -n "${head_commit}" ] && [ -n "${b_hash}" ] && [ "${b_hash}" != "unknown" ] && [[ "${head_commit}" != "${b_hash}"* ]]; then
		warn "${name}: the content was exported from commit ${b_hash}, but the checkout is at ${head_commit:0:10}"
	fi
}

# The two platforms must come from the same export run (a --platform export replaces only its own folder).
check_build_info_agree() {
	local win_file="${content_dir}/windows/build_info.txt" linux_file="${content_dir}/linux/build_info.txt"
	[ -f "${win_file}" ] && [ -f "${linux_file}" ] || return 0
	local key win_value linux_value
	for key in version git; do
		win_value="$(build_info_value "${win_file}" "${key}")"
		linux_value="$(build_info_value "${linux_file}" "${key}")"
		[ "${win_value}" = "${linux_value}" ] \
			|| problem "windows and linux were not exported together: ${key} is '${win_value}' in windows/build_info.txt but '${linux_value}'" \
				"in linux/build_info.txt (run tools/build/export.sh --steam for both platforms)"
	done
}

check_platform() {
	local name="$1" exe="$2" api_lib="$3" api_flag="$4" ext_lib="$5" ext_flag="$6"
	local dir="${content_dir}/${name}"
	if [ ! -d "${dir}" ]; then
		problem "the ${name} content folder is missing: ${dir} (run tools/build/export.sh --steam)"
		return 0
	fi
	if [ -z "$(find "${dir}" -type f 2> /dev/null | head -n 1 || true)" ]; then
		problem "the ${name} content folder is empty: ${dir}"
		return 0
	fi
	[ -f "${dir}/${exe}" ] || problem "${name}: ${exe} is not in ${dir}"
	[ -n "$(first_match "${dir}" "${api_flag}" "${api_lib}")" ] \
		|| problem "${name}: the Steamworks library ${api_lib} is not in ${dir} (the export must be made with tools/build/export.sh --steam)"
	[ -n "$(first_match "${dir}" "${ext_flag}" "${ext_lib}")" ] \
		|| problem "${name}: the GodotSteam library ${ext_lib} is not in ${dir} (the export must be made with tools/build/export.sh --steam)"
	local stray
	stray="$(first_match "${dir}" -iname "steam_appid.txt")"
	[ -z "${stray}" ] || problem "${name}: ${stray} must not be uploaded (it stops the game from relaunching through Steam); delete it"
	check_build_info "${name}"
}

check_platform "windows" "${EXE_WINDOWS}" "steam_api64.dll" -iname "libgodotsteam*.dll" -iname
check_platform "linux" "${EXE_LINUX}" "libsteam_api.so" -name "libgodotsteam*.so" -name
check_build_info_agree
if [ "${os}" = "windows" ]; then
	warn "this is a Windows host: its file system does not keep the executable bit of ${EXE_LINUX}, and a Linux depot without it may not" \
		"start (Linux, Steam Deck). Build and upload the Linux depot from Linux or WSL (repository on the Linux file system), see docs/STEAM_RELEASE.md"
fi
if [ "${os}" != "windows" ] && [ -f "${content_dir}/linux/${EXE_LINUX}" ] && [ ! -x "${content_dir}/linux/${EXE_LINUX}" ]; then
	warn "${content_dir}/linux/${EXE_LINUX} is not executable (chmod +x it, or the Linux depot may not start)"
fi

if [ "${#problems[@]}" -gt 0 ]; then
	echo "upload: cannot upload, ${#problems[@]} problem(s):" >&2
	for p in "${problems[@]}"; do
		echo "  - ${p}" >&2
	done
	exit 1
fi

# The default description names what is in the content (its build_info.txt), not what is checked out now. Both
# platforms agree on version and git (checked above).
if [ -z "${desc}" ]; then
	content_git="$(build_info_value "${content_dir}/windows/build_info.txt" git)"
	desc="v$(build_info_value "${content_dir}/windows/build_info.txt" version) ${content_git:-nogit}"
fi

# --- Write the VDF scripts -----------------------------------------------------------------------

for t in app_build depot_build_windows depot_build_linux; do
	[ -f "${template_dir}/${t}.vdf.in" ] || die "template missing: ${template_dir}/${t}.vdf.in"
done

for p in "${content_dir}" "${output_dir}" "${scripts_dir}"; do
	case "${p}" in
		*'"'* | *$'\n'*) die "the path ${p} has a quote or a line break in it, which a VDF cannot hold" ;;
	esac
done

# render TEMPLATE OUTPUT KEY=VALUE...: every @KEY@ of the template is replaced. A placeholder that no KEY fills is a bug
# in the template (checked before anything is written, so a user's text such as a description cannot trigger it).
render() {
	local template="$1" target="$2"
	shift 2
	local text kv placeholder filled
	for placeholder in $(grep -Eo '@[A-Z][A-Z_]*@' "${template}" | sort -u); do
		filled=0
		for kv in "$@"; do
			[ "@${kv%%=*}@" = "${placeholder}" ] && filled=1
		done
		[ "${filled}" -eq 1 ] || die "${template} has the placeholder ${placeholder}, which upload.sh does not fill"
	done
	text="$(cat "${template}")"
	for kv in "$@"; do
		text="$(subst "${text}" "@${kv%%=*}@" "${kv#*=}")"
	done
	printf '%s\n' "${text}" > "${target}"
}

mkdir -p "${scripts_dir}" "${output_dir}"
app_vdf="${scripts_dir}/app_build_${app_id}.vdf"
win_vdf="${scripts_dir}/depot_build_${depot_win}.vdf"
linux_vdf="${scripts_dir}/depot_build_${depot_linux}.vdf"

render "${template_dir}/app_build.vdf.in" "${app_vdf}" \
	"APP_ID=${app_id}" "DESC=$(vdf_string "${desc}")" "PREVIEW=${preview}" "SET_LIVE=${set_live}" \
	"CONTENT_ROOT=$(native_path "${content_dir}")" "BUILD_OUTPUT=$(native_path "${output_dir}")" \
	"DEPOT_WIN=${depot_win}" "DEPOT_LINUX=${depot_linux}"
render "${template_dir}/depot_build_windows.vdf.in" "${win_vdf}" \
	"DEPOT_ID=${depot_win}" "DEPOT_CONTENT_ROOT=$(native_path "${content_dir}/windows")"
render "${template_dir}/depot_build_linux.vdf.in" "${linux_vdf}" \
	"DEPOT_ID=${depot_linux}" "DEPOT_CONTENT_ROOT=$(native_path "${content_dir}/linux")"

# --- Report -----------------------------------------------------------------------------------------

info "app ${app_id}, version ${version}, build \"${desc}\""
info "Windows depot ${depot_win}: ${content_dir}/windows ($(file_count "${content_dir}/windows") files, $(size_mib "${content_dir}/windows") MiB)"
info "Linux depot   ${depot_linux}: ${content_dir}/linux ($(file_count "${content_dir}/linux") files, $(size_mib "${content_dir}/linux") MiB)"
for name in windows linux; do
	if [ -f "${content_dir}/${name}/build_info.txt" ]; then
		info "${name}/build_info.txt: $(tr '\r\n' '  ' < "${content_dir}/${name}/build_info.txt" | cut -c1-200)"
	fi
done
if [ -n "${set_live}" ]; then
	info "after the upload the build is set live on the beta branch '${set_live}'"
else
	info "nothing is set live: do it on https://partner.steamgames.com/apps/builds/${app_id}"
fi
info "scripts written: ${app_vdf}"
info "                 ${win_vdf}"
info "                 ${linux_vdf}"

if [ "${print_vdf}" -eq 1 ]; then
	for f in "${app_vdf}" "${win_vdf}" "${linux_vdf}"; do
		echo "----- ${f}"
		cat "${f}"
	done
	echo "-----"
fi

login_user="${steam_user:-YOUR_STEAM_BUILD_ACCOUNT}"
if [ "${mode}" = "dry-run" ]; then
	info "dry run: no login, no upload. The real run would start:"
	info "  ${steamcmd_arg:-$(default_steamcmd)} +@ShutdownOnFailedCommand 1 +login ${login_user} +run_app_build $(native_path "${app_vdf}") +quit"
	exit 0
fi

# --- Run steamcmd ----------------------------------------------------------------------------------

ensure_steamcmd
if [ "${preview}" -eq 1 ]; then
	info "PREVIEW build: logs and the file manifest go to ${output_dir}, nothing is uploaded"
fi
if [ ! -t 0 ]; then
	warn "standard input is not a terminal: steamcmd cannot ask for the password or the Steam Guard code, so this only works" \
		"when a login token for ${steam_user} is already cached (run it once in a terminal)"
fi
info "logging in as ${steam_user}: steamcmd asks for the password / Steam Guard code itself if it needs them"
status=0
"${steamcmd_bin}" +@ShutdownOnFailedCommand 1 +login "${steam_user}" +run_app_build "$(native_path "${app_vdf}")" +quit || status=$?
if [ "${status}" -ne 0 ]; then
	die "steamcmd failed (exit code ${status}). The reason is in its output above and in the *.log files in ${output_dir}"
fi
if [ "${preview}" -eq 1 ]; then
	info "preview finished. Check the file list in ${output_dir}, then run again without --preview"
else
	info "upload finished. Next: https://partner.steamgames.com/apps/builds/${app_id} (build id, branches, set live)"
fi
