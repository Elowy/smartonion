#!/usr/bin/env python3
"""Edits the SmartOnion trailer from the rendered takes (called by make_trailer.sh; see README.md).

Reads   <work>/takes/<take>.avi + .json     the movies of the takes and their clip marks (trailer_director.gd)
        <work>/cards/cards_{text,dim}.avi + .json     the text cards (cards.gd)
Writes  <work>/shots/NN_name.mkv            every shot cut from its clip, cards laid over it
        <work>/audio/*.wav                  SFX track, music bed, mix
        <work>/smartonion_trailer.mp4       the trailer (H.264 + AAC)

Python standard library only; ffmpeg / ffprobe do all the work. The EDIT LIST below is the shot list: change it, run
make_trailer.sh again (finished takes are not rendered a second time).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

FPS = 30
BPM = 152.0                  # the combat track (assets/audio/music/music_combat.ogg)
BEAT = 60.0 / BPM
COMBAT_FIRST_BEAT = 0.17     # seconds into music_combat.ogg of its first beat

# --- EDIT LIST -------------------------------------------------------------------------------------------------
# One entry per shot, in order. src = "take/clip" (the names of the marks files); ss = seconds into the clip;
# beats = length in beats of the music's grid (the combat track, 152 bpm, a bar is 4 beats); cards = [(card id, seconds into the shot)]; flash = seconds of a white flash-in;
# fadein / fadeout = seconds of a fade from / to black; sfx = [dict(f=file in assets/audio/sfx, at=seconds into the
# shot, db=level, rise=seconds)] accents (rise: the sound is slowed to that length and fades in, ending at `at`: a
# riser). One music track (the combat track) runs under the whole trailer.
BIG_HIT = [dict(f="impact_impactBell_heavy_000", at=0.0, db=-1.0), dict(f="scifi_lowFrequency_explosion_001", at=0.0, db=-3.0)]
SHOTS: list[dict] = [
    # Cold open: the party at work, then the title slams in on the bar.
    dict(src="intro/intro", ss=0.4, beats=16, fadein=0.5, cards=[("title", 8 * BEAT)],
         sfx=[dict(f="scifi_thrusterFire_004_t80", at=8 * BEAT, db=-5.0, rise=3.0),
              dict(f="impact_impactBell_heavy_000", at=8 * BEAT, db=-1.0), dict(f="scifi_lowFrequency_explosion_001", at=8 * BEAT, db=-3.0)]),
    # Co-op chaos.
    dict(src="classes_a/coop", ss=0.3, beats=10, cards=[("coop", 0.3)]),
    # The classes, one cut each (the Hunter's companions, the Shaman's totems).
    dict(src="classes_a/cls_warrior", ss=0.0, beats=4, cards=[("classes", 0.0), ("l_warrior", 0.1)]),
    dict(src="classes_a/cls_mage", ss=0.0, beats=4, cards=[("l_mage", 0.1)]),
    dict(src="main_cuts/cls_paladin", ss=0.0, beats=4, cards=[("l_paladin", 0.1)]),
    dict(src="main_cuts/cls_rogue", ss=0.0, beats=4, cards=[("l_rogue", 0.1)]),
    dict(src="main_cuts/cls_warlock", ss=0.0, beats=4, cards=[("l_warlock", 0.1)]),
    dict(src="main_cuts/cls_hunter", ss=0.0, beats=4, cards=[("l_hunter", 0.1)]),
    dict(src="sets/hunter_pets", ss=0.2, beats=3),
    dict(src="classes_a/cls_shaman", ss=0.0, beats=4, cards=[("l_shaman", 0.1)]),
    # Loot: the drops with their beams, the Need / Greed roll with a Legendary and an Artifact.
    dict(src="main_cuts/loot_drops", ss=0.0, beats=10, cards=[("loot", 0.2)]),
    # The market, the forge, the talent tree, the tier sets.
    dict(src="main/market", ss=0.3, beats=4),
    dict(src="main/market", ss=3.6, beats=6, cards=[("build", 0.2)]),
    dict(src="main/market", ss=9.2, beats=5),
    dict(src="sets/sets", ss=0.0, beats=7),
    # Variety: the arena roll, the five arenas, the dungeon.
    dict(src="arenas/roll", ss=0.8, beats=8, cards=[("variety", 0.2)]),
    dict(src="arenas/env_forest_ruin", ss=0.0, beats=3),
    dict(src="arenas/env_swamp", ss=0.0, beats=3),
    dict(src="arenas/env_ice_cave", ss=0.0, beats=3),
    dict(src="arenas/env_cemetery", ss=0.0, beats=3),
    dict(src="arenas/env_volcano", ss=0.0, beats=3),
    dict(src="main/dungeon_room", ss=0.6, beats=4),
    dict(src="main/dungeon_warden", ss=1.2, beats=4),
    # Bosses, the climax and the end card.
    dict(src="main/boss1_intro", ss=1.7, beats=8, cards=[("bosses", 0.3)], flash=0.12, sfx=BIG_HIT),
    dict(src="main/boss1_fight", ss=0.4, beats=5),
    dict(src="main_boss2/boss2_intro", ss=1.4, beats=8),
    dict(src="main_boss2/boss2_fight", ss=0.4, beats=5),
    dict(src="main_late/climax", ss=0.0, beats=16, flash=0.12, cards=[("survive", 0.3)], sfx=BIG_HIT),
    dict(src="endcard/endcard", ss=0.0, beats=14, fadein=0.3, fadeout=1.4, cards=[("end", 0.4)]),
]
# ----------------------------------------------------------------------------------------------------------------

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")
GLOW_SIGMA = 14
GLOW_OPACITY = 0.65
# Mix levels (dB, before the final loudness pass).
MUSIC_DB = -4.0
MUSIC_FADE_IN = 1.2
MUSIC_FADE_OUT = 2.6
SFX_DB = -13.0
TARGET_LUFS = -15.0


def run(cmd: list[str], quiet: bool = True) -> None:
    if not quiet:
        print("+", " ".join(cmd))
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:])
        raise SystemExit("ffmpeg failed: " + " ".join(cmd[:6]) + " ...")


def frames_for(seconds: float) -> int:
    return max(1, round(seconds * FPS))


def resolve(shots: list[dict]) -> float:
    """Gives every shot its length (_dur, seconds: its beats on the grid of the music) and start time (_t0); returns the
    total."""
    t = 0.0
    for shot in shots:
        shot["_dur"] = frames_for(shot["beats"] * BEAT) / FPS
        shot["_t0"] = t
        t += shot["_dur"]
    return t


class Marks:
    """The clip marks of the takes and of the card passes."""

    def __init__(self, work: str):
        self.work = work
        self.clips: dict[str, dict] = {}
        self.cards: dict[str, dict] = {}
        takes_dir = os.path.join(work, "takes")
        if os.path.isdir(takes_dir):
            for f in sorted(os.listdir(takes_dir)):
                if f.endswith(".json"):
                    stem = f[:-5]
                    data = json.load(open(os.path.join(takes_dir, f)))
                    # A take may be rendered in parts (main.json, main_cuts.json ...): the movie is named like the marks
                    # file and the shot list names the clips "<marks file>/<clip>".
                    take = stem
                    for c in data.get("clips", []):
                        self.clips[f"{take}/{c['name']}"] = dict(c, avi=os.path.join(takes_dir, stem + ".avi"))
        cards_json = os.path.join(work, "cards", "cards_text.json")
        if os.path.exists(cards_json):
            for c in json.load(open(cards_json)).get("clips", []):
                self.cards[c["name"]] = c


def build_shot(index: int, shot: dict, marks: Marks, work: str, preview: bool) -> str | None:
    """Cuts one shot (video + the game's audio) and lays its cards over it. Returns the file or None (clip missing)."""
    clip = marks.clips.get(shot["src"])
    if clip is None:
        print(f"  ! shot {index}: clip '{shot['src']}' is missing - skipped")
        return None
    dur_frames = frames_for(shot["_dur"])
    ss_frames = frames_for(shot.get("ss", 0.0)) if shot.get("ss", 0.0) > 0 else 0
    if ss_frames + dur_frames > clip["frames"]:
        short = ss_frames + dur_frames - clip["frames"]
        print(f"  ! shot {index} ({shot['src']}): the clip is {short} frames too short - the last frame is held")
    start = clip["start"] + ss_frames
    dur = dur_frames / FPS
    name = shot["src"].replace("/", "_")
    out = os.path.join(work, "shots", f"{index:02d}_{name}.mkv")
    inputs = ["-ss", f"{start / FPS:.6f}", "-i", clip["avi"]]
    chains = []
    # Hold the last frame when the clip is a little short; the audio is padded with silence.
    chains.append(f"[0:v]setpts=PTS-STARTPTS,fps={FPS},tpad=stop_mode=clone:stop_duration=4,trim=end_frame={dur_frames},"
                  f"setpts=PTS-STARTPTS,format=gbrp[v0]")
    last = "v0"
    n = 1
    cards = shot.get("cards", [])
    if cards and not marks.cards:
        print(f"  ! shot {index}: no cards rendered yet - the cards are left out")
        cards = []
    for k, (card_id, at) in enumerate(cards):
        card = marks.cards.get(card_id)
        if card is None:
            print(f"  ! shot {index}: card '{card_id}' unknown")
            continue
        cs = card["start"] / FPS
        cd = card["frames"] / FPS
        for kind in ("dim", "text"):
            avi = os.path.join(work, "cards", f"cards_{kind}.avi")
            inputs += ["-ss", f"{cs:.6f}", "-t", f"{cd:.6f}", "-i", avi]
        di, ti = n, n + 1
        n += 2
        pad = "white", "black"
        chains.append(f"[{di}:v]setpts=PTS-STARTPTS,fps={FPS},tpad=start_mode=add:start_duration={at:.4f}:color=white,"
                      f"tpad=stop_mode=add:stop_duration=30:color=white,trim=end_frame={dur_frames},setpts=PTS-STARTPTS,format=gbrp[d{k}]")
        chains.append(f"[{ti}:v]setpts=PTS-STARTPTS,fps={FPS},tpad=start_mode=add:start_duration={at:.4f}:color=black,"
                      f"tpad=stop_mode=add:stop_duration=30:color=black,trim=end_frame={dur_frames},setpts=PTS-STARTPTS,format=gbrp,split[t{k}a][t{k}b]")
        chains.append(f"[t{k}b]gblur=sigma={GLOW_SIGMA}[g{k}]")
        chains.append(f"[t{k}a][g{k}]blend=all_mode=addition:all_opacity={GLOW_OPACITY}[tg{k}]")
        chains.append(f"[{last}][d{k}]blend=all_mode=multiply[vd{k}]")
        chains.append(f"[vd{k}][tg{k}]blend=all_mode=addition[c{k}]")
        last = f"c{k}"
    tail = []
    if shot.get("fadein"):
        tail.append(f"fade=t=in:st=0:d={shot['fadein']}")
    if shot.get("flash"):
        tail.append(f"fade=t=in:st=0:d={shot['flash']}:color=white")
    if shot.get("fadeout"):
        tail.append(f"fade=t=out:st={dur - shot['fadeout']:.4f}:d={shot['fadeout']}")
    tail.append("format=yuv420p")
    chains.append(f"[{last}]{','.join(tail)}[vout]")
    fade_a = 0.012
    chains.append(f"[0:a]aresample=48000,apad=whole_dur={dur:.4f},atrim=end={dur:.4f},asetpts=PTS-STARTPTS,"
                  f"afade=t=in:st=0:d={fade_a},afade=t=out:st={dur - fade_a:.4f}:d={fade_a}"
                  f"{',volume=0' if shot.get('mute') else ''}[aout]")
    crf = "20" if preview else "11"
    cmd = ["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(chains), "-map", "[vout]", "-map", "[aout]",
           "-c:v", "libx264", "-preset", "veryfast", "-crf", crf, "-pix_fmt", "yuv420p", "-r", str(FPS),
           "-c:a", "pcm_s16le", "-ar", "48000", "-frames:v", str(dur_frames), out]
    run(cmd)
    return out


def make_audio(files: list[tuple[dict, str]], work: str, final: str) -> None:
    """The SFX track (the shots' own audio), the music bed and the mix; writes <work>/audio/mix.wav."""
    adir = os.path.join(work, "audio")
    os.makedirs(adir, exist_ok=True)
    concat_list = os.path.join(adir, "shots.txt")
    with open(concat_list, "w") as f:
        for _, path in files:
            f.write(f"file '{path}'\n")
    sfx = os.path.join(adir, "sfx.wav")
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", concat_list, "-vn", "-c:a", "pcm_s16le", "-ar", "48000", sfx])
    # Times of every accent (the shots that were skipped, missing clips, are simply not in the list).
    t = 0.0
    accents: list[dict] = []
    for shot, _ in files:
        for a in shot.get("sfx", []):
            accents.append(dict(a, at=t + a["at"]))
        t += frames_for(shot["_dur"]) / FPS
    total = t
    # Music: ONE track, the game's combat track, from its first beat, under the whole trailer: faded in at the start,
    # faded out over the end card (the trailer is shorter than the track, so it needs no loop).
    music = os.path.join(adir, "music.wav")
    combat = os.path.join(MUSIC_DIR, "music_combat.ogg")
    run(["ffmpeg", "-v", "error", "-y", "-i", combat, "-af",
         f"atrim=start={COMBAT_FIRST_BEAT}:end={COMBAT_FIRST_BEAT + total + 0.05:.4f},asetpts=PTS-STARTPTS,"
         f"afade=t=in:st=0:d={MUSIC_FADE_IN},afade=t=out:st={total - MUSIC_FADE_OUT:.4f}:d={MUSIC_FADE_OUT},aresample=48000",
         "-t", f"{total:.4f}", "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", music])
    # Accents (the game's own sounds), laid on the SFX track's timeline.
    mix_inputs = ["-i", music, "-i", sfx]
    filters = [f"[0:a]volume={MUSIC_DB}dB[m]", f"[1:a]volume={SFX_DB}dB[s]"]
    labels = ["[m]", "[s]"]
    for i, a in enumerate(accents):
        path = os.path.join(SFX_DIR, a["f"] + ".ogg")
        mix_inputs += ["-i", path]
        chain = "aresample=48000,aformat=channel_layouts=stereo"
        start = a["at"]
        if a.get("rise"):
            # A riser: the sound slowed down to [rise] seconds, fading in, ending where the accent's time is.
            src_len = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                                           capture_output=True, text=True).stdout.strip())
            factor = src_len / a["rise"]
            tempos = []
            while factor < 0.5:
                tempos.append("atempo=0.5")
                factor /= 0.5
            tempos.append(f"atempo={factor:.4f}")
            chain += "," + ",".join(tempos) + f",afade=t=in:st=0:d={a['rise']}:curve=qsin"
            start = max(a["at"] - a["rise"], 0.0)
        chain += f",adelay={int(start * 1000)}|{int(start * 1000)},volume={a['db']}dB"
        filters.append(f"[{i + 2}:a]{chain}[x{i}]")
        labels.append(f"[x{i}]")
    filters.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0:duration=longest,"
                   f"atrim=end={total:.4f},loudnorm=I={TARGET_LUFS}:TP=-1.5:LRA=9,aresample=48000[mix]")
    mix = os.path.join(adir, "mix.wav")
    run(["ffmpeg", "-v", "error", "-y"] + mix_inputs + ["-filter_complex", ";".join(filters), "-map", "[mix]",
         "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", mix])


def final_encode(files: list[tuple[dict, str]], work: str, out: str, preview: bool) -> None:
    adir = os.path.join(work, "audio")
    concat_list = os.path.join(adir, "shots.txt")
    mix = os.path.join(adir, "mix.wav")
    crf = "24" if preview else "18"
    preset = "veryfast" if preview else "medium"
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", concat_list, "-i", mix, "-map", "0:v", "-map", "1:a",
         "-c:v", "libx264", "-preset", preset, "-crf", crf, "-maxrate", "8000k", "-bufsize", "16000k", "-pix_fmt", "yuv420p",
         "-profile:v", "high", "-level", "4.2", "-movflags", "+faststart", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", "-shortest", out])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--out", default=None)
    ap.add_argument("--preview", action="store_true", help="faster, lower quality intermediates")
    ap.add_argument("--only", default="", help="comma separated shot numbers to (re)build; the rest are reused")
    ap.add_argument("--list", action="store_true", help="print the shot list with the available clips and exit")
    args = ap.parse_args()
    work = os.path.abspath(args.work)
    os.makedirs(os.path.join(work, "shots"), exist_ok=True)
    marks = Marks(work)
    resolve(SHOTS)
    if not args.list:
        # Every movie must be 1920x1080 (Movie Maker records the window size: see the override.cfg note in README.md).
        for path in sorted({c["avi"] for c in marks.clips.values()} | {os.path.join(work, "cards", f"cards_{k}.avi") for k in ("text", "dim")}):
            if not os.path.exists(path):
                continue
            size = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=width,height", "-of",
                                   "csv=p=0:s=x", path], capture_output=True, text=True).stdout.strip()
            if size != "1920x1080":
                raise SystemExit(f"{path} is {size}, not 1920x1080: render it again (make_trailer.sh --force <take>)")
    if args.list:
        t = 0.0
        for i, s in enumerate(SHOTS):
            clip = marks.clips.get(s["src"])
            have = f"{clip['frames'] / FPS:.1f}s available" if clip else "MISSING"
            d = s["_dur"]
            print(f"{i:2d} {t:6.2f}s +{d:4.2f}s  {s['src']:34s} {have}")
            t += d
        print(f"total {t:.1f} s")
        return
    only = {int(x) for x in args.only.split(",") if x.strip()} if args.only else None
    built: list[tuple[dict, str]] = []
    for i, s in enumerate(SHOTS):
        name = s["src"].replace("/", "_")
        path = os.path.join(work, "shots", f"{i:02d}_{name}.mkv")
        if only is not None and i not in only and os.path.exists(path):
            built.append((s, path))
            continue
        print(f"shot {i:2d}: {s['src']} ({s['beats']} beats)")
        res = build_shot(i, s, marks, work, args.preview)
        if res:
            built.append((s, res))
    if not built:
        raise SystemExit("nothing to assemble")
    print("audio ...")
    make_audio(built, work, args.out or "")
    out = args.out or os.path.join(work, "smartonion_trailer.mp4")
    print("final encode ...")
    final_encode(built, work, out, args.preview)
    print("wrote", out)


if __name__ == "__main__":
    main()
