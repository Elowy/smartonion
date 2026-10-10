# SmartOnion – working notes for Claude

Brotato-like, WoW-flavoured top-down arena survivor with 1–4 player local co-op.
The heroes are onions in WoW armour. Design: `docs/GDD.md` (Hungarian). Code structure and
module contracts: `docs/ARCHITECTURE.md`.

## Engine & commands

- Godot **4.7.2**, GDScript, renderer **GL Compatibility** (runs on low-end PCs and under Xvfb).
- Import (after adding files / scripts with new `class_name`):
  `godot --headless --path . --import`
- Unit tests (must stay green): `godot --headless --path . -s res://tests/run_tests.gd`
  (`-- --filter=<substring>` to run a subset)
- Smoke run (4 bots play N waves fast, exit code 1 on errors):
  `godot --headless --path . -- --smoke --waves=3`
  For bit-identical results with the same `--seed`, add `--fixed-fps 60` (engine flag, before
  `--path`): the camera moves per rendered frame and spawn points prefer the on-screen area.
- Screenshot (needs a virtual display):
  `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 -- --demo --screenshot=/tmp/shot.png --shot-time=8`

## Conventions

- Static typing everywhere (`var x: int`, `:=`, typed arrays / dictionaries). Tabs for indent.
- `class_name` for every reusable script; files `snake_case.gd`; signals in past tense.
- Entities are built in code through static `create(...)` factories (no hand-made .tscn needed).
- Ground plane is XZ, Y up, screen-up is **-Z**; input `Vector2(x, y)` → `Vector3(x, 0, y)`.
- Never read Godot's global `Input` actions for gameplay – go through `PlayerSlot.input`
  (`PlayerInput`); every player has their own device. Menus that any player may drive also use
  the per-slot inputs.
- Use `RunState.rng` for gameplay randomness (deterministic smoke runs).
- Content is data: classes / weapons / enemies are `.tres` files under `data/`, loaded by `Db`.
- UI text is **English**. No Blizzard trademarks (Azeroth, Murloc, Horde, Alliance, Thunderfury …).
- Placeholder art is procedural (primitives + `Mats` materials) until real models arrive.
