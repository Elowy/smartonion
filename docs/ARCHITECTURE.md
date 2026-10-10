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
Main (Node)
├── MainMenu / Lobby / Intermission / GameOverScreen / PauseMenu  (CanvasLayer UI)
├── Arena (Node3D)             – Arena.current
│   ├── environment, ground, walls, props
│   ├── CameraRig
│   └── entities (Node3D)      – players, enemies, projectiles, pickups, VFX
├── WaveDirector (Node)
└── Hud (CanvasLayer UI)
```

1. **MENU** – MainMenu. Play → LOBBY.
2. **LOBBY** – `PlayerManager.joining_enabled = true`. Each slot picks a class (◀ ▶), readies
   with A, leaves with B. All joined players ready → `RunState.start_run(count)` → RUN.
3. **RUN / WAVE n** – Main spawns one `Player` per slot at `arena.get_player_spawn_points()`,
   calls `player.begin_wave()`, `wave_director.start_wave(n)`. HUD shows frames / timer.
   - A player at 0 HP is **downed**; a living teammate standing within `REVIVE_RADIUS` for
     `REVIVE_TIME` revives them at 30% HP. Everybody downed at once → GAME_OVER (defeat).
     Solo: downed = defeat.
4. **wave_cleared** → `wave_director.stop()` banks loot → if n == 25 → GAME_OVER (victory),
   else **INTERMISSION** (`RunState.pending_level_ups` shown, players ready with A) → wave n+1.
5. START on any player's device → PauseMenu (`get_tree().paused`).

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

- Duration `RunState.wave_duration(w)`. Spawn budget per second
  `(0.9 + 0.22 * (w - 1)) * RunState.coop_count_mult()`; weighted pick among enemies with
  `first_wave <= w`; group size in `[group_min, group_max]`; position = random arena point
  ≥ 6 m from every living player; `Vfx.spawn_telegraph` 1 s before the group appears.
- At most `MAX_ENEMIES` alive. When the timer ends: remaining enemies `despawn()` (no loot),
  pickups `collect_to_bank()`, `wave_cleared` emitted.
- Waves 10 / 20 / 25 (boss / elite) are regular waves until milestone M6.

## Command line (Main)

`-- --smoke` 4 bots, random classes, menus skipped, `Engine.time_scale = 4`, plays
`--waves=N` waves (default 3), prints `SMOKE_RESULT {json}` and quits (exit 1 if a wave
could not complete). `--players=N` bot count, `--seed=N`, `--demo` bots without time scaling
(for screenshots), `--screenshot=path` + `--shot-time=seconds` saves a PNG then quits.

## Visuals (procedural art)

- No imported assets yet: `MeshKit` merges primitives / lathes / extrusions into one
  vertex-coloured `ArrayMesh` per prop, enemy or weapon (cached by key, shared by every
  instance) drawn with `Mats.toon_vc()`. All toon materials share a few cached shaders
  (two-band toon light, warm rim, inverted-hull outline as `next_pass`; the outline is drawn
  in the alpha pass only, so it costs nothing in the shadow pass).
- Per-node looks go through instance uniforms, never duplicated materials:
  `Mats.set_overlay` (hit flash / wind-up tint), `Mats.set_ring` (ground rings),
  `Mats.set_cast_bar`.
- Public helpers beyond the stubs:
  - `OnionModel.set_revive_progress(progress, reviver_color, seconds_left)` – revive ring arc
    plus a WoW-like "Resurrecting" cast bar above the ghost, in the reviver's colour.
  - `OnionModel.set_channel_target(downed_player)` / `null` – the reviver raises golden,
    glowing hands and a light beam connects it to the ghost.
  - `Vfx.resurrect_column(feet_pos)` – shaft of light from the sky when a revive completes.
  - `CameraRig.get_walk_rect(player)` – shared screen (GDD 13): the rectangle a player may
    walk in so nobody leaves the screen once the camera is fully zoomed out (in the MVP
    arena it never binds: the whole arena fits at `MAX_DISTANCE`).
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
