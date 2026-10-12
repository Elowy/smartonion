# SmartOnion – architecture

Scope of the first playable build (milestones **M0 + M1** of the GDD): 1–4 players join with
controllers / keyboard, pick a class, and fight 25 waves of enemies with auto-attacking
weapons, collecting gold (shared wallet) and XP (shared level). Between waves a simple
"ready up" screen. Later milestones have their own sections below: M2 items, loot and the
shop; M3 class resources, abilities and Mastery; M4 level-up cards, ranks and the Trainer; M5
talents, tier sets, forging, elites, the Loot Goblin and the shared-purse tools.

## Layout

```
autoload/   Db (data registry), PlayerManager (devices / slots), RunState (shared run state)
core/       Stats, StatBlock, CombatMath, PlayerSlot, input/ (PlayerInput + devices + bots);
            items/ shop/ loot/ (M2), abilities/ (M3), progression/ (M4), bonus/ talents/ (M5)
data/       *_data.gd resource classes + classes/ weapons/ enemies/ .tres content; items/
            item_bases/ affixes/ enchants/ uniques/ (M2), abilities/ resources/ (M3),
            talents/ sets/ forge/ (M5)
scenes/
  main/     Main – game flow state machine                         [integration]
  arena/    Arena – battlefield, walls, entities root               [visuals]
  camera/   CameraRig                                                [visuals]
  world/    SpiritHealer – level object of the arena (revives ghosts)  [visuals]
  visuals/  Mats, OnionModel, EnemyModel, WeaponModel               [visuals]
  vfx/      Vfx – fire-and-forget effects                           [visuals]
  player/   Player, WeaponRunner, Projectile                        [player]
  abilities/  per-class AbilityEffect / MasteryEffect scripts (M3, M4)
  talents/  per-class TalentEffect scripts (M5)
  enemies/  Enemy; EliteAffixes, ElitePlate, LootGoblin, GoblinPortal (M5)  [enemies]
  pickups/  Pickup, LootBag (M2)                                     [enemies]
  waves/    WaveDirector; GoblinSpawner (M5)                         [enemies]
  ui/       UiTheme, MainMenu, Lobby, Hud, Intermission,            [ui]
            GameOverScreen, PauseMenu; items/ shop/ loot/ (M2), level_up/ trainer/ (M4),
            talents/ purse/ (M5)
tests/      run_tests.gd runner + test_*.gd (extend TestCase); shared helpers without the
            test_ prefix (*_fakes.gd, *_base.gd, talent_effect_probe.gd)
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
│   ├── SpiritHealer           – arena.spirit_healer at Arena.SPIRIT_HEALER_POINT (centre)
│   ├── entities (Node3D)      – players, enemies, projectiles, pickups, VFX
│   └── CameraRig
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
   - A player at 0 HP is **downed**: a ghost that moves at full speed
     (`Player.GHOST_SPEED_MULT` = 1) and that enemies ignore.
   - **Spirit Healer** (`SpiritHealer`, `scenes/world/`): part of the level – the Arena builds
     one at `Arena.SPIRIT_HEALER_POINT` (the centre; no decor there) as its own child (not an
     entity), `Arena.current.spirit_healer`; no collision.
     - It is only drawn while a ghost exists (`is_active()`, `is_shown()`). `_shown` fades
       it in over `APPEAR_TIME` (0.6 s): alpha, a rising and growing spirit, a growing ring
       and a soft flash. It fades out the same way and the node's `visible` is false when
       nobody is down.
     - The pulse runs regardless. Every physics tick (before the
     entities, paused with the arena) its countdown `pulse_left` runs down from
     `PULSE_INTERVAL` (10 s; restarted by `begin_wave` on `RunState.wave_changed`); at 0
     every ghost within `HEAL_RADIUS` (1.6 m, flat XZ) without Resurrection Sickness
     (`will_revive`) gets `revive(REVIVE_HP_RATIO = 1.0)` + `Vfx.resurrect_column` +
     "Resurrected!", `Player.res_sickness_left = Player.RES_SICKNESS_TIME` (15 s; ticks in
     `Player._physics_process`, cleared at wave start; blocks only the healer) and the
     `resurrected(player)` signal. A Label3D shows the seconds above the spirit while ghosts
     exist; the living are not affected. It writes `Player.healer_channel` / `healer_seconds_left`, and the ghost's cast
     bar shows whichever revive (teammates' or the healer's) is further along, in
     `SpiritHealer.CAST_COLOR` for the healer; whichever finishes first revives. Look:
     procedural winged spirit (own copies of `Mats.ghost`), halo, rune circle on
     `HEAL_RADIUS`, motes, one `OmniLight3D`; while a ghost exists (`is_active()`) it pulses
     brighter and shows a light column.
   - A living teammate standing within `REVIVE_RADIUS` for `REVIVE_TIME` (5 s) still revives
     them at 30% HP. Every additional living reviver in the
     circle adds +50% speed (`Player.revive_speed(n)`: 1 → 1×, 2 → 1.5×, 3 → 2×); with
     nobody in the circle the progress drains slowly (`REVIVE_DECAY_PER_SECOND`); taking
     damage never interrupts it. Cast bar in the reviver's colour with the time left at the
     current speed (`Player.revive_seconds_left()`), channel beam; on completion
     `Vfx.resurrect_column` at the feet, "Resurrected!" and `INVULNERABLE_AFTER_REVIVE`
     (1 s). Everybody downed at once → GAME_OVER (defeat). Solo: downed = defeat.
4. **wave_cleared** (the director already stopped: enemies despawned, loot banked) →
   **WAVE_END** ("Wave cleared!" banner, `Main.WAVE_END_DELAY` = 1.6 s, players can still
   move) → if n == 25 → GAME_OVER (victory), else **INTERMISSION** (tree paused,
   `Player.end_wave()` on every hero – abilities / Mastery drop auras and buffs –,
   `Intermission.open(n, RunState.pending_level_ups)`: loot roll → level-up cards (when levels
   were gained) → market; players ready with START, bots and unplugged
   devices auto-ready; after `Intermission.auto_continue_time` – default
   `AUTO_CONTINUE_TIME` = 60 s, ≤ 0 switches it off – the next wave starts even if not
   everyone is ready) → `pending_level_ups = 0` (the cards resolved them) → wave n+1.
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
- Every team level gained above the starting level gives every player +1 Stamina (+1 Max
  HP) via the source `&"level"` (`Player.LEVEL_STAMINA`; applied in `Player.create` for the
  current level and on `RunState.leveled_up`, current HP rises by the Max HP gained); the
  real reward is the level-up card picked after the wave (M4 sections below).
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
- `Player.take_damage`: dodge roll → "Dodge" text; block roll (`Player.block_chance()`:
  shields + the M5 Block stat, at most `Stats.BLOCK_CAP` 50) → the hit is reduced by
  `CombatMath.block_absorb` (half, + Block Value %, at most `BLOCK_ABSORB_CAP` 0.85);
  `CombatMath.incoming_damage` (not rounded – small Armor / Versatility / Avoidance values
  count; at least 1); i-frames `INVULNERABLE_AFTER_HIT`. HP may be fractional: only the
  displayed numbers are rounded (floating text to one decimal, unit frames round up).
- Enemy stats at wave w (GDD 9), n = w - 1:
  - HP: `data.hp_at_wave(w) * RunState.coop_hp_mult()` =
    `max_hp * (1 + hp_growth * n) * (1 + hp_compound)^n * coop`.
  - Contact / projectile damage: `data.contact_damage_at_wave(w) * RunState.coop_damage_mult()`
    = `base * (1 + damage_growth * n) * (1 + damage_compound)^n * party`. Uses
    `EnemyData.growth_mult` and is applied once in `Enemy.create`.
  - Defaults: `hp_growth` 0.12, `hp_compound` 0.22, `damage_growth` 0.15, `damage_compound`
    0.08. A future DifficultyData may override them.
  - `party` = `RunState.COOP_DAMAGE_MULTS[players - 1]` = 0.35 / 0.45 / 0.6 / 0.8 for 1–4
    players: small parties have fewer rescuers (solo: the first down is defeat) and more
    enemies per head.
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
  `(0.9 + 0.08 * (w - 1)) * RunState.coop_count_mult()`; weighted pick among enemies with
  `first_wave <= w`; group size in `[group_min, group_max]`; position = random arena point
  ≥ 6 m from every living player, preferably on screen outside the HUD
  (`CameraRig.get_safe_ground_rect()`; 16 tries there, then 8 anywhere in the arena);
  `Vfx.spawn_telegraph` (red rune with a white-hot core, readable without colour) 1 s before
  the group appears.
- At most `MAX_ENEMIES` alive. When the timer ends: remaining enemies `despawn()` (no loot),
  pickups `collect_to_bank()`, `wave_cleared` emitted.
- Waves 10 / 20 / 25 (boss / elite; `RunState.is_boss_wave` / `is_elite_wave`) are regular
  waves until milestone M6. M5 adds elites from wave 5 (on those waves too) and the Loot
  Goblin (never on them) – see "Elites" and "Loot Goblin" in the M5 section.

## Command line (Main)

Parsed by `LaunchOptions` from `OS.get_cmdline_user_args()` (everything after `--`).

| Flag | Meaning |
|---|---|
| `--smoke` | Bots, menus skipped, `Engine.time_scale = 4` (with 4× physics ticks, so the simulation step stays 1/60 s of game time), plays `--waves=N` waves (default 3), prints one line `SMOKE_RESULT {json}` and quits. Exit 0 only when every wave completed and no engine / script error was logged (`ErrorCounter` is an `OS.add_logger` logger); exit 1 on errors, on a timeout (real-time watchdog) or – with `--allow-defeat` – on a defeat. Without `--allow-defeat` a full party wipe is counted (`wipes`) and everybody is revived, so later waves still get exercised. |
| `--demo` | Bots at normal speed, endless (the next run starts 6 s after a Game Over). |
| `--players=N` | Bot count 1–4 (default 4); classes cycle through `Db.class_ids`. |
| `--classes=a,b,...` | Bot classes in join order (cycled; unknown ids warn and are skipped), e.g. `--classes=warrior,mage,paladin,rogue`. Default: `Db.class_ids`. |
| `--seed=N` | `RunState` seed and bot seeds (smoke runs default to seed 1). |
| `--start-wave=N` | First wave of the run (testing later waves). |
| `--screenshot=PATH` `--shot-time=S` | Saves the viewport as PNG after S seconds of game time since the run started (since boot for the menu / lobby) and quits. Needs a display: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 -- ...` |
| `--view=NAME` `--view-time=S` | Dev: reach a screen for a screenshot – `menu`, `lobby` (bots join, P1 ready), `game`, `intermission` (the wave timer is run out), `game_over`, `victory`, `pause`; forced at S seconds of game time (default: shot time − 3 s) and held open. |
| `--time-scale=X` | Overrides the time scale. |
| `--goblin-chance=X` | M5 test hook: Loot Goblin chance per eligible wave, 0..1 (`GoblinSpawner.chance_override`; default: the normal chance). |
| `--elite-mult=X` | M5 test hook: multiplies the expected elites per wave (`EliteAffixes.rate_mult`, ≥ 0). |
| `--start-level=N` | M5 test hook: team level at run start (1..99; `RunState.set_start_level` after `RunState.start_run`, before the heroes spawn – talent points from level 10, no pending level-ups). |
| `--panel-tab=NAME` | Dev: when the market first opens, P1's PlayerPanel switches to `talents`, `trainer` or `character` (`PlayerPanel.debug_start_tab`, screenshots of the Talents tab). |

`SMOKE_RESULT` keys: `result` (completed / defeat / timeout), `waves_completed`, `first_wave`,
`last_wave`, `players`, `seed`, `kills`, `gold`,
`gold_at_last_shop` (the shared wallet when the last market closed, i.e. the gold carried into
the last wave; `gold` also holds the last wave's haul, which no shop follows),
`level`, `players_downed`, `revives`, `wipes`, `errors`, `warnings`, `error_samples` (only
with errors), `game_time`, `real_time`, and `perf` – physics tick times measured by
`PhysicsClock` and grouped by living enemies (`RunPerf`): `physics_ms_avg`,
`physics_ms_at_peak` (ticks with ≥ 80% of the peak enemy count), `script_ms_at_peak`,
`physics_ms_max`, and `monitor_physics_ms_at_peak` (`Performance.TIME_PHYSICS_PROCESS`, which
is the slowest tick of the last second). M2 and M4 add the keys listed in their sections. M5
adds `elites_spawned`, `elites_killed`, `goblins_spawned`, `goblins_killed`, `goblins_escaped`,
`weapons_forged` (RunState counters), `talent_points_spent` (Σ `TalentState.points_spent()`
over the heroes), `talent_resets`, `set_bonuses` (Σ `SetBonuses.active_count`) and
`gold_spent` (every `RunState.try_spend_for`). Each cleared wave also prints a
`SMOKE wave n cleared ...` line (M5: `elites killed/spawned, goblin spawned/killed/escaped`),
and each closed market prints `SMOKE market closed after wave n: G gold carried into wave n+1
(R bot rerolls so far)`.
Bots (`BotInput`) kite by weapon reach (melee heroes close in, back off when hurt or
crowded), avoid walls, stay near the team and run to downed teammates within
`BotInput.RESCUE_RANGE` (5 m) when it is safe; a ghost bot walks straight to the Spirit Healer
and waits inside its circle (`HEALER_STOP_DISTANCE`) – with Resurrection Sickness it drifts to
a living teammate instead. A Loot Goblin is never a threat to them; they chase it when nothing
else is close (M5, "Loot Goblin"). Between waves bots equip, forge, buy, train, spend talent
points and reroll (M2, M4, M5 sections).
**Determinism:** bots decide in `BotInput.think(delta)`, called by
`PlayerManager._physics_process` once per unpaused physics tick (`process_physics_priority`
-1000, before the heroes move); `poll()` only handles per-frame button / nav edges. Main
counts `WAVE_END_DELAY` in physics ticks. With the engine flag `--fixed-fps 60` the same
`--seed` reproduces a smoke run exactly (same kills, gold, downs); without it the camera
(updated per rendered frame) can shift the on-screen spawn-point preference slightly. M5's
draw points are listed under "Determinism" in the M5 section.

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
  - Overhead health bar (child `Marker/HpBar`): three fixed-size, no-depth-test Sprite3Ds –
    framed back, HP fill (`region_rect` width = HP ratio, coloured by
    `OnionModel.hp_bar_color`: green → yellow → red) and the absorb-shield segment.
    - Its bottom edge sits on the marker origin (`MARKER_Y`); `_lift_plate` raises the
      diamond and tag above it.
    - `set_hp_ratio` drives the fill. `Player._physics_process` pushes
      `procs.shield_hp / max_hp()` through `set_shield_ratio`, which is a no-op when the
      value is unchanged.
    - Hidden with the marker and while downed (the diamond drops back onto the origin).
    - Test helpers: `is_hp_bar_visible()`, `hp_bar_fill()`, `hp_bar_shield()`.
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
  - Camera framing (`CameraRig.framing_points(living, ghosts, anchors)` →
    `compute_framing`): the living players plus, while anybody is a ghost, the Spirit Healer
    (so it is always on screen and reachable); everybody down → the ghosts (old fallback).
  - `CameraRig.compute_framing(points, aspect, rect, extras)` – `extras` are soft points (the
    living, not escaped Loot Goblins, `CameraRig.goblin_points(get_nodes_in_group(&"loot_goblins"))`,
    only while somebody stands). They count for the zoom and the centroid; `keep_in_margins`
    first fits all points, then the hard points again, so the players' margin guarantee wins
    and the view leans as far towards the goblin as the players allow. Goblins never enter
    `get_walk_rect`. `CameraRig.PROCESS_PRIORITY` (100) is the rig's process priority.
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
    fits at `MAX_DISTANCE`; the Spirit Healer counts as a framed point while a ghost exists);
    a ghost, which the camera does not follow, is kept inside the current view, out from
    under the HUD (`safe_ground_rect`), grown to reach the Spirit Healer
    (`CameraRig.ghost_walk_rect`).
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
  Compact: `UnitFrame`s ~430 x 104 px at 80% panel opacity (smallest text 18 px, readable at
  720p; at most `UnitFrame.MAX_HEIGHT` 112 px – CameraRig's top / bottom margins are
  full-width bands sized for ~100 px frames, so frames grow sideways, not down), a compact
  wave / timer plaque, the XP bar as a thin segmented strip along the whole
  bottom edge (WoW style; level at its left end, "xp / needed XP" at its right end) and a slim
  translucent banner (`BANNER_HEIGHT` 100 px, ribbon alpha 0.38) anchored just below the
  plaque. Unit frames hide when their player is freed; while downed they show the revive
  progress (teammates' or the Spirit Healer's, whichever is further along; spirit blue for the
  healer) and a hint: "Go to the Spirit Healer (7 s)" (`GHOST_HINT` + the next pulse),
  "Spirit Healer: 7 s" in its circle (`WAITING_HINT`), "Resurrection Sickness: 12 s"
  (`SICKNESS_HINT`).
  Frame layout: `[portrait | name row over (HP + resource bars | ability icons)]`, mirrored
  for P2 / P4 (portrait outside, icons on the inner side). The bars cell is as tall as the
  DOWNED overlay, so going down never changes the frame height.
  - `ResourceDisplay` (VBox under the HP bar, bound to `player.abilities`): one row per
    `ClassResource` in `resource_order`, following `ClassResource.changed` (no polling).
    `BAR` resources: a `UiBar` in `ResourceData.color` with "value / max" (floored), a spend
    of ≥ 10% flashes it. `PIPS` (≤ `MAX_PIPS` 10): diamonds (crystals for Soul Shards);
    primary in a trough like a bar, a secondary row inline in `inline_holder` (the frame's
    `name_pips`, inner end of the name row: the Rogue's combo points add no height).
    No resources → the M1 placeholder bar (`ClassData.resource_type` / `resource_color`).
  - `AbilityBar` (HBox of 4 `AbilityIcon`s, 42 px): slots 0 / 1 always shown, 2 / 3 once
    slotted. `bind(runner, input)` follows `slots_changed` (rebuild: abilities, costs,
    prompts) and `ability_cast` (flash). Per rendered frame – only while visible in the tree
    (the HUD is hidden in the market) – `refresh()` reads **one**
    `AbilityRunner.slot_state(i)` per slot (`{charges, charges_max, left, ratio, ready, cost}`,
    one cached `params_for`) and pushes it into the icons; costs every `COST_REFRESH` 0.25 s.
    Prompts: `AbilityBar.prompt_text(input, slot)` follows the device's real binding
    (`PlayerInput.ability_button(slot)`): controllers RT / LT / RB / LB, keyboard
    LMB / RMB / **Q** (slot 2) / **E** (slot 3); the icon spacing widens when a pill ("LMB")
    is wider than an icon.
  - `AbilityIcon` (Control, drawn in code, no assets): gold-rimmed square with a procedural
    glyph (`glyph_for`: `AbilityData.icon`, then the id's words, then the school), tinted by
    `AbilityData.color` / school; clockwise cooldown pie (`sweep_polygon`) + seconds
    (`format_cooldown`: one decimal under 3 s), dimmed when off cooldown but unusable (red
    cost), cast flash, charge counter (top-left, while `charges_max` > 1), cost (top-right),
    prompt pill hanging below.
    - Redraws: `set_state` only redraws when one of these changed:
      - the shown seconds (`show_cooldown_text`);
      - the dim / ready state;
      - the pie crossed to or from empty;
      - the pie moved `sweep_redraw_step()` since the last drawn ratio (`SWEEP_REDRAW_STEP`
        0.004, or about 1 px of edge on smaller icons: 1 / (4 × side)).
    - Layers: the background and glyph are drawn by an internal child `GlyphLayer`
      (`show_behind_parent`), which only re-records on `set_ability` / glyph / tint changes.
      A sweep redraw therefore re-records only the overlay (sweep, veil, flash, rim, texts,
      rank, prompt). StyleBoxes are cached.
    - Rank: gold diamond pips up the left edge. Icons below `SMALL_ICON` (the 26 px auto-cast
      icons) show the roman numeral instead (`uses_rank_badge`):
      - outlined, at `RANK_BADGE_FONT` = `SMALL_FONT` − 3;
      - on a see-through plate (alpha 0.7) that backs exactly the outlined numeral, tucked
        into the bottom-left corner on the rim (`rank_badge_origin` / `rank_badge_rect`;
        about a fifth of the icon).

      Both turn orange once specialised. Rank 0 draws no rank: the lobby preview and the
      Trainer rows, whose rank column shows it. Also used by the lobby cards (abilities + Mastery line;
    `LobbyCard.mastery_parts` splits "Name: text" and capitalises the text, which must fit
    `MASTERY_MAX_LINES` 3 at the 1920x1080 canvas – every 16:9 window size, 720p included).
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
  (`Shop.team_fortune`, still max Epic); `try_buy` → `Shop.BuyResult` (OK / SOLD /
  BACKPACK_FULL / NOT_ENOUGH_GOLD ...; M5 adds FORGED – the auto-forge);
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
  stay per target. M5 adds talent / set procs and new triggers, keys and blocks (see
  "ProcSystem: talent and set procs" in the M5 section).
- **Exotic stats**: Attack / Spell Power add `power x base weapon cooldown` per hit (magic
  weapons – non-physical `WeaponData.school` – use Spell Power); Executioner / Slayer multiply;
  Parry ≤ 50%, melee only, riposte counts as an extra attack; count stats
  (`Stats.INTEGER_STATS`) are whole numbers. Armor Specialization is computed after the
  weapons' bonus stats are applied (`Player.apply_equipment`).
- **Between waves** (`scenes/ui/intermission.gd`): LOOT phase (`LootRollScreen`, 15 s per
  item, hidden choices, bots `LootRoll.bot_choice`, solo Take / Sell / Leave), then the M4
  LEVEL_UP phase (see "M4: level-up cards between waves"), then MARKET
  (`ShopPanel` centred, one `PlayerPanel` per hero scaled into its corner with
  `tooltip_inside = true`). Per player: LB / RB switch focus shop ↔ own panel, A buys
  (hold when > 50% of the wallet), X lock, R3 / Tab ping, Y reroll vote, START ready, B
  unready unless the panel consumed it (`last_input_consumed`; the shop consumes the B that
  cancels a hold-to-buy); panel tabs on LT / RT. The 60 s
  auto-continue runs only in MARKET. The HUD is hidden during the intermission. The
  Intermission itself stays in the tree, hidden, during waves, so `ShopPanel` and
  `TrainerTab` skip `RunState.gold_changed` work while not visible in the tree. They catch
  up once at the end of the frame they are shown in (deferred). `refresh()` clears their
  stale mark, so the market start's own refresh is the only rebuild, and `Intermission.open`'s
  momentary show before the loot roll does nothing. During waves the HUD shows a
  "Team Loot: N" counter.
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
- **Market tooltips** (corner panels, `tooltip_inside`): inside a corner panel the selected
  item's tooltip sits on the panel half away from the selection, scaled down to the panel's
  height but never below `PlayerPanel.MIN_INSIDE_TOOLTIP_FIT` (0.9) – except to stop short of
  the column's other corner panel.
  - A taller one (a set piece or a Legendary with the comparison block) hangs from the panel's
    top edge (top corners) or rises from its bottom edge (bottom corners) over the free band
    between the two panels of its screen column (P1 / P3 left, P2 / P4 right), at most as far
    as `PlayerPanel.TOOLTIP_NEIGHBOUR_GAP` (8 px) before the other panel
    (`_inside_tooltip_span`: the y range from the panel's outer edge to the mirror-image panel
    at the column's other end); only then does its scale drop below 0.9 (at 1920 × 1080 the
    room is 646 px; a wave-25 Stormcaller compared with a many-stat sword ends at about
    0.66–0.70). When the column's other corner is empty (`tooltip_column_mate`, kept up to date
    by `Intermission._sync_panels`, also after a player leaves) it keeps 0.9 and may reach the
    screen edge.
  - Column mates: when both players of a column show such a tooltip and the two would meet in
    the band, the top one (P1 / P2) keeps its place and the bottom one (P3 / P4) makes way.
    `_sync_panels` hands each bottom panel its column mate's `planned_outside_tooltip_rect` as
    `PlayerPanel.tooltip_obstacle` (where the top tooltip goes for the current selection – a
    plan computed by `_tooltip_plan`, not the drawn rect, so layout order does not matter and
    the two never resize each other). The bottom tooltip moves to its panel's other half – the
    selected icon's (`_keep_tooltip_clear`) – just above the selected icon (else just below
    it), shrunk for that down to `MIN_MOVED_TOOLTIP_FIT` (0.75); when even that does not fit it
    keeps its size and rises from the panel's bottom edge over the icon. It moves back once the
    top tooltip is gone or no longer reaches it.
  - Shop tooltips keep clear of such a panel tooltip: `Intermission` hands the visible ones that
    reach out of their panel (`PlayerPanel.outside_tooltip_rect`) to
    `ShopPanel.tooltip_obstacles`, and `ShopPanel.layout_tooltips` counts a spot over one
    `COVER_WEIGHT` (4) times its overlap, like covering the hovered card. The panels lay out
    before the shop each frame (they come first in the tree).
  - A shop tooltip whose content changes is measured at once (`ItemTooltip.layout_now`: the
    containers sort top-down and the wrapped lines report their real height) and placed in
    that same frame; `PlayerPanel` measures its tooltip the same way. The tooltip is rebuilt
    only when the offer, its price or the compared item change – a two-hander compared with
    both hands (`ItemTooltip.EquippedPair`, a new object every call) is identified by its parts
    (`ItemTooltip.compare_key`). A tooltip that fits no spot even at the smallest scale goes to
    the stall's top-left, never to the screen's corner.
  - The panel tooltip hides while the panel's action menu (Equip / Sell / Trade / Forge …) is
    open – both use that half.
  - The Character tab's compact stat list never widens the panel: the names clip with an
    ellipsis, the inset clips, and the long stats have short names (`SHORT_STAT_NAMES`: Regen,
    CDR, Crit Dmg, Healing, Pickup, Atk Power, Extra Atk, Block Val., Execute, and the spell
    schools without "Dmg"); every stat's name shows whole next to a "12.5%" value in a
    700 × 480 panel (`test_stat_list_fits_its_inset_with_long_rows`).
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
  NEAREST_ENEMY, DENSEST_CLUSTER, MOVE_DIRECTION, ALLY with `prefer_downed`, which picks the
  nearest ghost in range but skips one the Spirit Healer revives within
  `PaladinWordOfGlory.HEALER_SOON`, so Word of Glory revives another ghost instead of
  healing); bots
  (`BotInput`) auto-cast when `AbilityEffect.wants_auto_cast`.
  - Timing: every `AUTO_CAST_INTERVAL` 0.25 s, which is exactly 15 ticks at 60 Hz.
    `begin_wave` staggers the players' passes by slot index, so P1–P4 first pass on ticks
    1 / 4 / 8 / 12.
  - One targeting pass per decision. DENSEST_CLUSTER only considers enemies whose centre is
    within `cast_range`. Keyboard: LMB / RMB = slots 0 / 1, Q = slot 2, E = slot 3
  (`KeyboardInput.ability_button`); controllers use `PlayerInput.ABILITY_BUTTONS`.
- `params_for(ability)` (base cooldown / cost / charges + `AbilityData.params` + item mods) is
  **cached per ability and read-only** – copy it before changing anything.
  `invalidate_params()` drops the cache: `set_slot`, `Player.apply_equipment` (item ability
  mods), any future rank change. `slot_state(i)` gives the HUD everything from one lookup;
  `is_ready(i)` = alive, off cooldown, affordable (no targeting); `can_cast` adds the effect's
  own check with full targeting.
- Effects' `tick(ctx, delta)` gets one reused `AbilityContext` per ability id. It is
  refreshed every tick and dropped on `set_slot` / `forget`. An effect must not keep a ctx
  past the call.
- Charges: `params.charges` (default 1, e.g. Blink + the Band of the Blinking Star); the
  recharge timer runs while charges are spent, each expiry returns one
  (`charges_max` / `charges_available`; `remaining()` is 0 while a charge is left).
  `set_cooldown(ability, s)` lets effects shorten / reset a running recharge (≤ 0 = ready).
  `spend_charge(ability)` uses one charge as a cast would, for self-triggering passives such
  as Cheat Death. `cooldown_from_params(ability, params)` gives the cooldown for a preview
  params dict.
- Wave hooks: `begin_wave` (resources / cooldowns reset, `AbilityEffect.begin_wave`,
  `MasteryEffect.begin_wave`; `Player.begin_wave` also clears `forced_crits` and
  `damage_mults`) and `end_wave` (`AbilityEffect.end_wave(ctx)`, `MasteryEffect.end_wave()`,
  via `Player.end_wave()` before the intermission: auras / buffs must not show in the
  market). Ability ground areas (group `ability_areas`) are freed by `WaveDirector.stop()`,
  and again by `Main.open_intermission()` for areas that landed during the "Wave cleared!"
  pause.
- `MasteryEffect.tick` runs every physics tick, **also while downed** (Ignite / Deadly Poison
  DoTs keep burning like item DoTs); pets and auras check `player.is_alive()` themselves.
  Ability effects only tick while alive.
- Item proc `resource {amount}` (Soulreaping) → `AbilityRunner.gain_from_proc(amount)`: whole
  points of the first pip resource (Holy Power, Soul Shards, Combo Points), else 10% of the
  primary bar per point.
- Player state used by abilities / bots: `stealth_left` / `is_stealthed()` (Vanish: enemies
  neither target, touch nor shoot the player; cleared at wave start), `is_reviving()` (alive
  and next to a downed teammate – bots must not dash away), `forced_crits`, `damage_mults`.
- Crit DoT Masteries (Ignite, Deadly Poison) pick their enemy with `CritDot.target_for(hit)`
  (`scenes/abilities/crit_dot.gd`): the hit enemy while it lives, else the nearest living
  enemy within `CritDot.SPREAD_RADIUS` (2.5 m) of the corpse (`EnemyGrid.nearest`, ties in
  group order), else nothing.
- `RogueVanish` follows `Player.hp_changed` / `downed_changed`: it re-fades meshes whose look
  the model replaced (the HP peel on a heal / stat change), ends at 0 HP before the downed
  ghost look saves the materials, and ends on `begin_wave` / `end_wave`. (Cleaner later: a
  stealth state on `OnionModel`, handled like `downed`.) `WarlockImpBolt` overrides
  `Projectile.advance` so a ricochet keeps its new start point; `DrainLife.end_wave` stops
  the channel.
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

## M4: level-up cards between waves

```
scenes/ui/level_up/  LevelUpScreen (the phase, layout, timer, bots), LevelUpPanel (one
                     player's region + state machine), LevelCardView (one card, drawn in code)
core/progression/    LevelUpDeck / LevelCard / StatCards / Trainer (the rules; see the M4 core)
```

- **Phase order** (`Intermission.Phase`): LOOT (team loot only) → **LEVEL_UP** (only when
  `level_ups` > 0 and some slot has a hero – `Intermission.wants_level_up()`) → MARKET. The
  market's auto-continue countdown starts only with MARKET. Main passes
  `RunState.pending_level_ups` to `Intermission.open` and clears it when the next wave starts.
- **Layout** (1920x1080 canvas, `LevelUpScreen`): a header band (`HEADER_HEIGHT` 94: "Level Up!",
  the levels, the shared gold and the "Auto-pick in N s" bar) and one `LevelUpPanel`
  (`DESIGN_SIZE` 936x476) per hero: 3–4 players in their quarters like the HUD / market (P1
  top-left, P2 top-right, P3 bottom-left, P4 bottom-right, by slot index), two players side by
  side in the middle band, a solo player centred at `SOLO_SCALE` 1.45. Panel: header in the
  player's colour (portrait, Pn, class, "Level 6 – pick 1 of 5 (2 left)"), 5 `LevelCardView`s
  (172x356), the player's own prompts (`UiGlyph.for_input`: key caps for the keyboard) with
  the reroll price (red when the wallet cannot pay) and a message line.
- **Cards** (`LevelCardView`): ability cards – ribbon "New Active" / "New Auto-cast" (green)
  or "Rank II → III" (gold), `AbilityIcon`, name, school · cost · cooldown (a rank-up that
  shortens it shows "3.6 → 3.2 s"), `AbilityRanks.rank_text` in green (Rank V names both
  specs), the description via `AbilityIcon.format_description(ability, params)` – `runner.params_for`
  for new abilities, the next rank's params for rank-ups (`LevelCardView.next_rank_params` →
  `AbilityRunner.params_at_rank`) – and a red "Slots full – replaces one"
  strip when the kind's slots are all taken. Stat cards: ribbon, gem and title in the Items
  rarity colour, `LevelCard.lines()`. The player's cursor lifts the card with a border / glow
  in the player's colour.
- **Per player** (`LevelUpPanel`, only `PlayerSlot.input`): CARDS (◀ ▶, A pick, Y reroll for
  `LevelUpDeck.reroll_price(cleared wave, rerolls)` from the shared wallet via
  `RunState.try_spend_for(…, &"level_reroll", "Level-up reroll")` (M5 spend log) – per
  player, rising +2 per reroll in this round, refused with "Not
  enough gold" when broke) → REPLACE when a new ability's kind is full (the slots of that kind
  with icon, name, rank and refund `AbilityRanks.replace_refund(rank, RunState.wave)`; A =
  `LevelUpDeck.apply(player, card, slot)`, the refund goes to the wallet; B back) → SPEC when a
  pick reached Rank V and `runner.needs_spec` (two specs, A = `runner.set_spec`, no way back)
  → next hand / DONE (summary of the picks). One pick per level gained; the next hand is
  drawn after each pick so it reflects what was learned.
- **Randomness**: when the phase opens every player (slot order) gets their own
  `RandomNumberGenerator` seeded with `RunState.rng.randi()`; all of that player's hands and
  rerolls come from it. Hands are reproducible per seed, one player's rerolls / pick timing
  never change another player's cards, and `RunState.rng` advances by exactly one draw per
  player whatever the humans do (the shop round after it stays reproducible).
- **Automatic picks** (`LevelUpPanel.auto_pick` / `auto_finish`): `LevelUpDeck.bot_pick`,
  never a card that needs a replacement (other cards are tried if one fails to apply); a
  pending specialisation takes the highlighted one (bots: the first). Bots
  (`PlayerSlot.is_bot()`) pick at once, or after `LevelUpScreen.bot_think_time` per pick with a
  visible cursor walk (demo: `Main.DEMO_LEVEL_UP_THINK_TIME` 1 s); unplugged pads (also when
  unplugged mid-phase) pick at once. The countdown `PICK_TIME` 40 s + `EXTRA_PICK_TIME` 20 s per
  further level (`LevelUpScreen.pick_time` ≤ 0 = off) auto-finishes every idle human.
- **Input hygiene**: the phase swallows every human's held buttons / stick when it opens,
  skips the opening frame and ignores A / Y / B for `LevelUpScreen.INPUT_LOCKOUT` (0.4 s);
  each new hand / sub-prompt ignores A / Y for `LevelUpPanel.PICK_INPUT_DELAY` (0.3 s), so a
  mashed A never picks an unseen card. A player who leaves loses their panel; the phase ends
  when everyone left is done.
- **Trainer bots** (smoke / demo, after their market shopping): `Intermission._bots_train`
  calls `Trainer.bot_train(player, reserve)` for every bot in slot order with an even share of
  the gold above `Intermission.bot_train_reserve` (one Uncommon item at the next wave's price
  per two bots), so the shop still gets gold next round.
  - Then `Intermission._bots_reroll` spends the gold neither the offers nor the Trainer could
    take, while the wallet keeps `BOT_REROLL_RESERVE_MULT` (2) × `bot_train_reserve` after
    paying `Shop.reroll_cost()`.
  - Each time, one shopping bot (in turn) votes a reroll alone
    (`Shop.vote_reroll(index, [index], RunState.rng)`) and the bots run their buying passes
    again (`_bots_buy`).
  - At most `BOT_MAX_REROLLS` (3) per round, and never while a human with a working device
    can vote (`ShopPanel.voter_indices()` not empty).

  `SMOKE_RESULT` adds `level_cards` (cards picked), `abilities_learned` (learned slots filled
  at the end), `ranks_trained` and `shop_rerolls` (`Intermission.bot_rerolled`).


## M4: ranks, learned abilities, Trainer

```
core/abilities/ability_ranks.gd  AbilityRanks: rank mods, Trainer prices, replacement refund
core/progression/                LevelUpDeck, LevelCard, StatCards, Trainer
scenes/ui/trainer/               TrainerTab / TrainerRow / SpecChooser (PlayerPanel's Trainer tab)
scenes/abilities/general/        the six general abilities (class_id empty)
```

- **Kinds and slots** (`AbilityData.kind`): CORE (RT / LT, fixed per class), ACTIVE (learned,
  RB / LB = slots 2 / 3; keyboard Q / E via `PlayerInput.ability_button`), AUTO (learned,
  slots 4–7, cast by themselves for everybody when `_cheap_ready` and the effect's
  `can_cast` + `wants_auto_cast` agree, every `AUTO_CAST_INTERVAL`). Bots also auto-cast the
  button slots. `AbilityRunner.learn` / `forget` (50 % refund of the ranks' gold value) /
  `rank_up` / `set_spec` / `needs_spec` / `params_at_rank` (previews) / `teardown` (every
  slotted effect gets `end_wave`, then the Mastery's teardown).
- **Ranks** (`AbilityRanks`, GDD 6.3): Rank II and IV `"power_pct"` +25 and `"cooldown_pct"`
  −10 each; Rank III merges `AbilityData.rank3`. Rank V's chosen
  `AbilityData.specs[i]["mods"]` (`AbilityRanks.spec_mods`, a deep copy) apply as a second `apply_mods`
  pass after the rank mods, then the item mods come last. So a spec's `_pct` scales the
  Rank IV value (Hot Streak: 10 s × 0.8 × 0.7 = 5.6 s). Every effect multiplies its damage / heal / shield / buff
  amounts by `ctx.num("power", 1.0)`. Trainer price `25 × rank × (1 + 0.08 × (wave − 1))`.
  Core abilities train too. `apply_mods`: `<param>_add` adds, `<param>_pct` scales an existing
  `<param>` (else it sets the key itself), anything else replaces – a data test per kit
  applies every rank3 / spec mod through `params_at_rank` and checks the intended param moves.
- **Level-up cards** (`LevelUpDeck`): 5 cards, about half ability cards (new learned
  abilities from `Db.ability_pool(class)` – class + general, unlocked, `card_weight` > 0 – or
  free rank-ups of slotted abilities incl. core ones), at least one ability and one stat
  card.
  - Full slots of a kind make new abilities of that kind rarer (×0.3) and rank-ups more
    likely.
  - A card that would need a replacement (a new ability whose kind is full) also counts only
    `FULL_SLOTS_MIN_SHARE` (0.2) of its weight. The per-card ability chance is
    `ABILITY_SHARE` 0.5 × (usable + 0.2 × replacement-only weight) / total weight
    (`LevelUpDeck.ability_share`), and ability cards are picked from
    `LevelUpDeck.pick_weights` (replacement-only ×0.2).
  - So rank-ups keep their 0.5 × weight / total chance per card, and what full slots take
    goes to stat cards. With every slot full at Rank V that is 10% per card, plus the
    one-ability-card guarantee.
  - Stat cards (`StatCards`): rarity Common 50 / Uncommon 30 / Rare 15 / Epic 5, 1–3
  stats from a weighted table with whole amounts (the class's own primary stat only). Stat
  cards go to the Player source `&"level_cards"`; team levels themselves give only +1 Stamina
  (`&"level"`). Every hero also has `Stats.BASE_MASTERY` 5 (`&"base"`; test heroes from
  `tests/player_fakes.gd` drop it).
- **Trainer tab** (`TrainerTab` in `PlayerPanel`, `set_tab` / `TRAINER_TAB`): eight rows (core,
  Active, Auto), rank, next-rank text, price; A trains (`Trainer.try_buy_rank`; hold A for
  `ShopPanel.HOLD_TIME` above half the wallet), Y previews the next rank, Rank V opens
  `SpecChooser` (B = later, the row shows "Choose"). Bots: `Trainer.bot_train` from the
  intermission.
  - The Y preview shows the rank, the description and the `CD X s · Power Y%` stats in green.
    The stats sit right-aligned on the rank row (`TrainerTab.stats_text` via
    `AbilityRunner.cooldown_from_params`), so the description keeps that line.
  - The detail description gets the whole lines left in its clip holder under the next-rank
    and specialisation lines (`_fit_description`, at least `MIN_DESCRIPTION_LINES`), with an
    ellipsis when cut.
  - The row icons carry no rank of their own; the rank column shows it.
  - M5: R3 (keyboard Tab) pings a rank for the team and a purchase is logged as "Fireball
    Rank III" (see "Shared purse" in the M5 section).
  - While hidden, the tab skips gold and rank refreshes and only marks itself stale. It
    catches up once at the end of the frame it is shown in (`call_deferred` from
    NOTIFICATION_VISIBILITY_CHANGED). An explicit `refresh()` first (`PlayerPanel.set_tab`,
    the market start) cancels the catch-up.
- **HUD**: `AbilityBar` shows the four button slots (prompts per device) and a 2×2 cluster of
  26 px auto-cast icons (sweep only) once an auto-cast ability is learned. Every icon carries
  its rank: pips on the button icons, a small corner numeral on the 26 px auto-cast icons,
  orange once specialised. Frames stay ≤ 112 px tall (wider with learned slots).
- **Core hooks for the kits**:
  - `ProcSystem.add_shield(amount, duration, source := &"")`: one entry per source, each on
    its own timer. `absorb` drains the entry that runs out first. `shield_hp` is the total
    and `shield_of(source)` gives one entry's HP. Item procs and most kit shields share the
    anonymous `&""` entry.
    - `shield_hp` is read-only: assigning it only reports an error.
    - `clear_shields()` empties every entry (begin_wave, tests).
    - `absorbed_total` is the running sum of damage any shield soaked. It is never reset, so
      effects compare it between ticks.
  - `Player.damage_taken_mults`: named incoming multipliers, cleared at wave start.
  - `Player.death_guards`: Callables tried *before* the limited item cheat-death procs, so a
    free or recharging guard such as Last Stand or Cheat Death never uses one up.
  - Also `Enemy.apply_fear(duration, from)`, `Enemy.apply_taunt(target, duration)` and
    `Enemy.is_boss()` (false until bosses exist).
- **Kit helpers** (per class folder; all damage through `ProcSystem.deal_raw` with sources
  `&"ability"`, `&"dot"`, `&"pet"`):
  - Warrior: `WarriorSpin` (storm ticks for Whirlwind / Bladestorm / Ravager), `WarriorFx`
    (VFX base); Bladestorm's "cannot be slowed" is the stat source `&"bladestorm"` cancelling
    negative Speed. `WarriorKit.is_displaced(player)` makes Charge and Heroic Leap exclusive:
    neither starts while the other moves the hero. Execute instantly kills elites (M5) and
    the Loot Goblin too – `WarriorExecute.strike` zeroes a Shielding elite's `shield_hp`
    first, so the absorb shield cannot save it; only bosses (`Enemy.is_boss()`) take
    `boss_mult` × damage instead. Its victim choice prefers an executable enemy, then
    `is_elite()` (elites, the goblin) / bosses. M5 talent hooks: see the M5 class kit hooks.
  - Mage: `MageSpell` (spell damage with a per-spell Spell Power factor, freeze), `MageBolt`
    (Projectile subclass dealing ability damage: burn / splash / bounce / pierce / homing),
    `MageBurn` / `MageFrozen` (nodes on the enemy), `MageMeteorStrike` (group
    `ability_areas`).
    - Ice Barrier = `add_shield(amount, 3600, &"ice_barrier")`, its own entry
      (`MageIceBarrier.SHIELD_SOURCE`), lasting until used up or wave end. Other shields
      neither block its recast nor inherit its timer.
    - Its Rank III chill fires when `ProcSystem.absorbed_total` grew while the barrier is up,
      so a hit soaked by a shorter-lived shield on top still chills. A shield expiring on its
      timer does not.
    - Frost Nova's Shatter: the ice of one nova shares a `MageFrozen.ShatterGroup`, so each
      enemy takes one nova's shatter at most once.
  - Paladin: `PaladinKit` (holy strike damage, heals, per-Paladin buff keys),
    `PaladinHolyMissile` (homing / ricochet hammer and shield), `PaladinVfx`. Blessing of
    Kings = stat source `kings:paladin<slot>` per hero; Lay on Hands never revives (only Word
    of Glory and the Spirit Healer / teammates do). Word of Glory does not revive a ghost the
    Spirit Healer revives within `PaladinWordOfGlory.HEALER_SOON` (1 s,
    `Player.healer_seconds_left`); it heals instead. Radiant Bubble ticks are not scaled by
    power: power only lengthens the bubble.
  - Rogue: `RogueBlade` (Projectile subclass for knives / shuriken: weapon hits, optional
    poison and returning), `RogueVanish.shroud()` (stealth + silhouette for other effects);
    Cheat Death is a `Player.death_guards` entry with the runner's cooldown; each save spends
    one charge (`AbilityRunner.spend_charge`). Blade Flurry echoes carry each echo target's
    own Executioner / Slayer bonus, not the struck enemy's.
  - Warlock: `WarlockSpell`, `WarlockAfflictions` (one DoT manager node per Warlock, ticks
    while downed; Demonic Pact on `"dot"` / `"pet"`). Afflictions listen to `Enemy.died`. A
    host that vanishes without dying (the wave-end despawn) only ends its afflictions: no
    seed burst, no Corruption spread, no Blighted Ground. Fear's Dread deals its damage per
    second without the rank power (`WarlockFear.dread_rate`): power lengthens the fear, so
    the Dread total scales with power once (the same rule as Radiant Bubble).
    Pets (Voidwalker taunts, Infernal for 8 s) free themselves when their owner is gone;
    `damage_taken_mults["voidwalker"]`.
  - General: `GeneralKit` (weapon damage normalised to a 1 s swing, spell damage with the
    best of Attack / Spell Power), `GeneralBuff` (timed hero buff: named stat source +
    damage-taken multiplier, refreshed not stacked), Spirit Wolf pet; Bandage is not
    interrupted by damage.
    - A Sprint cast (own or Rallying) never weakens or shortens a running Sprint. Per stat
      the higher value and the longer time are kept (`GeneralSprint.merged_stats`), so a
      refresh may extend a rally's numbers. The Trailblazer trail lasts as long as the
      caster's own merged Sprint.
    - Bandage Rank III's extra bandage goes to the most wounded unbandaged ally.

## M5: depth – talents, tier sets, forging, elites, Loot Goblin

```
core/bonus/          BonusVocabulary (the effect vocabulary), PlayerBonuses (the bonus engine)
core/talents/        TalentState (points, gates, undo, reset), TalentEffect (script base),
                     TalentBot
core/items/          forge.gd (Forge), set_bonuses.gd (SetBonuses)
data/talents/        TalentTreeData, TalentData; <class>/<tree>.tres (three trees per class)
data/sets/           SetData; <set_id>.tres (one per class); pieces in uniques/set_<class>_<slot>
data/forge/          ForgeLegendaryData; legendary_<weapon_id>.tres (one per base weapon)
data/enemies/        loot_goblin.tres
scenes/talents/      <class>/<tree>_<name>.gd – TalentEffect scripts (capstones and the like)
scenes/enemies/      EliteAffixes, ElitePlate, LootGoblin, GoblinPortal
scenes/waves/        GoblinSpawner (child of the WaveDirector)
scenes/ui/talents/   TalentTab, TalentTreeView (+ TierRail), TalentNode, TalentGlyph
scenes/ui/purse/     PurseBoard
```

- Talents and tier-set bonuses are data (`TalentData.effects`, `SetData.bonuses`): lists of
  bonus-vocabulary entries that one engine per hero (`player.bonuses`) turns into stat sources,
  ability mods, damage multipliers, resource bonuses, procs and `TalentEffect` scripts.
- New stats: `Stats.BLOCK_CHANCE` (added to the shields' block chance, total at most
  `Stats.BLOCK_CAP` 50) and `Stats.HEALING_DONE` (+% healing; kits opt in, e.g.
  `PaladinKit.healing_mult`).
- Run statics: `RunState.start_run` resets `EliteAffixes.rate_mult` (1.0) and
  `GoblinSpawner.chance_override` (−1.0) and bumps `RunState.run_serial` (kit statics such as
  `MageFrozen`'s ice count clear themselves when it changes); `Main.start_run` applies the
  launch options right after it.
- Run statistics: the counters `RunState.elites_spawned` / `elites_killed` / `goblins_*` /
  `weapons_forged` / `talent_resets`, `gold_spent` and `record_special_kill(kind, killer)`
  (signal `special_killed`) feed SMOKE_RESULT and, later, the meta statistics.

### Bonus-effect engine (core/bonus/)

- `BonusVocabulary` (pure, frozen): the only entries talents and set bonuses may use.
  - Kinds `stats`, `ability`, `damage`, `damage_taken`, `resource`, `proc`, `script`
    (`KINDS`); also `DAMAGE_SOURCES` (weapon / ability / dot / pet / proc), `SCHOOLS`, `TAGS`
    (`AbilityData.tags` on every ability), `TARGET_CONDITIONS`, `WEAPON_REQUIREMENTS`,
    `TRIGGERS`, `PROC_BLOCKS` (`ProcSystem.BLOCKS` + `EXTRA_BLOCKS`), `SAFE_GENERIC_MOD_KEYS`,
    `RESOURCE_FIELDS`.
  - Any entry may carry `"requires"`: `{"weapon": two_handed | one_handed | dual_wield |
    shield | melee | ranged | magic}` or `{"knows": <ability id>}`. The source adds `"rank"`,
    `"id"` and `"label"`.
  - `validate(entry, class_id) -> String` ("" = valid) is the data tests' contract: unknown
    kinds / keys / stats / tags / schools / triggers / blocks, unsafe mod keys in generic
    matches, mod keys that change no param of the named ability (defaults + `params` + keys
    made by Rank III / V mods), a `"<x>_pct"` mod without an `<x>` param (it would replace
    instead of scale – use `"<x>_pct_add"`), another class's abilities / resources,
    `max_value_add` on a pip resource, proc key rules (`hit_pct` only on `on_hit` /
    `on_crit`; `on_cast` / `cooldown` need exactly one of `ability` / `match`; `"scale"` lists
    only number keys) and script entries by shape (`res://….gd`; the data test loads them).
  - `PSEUDO_IDS` (closed registry, id → class): kit params that are not abilities –
    `warlock_imp`, `warlock_shards`, `warlock_afflictions`, `paladin_aura`,
    `rogue_deadly_poison`. Accepted only as `{"match": {"id": ...}}` in that class's content,
    mod keys unchecked; kits read them with
    `AbilityRunner.apply_mods(BASE, player.ability_mods(id))`. A new one is an integrator change.
  - **Rank resolution** `resolve(entry, rank)`: a deep copy with the amounts × rank – stats:
    every number; ability: `_add` / `_pct` mods (replace keys never); damage / damage_taken:
    `pct`; resource: every `_add`; proc: only the keys listed in its `"scale"`; script:
    nothing (scripts read `rank`).
  - `matches(filter, ability, owner_class)`: the `"match"` filter (`id`, `ids`, `school`,
    `tag`, `kind`, `resource`, `class: true` = the owner's class abilities, general ones
    excluded). `matches_id(filter, ability_id, owner_class)` asks by id; a pseudo id (no
    `AbilityData`) matches only `{"id": <that id>}`.
- `PlayerBonuses` (`player.bonuses`): `set_effects(source, entries)` replaces one source's
  entries – `SOURCE_TALENTS` `&"talents"` (`TalentState.effects()`), `SOURCE_SETS`
  `&"set_bonus"` (`SetBonuses.effects_for`) – and **rebuilds everything from all sources**, so an
  equipment change re-evaluates the talent conditions too.
  - `"requires"` is checked first (`requirement_met` / `weapon_requirement_met`, static);
    unmet entries give nothing. `AbilityRunner.slots_changed` rebuilds only when a `knows`
    condition flipped.
  - `stats`: summed per source into the StatBlock source of the same name (`"primary"` = the
    class's primary stat), then `Player.refresh_armor_spec()`.
  - `ability`: `ability_mods_for(id)` merges the mods of every matching entry
    (`matches_id`; numbers on one key summed, anything else replaces), cached per id until the
    next rebuild, read-only. `Player.ability_mods` merges it after the item mods.
  - `damage`: `damage_mult(target, school, source)` = 1 + Σ pct / 100 of the matching entries
    × every script's `damage_mult`. Filters: `source`, `school` (a name or a list), `target`
    – elite (`is_elite()`: elites, the Loot Goblin, bosses) / boss / stunned (frozen too) /
    slowed / feared / below_pct / above_pct with `target_pct` –, `self_below_pct` /
    `self_above_pct` on the hero's HP %; comparisons strict. Unconditional entries are
    pre-summed, conditional ones pre-parsed (`DamageRule`): nothing allocated per hit.
  - `damage_taken`: `damage_taken_mult(kind, attacker)` = max(0.1, 1 + Σ pct / 100) of the
    entries without a `kind_filter` or with the hit's kind, × the scripts'.
  - `resource`: `<field>_add` summed per resource id (`"primary"` = the first resource) →
    `ClassResource.set_bonus(dict)` on every resource of the hero (`{}` when none).
  - `proc`: the resolved `"proc"` dicts per source → `ProcSystem.set_extra_procs(source, defs)`
    (each def carries the entry's `"label"` unless the proc names one, and its `"id"`). Only
    a source whose defs changed is handed over, then `PlayerBonuses._apply_procs` calls
    `procs.refresh()` **once** – the engine owns the rebuild, `set_extra_procs` only stores.
    A talent change that touches no proc keeps the running proc buffs.
  - `script`: one `TalentEffect` per entry (`load(script).new()`, `source_id` = the entry id,
    `setup(player, rank, raw params)`), diffed by `source|id|index|rank|str(params)`: an
    unchanged script keeps its instance and wave state; removed ones are torn down **before**
    new ones are set up. `scripts()`, `script_for(source_id)`; hooks run in source order
    (talents, set bonuses, others).
  - After a rebuild: `abilities.invalidate_params()` and **one** `changed`.
  - The Player's hooks (the `TalentEffect` list below) are forwarded to every script;
    `crit_forced(target)` is true when any script says so; `teardown()` (Player `_exit_tree`)
    tears every script down. The engine itself draws no random numbers.
- **Derived-damage rule** (one rule for all M5 content): damage derived from a weapon hit is a
  share of the hit's **base amount** – `WeaponRunner.apply_hit`'s incoming damage, crit
  included, before Executioner / Slayer and the outgoing multipliers – dealt with
  `procs.deal_raw(..., target_bonus = false, ...)`, so the outgoing multipliers apply once and
  Executioner / Slayer not again. It arrives as `on_hit_dealt(..., base_damage)` and sits in
  `Player.last_hit_base` during the call (`hit_pct` procs, Seal of Command, Combustion, Agony);
  the Mastery keeps the dealt amount. Damage built from the hero's own stats (Mortal Strike,
  ability-like strikes) uses `target_bonus = true`.

### Player and WeaponRunner hooks

- `Player.create`: `bonuses` and `talents = TalentState.create(class)` before
  `apply_equipment`; `talents.changed` → `bonuses.set_effects(&"talents", talents.effects())`;
  `bonuses.changed` → `abilities.invalidate_params()`; `abilities.ability_cast` →
  `procs.on_ability_cast` + `bonuses.on_cast`.
- `apply_equipment`: item sources → weapons → `bonuses.set_effects(&"set_bonus", …)` →
  `refresh_armor_spec()` (Armor Specialization; the engine also calls it after a stat
  rebuild) → `procs.refresh()` (once per equipment change) → `invalidate_params()`.
- `begin_wave` recomputes Armor Specialization right after `procs.begin_wave()` (the transient
  proc buffs are gone); `end_wave` ends the proc buffs (`ProcSystem.end_wave()`), so market
  recomputes never see them.
- `ability_mods(id)`: item mods, then `bonuses.ability_mods_for(id)` (numbers summed);
  `outgoing_damage_mult` × `bonuses.damage_mult`.
- `take_damage`: a dodge / parry / block (full or partial) calls `_avoided(kind, attacker)` →
  `procs.on_avoided` + `bonuses.on_avoided`; after the temporary multipliers
  `dmg *= bonuses.damage_taken_mult(kind, attacker)`; after `abilities.on_damage_taken`,
  `bonuses.on_damage_taken`.
- Weapon hits: `bonuses.on_hit` runs for **every** hit with `first` = the attack's `ProcGate`
  hit (roll chances and count attacks only then); `notify_kill` (alive) → `bonuses.on_kill`.
- Crits (riposte, melee arc per enemy, projectiles for the aimed enemy): `consume_forced_crit()`
  first (a banked crit is spent even inside Shadow Dance – intended), then
  `bonuses.crit_forced(target)`, then the roll (no draw when forced).
- `begin_wave`: `talents.commit()` first … `procs.begin_wave()` → `abilities.begin_wave()`
  (resources reset) → `procs.after_wave_start()` (`wave_start` procs) → `bonuses.begin_wave()`.
  `end_wave` → `bonuses.end_wave()`; `_physics_process` → `bonuses.tick(delta)`.

### ProcSystem: talent and set procs (core/items/proc_system.gd)

- **Extra procs**: `set_extra_procs(source, defs)` only **stores** a source's rank-resolved
  defs (identical defs: no-op; `[]` removes the source; `extra_defs(source)` reads them) – the
  caller (`PlayerBonuses`) refreshes. A def is the whole entry (`{"kind": "proc", "proc":
  {...}, "label", "id"}`) or a bare params dict. `refresh()` builds the items' enchants /
  uniques first, then the extra procs in source / entry order (`proc_from_params`,
  `proc_from_def`; no id → `"<source>:<index>"`). Numbers are used as written (no enchant rank
  multiplier, no `_fixed`).
- **Triggers** (besides on_hit, on_kill, when_struck, low_hp, periodic, equip):
  - `on_crit`: inside `on_hit` when the attack's ProcGate hit crit – once per attack, chance
    default 100, after the `on_hit` procs of that hit.
  - `on_cast`: `on_ability_cast(ability)`; filter `"ability"` (id) or `"match"`
    (`BonusVocabulary.matches`), none = every cast; damaging blocks take the nearest enemy
    (9 m).
  - `wave_start`: `after_wave_start()`, after the class resources were reset (resource /
    cooldown effects stick).
  - `on_dodge` / `on_parry` / `on_block`: `on_avoided(kind, attacker)` (full and partial
    blocks); the attacker is the target, `extra_attack` swings at it (out of reach = a miss).
  - `periodic` now rolls `chance` (default 100) once per `interval`.
- **Keys**:
  - `every` (N): every Nth qualifying event (after the trigger's filters) fires without a chance
    roll; the count keeps growing while the proc is on `icd` / spent for the wave and resets at
    wave start – except for `wave_start` procs, whose count is the waves.
  - `hit_pct` (on_hit / on_crit only): each damaging block (bolt, chain, nova, explode, drain,
    reflect, smite_heal) deals that % of the hit's base amount (the derived-damage rule, source
    `&"proc"`); a `dot` takes it as its total (ticks `&"dot"`, `target_bonus` false); a `drain`
    heals what it dealt.
  - `max_hp_pct` (heal / shield): % of the **receiver's** Max HP, added to `amount`;
    `"target": "self" | "lowest_ally"` for heal and shield (the shield goes into the
    receiver's ProcSystem).
- **Blocks** (`EXTRA_BLOCKS`; `BLOCKS` unchanged):
  - `cooldown {ability | match, reduce: s}` → `AbilityRunner.reduce_cooldown` on every slotted
    ability it names whose recharge runs; `{…, reset: true}` → `set_cooldown(a, 0)`.
  - `forced_crit {count}` → `player.forced_crits += count`.
  - `resource {resource: <id> | "primary", value}` → `ClassResource.add(value, true)` (Resource
    Regen scales bars, pips are exact), next to the item form `resource {amount}`.
- **Labels** (floating text = the talent / set name): buff, shield, cheat_death, cooldown (only
  when a recharge was really shortened / reset), forced_crit, resource, and heal of extra
  procs; a heal / shield given to another hero shows above that hero. `"label": ""` silences
  every block; damaging blocks show numbers.
- Items behave bit-identically; uniques may use the new triggers / keys / blocks too (the forged
  Legendaries use `every`, `hit_pct`, `on_block`).

### Class resources and casts

- `ClassResource.bonus` (`"<field>_add"` per `BonusVocabulary.RESOURCE_FIELDS`, set by
  `set_bonus(dict)`; clamps the value, emits `changed`) is read through effective getters
  wherever a rule uses the field: `max_value()`, `start_value()`, `regen_per_second()`,
  `decay_per_second()`, `gain_on_hit()`, `gain_on_damage_taken()`, `gain_on_crit()`,
  `gain_per_hits()`, `gain_per_kills()` (`bonus_of(field)` reads one add). It applies on top of
  whichever `ResourceData` is in place (the Mage's Mana copy, the Warlock's shard rule).
  - Clamps: maximum, gains, regen and decay ≥ 0; `gain_per_hits` / `gain_per_kills` ≥ 1 (a rule
    the data lacks starts only with a positive add); start value within 0..maximum;
    `max_value_add` on BAR resources only (pips stay fixed).
  - A pool that starts full (Mana, Energy) starts at the raised maximum:
    `AbilityRunner.begin_wave` calls `ClassResource.top_up_to_start()` after the Mastery's
    `begin_wave` (never lowers).
- `AbilityRunner` (M5):
  - `reduce_cooldown(ability, s)`: shortens the running recharge like time passing; reaching 0
    returns **one** charge and restarts the timer with the overshoot; no-op without a recharge
    or for s ≤ 0. `set_cooldown(a, 0)` still refunds every charge.
  - `cooldown_left(ability)`: the running recharge, also while charges are left.
  - `free_chance` param (percent, mods `free_chance_add`): for a cast with a resource cost the
    runner rolls `RunState.rng.randf() * 100 < clamp(free_chance, 0, FREE_CHANCE_CAP 75)`
    **before** the effect's `cast()`; a free cast spends nothing and shows "Free!"
    (`FREE_TEXT`); a failed `cast()` spends nothing.
  - `last_paid(ability)`: what the current / last cast really pays (0 when free or costless,
    0 before the first cast of the wave), settled before `cast()` and restored when it fails.
    Kits that refund part of a cast cap with it (Meat Cleaver), also inside `cast()`. The cost is
    still taken after `cast()`, so a refund granted inside it is clamped by the maximum then.

### Talents (core/talents/, data/talents/)

- **Data**: `TalentTreeData` (`id` = `<class>_<tree>`, `class_id`, `display_name`, `index` =
  tab order, `description`, `icon`, `color`, `talents`; `get_talent`, `talents_in_tier`) with
  its `TalentData` as sub-resources (`kind` TALENT / MODIFIER / CAPSTONE, `values` per rank for
  the text placeholders – `_fixed` keys unscaled –, `tier`, `column`, `max_rank`,
  `prerequisite`, `ability` (a modifier's ability), `icon`, `effects`; `text_for_rank`,
  `is_capstone`, `is_modifier`). `Db.talent_trees`, `Db.talents` (global ids, a duplicate is an
  error), `talent_trees_for(class)` (by index), `get_talent`, `get_talent_tree`.
  - Tree shape: tiers 1, 2 and 4 two talents, tier 3 a talent of max rank 2 + the modifier,
    tier 5 the capstone – 22 points per tree; talent ids start with the tree id.
- **TalentState** (`player.talents`, per hero): points = `RunState.talent_points_earned()` (one
  per team level from `TALENT_START_LEVEL` 10); every hero has the full count, spent in the
  market only.
  - `add` / `remove` and their block reasons (UI texts): "Talent points from level 10", "Max
    rank", "Needs N points in <tree>", "Requires <talent>", "No talent points"; "Only points
    spent since the last wave can be taken back", "<talent> depends on it", "<talent> needs
    those points".
  - Tier gates `TIER_POINTS` 0 / 3 / 6 / 9 / 12 counted in the lower tiers of the same tree
    (the capstone is the 13th point); a prerequisite is another talent of the tree at max rank.
  - X undo: only `pending` points (added since the last wave start) while nothing taken
    depends on them; `commit()` (Player.begin_wave) makes them permanent and emits nothing.
  - `try_reset(slot)`: refunds every point for `RESET_BASE_PRICE` 20 × 2^resets gold per hero
    through `RunState.try_spend_for(…, &"talent_reset", "Reset Talents")`.
  - `effects()`: deep copies of the taken talents' entries + `rank`, `id`, `label`. `changed`
    (add / remove / reset / `from_dict`) → the Player re-sets the `&"talents"` source.
    `to_dict` / `from_dict` (`{"version": 1, …}`) for the future autosave.
- **TalentEffect** (base of `script` entries): `player`, `rank`, raw `params` (not
  rank-scaled), `source_id`; hooks `setup`, `damage_mult(target, school, source)`,
  `damage_taken_mult`, `crit_forced(target)` (target may be null), `on_hit(target, base,
  is_crit, first)`, `on_kill`, `on_damage_taken`, `on_cast`, `on_avoided`, `begin_wave`,
  `end_wave`, `tick` (also while downed), `teardown`, `describe`.
  - Rules: count attacks / roll chances only when `first`; damage only through
    `procs.deal_raw` (derived-damage rule); hot-path hooks allocate nothing; randomness only
    from `RunState.rng`; `teardown` removes every stat source, `damage_mults` key,
    `death_guards` entry and node the script added.
  - Files `scenes/talents/<class>/<tree>_<name>.gd`, `class_name <Class><Tree><Name>`.
- **TalentBot** (`TalentBot.spend_all(player, slot_index)` from `Intermission._bots_talents`
  after training; `next_talent` for tests): one point at a time; trees in tab order from
  `slot_index % trees.size()`; the first tree that offers something gets the point – its
  capstone (never deferred), else its modifier, else its first addable talent by (tier,
  column).
  - Pass 1 skips **deferred** talents: a modifier whose ability is not slotted, or a talent
    whose effects all `require` something that does not hold now. Pass 2 allows them only when
    no tree offers anything else.
  - So a bot takes its modifier at point 7 and its capstone at point 13. No resets, no RNG.

### Talents tab (scenes/ui/talents/)

- `TalentTab` is `PlayerPanel.TALENTS_TAB` (the third tab; no tab is locked any more), with the
  Trainer's 700 × 480 design body, wired like `TrainerTab` (`message`, `prompts_changed`,
  `handle_input(input, delta) -> bool`, `is_modal()` keeps LT / RT during a reset confirm /
  hold, `prompt_spec()`, `context_text()`) plus `points_changed`: the panel relabels the tab
  "Talents (N)" (`tab_label`; plain "Talents" without free points, before level 10 and for a
  class without trees, which shows "No talents for this class yet").
- Left: `TalentTreeView.TierRail` (gates 3 / 6 / 9 / 12, gold once the selected tree reached
  them, padlocked before) and the trees side by side (`TalentTreeView`, 128 px): name, five
  tier rows of `TalentNode`s at fixed positions (`node_rect`, the capstone centred and bigger),
  prerequisite arrows (`links()`, gold once met, routed between the columns so they never
  cross a node), a dark band over locked tiers, the tree's points.
- `TalentNode`: glyph from `TalentData.icon`, else the modifier's ability (ability / school /
  `TalentGlyph` stat glyph), else the kind's `TalentGlyph` (rune, gear, crown); state rim
  (`State` LOCKED / UNAVAILABLE / AVAILABLE / PARTIAL / MAXED), rank pill "2/3" ringed in the
  player's colour while ranks are pending, gear badge on modifiers, gold capstone frame.
  `state_for` / `source_for` are pure. Sizes kept legible on a 4-player panel at 1280 × 720:
  rank pill 17 px (19 high), tier gate numbers 16 px, the "pts" caption 15 px. Within a shipped
  tree no two plain talents draw the same glyph and the capstone's glyph is its own (modifiers
  may show the ability they change; `test_shipped_trees_have_distinct_glyphs`).
- Right: the header ("Talent points: 2 free · 11 spent", or "Talent points from level 10
  (level 7)" – the trees stay browsable), the selection's detail ("Talent · Tier 2" /
  "Modifier · Whirlwind" / "Capstone" – the tree's name is on the prompt row; every shipped
  talent's kind fits the column on one line –, rank + "+1 this round", the text at the
  current rank – rank 0 shows rank 1 –, "Next rank: …" in green, "You haven't learned X" for a
  modifier whose ability is not slotted, the block reason in red, the tree's identity line
  when it fits; long texts shrink from 16 to 14 px before they are cut) and the Reset row
  ("Reset Talents – 40 g").
- Input (the slot's own `PlayerInput`): spatial d-pad / stick moves (no wrap; down from the
  bottom row reaches the Reset row). **A** adds a point, **X** takes a pending point back,
  **Y** previews the next rank (until the selection changes); refusals show the block reason.
  Reset: A arms "Press A again to reset (40 g)" for `CONFIRM_TIME` 2 s, the second A resets –
  above `ShopPanel.HOLD_SHARE` of the wallet it must be held `HOLD_TIME`; moving, B or losing
  focus cancels. B counts as used only when it cancels, so the Intermission can still unready.
- Hidden, the tab only marks itself stale (talent / gold / level / slot changes) and refreshes
  at the end of the frame it is shown in; the tab label follows at once. Talent stats skip
  `Equipment.changed`, so `points_changed` rebuilds a shown Character tab and
  `set_tab(CHARACTER_TAB)` always rebuilds it.
- Screenshot: `--view=intermission --start-wave=12 --start-level=22 --panel-tab=talents
  --shot-time=16 --classes=warrior` (with the usual `xvfb-run … --screenshot=PATH`).

### Talent content and class kit hooks

Fifteen trees, three per class (`data/talents/<class>/`, GDD 7). Talents are data except the
scripts below; every number is in the `.tres`.

| Class | Trees (index 0 / 1 / 2) | Scripts (`scenes/talents/<class>/`) |
|---|---|---|
| Warrior | Arms (the reference tree), Fury, Protection | `WarriorArmsMortalStrike`, `WarriorFuryRampage`, `WarriorProtectionUnbreakable` |
| Mage | Arcane, Fire, Frost | `MageFireCombustion`, `MageFrostIceLance` (Arcane Power is data) |
| Paladin | Holy, Protection, Retribution | `PaladinHolyHolyShock`, `PaladinProtectionHolyShield`, `PaladinRetributionSealOfCommand` |
| Rogue | Assassination, Combat, Subtlety | `RogueCombatAdrenalineRush`, `RogueSubtletyShadowDance` (Cold Blood is data) |
| Warlock | Affliction, Demonology, Destruction | `WarlockAfflictionUnstableAffliction` (Soul Link, Conflagrate are data) |

Modifiers and data talents reach the kits through new **neutral params** (0 = off) in the
abilities' `.tres` and through the pseudo ids; each kit reads them at cast / refresh time. The
scripts follow the `TalentEffect` rules (no RNG unless noted, `teardown` cleans up).

- **Warrior**
  - Mortal Strike: every 5th attack (`first`) also deals 150% weapon damage and an 8 s Mortal
    Wound (`Enemy.apply_healing_reduction(50, 8)`, ×1.1 damage from this Warrior).
  - Rampage: kill stacks (+2% each, up to 10, 5 s); half of it goes to allies within 8 m as
    `damage_mults["warrior_fury_rampage:<slot>"]`.
  - Unbreakable: a once-per-wave `death_guards` entry (1 s invulnerability, then +30% Max HP for
    10 s, 15% for allies within 8 m); it yields to Shield Wall's "Last Stand"
    (`WarriorShieldWall.guards_lethal()`).
  - Kit: Whirlwind `rage_per_enemy` / `rage_per_enemy_max` (Meat Cleaver: Rage per distinct
    enemy of a spin via `WarriorSpin.on_first_strike`, capped by `last_paid` – a free spin
    refunds nothing; first-pulse refunds are paid on `ability_cast`); Charge `taunt` /
    `shield_per_enemy` / `shield_max` / `shield_duration` (Challenging Charge; taunts released
    with `Enemy.release_taunt` on down / wave / forget); `WarriorAuraVfx` (capstone ring).
- **Mage**
  - Combustion: a first-hit weapon crit burns up to 4 enemies within 2.5 m for a share of the
    base amount (`MageBurn.apply`, 1 s refresh per enemy).
  - Ice Lance: `crit_forced` on frozen enemies; ×(2 + Critical Damage) for ability / dot / pet
    damage on them.
  - Kit: `MageFrozen.is_frozen(e)` (static O(1) live-ice count, cleared on a new
    `run_serial`); Fireball `bomb_pct` / `bomb_radius` → `MageBolt` arms Living Bomb on
    `MageBurn` (`arm_bomb`: explodes when the burn ends or the enemy dies, not on despawn);
    Blink `image_*` → `MageMirrorImage` (a decoy that taunts non-boss enemies, then bursts);
    Blizzard `end_freeze` / `tick_freeze_chance` / `tick_freeze` (Deep / Flash Freeze, tracked
    as `BlizzardEffect.Storm` records; Flash Freeze draws).
- **Paladin**
  - Holy Shock: every 4 s (Haste / CDR scaled) heals the most wounded hero within 8 m below
    90%, else smites the nearest enemy.
  - Holy Shield: on a block, Holy retaliation + a small absorb on the weakest ally
    (`PaladinKit.buff_key`).
  - Seal of Command: 15% per attack (one draw): 70% of the base amount as Holy on the target
    and 2 more enemies + a small heal.
  - Kit: `PaladinKit.healing_mult(caster)` (Healing Done, applied once by every heal / absorb
    that can grow – not Lay on Hands' full heal, revives or Holy Shield); pseudo id
    `paladin_aura` (`BASE` radius / guard / might, read on each aura refresh →
    `damage_taken_mults` / `damage_mults` of every hero inside); Consecration `ally_range` /
    `heal_max_hp_pct` (Light's Hammer) and `taunt` / `ward` (Righteous Fury,
    `damage_taken_mults[PaladinConsecration.ward_key(p)]`), tinted by `ConsecrationVfx`; Word
    of Glory `verdict_pct` / `verdict_sp_scale` / `verdict_range` (Divine Verdict, after
    revive and heal).
- **Rogue**
  - Adrenaline Rush: with ≥ 3 enemies within 5 m, `resource_regen` +50 on the Rogue and
    `haste` +10 on allies within 8 m (1 s linger).
  - Shadow Dance: a real Vanish cast opens 5 s of `crit_forced` (12 s icd); allies within 8 m
    get `crit` +10.
  - Kit: pseudo id `rogue_deadly_poison` (`RogueMastery.BASE` max_stacks / kill_energy);
    `RogueUtil.bonus_crit` (Fan of Knives, Shuriken Toss, Killing Spree and Ambush ask
    `crit_forced`), `RogueUtil.reduce_other_cooldowns` (Restless Blades), `RogueVfx.ring`; Fan
    of Knives `envenom_pct` / `cdr_per_combo` / `cold_blood_*` (Cold Blood: every Nth fan crits
    and slows), `RogueFanOfKnives.throw_free` (Unseen Blades: no cost, no `ability_cast`);
    Vanish `end_fan` and `auto_offense` (bots); `RogueBlade` envenom / slow.
- **Warlock**
  - Unstable Affliction: an afflicted enemy's death (`WarlockAfflictions.afflicted_died`)
    queues a Shadow burst + 1 s stun at the corpse, at most 4 per tick, chaining (4 s stun
    memory).
  - Kit: pseudo ids `warlock_afflictions` (`WarlockMastery.AFFLICTION_BASE`: `agony_pct`,
    `agony_duration`, `agony_spread`, `agony_spread_radius`, `slow`; cached, dropped on
    `bonuses.changed` / `equipment.changed`), `warlock_imp` (`damage_bonus`, Wild Imps too)
    and `warlock_shards` (the shard rule; `kills_per_shard()` returns the effective rule).
  - Agony: every weapon hit of a living Warlock adds `last_hit_base × agony_pct` as a Shadow
    DoT (`WarlockAfflictions.agonize`, ticks `target_bonus = false`); Writhe in Agony splits a
    dying host's Agony.
  - Drain Life `harvest_*` (Dark Harvest) / `shadowburn_*` (a scorch, + a Soul Shard on a
    kill, 10 s shard timer); Rain of Fire `slow`, `wild_imps` / `wild_imp_*`
    (`WarlockImp.spawn_wild`, timed and capped) and `ember_*` (Conflagrate: `WarlockEmbers`
    keeps the area burning).

### Shared purse (GDD 10)

- **Spend log**: every wallet spend of game code goes through `RunState.try_spend_for(amount,
  slot_index, kind, label)` – kinds `&"shop"` ("Rare Dagger"), `&"shop_forge"` ("Rare Dagger
  (forged)"), `&"shop_reroll"` (slot −1, "Stall reroll"), `&"trainer"` ("Fireball Rank III"),
  `&"level_reroll"`, `&"talent_reset"` ("Reset Talents"). Entries `{slot, kind, label, amount,
  wave}` go to `RunState.spend_log` (this round), the amount to `gold_spent` (run), signal
  `spent`. `Intermission.open` starts a round (`begin_spend_round()`: log and wants cleared).
  Selling and Greed gold are income, never logged; plain `try_spend` stays for tests.
- **Wants**: `RunState.wants` (`toggle_want` / `clear_want` / `has_want`, `wants_changed`)
  holds the Trainer pings; shop pings stay on `Shop.Offer.pinged_by`.
- **PurseBoard** (`Intermission.purse_board`, 712 px, in the MARKET header under the title and
  "Next up: Wave N of 25 · S seconds · Level L +k this wave"):
  - wallet (`gold_value`, also `Intermission.gold_value`), `ReadyPips` (a diamond per joined
    player, filled while ready) and "2/4 ready";
  - **Spent**: the round's log newest first, at most `TICKER_LINES` 2 lines + "+N more"
    (`entry_text`: "P1 [Rare Dagger] 62 · Team Stall reroll 12", shop items in their rarity
    colour while the stall lists them);
  - **Wants**: `merged_wants(shop, RunState.wants)` – shop pings, then Trainer pings, per player
    in slot order, on the bottom line + "+N more"; while the spend ticker needs only one line
    the wants may take its second one too (bottom-aligned, the "Wants" caption moves up a row;
    `wants_lines()`, `wants_text()` joins them); players who left are skipped;
  - lines packed by measured width (`pack`); signals only mark the board dirty, `update`
    (every MARKET frame; it compares the players' last index / colour / ready flag field by
    field – typed arrays, no strings) / `refresh` rebuild it; nothing runs during waves; no RNG.
- **Trainer pings**: R3 (keyboard Tab) on a row → `TrainerTab.toggle_ping(i)` →
  `RunState.toggle_want(slot, Trainer.want_key(id) = "trainer:<ability_id>",
  Trainer.spend_label(...), price)`; again removes it. Refused for an empty slot, Rank V and an
  open specialisation; gold does not matter. The row shows a "Wants" tag in the player's colour
  (`TrainerRow.set_ping`); `Trainer.try_buy_rank` clears the buyer's own ping; a player who
  leaves takes their Trainer and shop pings along (`Intermission._on_player_left`,
  `drop_shop_pings`). `UiGlyph.pad` draws L3 / R3 as pills.
- **Hold rule**: shop buys and Trainer ranks above `ShopPanel.HOLD_SHARE` (50%) of the wallet
  need A held `HOLD_TIME` (1 s); the talent reset uses it after its confirm; rerolls never hold.
- **Simultaneous buys**: the Intermission routes input in slot order inside a frame, so when
  the wallet covers one of two purchases the lower slot gets it; the other reads "Not enough
  gold".
- **Ready chips and layout**: a "★N" badge (`Intermission.TalentBadge`) on the portrait while the
  hero has N unspent talent points (`talent_points_free(slot)`); compact chips (min 170 × 56) so
  four fit between the bottom corner panels; the stall sits `STALL_OFFSET_Y` 36 px below the
  centre, the footer `FOOTER_BOTTOM` 6 px above the edge.

### Weapon forging (GDD 4.1)

- `Forge` (`core/items/forge.gd`, static; the only place that decides what forges):
  - `is_forgeable(item)`: a Common..Epic weapon, not hand-made (`ItemInstance.unique`), base
    `source_id` a `Db` weapon (starting weapons too). `pairs_with(a, b)`: two different
    forgeable items with the same base and rarity.
  - `partner_for(eq, item)`: the first match in the backpack (lowest index), then main hand,
    then off hand.
  - `blocked_reason(eq, item)` ("" = can forge): "Only weapons can be forged", "Artifacts grow
    on their own", "Legendary is the highest rarity", "Hand-made weapons cannot be forged",
    "No other Common Dagger", "No room for the forged weapon". `forged_rarity`, `result_text`
    ("→ Rare").
  - `make_result(a, b, rng)`: `ItemGenerator.generate_weapon(base, rarity + 1, max(a.wave,
    b.wave, RunState.wave), a.looted or b.looted, rng)` – fresh suffix stats and enchants. A
    Legendary result gets its weapon type's `ForgeLegendaryData` (`apply_legendary`: name,
    `unique_effect` / `unique_params` / `unique_text`, flavor; it stays `unique = false`).
  - `forge(eq, item, rng)` (panel; only the hero's own weapons): takes both pieces and places
    the result in the main hand if either piece held it, else in the equipped piece's
    position, else in the backpack – the hero is never unarmed; refusals change nothing and
    draw nothing. `RunState.weapons_forged += 1` per forge.
  - `forge_with_offer(eq, offer_item, rng)` (shop), `offer_forge_slots(offer_item, slots)`
    (anvil pips), `bot_forge_all(slot)` (every backpack weapon with a partner – another
    backpack weapon or an equipped one whose position the result takes; never two equipped
    weapons).
- **Legendary effects** (`data/forge/legendary_<weapon_id>.tres`, loaded by
  `Forge.legendaries()`, not by `Db`): ordinary unique procs (`ProcSystem.proc_from_unique`,
  label = the name) that are also valid `BonusVocabulary` proc dicts:

  | Weapon | Legendary | Effect |
  |---|---|---|
  | Dagger | Nettlefang | every 4th hit: `bolt` 100% of the hit as Nature + poison rider (6 over 4 s, 3 stacks) |
  | One-Hand Sword | Oathcleaver | every 3rd hit: `nova` at the target, 60% of the hit, 2.5 m |
  | Mace | Knell of Stone | every 5th hit: `nova` at the target, 80% of the hit, 2 m, 1 s stun |
  | Two-Hand Axe | Reaper's Due | every 4th hit: `nova` around you, 75% of the hit, 3 m, bleed rider (10 over 4 s) |
  | Bow | Thornsong | every 3rd shot: `chain`, 70% of the shot to up to 3 enemies |
  | Gun | Ashmouth | every 3rd shot: `explode` 60% of the shot as Fire, 2.5 m, burn rider (8 over 3 s) |
  | Staff | Pyrewillow | every 4th bolt: `dot` 120% of the hit as Fire over 4 s, spreads 3 m on death |
  | Wand | Moonquill | every 5th bolt: `nova` at the target, 100% of the hit as Arcane, 2.5 m, 30% slow 2 s |
  | Shield | Dawnwall | `on_block`: `reflect` 30 Holy + 1 s stun at the attacker, icd 1.5 s |
  | Tome | The Whispering Codex | every 5th attack: `drain` 120% of the hit as Shadow (heals you) |

- **Shop auto-forge**: `Shop.BuyResult.FORGED`. `try_buy` with a full backpack checks
  `forges_on_buy(index, slot)` (an unsold weapon offer, a partner, room for the result), pays
  through `try_spend_for(…, &"shop_forge", "<name> (forged)")`, runs `Forge.forge_with_offer`
  and keeps the result in `Shop.last_forged`. Without a partner a full backpack still refuses;
  with room the item goes to the backpack as before. `ShopPanel` logs "P1 bought and forged
  [Rare Dagger] – 62 g"; `ShopOfferCard.draw_anvil` marks every player in
  `Forge.offer_forge_slots` (re-evaluated on `Equipment.changed`).
- **Character panel**: "Forge" after Equip / Unequip for every weapon (greyed with
  `blocked_reason`, detail `result_text`); "Forged [Nettlefang]!" selects the result.
- **Bots**: `Intermission._bots_shop` runs `bot_equip_upgrades` → `Forge.bot_forge_all` →
  `bot_equip_upgrades` before buying; `_bot_make_room` sells before every purchase, so bots
  never reach `FORGED`.

### Tier sets (GDD 5.5 / 5.2)

- **Content**: one `SetData` per class (`data/sets/<set_id>.tres`: `id`, `display_name`,
  `class_id`, `piece_ids` Head → Shoulders → Chest → Hands → Legs, `bonuses` =
  `[{"pieces": 2, "text", "effects"}, {"pieces": 4, …}]`; `Db.sets`, `get_set`,
  `set_for_class`). Pieces are Epic `UniqueItemData` (`data/uniques/set_<class>_<slot>.tres`:
  `class_restriction`, the class's armour, `set_id`, primary + Stamina + one secondary on the
  Epic budget, `min_wave` 6, every source, **`weight` 0** – only the set roll picks them).

  | Class | Set (id) | 2 pieces | 4 pieces |
  |---|---|---|---|
  | Warrior | Battlegear of Fury (`battlegear_of_fury`) | `stats {resource_regen: 10}` | `ability {id: whirlwind} {free_chance_add: 30}` |
  | Mage | Regalia of the Arcane (`regalia_of_the_arcane`) | `stats {haste: 10}` | `proc {on_cast, ability: blink, buff {damage_pct: 30}, duration 3, icd 6}` |
  | Paladin | Dawnforged Plate (`dawnforged_plate`) | `stats {armor: 3}` | `ability {id: word_of_glory} {heal_all: true}` |
  | Rogue | Shadowstitch Garb (`shadowstitch_garb`) | `stats {crit: 5}` | `proc {on_cast, ability: vanish, buff {crit_damage: 50}, duration 4}` |
  | Warlock | Felfire Raiment (`felfire_raiment`) | `damage {source: pet, pct: 10}` | `ability {id: rain_of_fire} {free_chance_add: 20}` |

- **Roll** (`ItemGenerator.generate`, after the rarity roll): an Epic becomes a set piece with
  `set_chance(source)` = `SET_CHANCE_SHOP` 5% in the shop, × `SET_LOOT_MULT` 3 = 15% from
  loot / elites / the goblin / bosses. Class: `&"usable_by"`, else the `&"class_data"` bias,
  else a random class with a set from `&"team_classes"` (`LootDrops.team_classes()`, the
  party), else any; the piece is uniform among the available ones (`set_piece_available`; a
  forced `&"slot_type"` is respected, non-set slots never roll). Built with `from_unique`.
- **Bonuses**: `Equipment.set_counts()` counts **distinct** pieces per set;
  `SetBonuses.active_bonuses(set, pieces)` is cumulative (4 pieces = both bonuses);
  `SetBonuses.effects_for(eq)` – the active effects with `"rank": 1`, `"id": "<set id>:<pieces>"`,
  `"label"` = the set name – goes to `bonuses.set_effects(&"set_bonus", …)` on every equipment
  change. Unknown set ids count but give nothing. `active_count(eq)` → SMOKE_RESULT
  `set_bonuses`.
- **Tooltip** (`ItemTooltip`, rows from `SetBonuses.describe(item, eq)`): the set name with
  "(n/5)" for `viewer_equipment` (PlayerPanel / ShopPanel set it) or "(5 pieces)" without
  (the loot roll), the five pieces (bright when worn) – with a
  `viewer_equipment` (the player panels, the shop) the compact block: the pieces' slot names on
  one line ("Head  Shoulders  Chest  Hands  Legs", `SetBonuses.describe` piece rows carry
  `"slot"`) and no flavor text (`ItemTooltip.compact_set()`); without one (the loot roll) the
  full piece names and the flavor –, then "(2) Set: …" / "(4) Set: …"
  green when active. A `set_id` without `SetData` keeps the old "Part of the … set" line.
- **Bot value** (`ItemTooltip.upgrade_direction(item, equipped, viewer, equipment)` – bot
  equips and buys, Need, badges): `SetBonuses.bonus_change(item, displaced, eq, lookahead)`.
  Completing a bonus is an upgrade unless the item scores more than `SET_UPGRADE_TOLERANCE`
  (30%) below the replaced one; breaking one is a downgrade unless the set piece scores 30%
  below the new item.
- **Look-ahead:** `ItemTooltip.set_lookahead(item, displaced, eq, viewer)` lists the backpack
  candidates, best `item_score` first (the item's or a displaced piece's set; other slots; the
  best piece per slot; never displacing a worn set piece; at most `SET_UPGRADE_TOLERANCE` below
  what they replace); `upgrade_direction` passes it, so `Intermission.bot_equip_upgrades`,
  `LootRoll.bot_choice`, `Intermission.bot_offer_choice` and the UI badges all use it. Per
  set, `bonus_change` counts only as many look-ahead pieces as
  `SetBonuses.pieces_to_next_bonus(data, worn)` still needs, in list order (worn = with the
  item on for the item's set, before the swap for a displaced piece's set); they count as worn
  on both sides, pieces already counted (or the item itself) are skipped.
- `Intermission.bot_equip_upgrades` repeats its backpack pass (`_bot_equip_pass`) until one
  equips nothing, at most `Items.BACKPACK_SIZE` passes; it returns the total equipped.

### Elites (GDD 8)

- **Numbers** (`EliteAffixes`, pure statics): from `FIRST_WAVE` 5; HP ×3, `GOLD` 10, XP ×5,
  model and body ×1.3. Expected count `(0.4 + 0.06 (w − 5)) × (1 + 0.35 (n − 1)) × rate_mult`
  (solo: wave 5 0.4, 15 1.0, 25 1.6; four players ×2.05), the fraction is the chance of one
  more (`roll_count`); spawn times uniform in 15–70% of the wave (`schedule`, sorted); the affix
  uniform over `ALL` (`roll_affix`).
  - Shielding: an absorb shield of 30% Max HP, regrowing 8 s after it broke.
  - Enraged: once at ≤ 50% HP – damage ×1.5, speed ×1.3, slow-immune (stuns, freezes, fear
    still work).
  - Frenzied: speed ×1.25, contact / lunge / throw cooldowns ×0.6.
  - Vampiric: heals 10% Max HP per landed hit (through `heal()`, so healing reduction applies).
- **Spawning** (`WaveDirector`): `start_wave` draws the schedule (`elite_times()`) and
  pre-builds the plate textures; `_spawn_group` makes each new enemy an elite while a
  scheduled time has passed (one time per enemy, `make_elite` before `add_child`). Counters
  `RunState.elites_spawned`, `elites_this_wave`; elites count towards `MAX_ENEMIES`; unused
  times are dropped at the wave end.
- **Enemy API** (M5):
  - `Enemy.setup(instance, data, wave)` (subclasses: `create` = `setup(Sub.new(), …)`),
    `_think(delta, here, feared)` (the AI step), `deals_contact_damage()`,
    `_death_loot(pos, attacker)`, `heal(amount) -> float`, `apply_healing_reduction(pct,
    duration)` (strongest wins, equal extends), `healing_taken_mult()`, `release_taunt(target)`.
  - `elite_affix` (`&""` = normal), `make_elite(affix)` (once, no draw), `is_elite()`
    (overridden by the Loot Goblin), `is_enraged()`, `shield_hp` (drained first, "Absorb"
    text), per-enemy `speed_mult` (`walk_speed()`; lunges keep `lunge_speed`),
    `attack_cooldown_mult` (`attack_cooldown()`), `damage_mult`, `kill(attacker)` (instant
    death through the shield, normal loot / credit).
  - Vampiric connects to every hero's `damage_taken` in `make_elite` and disconnects on death /
    despawn.
- **Rewards** branch on `elite_affix` in `_death_loot`: `GOLD` gold and XP ×5,
  `LootDrops.drop_special(ItemGenerator.Source.ELITE, …)` (guaranteed Rare+, killer's Fortune,
  not counted against `loot_drops_this_wave`; M6's Artifact roll goes here too),
  `RunState.record_special_kill(&"elite", slot)`, then the normal drop roll. Every generated
  drop passes `&"team_classes"`. A despawned elite gives nothing.
- **Look** (`ElitePlate`, a visual-only child, never draws): "<Affix> <Enemy name>" in silver
  above the head, a thin HP bar with the shield segment, a gem in the affix colour
  (`EliteAffixes.COLORS`) and silver dragon wings on the bar ends – fixed-size billboards
  without depth test, shared textures. Shielding shows a blue bubble, Enraged a red tint.

### Loot Goblin (GDD 8)

- **Data** `data/enemies/loot_goblin.tres` (`LootGoblin.DATA_ID`): 30 HP (usual growth), no
  contact damage, 4.4 m/s (heroes 5), `first_wave` 3, **`spawn_weight` 0** (never in
  `WaveDirector.eligible_enemies`), gold / XP 0 (custom rewards), `model_style &"goblin"`.
- **GoblinSpawner** (PAUSABLE child of the WaveDirector, made by Main; `announced(text,
  color)` → `Hud.show_banner`):
  - `chance_for(w, fortune)`: 0 below wave 3 and on waves 10 / 20 / 25, else 0.15 + 0.005 ×
    Fortune (`team_fortune()`: the luckiest living hero), at most 0.5; `chance_override` ≥ 0
    (`--goblin-chance`) replaces it on eligible waves.
  - `wave_started` → `roll_wave(w)`: the chance draw (none at 0), then a spawn time uniform in
    [3 s, max(3, 0.35 × duration)] only when it comes (`pending_time()`). Then `spawn_goblin()`
    at `director.find_spawn_point()`: gold burst, `goblins_spawned`, "A Loot Goblin appeared!".
  - At most one per wave; a wave end drops a pending spawn, and `WaveDirector.stop()` despawns
    a living goblin (no loot, neither killed nor escaped).
- **LootGoblin** (`extends Enemy`, group `&"loot_goblins"`):
  - Flight (`_think`): away from the living, visible heroes weighted by 1 / distance², a random
    jink of up to ±70° every 0.6–1.2 s, wall-aware headings (`best_heading`: 16 probes 3 m
    ahead) so a cornered goblin slides out along a wall. With nobody visible it jogs at half
    speed and turns once per jink.
  - Never attacks; taunt and fear are ignored; stun, freeze, slow and knockback work.
    `is_elite()` is true (Slayer, the `elite` talent condition, Execute's victim choice) but it
    has no affix, so no elite rewards; `is_boss()` is false.
  - Each damaging hit spills a 1-gold coin (at most one per 0.15 s, 30 per goblin).
  - Escape: at 15 s of age (`GoblinSpawner.ESCAPE_TIME`) it stops and a `GoblinPortal` opens for
    1.2 s (still killable), then `goblins_escaped`, `escaped` → "The Loot Goblin escaped!",
    `despawn()`.
  - Killed: `kill_gold(w)` = 30 × and `kill_xp(w)` = 25 × the wave's average enemy reward in 8
    piles, `drop_special(Source.GOBLIN, …)` (Rare+, 25% Epic+),
    `record_special_kill(&"goblin", slot)`, a coin burst.
  - Look: `EnemyModel` style **goblin** (big ears, gold-tooth grin, a sack of gold with a
    twinkling glint) and a gold "Loot Goblin" label; `GoblinPortal` is a violet swirl with a
    ground ring (meshes via `MeshKit.cached`).
  - `keep_tag_on_screen()` runs in `_process` (process_priority =
    `CameraRig.PROCESS_PRIORITY + 1`, rendered frames only, no RNG, no gameplay state): the
    "Loot Goblin" tag stays `TAG_SCREEN_PAD` px inside the viewport (`clamp_tag`,
    `tag_screen_size`); off its home spot it is placed with `Camera3D.project_position` at the
    same depth.
- **Bots** never count the goblin as a threat. A living bot with no other enemy within
  `CROWD_RADIUS` and HP ≥ `RETREAT_HP_RATIO` chases the nearest goblin within
  `ENGAGE_DISTANCE` up to its keep distance (melee reach, or `KITE_DISTANCE` when ranged).

### Ghost slow (GDD 16.1, M5 integration)

- While a hero is downed, every physics tick `Player._update_ghost_slow()` (after
  `_update_revive`) asks `EnemyGrid.gather_around(ghost, REVIVE_RADIUS)` for the enemies
  around the ghost and refreshes `Enemy.apply_ghost_slow(Player.GHOST_SLOW_LINGER)` (0.1 s)
  on every living one whose centre is within `Player.REVIVE_RADIUS` (1.8 m) – the circle a
  teammate channels the revive in. `Player.ghost_slowed` counts them (0 when alive).
- `Enemy.ghost_slow_left` is a slot of its own next to `apply_slow`'s `slow_pct` /
  `slow_left`: several ghosts refresh the same slot (it never stacks), it never replaces or
  shortens another slow, and it runs out 0.1 s after the last refresh (the enemy left the
  circle, the ghost walked away or revived). `Enemy.current_slow_pct()` = the stronger of the
  two (`Player.GHOST_SLOW_PCT` 33 vs `slow_pct`); `_apply_movement` inlines the same rule for
  walking and lunges. `is_slowed()` is true for either (the `slowed` talent condition counts
  it). An enraged elite ignores it like every slow (`apply_ghost_slow` refuses, `_enrage`
  clears it); the Loot Goblin is slowed like by every other crowd control.
- Cost: one grid query per ghost per tick, no allocation per enemy, no RNG (group order).
- Look: `OnionModel.set_ghost_slowing(active)` (the Player forwards `ghost_slowed > 0`; only
  changes act): the revive ring leans towards `GHOST_SLOW_TINT` (pale spectral blue,
  `GHOST_SLOW_TINT_MIX` 0.55) and its inner disc breathes from `REVIVE_AREA_FILL` 0.06 up by
  `GHOST_SLOW_FILL` 0.14 at `GHOST_SLOW_PULSE` 2.6 rad/s; `set_downed(false)` turns it off.

### Determinism (M5 draw points)

Everything goes through `RunState.rng`; `--fixed-fps 60` smokes stay bit-identical per seed.

- Wave start (`WaveDirector.start_wave`): eligible list → elite count (one draw when the
  expected count is > 0; waves 1–4 draw nothing new) + one time per elite → next group pick →
  `wave_started` → `GoblinSpawner.roll_wave` (the chance draw when it is > 0, the time draw
  only when the goblin comes) → opening group.
- During a wave: one affix draw per elite right after `Enemy.create`; the goblin's
  `Enemy.setup` draws and two draws per jink; `drop_special` on elite / goblin kills.
  `make_elite`, the plate, coins, piles, the portal and the bots' goblin chase draw nothing.
- Casts: one `free_chance` draw per cast that reaches `cast()` while the clamped chance is > 0
  and it costs something – before the effect's own draws.
- Talent / set procs: like item procs, a draw only when the chance (or PPM) is below 100%;
  `every` procs never draw; `on_crit` procs roll after the `on_hit` procs of the same hit.
- Scripts and kit hooks draw nothing, except Seal of Command (one draw per attack) and Flash
  Freeze (one per unfrozen enemy inside a storm per storm tick). The engine and TalentBot
  never draw.
- Between waves: set rolls inside the generator (only on Epic rolls: the chance, then the
  class and the piece when there is a choice – waves before the first Epic are unchanged);
  forging = exactly one `generate_weapon` per forge (bots forge in `_bots_shop`, slot order);
  the purse draws nothing.

### M5 tests

- Engine and core: `test_m5_foundation.gd` (the foundation contracts: TalentState on fixture trees,
  BonusVocabulary, Db loading, block caps, hooks through test doubles, RunState purse /
  counters / start level, launch options; fixtures live only under the `zz_test` class and
  `Db.talent_trees` / `talents` / `sets` are restored after each test), `test_bonus_engine.gd`,
  `test_proc_triggers.gd`, `test_resource_bonus.gd`, `test_ability_runner_m5.gd`.
- Talent data, bots and UI: `test_talent_data.gd` – the content contract for **every** tree in
  `Db` (shape, ids, prerequisites, placeholders at every rank, `BonusVocabulary.validate`,
  modifiers, icons, script location and `class_name`); new trees must pass it.
  `test_talents_bots.gd`, `test_ui_talents.gd` (fixture trees).
- Per class: `test_talents_<class>*.gd` (every talent added and taken back through
  `player.talents` on a real hero, the scripts end to end, the bot paths) and the text-fit
  tests `test_talents_{warrior,paladin,warlock}_ui.gd` / `test_talents_mage_text.gd` (every
  shipped description shows whole in the Talents tab at `PlayerPanel.DESIGN_SIZE`). Shared
  helpers without the `test_` prefix: `talent_effect_probe.gd` (a recording TalentEffect),
  `talents_mage_base.gd`, `talents_rogue_base.gd`, `talents_warlock_fakes.gd` (`DyingEnemy`).
- Features: `test_purse.gd`, `test_forge.gd`, `test_ui_forge.gd`, `test_sets.gd`,
  `test_elites.gd`, `test_goblin.gd`, plus M5 cases in `test_shop.gd`, `test_ui_trainer.gd`,
  `test_ui_items.gd`, `test_ui_market_loot.gd`, `test_loot_roll.gd`,
  `test_items_weapon_rules.gd`, `test_items_gen_content.gd`, `test_main_bot_input.gd`,
  `test_visuals_models.gd` and `test_class_warrior_m4.gd` (Execute through a shield).
- Tests that change a static (`EliteAffixes.rate_mult`, `GoblinSpawner.chance_override`)
  restore it in their teardown.
- Feature smoke: `godot --headless --fixed-fps 60 --path . -- --smoke --waves=3 --start-wave=4
  --goblin-chance=1 --elite-mult=3 --seed=5`; class smoke with talents: `--smoke --waves=2
  --start-wave=14 --start-level=30 --classes=mage,mage,mage --seed=7`.
- Integration (Wave 3): `test_m5_integration.gd` – tier sets through the engine (Warrior:
  2-piece Resource Regen as a stat and as Rage gained, 4-piece free Whirlwind as a param and as
  the runner's free roll; Mage: 2-piece Haste, 4-piece Blink proc firing / buffing / icd; each
  unequip takes its bonus along), forged Legendaries on real weapon hits (Knell of Stone: every
  5th hit, 80% of the base amount at the target and within 2 m, stun, an outgoing multiplier
  applied once; Pyrewillow: every 4th bolt, a burn of 120% of the base amount), an elite's and
  a goblin's guaranteed drops from the kill through `WaveDirector.stop` banking into the
  Intermission's loot roll, the spend log (a source scan: no `try_spend(` outside RunState and
  exactly the four known spender scripts; then all six kinds in one round with payers, amounts
  and totals), `params_for` merging talents + set + item mods (+ the rank) on Whirlwind and an
  item + talent `radius_pct` summed on Blizzard, a talent reset (refund, every effect kind
  removed, the logged payment, the doubled price, a refused reset logs nothing), the set-aware
  upgrade badges (shop pip, loot chip) and the goblin's `walk_speed()`.
- `test_ghost_slow.gd` – the ghost slow (inside / outside / edge, a living hero slows nothing,
  corpses skipped, 67% speed and ground covered, leaving the circle, a moving ghost, revive
  directly and through a channelling teammate, several ghosts without stacking, other slows
  kept, the goblin slowed, an enraged elite immune, no RNG and repeatable positions).
