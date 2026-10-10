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
   → run (a new join or an unready cancels the countdown). B with nobody joined → MENU.
   The join press is swallowed (`PlayerInput.swallow()`): it never also readies the player,
   and navigation waits until the stick is neutral. Slots of unplugged pads are pruned
   (`PlayerManager.prune_disconnected()`) when the lobby opens / resets and every frame
   while it is open, so a dead controller can never block the countdown or Back.
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
   The menu ignores navigation until the stick has been neutral once (`PlayerInput.nav_held()`),
   so a stick held during play cannot move the selection. Resume unpauses; "Quit to Menu"
   needs a second press ("Are you sure? Press again") and then ends the run
   (`RunState.end_run(false)`) and goes to MENU.
   **Disconnects:** `PlayerManager.device_disconnected` during a run → pause + HUD notice;
   a wave never starts while a joined pad is unplugged (`Main.start_wave` pauses at once).
   While any joined pad is unplugged, START / B / Resume do nothing; the PauseMenu offers
   "Continue without Pn" → `Main.drop_player(slot)` frees that hero, `PlayerManager.leave`,
   rebinds the HUD and resumes (nobody left → LOBBY; the rest all downed → defeat).
   `device_reconnected` → notice hidden (the player resumes with START).
7. `RunState.leveled_up` during a wave → `Vfx.level_up_burst` on every living player (the HUD
   shows the "LEVEL UP!" banner by itself; each Player grows its temporary `&"level"` bonus,
   see Combat model).

## Combat model

- Player stats: `StatBlock` with sources `&"class"` (ClassData.base_stats),
  `&"weapon:main"`, `&"weapon:off"` (WeaponData.bonus_stats). Max HP = 10 + Stamina.
- Team level: a run starts at level 1 (`RunState.START_LEVEL`, WoW style); the n-th
  level-up needs `(n + 3)^2` XP × the co-op multiplier (`RunState.xp_needed_for_level`, so
  1 → 2 needs 16 solo); talent points from level 10 (`talent_points_earned`).
- **TEMPORARY placeholder until the M4 level-up cards:** every team level gained above the
  starting level gives every player +1 Stamina (+1 Max HP) and +4% damage via the source
  `&"level"` (`Player.LEVEL_*`; nothing at level 1; applied in `Player.create` for the current
  level and on `RunState.leveled_up`, current HP rises by the Max HP gained). Remove it when
  the level-up cards replace it.
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
  `CombatMath.incoming_damage` (not rounded – small Armor / Versatility / Avoidance values
  count; at least 1); i-frames `INVULNERABLE_AFTER_HIT`. HP may be fractional: only the
  displayed numbers are rounded (floating text to one decimal, unit frames round up).
- Enemy stats at wave w (GDD 9, additive): HP `data.hp_at_wave(w) * RunState.coop_hp_mult()`
  = `max_hp * (1 + hp_growth * (w - 1)) * coop`, contact / projectile damage
  `base * (1 + damage_growth * (w - 1))`; `EnemyData.hp_growth` = 0.12 and `damage_growth`
  = 0.08 by default (a future DifficultyData may override them).
- On death: `RunState.record_kill(killer_index)`, a `Pickup.create(data.gold, data.xp)` drops,
  `died` is emitted. Damage dealt by players is recorded with `RunState.record_damage`
  (`WeaponRunner.apply_hit`: only the HP the enemy had left, overkill does not count).
- Pickups fly to the nearest living player inside that player's `stats.pickup_range()`
  (Pickup Range is a percent stat: `BASE_PICKUP_RANGE * (1 + raw / 100)`);
  gold → `RunState.add_gold_for(slot_index, gold, Gold Find %)`, which keeps each slot's
  fractional remainder so +10% on ten 1-gold coins pays 11; xp → `RunState.add_xp(xp)`.
  Loot banked at the wave end (`collect_to_bank`, no collector) gets **no** Gold Find.

### Hot-path helpers (scenes/enemies/, static state, no autoload)

- Enemies collide with the **world only** (layer 3, mask 1). Crowd separation comes from
  `EnemyGrid` – a spatial hash of group `&"enemies"` (sorted cell keys, cells ≥ 1.2 m) built
  lazily once per physics tick: every touching pair is evaluated once per build and each
  enemy slides along touching neighbours and pushes itself out of overlaps
  (`EnemyGrid.crowd_velocity`). In the open field (a per-tick shape query confirms the arena
  interior holds no world collider) an enemy moves directly; near walls it uses move_and_slide.
- The same grid answers `Projectile` sweeps / explosions (`gather_touching`) and
  `WeaponRunner` targets / melee arcs (`nearest`, `gather_around`): queries widen by the
  enemies' possible drift since the build and test live positions, so results equal a full
  scan, in group order. A `WeaponRunner` with nothing in range searches again every
  `NO_TARGET_RETRY` (0.1 s) or at once when the enemy count changes.
- `LivingPlayers`: per-tick snapshot of the living players (positions, pickup range²) read by
  every enemy (target / contact) and idle pickup; contact hits and enemy projectiles mark it
  dirty. With ≥ `Pickup.IDLE_STAGGER_THRESHOLD` pickups, idle ones look for a collector every
  `IDLE_CHECK_TICKS` ticks. Tests that teleport enemies within one frame call
  `EnemyGrid.mark_dirty()`.

## Waves (WaveDirector)

- Duration `RunState.wave_duration(w)` (GDD 1): waves 1–10 `min(60, 20 + 5 * (w - 1))` s,
  above 10 `60 + 10 * (w - 10)` s (11 → 70 s, 15 → 110 s, 20 → 160 s, 25 → 210 s; a full
  run is 42 minutes of fighting). Spawn budget per second
  `(0.9 + 0.22 * (w - 1)) * RunState.coop_count_mult()`; weighted pick among enemies with
  `first_wave <= w`; group size in `[group_min, group_max]`; position = random arena point
  ≥ 6 m from every living player, preferably on screen outside the HUD
  (`CameraRig.get_safe_ground_rect()`; 16 tries there, then 8 anywhere in the arena);
  `Vfx.spawn_telegraph` (red rune with a white-hot core, readable without colour) 1 s before
  the group appears.
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
**Determinism:** bots decide in `BotInput.think(delta)`, called by
`PlayerManager._physics_process` once per unpaused physics tick (`process_physics_priority`
-1000, before the heroes move); `poll()` only handles per-frame button / nav edges. Main
counts `WAVE_END_DELAY` in physics ticks. With the engine flag `--fixed-fps 60` the same
`--seed` reproduces a smoke run exactly (same kills, gold, downs); without it the camera
(updated per rendered frame) can shift the on-screen spawn-point preference slightly.

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
  - `OnionModel.set_tag("P1")` – player marker above the head: a nameplate diamond in the
    player colour with the slot label, fixed screen size, no depth test (shows through
    crowds). `Player.create` sets it; "" hides it (lobby previews). Over a ghost it bobs and
    is lifted above the "Resurrecting" cast bar. Downed: the player-colour ring stays and
    pulses, the revive circle is tinted with the ghost's own colour, ghost alpha 0.6.
  - `Mats.set_ring_stroke(node, amount)` – dark outline + white inner stroke on a ground
    ring (player rings use it, so the player colour reads on any ground / class colour).
  - Heroes never fully overlap: `Player.separation_offset` – a soft push (no physics
    collision) when two bodies are closer than `SEPARATION_DISTANCE`.
  - Damage numbers: `Vfx.damage_number(target, pos, amount, color, size)` – hits on the same
    enemy within `Vfx.MERGE_WINDOW` (0.25 s) add up on one number that pops again; normal
    hits small (0.6) and translucent, crits 1.1; at most `Vfx.MAX_TEXTS` (28) texts (+8 for
    crits); WoW-like pop-in and sideways arc. A hero's own numbers (damage taken, heals,
    Dodge) start beside its head (`Player.self_text_position`), alternating sides.
  - Explosions: a short faint flash (`Vfx.EXPLOSION_FLASH_*`: alpha 0.45, 0.6 × radius,
    gone in 0.15 s); the ground ring and embers carry the blast so targets stay visible.
  - Enemy projectiles (`ProjectileVisual.build(..., enemy = true)`): 1.6× size, red-orange
    halo and a short trail, fast spin – a different hue family from the heroes' class-
    coloured bolts.
  - Camera framing keeps heroes out from under the HUD: per-side margins `FRAME_MARGIN`
    (sides), `FRAME_MARGIN_BOTTOM` and `CameraRig.top_margin(distance)` (grows with the zoom –
    the wave / timer plaque covers a fixed share of the screen – capped so the whole arena
    still fits at `MAX_DISTANCE`). `CameraRig.safe_ground_rect()` / `get_safe_ground_rect()`
    is the visible ground outside the HUD (spawn preference, ghost walk area).
  - `CameraRig.get_walk_rect(player)` – shared screen (GDD 13): the rectangle a player may
    walk in so nobody leaves the screen once the camera is fully zoomed out. `Player` clamps
    its motion to it every tick (when `Arena.current.camera` is in the tree) and slides
    along the edge (`Player.clamp_motion_to_rect`: a body already outside is never pushed,
    only kept from going further out). For living players it binds only when the team
    spreads wider than the fully zoomed-out view (never in the MVP arena: the whole arena
    fits at `MAX_DISTANCE`); a ghost, which the camera does not follow, is kept inside the
    current view, out from under the HUD (`safe_ground_rect`).
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
- `Hud`: listens to `RunState` (wave, gold with a count-up and one "+N" floater right of the
  coin that sums every pickup while it shows – `FLOATER_TIME` 0.6 s after the last one –, XP,
  level up → `show_banner("LEVEL UP!")`) by itself; Main calls `bind_players(players)` after
  spawning and connects `WaveDirector.wave_timer_changed` → `set_wave_time` (red ≤ 5 s).
  Compact: `UnitFrame`s ~340 px wide at 80% panel opacity (smallest text 18 px, readable at
  720p), a compact wave / timer plaque, the XP bar as a thin segmented strip along the whole
  bottom edge (WoW style; level at its left end, "xp / needed XP" at its right end) and a slim
  translucent banner (`BANNER_HEIGHT` 100 px, ribbon alpha 0.38) anchored just below the
  plaque. Unit frames hide when their player is freed; while downed they show the revive
  progress.
- `Intermission.open(wave, level_ups)` / `GameOverScreen.open(victory)` / `PauseMenu.open(slot)`
  ignore the input of the frame they were opened on (Game Over: the first
  `INPUT_DELAY` = 1 s) and emit their signal once per `open()`. Intermission: humans ready with
  A / START, unready with B; bots (`is_bot()`) and unplugged devices are auto-ready.
  A "Next wave in 42 s" line counts down `Intermission.auto_continue_time` (static setting,
  default 60 s, ≤ 0 = off and hidden – the settings menu comes later); at 0 it emits
  `continue_requested` without the stragglers.
  PauseMenu: `process_mode` ALWAYS, only the pausing player navigates (falls back to any
  device if that player's own pad is unplugged), their B or any player's START resumes
  unless a joined pad is unplugged; it hides itself when it emits.
  GameOverScreen reads only joined slots' inputs while a human with a working device is
  joined (global `ui_accept` / any pad only with no / bot-only / all-unplugged slots).
- Keyboard join keys are one constant, `KeyboardInput.JOIN_KEYS` (Enter, Space, Keypad
  Enter, F) – the same keys as confirm (A). Intermission / Game Over / Pause
  also run with `process_mode` ALWAYS, so Main may pause the tree behind them.
- `set_backdrop_opacity(alpha)` on MainMenu / Lobby / Intermission / GameOverScreen lets the
  3D scene show through the dark vignette backdrop.
- Screenshots: `docs/screenshots/ui_lobby.png`, `docs/screenshots/ui_hud.png`
  (`--resolution 1920x1080 -- --demo --seed=3 --start-wave=10 --shot-time=18`).

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

## M2: items, loot and the shared shop (in progress)

New code (contracts fixed by the stub scripts, like M1):

```
core/items/   Items (enums, slot / material / Item Level helpers), ItemInstance, EnchantRoll,
              Equipment (equipped + 10-slot backpack, strict proficiency), ItemGenerator,
              ProcSystem (enchant / unique-effect procs)
core/shop/    Shop (shared stall: offers, locks, pings, reroll vote)
core/loot/    LootRoll (Need / Greed / Pass), LootDrops (drop rules on enemy death)
data/items/   ItemBase, AffixData, EnchantData, UniqueItemData resource classes
data/item_bases/ data/affixes/ data/enchants/ data/uniques/   content (.tres, loaded by Db)
scenes/pickups/loot_bag.gd             LootBag (item on the ground, rarity light beam)
scenes/ui/items/   ItemIcon, ItemTooltip, PlayerPanel (paper doll + backpack + trade)
scenes/ui/shop/    ShopPanel          scenes/ui/loot/   LootRollScreen
```

- Every Player owns an `Equipment`; the class's starting weapons are Common `ItemInstance`s.
  `Player.apply_equipment()` (on `equipment.changed`) sets one stat source per equipped
  position (`Items.source_for(slot)`), `&"armor_spec"` (+10% primary stat when all 8 armor
  slots hold the class's armor type) and calls `equip_weapons(main, off)`, which keeps the
  weapons' own `bonus_stats` as `&"weapon:main"` / `&"weapon:off"`.
- Weapon items carry a private `WeaponData` copy with the rarity damage multiplier applied,
  so `WeaponRunner` is unchanged.
- Proficiency is strict (GDD 5.3): `ItemInstance.can_be_used_by(class_data)`.
- `RunState.team_loot` collects looted items during a wave; `RunState.shop` is the shared
  shop for the whole run.
- Between waves (Intermission): loot roll (if any loot) → shared shop in the middle + one
  `PlayerPanel` per player in their corner → everyone ready (START) → next wave.
- All player-facing content pools filter through `Db.is_unlocked(id)` (M9 hook).

### M2 details

- **Shop** (`core/shop/shop.gd`): offers `2 + 2 x players`; every joined class is topped up to 2
  usable offers, the remaining "generic" offers have no class bias but are generated
  `usable_by` a random joined class (nothing in the stall is useless for the whole team); every
  new offer (round or reroll) rolls its rarity with the team's highest Fortune
  (`Shop.team_fortune`, still max Epic); `try_buy` → `Shop.BuyResult` (OK / SOLD / BACKPACK_FULL / NOT_ENOUGH_GOLD ...);
  any player may remove any lock; locks persist across rounds until toggled or sold; pings
  clear on a new round / reroll / sale; a reroll needs every joined human with a working pad
  to vote and charges only when at least one offer would change.
- **Loot** (`core/loot/`): drop chance `1.5% + Fortune / 10` percentage points (killer's
  Fortune), at most `1 + players` normal-enemy drops per wave; `LootDrops.on_enemy_killed`
  returns the `LootBag`. `LootRoll`: Need beats Greed, ties re-roll, undecided = Pass; a Need
  winner whose backpack is full gets the item sold as Greed instead.
- **Generator enchants**: Mighty (+Attack Power) / Arcane-touched (+Spell Power) follow the
  class when one is known (`class_data` bias or `usable_by`): magic-weapon classes (Mage,
  Warlock – `ItemGenerator.uses_spell_power`) mostly roll Spell Power, the others Attack Power
  (`power_enchant_weight` 1.9 / 0.1); items for nobody in particular keep both.
- **Weapons** (`Equipment`, `ItemTooltip`): a hero never ends up without an attacking weapon
  (shields / tomes do not attack): `equip` refuses a shield / tome that would push out the only
  weapon (a two-hander, `equip_disarms`), `unequip` the last equipped attacking weapon,
  `remove_from_backpack` (sell, trade) the last usable weapon of an unarmed hero
  (`is_last_weapon`); the panel greys those entries out with "You need a weapon" and its Equip
  entry says what else goes ("Replaces Bow", "Replaces Dagger + Dagger").
  `ItemTooltip.equipped_for_compare` compares a two-hander with main + off hand together
  (`ItemTooltip.EquippedPair`: summed stats and DPS) and an off-hand item or one-hander next to
  a two-hander with that two-hander; `upgrade_direction` never calls a disarming item an
  upgrade. Badges, bots (`Intermission.bot_equip_upgrades` / `bot_offer_choice`) and
  `LootRoll.bot_choice` all use this one test (stats + DPS, not Item Level).
- **Procs** (`core/items/proc_system.gd`, header documents the full vocabulary): building
  blocks bolt, chain, dot, nova, explode, extra_attack, buff, heal, drain, slow, stun, gold,
  resource (M3), shield, reflect, smite_heal, cheat_death; triggers on_hit (PPM), on_kill /
  when_struck (% chance), low_hp (`threshold` in HP percent), periodic, equip; `per_wave`
  limit; proc damage is never a weapon hit (no chains) and never crits. On-hit procs roll once
  per attack (the attacked target of a melee arc first; the first hit of a projectile fan /
  pierce / explosion – `WeaponRunner.ProcGate`); damage, Executioner / Slayer, leech and stuns
  stay per target.
- **Exotic stats**: Attack / Spell Power add `power x base weapon cooldown` per hit (magic
  weapons – non-physical `WeaponData.school` – use Spell Power); Executioner / Slayer multiply;
  Parry ≤ 50%, melee only, riposte counts as an extra attack; count stats
  (`Stats.INTEGER_STATS`) are whole numbers. Armor Specialization is computed after the
  weapons' bonus stats are applied (`Player.apply_equipment`).
- **Between waves** (`scenes/ui/intermission.gd`): LOOT phase (`LootRollScreen`, 15 s per
  item, hidden choices, bots `LootRoll.bot_choice`, solo Take / Sell / Leave) then MARKET
  (`ShopPanel` centred, one `PlayerPanel` per hero scaled into its corner with
  `tooltip_inside = true`). Per player: LB / RB switch focus shop ↔ own panel, A buys
  (hold when > 50% of the wallet), X lock, R3 / Tab ping, Y reroll vote, START ready, B
  unready unless the panel consumed it (`last_input_consumed`; the shop consumes the B that
  cancels a hold-to-buy); panel tabs on LT / RT. The 60 s
  auto-continue runs only in MARKET. The HUD is hidden during the intermission; the HUD shows a
  "Team Loot: N" counter during waves.
  - **Input guards** (co-op, one screen): the loot roll and the market swallow every human's
    held buttons / stick (`PlayerInput.swallow()`) when they open and when the market starts
    after the roll; A and X (buy / lock) are additionally ignored for
    `Intermission.MARKET_INPUT_LOCKOUT` (0.4 s) after the market starts, so a Need press or a
    stick push meant for the roll never buys or drifts the cursor. Y (Greed all remaining) is
    taken in every loot phase (result line and the first moments of an item included).
  - **Reroll votes** are re-evaluated every frame (`ShopPanel.process_votes` →
    `Shop.try_reroll`, votes of non-voters dropped by `Shop.prune_votes`), so a reroll also
    fires when the last missing voter unplugs / leaves or the gold arrives later.
  - **Hold-to-buy** remembers the offer's item uid + price and is cancelled by a reroll
    (`Shop.rerolled`), any change of the offer, B, or the player unplugging / leaving.
  - **Unplug / leave:** a pad that comes back is un-readied (auto-ready lasts only while it is
    unplugged); an unplugged player's shop cursor and tooltip are hidden;
    `PlayerManager.player_left` refreshes panels, chips, the shop cursors and the votes.
- **Bots** (smoke / demo): equip upgrades from the backpack, then buy every affordable offer
  that is an upgrade (cheapest first, one buy per bot per pass so the shared wallet is spread)
  and wear it; sell non-upgrades when the backpack is full (never the last weapon); Need only
  real upgrades (`LootRoll.bot_choice`). `SMOKE_RESULT` adds `items_bought`,
  `items_looted`, `loot_rolls`, `need_wins`, `greed_gold`.

## M3: classes – resources, abilities, Mastery

```
core/abilities/  AbilityRunner (per player, child "Abilities"), ClassResource, AbilityContext,
                 AbilityEffect (behaviour base), MasteryEffect (Mastery / pets / auras base),
                 AbilityArea (shared ground AoE: damage / slow / stun / heal ticks)
data/abilities/  AbilityData (.tres per ability)      data/resources/  ResourceData (.tres)
scenes/abilities/<class>/   per-class AbilityEffect / MasteryEffect scripts, VFX, pets
```

- `ClassData.resources` (primary first), `ClassData.abilities` ([0] = RT, [1] = LT),
  `ClassData.mastery` (script extending MasteryEffect), `mastery_text`.
- `AbilityRunner`: 4 slots (0 RT, 1 LT core; 2 RB, 3 LB learned in M4); reads
  `ability_just_pressed` in `_process`; cooldown = `cooldown x stats.cooldown_mult() x
  (1 - Cooldown Reduction%)`; resources tick in `_physics_process` (Resource Regen % scales
  gains, Haste scales `regen_uses_haste` resources); targeting is automatic (SELF,
  NEAREST_ENEMY, DENSEST_CLUSTER, MOVE_DIRECTION, ALLY with `prefer_downed`); bots
  (`BotInput`) auto-cast when `AbilityEffect.wants_auto_cast` (every 0.25 s); `is_ready()` is
  the cheap HUD check.
- Player hooks: weapon hits → `abilities.on_weapon_hit` (resources, Mastery), damage taken →
  `on_damage_taken`, kills → `on_kill`, `begin_wave` resets resources and cooldowns;
  `Player.outgoing_damage_mult(target, school, source)` multiplies weapon hits
  (`WeaponRunner.apply_hit`), procs / DoTs / abilities (`ProcSystem.deal_raw(..., source)`)
  by `MasteryEffect.damage_mult` and `Player.damage_mults` (named temporary buffs);
  `Player.forced_crits` = guaranteed crits for the next weapon hits.
- Item ability mods (GDD 5.5 class items): `unique_effect = &"ability_mod"`,
  `unique_params = {"ability": id, "mods": {...}}`; `Player.ability_mods(id)` merges them,
  `AbilityRunner.apply_mods` applies `<param>_add`, `<param>_pct`, other keys replace.
- Ability damage: use `CombatMath.weapon_hit_damage(player.main_hand, player.stats) x pct`
  for weapon-based abilities, `CombatMath.proc_damage(base, school, stats)` for spells, and
  deal it with `player.procs.deal_raw(enemy, amount, school, true, &"ability")`.
