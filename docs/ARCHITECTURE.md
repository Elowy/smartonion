# SmartOnion – architecture

Scope of the first playable build (milestones **M0 + M1** of the GDD): 1–4 players join with
controllers / keyboard, pick a class, and fight 25 waves of enemies with auto-attacking
weapons, collecting gold (shared wallet) and XP (shared level). Between waves a simple
"ready up" screen. Shop, items, abilities and talents come in later milestones.

## Layout

```
autoload/   Db (data registry), PlayerManager (devices / slots), RunState (shared run state)
core/       Stats, StatBlock, CombatMath, PlayerSlot, input/ (PlayerInput + devices + bots)
data/       *_data.gd resource classes + classes/ weapons/ enemies/ .tres content
scenes/
  main/     Main – game flow state machine                         [integration]
  arena/    Arena – battlefield, walls, entities root               [visuals]
  camera/   CameraRig                                                [visuals]
  visuals/  Mats, OnionModel, EnemyModel, WeaponModel               [visuals]
  vfx/      Vfx – fire-and-forget effects                           [visuals]
  player/   Player, WeaponRunner, Projectile                        [player]
  enemies/  Enemy                                                    [enemies]
  pickups/  Pickup                                                   [enemies]
  waves/    WaveDirector                                             [enemies]
  ui/       UiTheme, MainMenu, Lobby, Hud, Intermission,            [ui]
            GameOverScreen, PauseMenu
tests/      run_tests.gd runner + test_*.gd (extend TestCase)
```

The public API of every module is fixed by the stub scripts committed with the foundation
(method names, signals, constants, static `create()` factories). Implementations may add
private members, helper scripts inside their own folder, and extra public helpers, but must
not rename or remove the contract members.

## Runtime flow

```
Main (Node, PROCESS_MODE_ALWAYS – drives the dev harness while the tree is paused)
├── Arena (Node3D, PAUSABLE)   – Arena.current
│   ├── environment, ground, walls, props
│   ├── CameraRig
│   └── entities (Node3D)      – players, enemies, projectiles, pickups, VFX
├── WaveDirector (Node, PAUSABLE)
├── HudLayer (CanvasLayer 10, PAUSABLE) / Hud
├── MenuLayer (20)          / MainMenu or Lobby
├── IntermissionLayer (30)  / Intermission      (ALWAYS)
├── GameOverLayer (40)      / GameOverScreen    (ALWAYS)
└── PauseLayer (50)         / PauseMenu         (ALWAYS)
```

States (`Main.State`): `MENU -> LOBBY -> WAVE -> WAVE_END -> INTERMISSION -> WAVE ... ->
GAME_OVER -> LOBBY`. Screens are created when their state starts and freed when it ends; the
run (arena, director, players, HUD, run screens) is built by `start_run()` and torn down by
`_teardown_run()`. Transitions triggered by UI signals are connected `CONNECT_DEFERRED`, so
the new screen never sees the button press that closed the old one.

1. **MENU** – MainMenu. Nobody has joined here, so entering MENU clears every slot. Play →
   LOBBY, Quit → quit.
2. **LOBBY** – the Lobby owns `PlayerManager.joining_enabled`. Each slot picks a class (◀ ▶),
   readies with A, leaves with B. All joined players ready → countdown → `start_requested`
   → run. B with nobody joined → MENU.
3. **RUN / WAVE n** – `RunState.start_run(count, seed)`, `Arena.create()`,
   `WaveDirector.create(arena)`, one `Player.create(slot)` per slot under `arena.entities`
   (`Main._spawn_player` is the single place a slot becomes a hero – the future M9 loadout
   hook), `hud.bind_players(players)`, `wave_timer_changed → hud.set_wave_time`. Every wave:
   players back on `arena.get_player_spawn_points()`, `player.begin_wave()` (heal / 50%
   return), `wave_director.start_wave(n)`, `arena.camera.snap()`, "Wave n" banner.
   - A player at 0 HP is **downed**; a living teammate standing within `REVIVE_RADIUS` for
     `REVIVE_TIME` (5 s) revives them at 30% HP. Every additional living reviver in the
     circle adds +50% speed (`Player.revive_speed(n)`: 1 → 1×, 2 → 1.5×, 3 → 2×); with
     nobody in the circle the progress drains slowly (`REVIVE_DECAY_PER_SECOND`); taking
     damage never interrupts it. Cast bar in the reviver's colour with the time left at the
     current speed (`Player.revive_seconds_left()`), channel beam; on completion
     `Vfx.resurrect_column` at the feet, "Resurrected!" and `INVULNERABLE_AFTER_REVIVE`
     (1 s). Everybody downed at once → GAME_OVER (defeat). Solo: downed = defeat.
4. **wave_cleared** (the director already stopped: enemies despawned, loot banked) →
   **WAVE_END** ("Wave cleared!" banner, `Main.WAVE_END_DELAY` = 1.6 s, players can still
   move) → if n == 25 → GAME_OVER (victory), else **INTERMISSION** (tree paused,
   `Intermission.open(n, RunState.pending_level_ups)`, players ready with A, bots and unplugged
   devices auto-ready; after `Intermission.auto_continue_time` – default
   `AUTO_CONTINUE_TIME` = 60 s, ≤ 0 switches it off – the next wave starts even if not
   everyone is ready) → `pending_level_ups = 0` (choices arrive in M4) → wave n+1.
5. **GAME_OVER** – `RunState.end_run(victory)`, tree paused, HUD hidden,
   `GameOverScreen.open(victory)`. A / START → **LOBBY with the same players** (ready again);
   the main menu only through the lobby's Back.
6. START on any player's device during WAVE / WAVE_END → PauseMenu (`get_tree().paused`).
   Resume unpauses; "Quit to Menu" ends the run (`RunState.end_run(false)`) and goes to MENU.
   `PlayerManager.device_disconnected` during a run → pause + HUD notice;
   `device_reconnected` → notice hidden (the player resumes with START).
7. `RunState.leveled_up` during a wave → `Vfx.level_up_burst` on every living player (the HUD
   shows the "LEVEL UP!" banner by itself).

## Combat model

- Player stats: `StatBlock` with sources `&"class"` (ClassData.base_stats),
  `&"weapon:main"`, `&"weapon:off"` (WeaponData.bonus_stats). Max HP = 10 + Stamina.
- `WeaponRunner` (one per weapon that `attacks()`): cooldown =
  `CombatMath.weapon_cooldown`; target = nearest living enemy within `attack_range`.
  - `MELEE_ARC`: every enemy within `attack_range + enemy.radius` and inside `arc_degrees`
    of the swing direction is hit.
  - `PROJECTILE`: spawns `Projectile.create(TEAM_PLAYERS, ...)`; `aoe_radius > 0` explodes.
  - Damage = `CombatMath.weapon_hit_damage`, crit via `CombatMath.roll_crit` → × `crit_mult`,
    `stun_chance` → `enemy.apply_stun(stun_duration)`. After each hit
    `player.on_hit_dealt()` (leech: `CombatMath.roll_leech` → heal 1).
- Enemies deal contact damage when within `enemy.radius + Player.RADIUS` (per-enemy cooldown
  1 s) via `player.take_damage(dmg, CombatMath.KIND_MELEE, enemy)`; ranged enemies throw
  `Projectile.create(TEAM_ENEMIES, ...)` with kind `KIND_PROJECTILE`.
- `Player.take_damage`: dodge roll → "Dodge" text; shield `block_chance` → half damage;
  `CombatMath.incoming_damage`; i-frames `INVULNERABLE_AFTER_HIT`.
- Enemy stats at wave w: `data.hp_at_wave(w) * RunState.coop_hp_mult()`,
  `data.contact_damage_at_wave(w)`, `data.projectile_damage_at_wave(w)`.
- On death: `RunState.record_kill(killer_index)`, a `Pickup.create(data.gold, data.xp)` drops,
  `died` is emitted. Damage dealt by players is recorded with `RunState.record_damage`.
- Pickups fly to the nearest living player inside that player's `stats.pickup_range()`;
  gold → `RunState.add_gold(CombatMath.gold_with_find(gold, player.stats))`, xp →
  `RunState.add_xp(xp)`.

## Waves (WaveDirector)

- Duration `RunState.wave_duration(w)` (GDD 1): waves 1–10 `min(60, 20 + 5 * (w - 1))` s,
  above 10 `60 + 10 * (w - 10)` s (11 → 70 s, 15 → 110 s, 20 → 160 s, 25 → 210 s; a full
  run is 42 minutes of fighting). Spawn budget per second
  `(0.9 + 0.22 * (w - 1)) * RunState.coop_count_mult()`; weighted pick among enemies with
  `first_wave <= w`; group size in `[group_min, group_max]`; position = random arena point
  ≥ 6 m from every living player; `Vfx.spawn_telegraph` 1 s before the group appears.
- At most `MAX_ENEMIES` alive. When the timer ends: remaining enemies `despawn()` (no loot),
  pickups `collect_to_bank()`, `wave_cleared` emitted.
- Waves 10 / 20 / 25 (boss / elite) are regular waves until milestone M6.

## Command line (Main)

Parsed by `LaunchOptions` from `OS.get_cmdline_user_args()` (everything after `--`).

| Flag | Meaning |
|---|---|
| `--smoke` | Bots, menus skipped, `Engine.time_scale = 4` (with 4× physics ticks, so the simulation step stays 1/60 s of game time), plays `--waves=N` waves (default 3), prints one line `SMOKE_RESULT {json}` and quits. Exit 0 only when every wave completed and no engine / script error was logged (`ErrorCounter` is an `OS.add_logger` logger); exit 1 on errors, on a timeout (real-time watchdog) or – with `--allow-defeat` – on a defeat. Without `--allow-defeat` a full party wipe is counted (`wipes`) and everybody is revived, so later waves still get exercised. |
| `--demo` | Bots at normal speed, endless (the next run starts 6 s after a Game Over). |
| `--players=N` | Bot count 1–4 (default 4); classes cycle through `Db.class_ids`. |
| `--seed=N` | `RunState` seed and bot seeds (smoke runs default to seed 1). |
| `--start-wave=N` | First wave of the run (testing later waves). |
| `--screenshot=PATH` `--shot-time=S` | Saves the viewport as PNG after S seconds of game time since the run started (since boot for the menu / lobby) and quits. Needs a display: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 -- ...` |
| `--view=NAME` `--view-time=S` | Dev: reach a screen for a screenshot – `menu`, `lobby` (bots join, P1 ready), `game`, `intermission` (the wave timer is run out), `game_over`, `victory`, `pause`; forced at S seconds of game time (default: shot time − 3 s) and held open. |
| `--time-scale=X` | Overrides the time scale. |

`SMOKE_RESULT` keys: `result` (completed / defeat / timeout), `waves_completed`, `kills`, `gold`,
`level`, `players_downed`, `revives`, `wipes`, `errors`, `warnings`, `error_samples`,
`game_time`, `real_time`, and `perf` – physics tick times measured by `PhysicsClock` and
grouped by living enemies (`RunPerf`): `physics_ms_avg`, `physics_ms_at_peak` (ticks with
≥ 80% of the peak enemy count), `script_ms_at_peak`, `physics_ms_max`, and
`monitor_physics_ms_at_peak` (`Performance.TIME_PHYSICS_PROCESS`, which is the slowest tick of
the last second). Each cleared wave also prints a `SMOKE wave n cleared ...` line.
Bots (`BotInput`) kite by weapon reach (melee heroes close in, back off when hurt or
crowded), avoid walls, stay near the team and run to downed teammates when it is safe.

Screenshots of every screen: `docs/screenshots/{menu,lobby,gameplay,intermission,game_over}.png`
(`--view=lobby --players=3`, `--demo --seed=5 --start-wave=4 --shot-time=12`,
`--view=intermission --start-wave=3 --shot-time=16`, `--view=game_over --start-wave=3 --shot-time=16`).

## Visuals (procedural art)

- No imported assets yet: `MeshKit` merges primitives / lathes / extrusions into one
  vertex-coloured `ArrayMesh` per prop, enemy or weapon (cached by key, shared by every
  instance) drawn with `Mats.toon_vc()`. All toon materials share a few cached shaders
  (two-band toon light, warm rim, inverted-hull outline as `next_pass`; the outline is drawn
  in the alpha pass only, so it costs nothing in the shadow pass).
- No `instance uniform`s (the Compatibility renderer only fits ~256 instances using them):
  per-node looks swap in cached material variants – `Mats.set_overlay` (hit flash / wind-up
  tint) – or use per-node materials (`Mats.set_ring` ground rings, `Mats.set_cast_bar`).
- Public helpers beyond the stubs:
  - `OnionModel.set_revive_progress(progress, reviver_color, seconds_left)` – revive ring arc
    plus a WoW-like "Resurrecting" cast bar above the ghost, in the reviver's colour.
  - `OnionModel.set_channel_target(downed_player)` / `null` – the reviver raises golden,
    glowing hands and a light beam connects it to the ghost.
  - `Vfx.resurrect_column(feet_pos)` – shaft of light from the sky when a revive completes.
  - `CameraRig.get_walk_rect(player)` – shared screen (GDD 13): the rectangle a player may
    walk in so nobody leaves the screen once the camera is fully zoomed out. `Player` clamps
    its motion to it every tick (when `Arena.current.camera` is in the tree) and slides
    along the edge (`Player.clamp_motion_to_rect`: a body already outside is never pushed,
    only kept from going further out). For living players it binds only when the team
    spreads wider than the fully zoomed-out view (never in the MVP arena: the whole arena
    fits at `MAX_DISTANCE`); a ghost, which the camera does not follow, is kept inside the
    current view.
  - `Arena.get_view_rect()` – what the camera may show (smaller margin towards the camera).
- Art showcase (dev tool, renders a PNG under Xvfb):
  `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 -s res://tools/showcase/showcase.gd -- --view=gameplay --out=/tmp/shot.png`
  (views: gameplay, live, onions, enemies, weapons, arena, revive). Latest gameplay view:
  `docs/screenshots/visuals_showcase.png`.

## UI (scenes/ui/)

- Every screen is a full-rect `Control` built in code (`create()`), themed by the cached
  `UiTheme.get_theme()` (WoW look: `UiFrameStyle` stone frames with gold borders, inner
  shadow and corner studs; parchment tooltips; outlined default font, emboldened via
  `FontVariation` for titles). Layout is anchors + containers on the 1920x1080
  `canvas_items` canvas, so it holds at 720p, 4:3 and 21:9. Icons, button glyphs, bars and
  portraits are drawn procedurally (`UiIcon`, `UiGlyph`, `UiBar`, `UiPortrait`).
- Input: joined players drive menus only through their own `PlayerSlot.input`. Before anyone
  joined (main menu, empty lobby) Godot's `ui_*` actions are used for keyboard / d-pad focus
  navigation, and `UiPads` reads A / B / START on every controller (the default `ui_accept`
  / `ui_cancel` have no pad buttons). Prompts follow the player's device
  (`UiGlyph.for_input`: key caps for the keyboard, A / B / X / Y for controllers). Because
  the keyboard maps Esc to both B and START, screens check B before START.
- `MainMenu`: `play_pressed` / `quit_pressed`; `activate_focused()` = controller A.
- `Lobby`: `PlayerManager.joining_enabled` is true while it is visible in the tree (armed only
  after the join button that opened it is released); showing it clears every slot's `ready`.
  ◀ ▶ = `Db.cycle_class`, A toggles ready, START readies, B unreadies or leaves. Everyone
  ready → `COUNTDOWN_TIME` (3 s) countdown, cancelled by an unready or a join →
  `start_requested` (once; joining is switched off). B / Esc with nobody joined →
  `back_requested`. A controller unplugged in the lobby leaves its slot. Each card has a live
  `OnionPreview` (SubViewport with its own World3D).
- `Hud`: listens to `RunState` (wave, gold with a count-up and "+N" floater, XP, level up →
  `show_banner("LEVEL UP!")`) by itself; Main calls `bind_players(players)` after spawning and
  connects `WaveDirector.wave_timer_changed` → `set_wave_time` (red ≤ 5 s). Unit frames hide
  when their player is freed; while downed they show the revive progress.
- `Intermission.open(wave, level_ups)` / `GameOverScreen.open(victory)` / `PauseMenu.open(slot)`
  ignore the input of the frame they were opened on (Game Over: the first
  `INPUT_DELAY` = 1 s) and emit their signal once per `open()`. Intermission: humans ready with
  A / START, unready with B; bots (`is_bot()`) and unplugged devices are auto-ready.
  A "Next wave in 42 s" line counts down `Intermission.auto_continue_time` (static setting,
  default 60 s, ≤ 0 = off and hidden – the settings menu comes later); at 0 it emits
  `continue_requested` without the stragglers.
  PauseMenu: `process_mode` ALWAYS, only the pausing player navigates, their B or any
  player's START resumes; it hides itself when it emits. Intermission / Game Over / Pause
  also run with `process_mode` ALWAYS, so Main may pause the tree behind them.
- `set_backdrop_opacity(alpha)` on MainMenu / Lobby / Intermission / GameOverScreen lets the
  3D scene show through the dark vignette backdrop.
- Screenshots: `docs/screenshots/ui_lobby.png`, `docs/screenshots/ui_hud.png`.

## Forward compatibility: meta-progression (GDD chapter 17, milestone M9)

Meta-progression ships last, but every system built before it must already allow it
without rewrites:

- **Stable content ids.** Every class / weapon / enemy / item base / affix / enchant /
  ability / talent / glyph has a permanent `id: StringName`. Never rename a shipped id
  (saves, unlocks and achievements reference them).
- **Unlock gating in content pools.** Code that draws from a content pool (level-up ability
  cards, shop offers, loot tables, lobby class list, difficulty list) filters through one
  place – a future `Unlocks.is_unlocked(profile, id)` check (everything returns true until
  M9). Do not iterate `Db.*` directly for player-facing pools without that hook.
- **Run statistics as events.** Notable run events (kill, boss kill, elite kill, goblin kill,
  item won by Need, legendary looted, player downed / revived, wave cleared, run won / lost,
  difficulty) go through `RunState` signals / counters, so Class XP, Valor and achievements
  can be computed from them later. Keep `RunState` per-player stats keyed by slot index.
- **One main profile.** All persistent progress lives in a single main profile (the game
  save) and is keyed **by class id** (Class Level, glyphs, heirlooms) or account-wide
  (achievements, transmog, Valor) – never by slot index or device. Any player who picks a
  class gets that class's level and unlocks; Class XP from a run is credited per class played
  (summed when two players used the same class).
- **Run start loadout.** Starting a run goes through one function (class, starting weapon,
  heirloom, glyphs, transmog) so M9 can inject choices from the lobby.
- **Versioned saves.** The end-of-wave autosave and future profile saves use a versioned
  format (`{"version": N, ...}`) with migration, stored under `user://`.
- **Power budget.** Balance Normal difficulty with zero meta-progression; meta bonuses add
  at most ~10% power.
