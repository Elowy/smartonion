#!/usr/bin/env bash
# Renders the SmartOnion gameplay trailer: the takes (Godot Movie Maker, real game with bots), the text cards, then the
# edit (ffmpeg). See tools/trailer/README.md.
#
#   tools/trailer/make_trailer.sh                  render what is missing, edit, encode
#   tools/trailer/make_trailer.sh --edit-only      only re-run the edit (shot list in edit.py, cards, music)
#   tools/trailer/make_trailer.sh --force main,intro   render these takes again (or "all", "cards")
#   tools/trailer/make_trailer.sh --preview        faster, lower quality 3D view (a quick look; same pipeline)
#
# Environment: TRAILER_WORK (work + output directory, default <repo>/build/trailer), GODOT (binary, default godot),
# JOBS (takes rendered in parallel, default 2), TRAILER_TAKES (override the take list).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${TRAILER_WORK:-$ROOT/build/trailer}"
GODOT="${GODOT:-godot}"
JOBS="${JOBS:-2}"
FPS=30
RES=1920x1080
# Longest first, so the parallel jobs finish together.
TAKES=(${TRAILER_TAKES:-main classes_a intro arenas sets endcard})

FORCE=""
EDIT_ONLY=0
PREVIEW=0
while [ $# -gt 0 ]; do
	case "$1" in
		--force) FORCE=",$2,"; shift 2 ;;
		--edit-only) EDIT_ONLY=1; shift ;;
		--preview) PREVIEW=1; shift ;;
		-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

for tool in "$GODOT" ffmpeg ffprobe xvfb-run python3; do
	command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done
mkdir -p "$WORK/takes" "$WORK/cards" "$WORK/logs" "$WORK/shots"

wants() { [[ "$FORCE" == ",all," || "$FORCE" == *",$1,"* ]]; }

# Movie Maker records at the window's size and the project overrides it (1600 x 900): the render needs its own
# override.cfg next to project.godot (removed again when this script ends). The video quality is the MJPEG quality of
# Movie Maker's intermediate file (the real compression is the final encode).
OVERRIDE="$ROOT/override.cfg"
cleanup() { [ "${MADE_OVERRIDE:-0}" = 1 ] && rm -f "$OVERRIDE" || true; }
trap cleanup EXIT
if [ "$EDIT_ONLY" = 0 ]; then
	if [ ! -e "$OVERRIDE" ]; then
		printf '[display]\nwindow/size/window_width_override=1920\nwindow/size/window_height_override=1080\n\n[editor]\nmovie_writer/video_quality=0.93\n' > "$OVERRIDE"
		MADE_OVERRIDE=1
	fi
	"$GODOT" --headless --path "$ROOT" --import >"$WORK/logs/import.log" 2>&1 || true
fi

movie() { # movie <out.avi> <godot args...>
	local out="$1"; shift
	xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --write-movie "$out" --fixed-fps "$FPS" --resolution "$RES" \
		--path "$ROOT" --rendering-driver opengl3 "$@"
}

render_cards() {
	local pass
	for pass in text dim; do
		if [ -e "$WORK/cards/cards_$pass.avi" ] && ! wants cards; then continue; fi
		echo "[cards] pass $pass"
		movie "$WORK/cards/cards_$pass.avi" -s res://tools/trailer/cards.gd -- --pass=$pass --marks="$WORK/cards/cards_$pass.json" \
			>"$WORK/logs/cards_$pass.log" 2>&1
	done
}

render_take() {
	local take="$1" extra=()
	[ "$PREVIEW" = 1 ] && extra=(--t-preview)
	if [ -e "$WORK/takes/$take.json" ] && ! wants "$take"; then echo "[take $take] done already"; return 0; fi
	echo "[take $take] rendering ..."
	rm -f "$WORK/takes/$take.json"
	if movie "$WORK/takes/$take.avi" -s res://tools/trailer/trailer.gd -- --take="$take" --marks="$WORK/takes/$take.json" "${extra[@]}" \
			>"$WORK/logs/$take.log" 2>&1 && [ -e "$WORK/takes/$take.json" ]; then
		echo "[take $take] finished: $(grep -c "clip '.*' ends" "$WORK/logs/$take.log") clips"
	else
		echo "[take $take] FAILED, see $WORK/logs/$take.log" >&2
		rm -f "$WORK/takes/$take.json"
		return 1
	fi
}

if [ "$EDIT_ONLY" = 0 ]; then
	render_cards
	running=0
	failed=0
	for take in "${TAKES[@]}"; do
		render_take "$take" &
		running=$((running + 1))
		if [ "$running" -ge "$JOBS" ]; then
			wait -n || failed=1
			running=$((running - 1))
		fi
	done
	while [ "$running" -gt 0 ]; do wait -n || failed=1; running=$((running - 1)); done
	[ "$failed" = 0 ] || { echo "some takes failed" >&2; exit 1; }
fi

EDIT_ARGS=(--work "$WORK")
[ "$PREVIEW" = 1 ] && EDIT_ARGS+=(--preview)
python3 "$ROOT/tools/trailer/edit.py" "${EDIT_ARGS[@]}"
OUT="$WORK/smartonion_trailer.mp4"
ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate -of default=nw=1 "$OUT"
