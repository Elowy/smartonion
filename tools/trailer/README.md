# Gameplay trailer pipeline

Makes the Steam-page trailer (about 70 s, 1920x1080, 30 fps, H.264 + AAC) from the real game: bots play, Godot's
Movie Maker records, ffmpeg edits. Nothing in the game's gameplay code is changed; everything here is dev tooling.

```
tools/trailer/make_trailer.sh            # render what is missing, edit, encode
```

Output: `$TRAILER_WORK/smartonion_trailer.mp4` (default work directory `<repo>/build/trailer`, which is git-ignored).
No video file is ever committed.

## Requirements

- Godot 4.7.2 (`GODOT=/path/to/godot`, default `godot` on the PATH), run with the GL Compatibility renderer
- `xvfb-run` (a virtual display; Movie Maker renders offline, so software GL is fine, just slow), `ffmpeg`, `ffprobe`,
  `python3` (standard library only)
- about 20 GB of free disk space while rendering (the takes are intermediate MJPEG movies, deleted by you afterwards)
- time: the long take plays a whole 25-wave run (about 25-40 minutes); the other takes take a few minutes each

## What it does

1. **Cards** (`cards.gd`): the text cards in Cinzel (the game's title font) are rendered as two small movies, `text`
   (gold lettering on black) and `dim` (the darkening band). The edit adds the first and multiplies the second into any
   shot at any time, so cards can be moved without rendering gameplay again.
2. **Takes** (`trailer.gd`, `trailer_director.gd`, `trailer_takes.gd`, `trailer_shots.gd`): a take is one play session
   of the real game ([Main] with bots at the controllers, `--demo` pacing) with a "director" on top. The director plays
   the long stretches fast (up to 10x with the 3D view off, the movie frames are black and never used), then
   `begin_clip` / `end_clip` mark the frames of a shot in a marks file (`<take>.json`). It also gives the camera a
   different job (zoom-follow, close cut on a hero, dolly), hides the HUD, keeps the last hero standing from dying
   (no party wipe ends the run mid-shot), dresses heroes in their tier sets, drops a loot burst, queues a Legendary and
   the Artifact for the loot roll and drives the break screens (forge on a panel, talent tree, UI zoom). Takes:

   | take | what it records |
   |---|---|
   | `intro` | cold open: dolly from the warrior's face to the whole party fighting |
   | `classes_a` | 1-4 player co-op chaos (volcano) and close cuts on Warrior, Mage, Shaman |
   | `main` | a whole run (cemetery): dungeon, Morvain, loot roll, market (forge, talents), loot burst, Paladin / Rogue / Warlock / Hunter cuts, the climax, Vor'thalax |
   | `arenas` | the "Rolling the arena..." reel and a short look at each of the five arenas |
   | `sets` | the seven class tier sets in the studio-lit arena |
   | `endcard` | the hero behind the end card |

   Runs are seeded, so a take reproduces the same footage when rendered again with the same scripts (changing a script
   early in a take can change what happens later in it: bots and spawns react to the camera).
3. **Edit** (`edit.py`): cuts every shot of the **EDIT LIST** (at the top of `edit.py`) from its clip on the beat grid of
   the combat track (152 bpm, one bar = 4 beats), lays the cards over, builds the audio and encodes. The game's own
   sounds recorded by Movie Maker are the SFX track (the game's music is muted while recording); the music bed is the
   game's combat track; a few of the game's impact sounds
   accent the title and the bosses. ONE music track plays under the whole trailer (faded in at the start, out over the end
   card). Loudness is normalised (-15 LUFS) with a true-peak limit.

## Changing things

- **Shot list, durations, card timing, music switch, levels**: edit `SHOTS` and the mix constants at the top of
  `edit.py`, then `make_trailer.sh --edit-only` (a few minutes at most; no gameplay is rendered again).
  `python3 tools/trailer/edit.py --work $TRAILER_WORK --list` prints the shot list with the available clips.
- **A card's wording or look**: `CARDS` in `cards.gd`, then `make_trailer.sh --force cards` (renders the cards again, the
  edit follows).
- **A shot's content** (which wave, which class, camera, what is on screen): the take's function in `trailer_takes.gd`
  (shots are recipes from `trailer_shots.gd`), then `make_trailer.sh --force <take>`. `--t-name=value` flags rehearse a
  take on a short run (see the `main` header in `trailer_takes.gd`: `--start-wave=8 --dungeon=1 --t-dungeon-wave=8
  --t-climax-wave=13 --t-no-final ...`). A take can also be rendered in parts into `takes/main.avi`, `takes/main_cuts.avi`, ...
  with their marks files; the shot list then says `main_cuts/<clip>`.
- **A new take**: add it to `TAKES` in `trailer_takes.gd` (launch flags as for the game, see `scenes/main/launch_options.gd`)
  and to the list in `make_trailer.sh`, then use its clips in `SHOTS`.
- `--preview` renders the 3D view at half resolution (a quick look with the same cuts).

## Files

| file | purpose |
|---|---|
| `make_trailer.sh` | entry point: renders cards and takes (in parallel, `JOBS`), runs the edit |
| `edit.py` | the shot list and the ffmpeg edit (video, cards, music, mix, final encode) |
| `trailer.gd` | SceneTree entry of a take (`-s res://tools/trailer/trailer.gd -- --take=NAME`) |
| `trailer_director.gd` | fast-forward, clips, camera, HUD, guard, UI zoom |
| `trailer_takes.gd` | the takes |
| `trailer_shots.gd`, `trailer_gear.gd`, `trailer_stage.gd` | staging recipes, dressing heroes, the glamour-shot set |
| `cards.gd` | the text cards |

Movie Maker records the window size, which the project overrides to 1600x900: `make_trailer.sh` writes a temporary
`override.cfg` (1920x1080, MJPEG quality 0.93) next to `project.godot` and removes it when it ends.

## Rotate-device card (phones held upright)

`tools/trailer/rotate_card.py <out_dir>` renders the 3 s "Rotate your device" card (PIL, Cinzel from
`assets/fonts/`) as PNG frames. Put it in front of the finished cut with silent audio:

```
python3 tools/trailer/rotate_card.py /tmp/rotate
ffmpeg -framerate 30 -i /tmp/rotate/rotate_%03d.png -f lavfi -t 3 -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -i smartonion_trailer.mp4 -filter_complex "[0:v]format=yuv420p,setsar=1[cv];[2:v]setsar=1[tv];[cv][1:a][tv][2:a]concat=n=2:v=1:a=1[v][a]" \
  -map "[v]" -map "[a]" -c:v libx264 -preset slow -crf 21 -pix_fmt yuv420p -r 30 -c:a aac -b:a 192k -movflags +faststart smartonion_trailer_rotate.mp4
```
