# SmartOnion – architecture

Scope of the first playable build (milestones **M0 + M1** of the GDD): 1–4 players join with
controllers / keyboard, pick a class, and fight 25 waves of enemies with auto-attacking
weapons, collecting gold (shared wallet) and XP (shared level). Between waves a simple
"ready up" screen. Later milestones have their own sections below: M2 items, loot and the
shop; M3 class resources, abilities and Mastery; M4 level-up cards, ranks and the Trainer; M5
talents, tier sets, forging, elites, the Loot Goblin and the shared-purse tools; M6a the two
bosses, three new enemies, Artifacts, the Enchanter, consumables and the damage meter.

## Layout

```
autoload/   Db (data registry), PlayerManager (devices / slots), RunState (shared run state)
core/       Stats, StatBlock, CombatMath, PlayerSlot, input/ (PlayerInput + devices + bots);
            items/ shop/ loot/ (M2), abilities/ (M3), progression/ (M4), bonus/ talents/ (M5);
            run_summary.gd, run_card.gd (M6a)
data/       *_data.gd resource classes + classes/ weapons/ enemies/ .tres content; items/
            item_bases/ affixes/ enchants/ uniques/ (M2), abilities/ resources/ (M3),
            talents/ sets/ forge/ (M5), bosses/ consumables/ artifacts/ (M6a)
scenes/
  main/     Main – game flow state machine                         [integration]
  arena/    Arena – battlefield, walls, entities root               [visuals]
  camera/   CameraRig                                                [visuals]
  world/    SpiritHealer – level object of the arena (revives ghosts)  [visuals]
  visuals/  Mats, OnionModel, EnemyModel, WeaponModel, BossModel (M6a)  [visuals]
  vfx/      Vfx – fire-and-forget effects                           [visuals]
  player/   Player, WeaponRunner, Projectile                        [player]
  abilities/  per-class AbilityEffect / MasteryEffect scripts (M3, M4)
  talents/  per-class TalentEffect scripts (M5)
  artifacts/  TalentEffect scripts of the Artifact properties (M6a)
  enemies/  Enemy; EliteAffixes, ElitePlate, LootGoblin, GoblinPortal (M5); Boss, PoisonPuddle,
            HookLine, hazards/ (M6a)                                 [enemies]
  pickups/  Pickup, LootBag (M2)                                     [enemies]
  waves/    WaveDirector; GoblinSpawner (M5)                         [enemies]
  ui/       UiTheme, MainMenu, Lobby, Hud, Intermission,            [ui]
            GameOverScreen (+ MeterPage), PauseMenu; items/ shop/ loot/ (M2), level_up/ trainer/ (M4),
            talents/ purse/ (M5), enchanter/ (M6a)
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
   - Waves 10 and 25 are **boss waves** (M6a): `start_wave` makes no timer and, 2 s after a rune on the ground,
     spawns the `Boss`; the wave ends with its death (see "Bosses, boss waves, elite wave 20, hazards, HUD").
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
   move) → if n == 25 (Vor'thalax's death, M6a) → GAME_OVER (victory), else **INTERMISSION** (tree paused,
   `Player.end_wave()` on every hero – abilities / Mastery drop auras and buffs –,
   `Intermission.open(n, RunState.pending_level_ups)`: loot roll → level-up cards (when levels
   were gained) → market; players ready with START, bots and unplugged
   devices auto-ready; after `Intermission.auto_continue_time` – default
   `AUTO_CONTINUE_TIME` = 60 s, ≤ 0 switches it off – the next wave starts even if not
   everyone is ready) → `pending_level_ups = 0` (the cards resolved them) → wave n+1.
5. **GAME_OVER** – `RunState.end_run(victory)`, tree paused, HUD hidden,
   `GameOverScreen.open(victory)` (M6a: two pages, Summary and Damage Meter, awards and the run card, see "Damage
   meter, end screen, run card"; `Main.end_run` records every hero's result first). A / START → **LOBBY with the
   same players** (ready again); the main menu only through the lobby's Back.
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
    0.10 (0.08 before the M5 balance pass). A future DifficultyData may override them.
  - `party` = `RunState.COOP_DAMAGE_MULTS[players - 1]` = 0.45 / 0.6 / 0.75 / 0.95 for 1–4
    players (M4: 0.35 / 0.45 / 0.6 / 0.8): small parties have fewer rescuers (solo: the first
    down is defeat) and more enemies per head.
  - Bosses (M6a) take their HP from `BossData.max_hp_for(wave, players)` = `hp_at_wave × (1 + coop_hp_per_player
    (n − 1))` (Morvain 0.75, Vor'thalax 2.0) instead of `coop_hp_mult`; their damage is the usual growth × `party`.
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
- Waves 10 and 25 are **boss waves** (`RunState.is_boss_wave` and a `BossData` for the wave in `Db.bosses`): the
  timer is replaced by the boss, the wave ends when it dies, the normal spawn runs at half rate (adds), and there
  are no elites and no Loot Goblin. Wave 20 (`RunState.is_elite_wave`) is the **elite wave**: every enemy gets a
  lite affix (HP ×1.5, normal rewards) and the real elites come twice as often. Details: "Bosses, boss waves,
  elite wave 20, hazards, HUD" in the M6a chapter. M5 adds elites from wave 5 and the Loot Goblin (never on waves
  10 / 20 / 25) – see "Elites" and "Loot Goblin" in the M5 section.

## Command line (Main)

Parsed by `LaunchOptions` from `OS.get_cmdline_user_args()` (everything after `--`).

| Flag | Meaning |
|---|---|
| `--smoke` | Bots, menus skipped, `Engine.time_scale = 4` (with 4× physics ticks, so the simulation step stays 1/60 s of game time), plays `--waves=N` waves (default 3), prints one line `SMOKE_RESULT {json}` and quits. Exit 0 only when every wave completed and no engine / script error was logged (`ErrorCounter` is an `OS.add_logger` logger); exit 1 on errors, on a timeout (real-time watchdog) or – with `--allow-defeat` – on a defeat. Without `--allow-defeat` a full party wipe is counted (`wipes`) and everybody is revived, so later waves still get exercised. A boss that outlives its enrage by 120 s is killed by the smoke safety (`SMOKE boss timeout`, M6a), so `completed` does not prove the boss is beatable. |
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
| `--panel-tab=NAME` | Dev: when the market first opens, P1's PlayerPanel switches to `talents`, `trainer`, `character` or `enchanter` (`PlayerPanel.debug_start_tab`, screenshots of the Talents tab). |
| `--boss-hp=X` | M6a test hook: multiplies boss HP (`BossData.hp_mult`, clamped 0.01..100, default 1; it scales Morvain too). |
| `--artifact-chance=X` | M6a test hook: replaces the chance of every Artifact roll (`LootDrops.artifact_chance_override`, 0..1; 0 = never, default off; from wave 10 and the class rule still apply). |
| `--end-page=NAME` | M6a dev: the page `--view=game_over` / `victory` opens on, `summary` or `meter`. |
| `--save-card` | M6a dev: saves the run card (needs a display) as soon as the end view is forced; prints `CARD <path>`. |

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
`gold_spent` (every `RunState.try_spend_for`). M6a adds `bosses_killed`, `artifacts_dropped`,
`consumables_bought`, `black_market_bought`, `enchants_done`, `dust_earned`, `dust_spent`, `run_time`, `meter`
(per slot) and `taken_by_source` (see the M6a chapter). Each cleared wave also prints a
`SMOKE wave n cleared ...` line (M5: `elites killed/spawned, goblin spawned/killed/escaped`),
and each closed market prints `SMOKE market closed after wave n: G gold carried into wave n+1
(R bot rerolls so far)`.
Bots (`BotInput`) kite by weapon reach (melee heroes close in, back off when hurt or
crowded), avoid walls, stay near the team and run to downed teammates within
`BotInput.RESCUE_RANGE` (5 m) when it is safe; a ghost bot walks straight to the Spirit Healer
and waits inside its circle (`HEALER_STOP_DISTANCE`) – with Resurrection Sickness it drifts to
a living teammate instead. A Loot Goblin is never a threat to them; they chase it when nothing
else is close (M5, "Loot Goblin"). M6a: they sidestep the Flesh Golem's hook, leave boss hazards and poison
puddles (`BotInput._hazard_steer`) and prioritise the Cultist Acolyte. Between waves bots equip, forge, buy,
train, spend talent points and reroll (M2, M4, M5 sections), and from M6a also enchant, buy consumables and the
Black Market (M6a chapter).
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
- M6a UI additions (details in the M6a chapter): the HUD plaque shows a boss frame instead of the timer on boss
  waves, `UnitFrame` the active consumables; the market has the consumables row, the Black Market card and the
  Enchanter tab (`PlayerPanel` tab 4); the loot roll's B button reads Disenchant / Pass (all pass: Dust); the
  `GameOverScreen` pages between the Summary and the Damage Meter on LB / RB (Q / E) and saves the run card on X (R).
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
    `Enemy.is_boss()` (true for `Boss`, M6a).
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
  `&"level_reroll"`, `&"talent_reset"` ("Reset Talents"); M6a adds `&"consumable"`, `&"black_market"` and
  `&"enchant"`. Entries `{slot, kind, label, amount,
  wave}` go to `RunState.spend_log` (this round), the amount to `gold_spent` (run), signal
  `spent`. `Intermission.open` starts a round (`begin_spend_round()`: log and wants cleared).
  Selling and Greed gold are income, never logged; plain `try_spend` stays for tests.
- **Wants**: `RunState.wants` (`toggle_want` / `clear_want` / `has_want`, `wants_changed`)
  holds the Trainer pings; shop pings stay on `Shop.Offer.pinged_by`.
- **PurseBoard** (`Intermission.purse_board`, 722 px since M6a, in the MARKET header under the title and
  "Next up: Wave N of 25 · S seconds · Level L +k this wave" – no seconds before a boss wave,
  `Intermission.next_wave_text`):
  - wallet (`gold_value`, also `Intermission.gold_value`; M6a: the Arcane Dust `dust_value` to its right),
    `ReadyPips` (a diamond per joined
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
  not counted against `loot_drops_this_wave`; the M6a Artifact roll is made here too),
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

## M6a: bosses, new enemies, Artifacts, Enchanter, consumables, damage meter

```
core/items/       artifacts.gd (Artifacts), enchanter.gd (Enchanter), consumables.gd (Consumables)
core/shop/        black_market.gd (BlackMarket)
core/             run_summary.gd (RunSummary), run_card.gd (RunCard)
data/             boss_data.gd + boss_ability.gd (BossData, BossAbility), consumable_data.gd,
                  items/artifact_data.gd; bosses/ consumables/ artifacts/ (.tres, loaded by Db)
scenes/enemies/   boss.gd (Boss), poison_puddle.gd, hook_line.gd, support_beam.gd, support_shield.gd;
                  hazards/ (EnemyHazard, FrostCircle, FrostBreath, FireField, MeteorStrike)
scenes/artifacts/ TalentEffect scripts of the Artifact properties
scenes/visuals/   boss_model.gd (BossModel)
scenes/ui/        meter_page.gd, meter_bar.gd, run_card_view.gd; enchanter/ (EnchanterTab, EnchanterRow,
                  DustIcon); shop/ consumable_card.gd, consumable_icon.gd, consumable_tooltip.gd
```

- Built as a foundation plus six features (enemies, bosses, Artifacts, Enchanter, consumables / Black Market,
  damage meter), merged, reviewed; a balance pass and a set of fixes followed. The sections below follow the
  features; "Cross-system contracts" lists what holds between them, "Balance pass" and "Validation and balance
  data points" the numbers.
- Out of scope: M6b (modes, environments, events, the Dungeon portal, content packs, the final balance), GDD 16.

### Foundation hooks

The shared hooks the M6a features are built on (behaviour-neutral on their own: a seeded
`--fixed-fps 60 --smoke --waves=6 --seed=5` gave the pre-M6 numbers); what each feature does with them is in its
own section below.

#### RunState (autoload/run_state.gd)

- **Arcane Dust** (the second team currency, GDD 5.7): `arcane_dust` (the pile), `dust_earned`,
  `dust_spent` (run totals), `add_dust(amount, slot_index := -1, label := "")` (non-positive does nothing),
  `can_afford_dust(amount)`, `try_spend_dust_for(amount, slot_index, kind, label) -> bool` (false and no
  change if too poor / negative). Signal `dust_changed(dust, delta)` fires on every change (and once with
  delta 0 from `start_run`). Dust has its own logs, **separate from the gold `spend_log`**:
  `dust_spend_log` (`{slot, kind, label, amount, wave}`) and `dust_gain_log` (`{slot, label, amount,
  wave}`), both cleared by `begin_spend_round()`. The purse board lists the gold log only; an Enchanter
  action carries its Dust cost in the gold entry's label ("Empower Blazing (8 Dust)").
- **Spend kinds** of `try_spend_for` (the Spent ticker shows every one): `&"shop"`, `&"shop_forge"`,
  `&"shop_reroll"`, `&"trainer"`, `&"level_reroll"`, `&"talent_reset"`, and the M6 kinds `&"consumable"`,
  `&"black_market"`, `&"enchant"`. An Enchanter action pays gold with `try_spend_for(..., &"enchant", ...)`
  and Dust with `try_spend_dust_for(..., &"enchant", ...)`; both are checked affordable before either is spent.
- **Damage meter record** (per player slot index, like `kills_by_player`): `healing_by_player`,
  `absorbed_by_player`, `damage_taken_by_player` (float), `revives_by_player`, `downs_by_player`,
  `bosses_by_player` (int) and the recorders `record_heal / record_absorb / record_damage_taken /
  record_revive / record_down` (a slot index < 0 and non-positive amounts are ignored); the callers are listed in
  "Damage meter, end screen, run card".
- **Damage by source** (balance diagnostics, no gameplay): `damage_taken_by_source: Dictionary` =
  `{source id: {wave: float}}`, cleared by `start_run`; `record_damage_taken(player_index, amount, source_id :=
  &"")` adds to it under the current wave when `source_id` is given (see "Balance pass").
- **Run clock**: `run_time: float`, `tick_run_time(delta)`. `Main._physics_process` ticks it while
  `state == State.WAVE` and the tree is not paused, i.e. the sum of the wave times ("Wave cleared!", the
  loot roll, the market and pauses do not count).
- **Counters**: `bosses_killed` (`record_special_kill(&"boss", slot)` counts it and emits `special_killed`
  like elite / goblin), `artifacts_dropped`, `consumables_bought`, `black_market_bought`, `enchants_done`,
  `artifact_pity: float`, `artifact_classes: Array[StringName]`, signal `artifact_dropped(item, source)`.
- All of the above are reset by `start_run`, which also resets the launch statics (`BossData.hp_mult = 1.0`,
  `LootDrops.artifact_chance_override = -1.0`) next to the existing `EliteAffixes.rate_mult` /
  `GoblinSpawner.chance_override`; `Main.start_run` re-applies them from `LaunchOptions` afterwards.

#### Enemies, Db, data

- `EnemyData.is_boss := false`; `Enemy.is_boss()` = `data != null and data.is_boss` (the Loot Goblin overrides
  it with `false`). Execute / Mirror Image / Word of Glory / `PlayerBonuses` "boss" conditions read it.
- `EnemyData.Behavior` = `CHASE, SWARM, LUNGE, RANGED, SUPPORT, BRUTE` (the two new values are appended: the
  stored ints of the existing `.tres` files are unchanged). `Enemy._think` dispatches them to
  `_think_support` / `_think_brute` (both implemented by the enemies below; the foundation default was `_update_chase`).
- `Enemy._on_death_effect()` (virtual): called from `_die` after `_death_loot` and **before
  `_leave_world()`**, i.e. while the enemy is still in the tree (`global_position` is the place of death).
  Not called by `despawn()` (wave end), only by real deaths (`take_damage`, `kill()`); it runs for every
  enemy including the goblin and bosses.
- `BossData extends EnemyData` (`is_boss` true by default); static `BossData.hp_mult` is the `--boss-hp`
  multiplier. `Db.BOSS_DIR = res://data/bosses/` -> `Db.bosses` / `get_boss(id)`;
  `Db.CONSUMABLE_DIR = res://data/consumables/` -> `Db.consumables` / `get_consumable(id)`;
  `Db.ARTIFACT_DIR = res://data/artifacts/` -> `Db.artifacts` / `get_artifact` / `artifact_for_class` /
  `artifact_classes()`. **Bosses are not in `Db.enemies`** (the wave director's random pool never sees them)
  and **Artifacts are not in `Db.uniques`**.
- `ConsumableData` (`data/consumable_data.gd`): `id`, `display_name`, `kind` (`POTION` / `FOOD`),
  `effects: Array[Dictionary]` (BonusVocabulary entries), `base_price`, `icon_id`, `description`.

#### Shop, Intermission, PlayerPanel

- `Shop.consumables` and `Shop.black_market` live next to `offers` but are **not part of `offers`** (that array
  drives `offer_count`, the usable-per-player maths, the reroll positions and the card grid).
- `Intermission._bots_shop` order (final): equip upgrades / forge -> `_bots_enchant` (from wave 12, a slice of
  the purse above the Trainer reserve) -> `_bots_buy` -> `_bots_black_market` (from wave 15) ->
  `_bots_consumables` (from wave 6) -> `_bots_train` -> `_bots_talents` -> `_bots_reroll`. Each new pass is
  free to draw from `RunState.rng` only when it does something; the Black Market and consumables passes draw
  nothing, the Enchanter pass draws one `randf` per Reroll / Imbue.
- `PlayerPanel.ENCHANTER_TAB = 3` (in `TAB_NAMES`, `TAB_IDS`, `LaunchOptions.PANEL_TABS`). The `LOCKED_TABS`
  mechanism (padlock + "Coming soon", `switch_tab` skips locked tabs, `set_tab` / `--panel-tab` refuse them) is
  kept, **empty** since the Enchanter tab is open.
- **Market header**: `Intermission.next_wave_text(next: int) -> String` (static) builds the "what comes next" line
  of the MARKET header: `"The final battle is won"` after the last wave; for `RunState.is_boss_wave(next)` the
  boss line `"Next up: Wave 10 of 25 – Boss wave! (ends when the boss falls)"` (no seconds, no `·`: a boss wave has
  no timer); otherwise `"Next up: Wave N of 25  ·  S seconds"` plus `"  –  Elite wave!"` on the elite wave. `_fill()`
  uses it; the header colour is red for boss / elite waves.

#### Items, Player, Loot

- `ItemInstance.enchant_uses := 0` (Enchanter actions done on the item; the price doubles with each); forged
  items are new instances (0).
- `Player.heal(amount, source_slot := -1)` and `Player.revive(hp_ratio, reviver_slots: Array[int] = [])`
  are the credit points of the damage meter (see "Damage meter, end screen, run card").
- `LootDrops.roll_artifact(source, enemy, killer)` is called **from `drop_special`** (ELITE / GOBLIN / BOSS,
  after the item bag) and **from `on_enemy_killed`** (LOOT, after the normal roll, also when the wave cap or
  the chance roll produced no item bag). An elite kill calls it twice and a boss kill once per hero; the real
  roll counts one kill once (see "Artifacts"). `on_enemy_killed` still returns only the normal item bag (the
  normal-roll body is `_roll_normal_drop`). Test hook: `LootDrops.artifact_roll_probe` (called with
  `source, enemy, killer`, return value used as the bag); `LootDrops.artifact_chance_override`
  (`--artifact-chance`, -1 = off).

#### Main, SMOKE_RESULT, command line

- SMOKE_RESULT keys added in M6: `bosses_killed artifacts_dropped consumables_bought black_market_bought
  enchants_done dust_earned dust_spent run_time` (`run_time` at 0.1 s), the damage meter's `meter` (per slot) and
  the balance pass's `taken_by_source` (see "Balance pass"). Key presence is asserted in
  `tests/test_m5_foundation.gd`, `test_main_m2_flow.gd` and `test_m6_foundation.gd`.
- Launch flags: `--boss-hp=X` (multiplies boss HP, `BossData.hp_mult`, clamped 0.01..100, default 1),
  `--artifact-chance=X` (overrides every Artifact roll's chance, clamped 0..1, default -1 = off; 0 = never, not
  off), `--panel-tab=enchanter`, the end screen's `--end-page=summary|meter` and `--save-card`. `--waves=N` is a
  **count**: `--start-wave=9 --waves=2` plays waves 9 and 10; `--start-wave=24 --waves=25` plays 24 and 25.
- New smoke log lines: `SMOKE boss <name> arrived / defeated ...`, `SMOKE boss timeout ...`, `SMOKE defeat with
  boss ...` (bosses), `SMOKE artifact drop: ...` / `SMOKE artifact held: ...` (Artifacts), `SMOKE meter P1 ...`
  (damage meter), `SMOKE heroes: ...` (balance, a second line at every boss arrival).

### Enemies: Plague Ghoul, Cultist Acolyte, Flesh Golem

New enemy types are pure data plus the behaviours below:

| id | behavior | wave | notes |
|---|---|---|---|
| `plague_ghoul` | CHASE | 7 | `death_effect = &"poison_puddle"` |
| `cultist_acolyte` | SUPPORT | 9 | `priority_target = true`, `attack_cooldown` = channel period |
| `flesh_golem` | BRUTE | 12 | `attack_cooldown` = hook period, `contact_damage` 2.5 (4.0 before the balance pass), hook = 1 x contact |

`EnemyData` gained three export groups, all read by `Enemy` (no per-type subclass; the behaviour
follows the data, so `Enemy.create(data, wave)` stays the one factory):
- **Death effect:** `death_effect` (`&""` / `&"poison_puddle"`), `death_radius`, `death_duration`,
  `death_tick_interval`, `death_damage_ratio` (fraction of the dead enemy's contact damage per
  tick), `death_color`. `Enemy._on_death_effect()` (the foundation hook) builds a `PoisonPuddle`.
- **Support:** `support_distance_min/max`, `support_range`, `support_channel`, `support_heal_pct`,
  `support_shield_pct`, `priority_target`.
- **Brute:** `hook_range_min/max`, `hook_telegraph`, `hook_pull`, `hook_damage_ratio`.

`Enemy.AiState` gained `CHANNEL` and `HOOK` (appended); `Enemy.SupportAction { NONE, HEAL, SHIELD }`.
`Enemy.create` / `setup` draw one extra `RunState.rng` value for SUPPORT and BRUTE (the staggered
first cooldown, like RANGED) and join `priority_targets` for `priority_target` data.

**Support (`_think_support`)**: `_update_support_move` (distance band, herd centroid from
`EnemyGrid.gather_around`, wall-aware retreat), `_pick_support_target` (heal = lowest HP share among non-bosses, else
shield = highest max HP below the shield goal - a boss can get that shield; grid query, group order
breaks ties),
`_start_channel` / `_update_channel` / `_finish_channel`. `apply_support_shield(pct)` is the no-stack
shield (raises `shield_hp` to `max_hp * pct` at most; a normal enemy gets a `SupportShield` bubble,
an elite shows it on its `ElitePlate`). **`Enemy._absorb` only starts the regrow timer for the
Shielding affix** (before, any broken `shield_hp` regrew like an elite's).
`_cancel_special(cooldown_ratio)` ends a channel / hook telegraph (called from `apply_stun`,
`apply_fear`, `apply_taunt`, the no-target wander branch of `_think` and, for CHANNEL only, a
knockback in `take_damage`); it leaves `attack_cooldown_left >= attack_cooldown() * ratio`.
`SUPPORT_*` constants hold the tuning that is not in the data (rescan 0.25 s, herd radius 10 m,
leash 1.5 m, retry 0.5 s ...).

**Brute (`_think_brute`)**: walks like CHASE; `_start_hook` (nearest visible living hero in the
band) -> `ai_state = HOOK`, a `HookLine` child; `_update_hook` (stands still, the aim follows the
hero until the last `HOOK_AIM_LOCK` = 40 % of the telegraph); `_fire_hook` (first visible living hero
whose centre is within `HookLine.HALF_WIDTH` = 0.6 m of the line and `hook_range_max + 0.5` m along
it -> `Player.take_hook`, pull limited by `HOOK_STOP_GAP`). `Enemy.hook_serial` counts hooks;
`Enemy.hook_escape_dir(pos, margin)` is the sidestep direction bots use.

**New nodes (scenes/enemies/):**
- `PoisonPuddle` (`class_name`, groups `enemy_hazards` and `ability_areas`): `spawn(parent, centre,
  radius, duration, tick, damage, colour)`, cap `MAX_ALIVE` = 12 (oldest by age, then by serial),
  `alive(tree)`, ticks heroes whose centre is inside with `KIND_AOE` and no source. Being in
  `ability_areas` is deliberate: `WaveDirector.stop()` and `Main.open_intermission()` already
  sweep that group, so no hazard outlives its wave without touching those files (the group is
  read by those two sweeps and by tests). The puddle is also an `enemy_hazards` node that answers the
  bots' `hazard_push(from)` (see "Cross-system contracts"); the bosses' hazards are swept through
  `enemy_hazards` by `WaveDirector.stop()`.
- `SupportBeam` (world-space beam + landing orb), `HookLine` (telegraph band shader + strike
  chain; `HALF_WIDTH` is the gameplay width too), `SupportShield` (violet bubble of a shielded
  normal enemy). All visual only, children of the enemy, freed with it.

**Player (scenes/player/player.gd):** `take_hook(raw, toward, distance, source) -> bool` (one Dodge
roll like `take_damage` with `KIND_PROJECTILE`; invulnerable / downed heroes are immune; a dodged
hit leaves no `invulnerable_left`, every other outcome does - that is how it tells a dodge from a
hit without a second roll), `pull_toward(point, distance, duration = PULL_TIME)` (a drag through
`_update_movement`, so walls / the screen edge still stop it; `_pull_motion` is the only line added
to the movement step), `is_pulled()`.

**Bots (core/input/bot_input.gd, scenes/player/weapon_runner.gd):** `BotInput.priority_enemy(tree,
pos, reach)` (O(1) without an Acolyte alive: group `priority_targets`), used by
`WeaponRunner.find_target()` **for bots only** (3 lines); chase of a priority target within 14 m
when healthy and not crowded; hook sidestep with `HOOK_DODGE_CHANCE` 0.6 (decided once per golem and hook by the
bot's own RNG: `_hook_serials` / `_hook_dodges` are dictionaries keyed by the golem's instance id,
pruned in `think()` when the golem is gone or no longer in `HOOK`).

**EnemyModel:** styles `ghoul`, `cultist`, `golem` (+ Glow parts: ghoul boil, cultist orb);
`play_windup(color)`, `play_channel()` (violet tell), `cancel_windup()`.

### Bosses, boss waves, elite wave 20, hazards, HUD

#### Data (`data/boss_data.gd`, `data/boss_ability.gd`, `data/bosses/*.tres`)

- `BossData extends EnemyData` (`is_boss = true`; `max_hp` / `contact_damage` are the base values,
  the usual wave growth applies). Fields: `boss_wave`, `intro`, `phase_hp_ratio` (0.5),
  `phase_cooldown_mult`, `abilities: Array[BossAbility]`, `coop_hp_per_player` (per boss: Morvain 0.75,
  Vor'thalax 2.0; the default of the field is 0.75), enrage
  (`enrage_time` 90, `enrage_damage_mult` 1.5, `enrage_speed_mult` 1.3, `enrage_step_time` 30,
  `enrage_step_damage` 0.25), `reward_gold` (50). Helpers: `BossData.for_wave(w)` (Db lookup by
  `boss_wave`, lowest id on a tie, null = the wave is a normal one), `max_hp_for(wave, players)` =
  `hp_at_wave × (1 + coop_hp_per_player (n − 1)) × BossData.hp_mult` (`--boss-hp`), `enrage_level_at(age)`,
  `enrage_damage_at(level)`, `intro_text()`. Crowd control is data + `Boss`: `knockback_resist = 1`
  in the files, the stun / slow / taunt / fear rules are constants of `Boss`.
- `BossAbility extends Resource` (a sub-resource of the .tres): `kind` (`FROST_CIRCLES`,
  `FROST_BREATH`, `SUMMON`, `FIRE_FIELDS`, `METEOR`), `interval`, `interval_p2` (0 = interval ×
  `phase_cooldown_mult`), `first_delay` (0 = 60% of the interval), `telegraph`, `radius`, `angle`,
  `range`, `damage_mult` (× the boss's contact damage; the shared TOTAL for the meteor),
  `fallback_damage_mult`, `count` / `count_p2`, `duration`, `tick_interval`, `slow_pct`,
  `slow_time`, `summon_id`. A new boss is a new .tres with other numbers; a new ability kind is a
  `Kind` value, a `_cast_*` in `Boss` and (if it lays something down) an `EnemyHazard` subclass.
- `data/bosses/lich_commander_morvain.tres` (wave 10: base HP 450, contact 3, speed 1.9, radius 0.8,
  scale 2.1, model `lich`, Frost Circles 7 s / Raise Dead 12 s (4, 6) / Frost Breath 9 s, cooldowns
  ×0.7 in phase 2, `coop_hp_per_player` 0.75 = x1 / x1.75 / x2.5 / x3.25 by party size) and
  `data/bosses/vorthalax.tres` (wave 25: base HP 450 (the plan's 1200 was never reachable, see "Balance data
  points"), contact 1.5 (4.0 before the balance pass), `coop_hp_per_player` 2.0 (0.75 before) = x1 / x3 / x5 / x7,
  speed 2.0, radius 1.1, scale 2.3, model `demon`, Fire Fields 8 s (2, 3) / Meteor 14 s (10 s) / Imp Swarm 20 s
  (6 Candlekin)). Bosses live in `Db.bosses`, never in `Db.enemies`.

#### Boss (`scenes/enemies/boss.gd`, `class_name Boss extends Enemy`)

- `Boss.create(data, wave)` (same signature as `Enemy.create`): `Enemy.setup`, group `&"bosses"`,
  max HP from `BossData.max_hp_for` (the boss co-op rule, not `coop_hp_mult`), one
  `AbilityState {ability, left, casts}` per ability (first cast after `first_cast_delay()`), and its
  own `BossModel` (replaces the placeholder `EnemyModel` `setup` built). Contact damage = base ×
  wave growth × `RunState.coop_damage_mult()` (as every enemy).
- It walks like CHASE and runs an ability scheduler in `_physics_process` (after `Enemy`'s): enrage
  (`enrage_level` from `_age`; sets `Enemy.damage_mult` / `speed_mult`, which contact hits and
  `damage_of(mult)` read), phase (`phase` 1 → 2 once at `phase_hp_ratio`; running timers keep their
  progress at the new interval), abilities (timers do not run while stunned; no target → retry
  after 0.5 s). Signals `phase_changed(phase)`, `enrage_changed(level)`, `ability_cast(ability)`.
  `age()`, `hp_ratio()`, `is_boss_enraged()` for the HUD / director.
- Crowd control: `take_damage` drops the knockback, `_apply_movement` clears direct
  `knockback_velocity` writes (Warrior kit), `apply_stun` ×0.25, `apply_slow` ×0.5, `walk_speed()`
  compensates so the ghost slow also lands halved, `apply_taunt` / `apply_fear` do nothing.
- Death (`_death_loot`): `reward_gold` + `data.xp` pickup, one `LootDrops.drop_special(Source.BOSS,
  self, hero)` per joined player (killer first, items on a 1.2 m ring around the corpse; without
  joined slots `RunState.player_count` drops), `RunState.record_special_kill(&"boss", killer)`.
  No `LootDrops.on_enemy_killed`: the Artifact roll is made by the BOSS-source `drop_special` calls
  only (the Artifact roll dedupes per enemy); the killer's call is first.
- Casts: Frost Circles = one `FrostCircle` under every living hero; Frost Breath = a `FrostBreath`
  from the boss towards the nearest hero; Summon = `WaveDirector.summon(...)`; Fire Fields =
  `count_at(phase)` `FireField`s on distinct heroes (Fisher-Yates on `RunState.rng`; extras 2.6 m
  from a hero); Meteor = one `MeteorStrike` on a random living hero (`RunState.rng`).

#### Hazards (`scenes/enemies/hazards/`)

- `EnemyHazard` (Node3D, group `&"enemy_hazards"`, constant `EnemyHazard.GROUP`): stages
  TELEGRAPH → ACTIVE → DONE (fade, then `queue_free`); `telegraph_time`, `radius`, `damage` (fixed
  when laid down), `source` (the boss). API: `is_telegraphing()`, `telegraph_left()`,
  `is_dangerous()`, `contains(point, margin)`, `hazard_push(from, margin) -> Vector2` (the bots'
  steering: out of the shape, 1–2 long inside, zero outside / when harmless), `living_heroes()`,
  `heroes_in_circle()`, `hit_hero(hero, amount)` (`Player.take_damage(amount, KIND_AOE, boss)`, so
  Avoidance / Dodge / absorbs apply). Marker visuals: ground ring quads (`Mats.ring`) and a flat
  sector mesh (`MeshKit.add_arc`); no physics bodies.
- `FrostCircle` (radius 2.2, 1.2 s, 2× contact, chill 40% / 2 s as a `GeneralBuff` under
  `FrostCircle.CHILL_KEY`), `FrostBreath` (60° / 7 m cone, locked direction, 1 s, 3×), `FireField`
  (r 2, 1 s then 8 s, tick 1× per second, the first tick at ignition), `MeteorStrike` (r 3, 3 s,
  falling meteor mesh in the last 1.1 s; total 8× split among the heroes inside, 4× each when nobody
  is inside; `hazard_push` pulls bots in when ≥ 2 heroes live).
- Other packages' hazards: the Plague Ghoul's `PoisonPuddle` joins `enemy_hazards` (freed by
  `WaveDirector.stop()`) and implements `is_dangerous()` / `hazard_push(from)` through the shared statics
  `EnemyHazard.circle_push` / `escape_direction`, so the bots avoid it like a boss circle.

#### WaveDirector (`scenes/waves/wave_director.gd`)

- Boss wave = `RunState.is_boss_wave(w)` and a `BossData` for it in Db (else a normal timed wave).
  `start_wave`: `boss_data`, `time_left = BOSS_WAVE_TIME` (1e6: nobody reaches it, harness hooks that
  set `time_left = 0` still end the wave), no elite schedule, `_emit_timer` silent; after the opening
  group the boss's point is drawn (`find_boss_point`: `BOSS_MIN_PLAYER_DISTANCE` 10 m, on screen if
  possible) and a rune shown; `BOSS_TELEGRAPH_TIME` 2 s later `_spawn_boss` (`Boss.create`,
  `boss.director = self`, signals `boss_spawned(boss)` and `enemy_spawned`). Spawn rate ×
  `BOSS_ADD_RATE_MULT` 0.5. `boss.died` → `boss_defeated(boss)` and the wave finishes on the next
  tick (`_finish_wave`: `stop()` despawns the rest, banks pickups / loot bags, emits `wave_cleared`).
  Gotcha: a boss freed by `queue_free()` compares equal to `null` in GDScript, so the director tracks
  the arrival with `_boss_arrived` / `_boss_dead` and checks `is_instance_valid(boss)` first (a smoke
  safety kill is processed by the director itself, the free happens before the next tick; hero kills
  happen earlier in the same tick). Main's "<Boss> defeated!" banner reads `wave_director.boss_data`,
  not the (possibly freed) boss.
- `summon(data, count, center, scatter) -> Array[Enemy]`: adds on a ring, capped by `MAX_ENEMIES`,
  counted in `spawned_this_wave`, announced through `enemy_spawned`; only `Enemy.setup` draws rng.
- `stop()` also frees the group `enemy_hazards` and clears the `boss_chill` buff of every hero.
- Smoke safety: `smoke_boss_timeout` (Main sets it from `options.smoke`): a boss older than
  `enrage_time + SMOKE_BOSS_GRACE` (120 s) is `kill()`ed and `SMOKE boss timeout: ...` printed (no
  warning / error, so the run result stays clean). `Main` adds `SMOKE_BOSS_ALLOWANCE` per boss wave to
  the smoke deadline.
- RunState.rng order of a boss wave start: eligible list → (no elite schedule) → first group pick →
  `wave_started` (GoblinSpawner draws nothing on a boss wave) → opening group → the boss point.
  Normal waves (1–9, 11–19, 21–24) draw exactly what they drew before: seeded smoke runs are
  unchanged up to wave 9.
- **Elite wave 20** (`RunState.is_elite_wave`): `_spawn_group` gives every enemy that is not a due
  real elite `make_elite(roll_affix(rng), true)` (one rng draw each); `EliteAffixes.expected_count`
  ×`ELITE_WAVE_COUNT_MULT` (2) on that wave.

#### Elites (`enemy.gd`, `elite_affixes.gd`, `elite_plate.gd`) – the lite affix

- `Enemy.make_elite(affix, lite := false)`: `lite` = affix state without the elite block: HP ×
  `EliteAffixes.LITE_HP_MULT` (1.5), no size change, `elite_lite = true`, `ElitePlate.create(self,
  true)`. `Enemy.is_elite()` is false for a lite enemy (Slayer / Execute targeting), `_death_loot`
  gives it the normal rewards (the elite block is keyed on `elite_affix != &"" and not
  elite_lite`). `ElitePlate` has a `compact` mode: affix gem sprite + shield bubble + enrage tint
  only. Both edits in `enemy.gd` are small optional-parameter changes in `make_elite` / `is_elite` /
  `_death_loot`.

#### HUD, Main, camera, bots

- `Hud`: `boss_frame` (VBox inside the top plaque, in the timer's place; name, `UiBar` HP in
  percent, two phase pips, pulsing ENRAGED), `bind_boss(boss)`, `clear_boss(_wave := 0)`; the
  ENRAGED row is always laid out (alpha 0 while calm, `Hud.ENRAGED_ALPHA_MIN` 0.8 .. 1 pulse when
  enraged, colour `UiTheme.RED.lightened(0.3)`), so the plaque never grows mid-fight and
  `is_boss_enraged_shown()` means "visible and not transparent"; the
  frame shows from the start of a boss wave (`_on_wave_changed` + `BossData.for_wave`), the timer
  label hides meanwhile. Main connects `boss_spawned → hud.bind_boss`, `wave_cleared → hud.clear_boss`.
- `Main`: arrival banner (`intro_text`, red), `"<Boss> defeated!"` / `"Victory!"` banners
  (`_wave_cleared_text`), log lines `boss <name> arrived on wave N at (x, z): HP` and `boss <name>
  defeated after S s (phase, enrage level, casts): standing, downs, revives`, and for a run lost
  while a boss lives `defeat with boss <name> alive after S s: P% HP left (phase, enrage level), N
  downs so far` (`Main.boss_arrival_text`, `Main.boss_standing_text`); positions are formatted by
  `Main.format_position` ("(x, y, z)", one decimal, also for the player / boss lines of the screenshot
  harness, no `-8.400001` noise). Victory is unchanged: `wave >= TOTAL_WAVES` after the
  wave-cleared pause, which now means Vor'thalax's death.
- `CameraRig.boss_points(bosses)`: a living `Boss` (group `bosses`) adds two soft framing points
  (feet, and 0.6 × its model height up the screen) next to the Loot Goblins' (without it the boss sat
  off-screen / under the HUD plaque); the heroes keep priority like they do over the goblins.
- `BotInput._hazard_steer(pos)` (`core/input/bot_input.gd`): sum of `hazard_push` of every
  `enemy_hazards` node, weight `HAZARD_WEIGHT` 5, only for living bots; also ends a rescue stand
  inside a hazard.
- `BossModel extends EnemyModel` (`scenes/visuals/boss_model.gd`, styles `lich` and `demon`): same
  contract and animation as `EnemyModel`, its own `boss_parts`; `Boss.create` swaps it in.

### Artifacts

#### Data and loading
- `data/items/artifact_data.gd`: `class_name ArtifactData extends UniqueItemData` – `class_id`,
  `unlock_waves` ([3, 6]), `properties: Array[Dictionary]` (`name`, `text`, optional `needs`
  ability id, `effects`: BonusVocabulary entries), `weapon_color`, and the pair fields
  (`pair_weapon`, `pair_name`, `pair_stats`, `pair_enchant_ids/ranks`). `rarity = 5`,
  `class_restriction = class_id`, `sources = [loot]`, `weight = 0`.
- `data/artifacts/*.tres` (5): earthsplitter, staff_of_the_frostwyrm, dawnbreaker,
  fangs_of_the_shadow, skull_of_the_damned. `Db.ARTIFACT_DIR` / `Db.artifacts` /
  `Db.get_artifact(id)` / `Db.artifact_for_class(class_id)` / `Db.artifact_classes()`.
  **Artifacts are not in `Db.uniques`** (the 63 hand-made items and every pool are unchanged);
  a new Artifact = a `.tres` in `data/artifacts/` (+ its class).
- `Artifacts.validate(data)` is the content check (class, weapon usable, 2 properties, valid
  vocabulary entries per `BonusVocabulary.validate`, enchants exist) – tested for all five.

#### Items
- `ItemInstance`: `artifact_waves` (wave ends held), `artifact_base_damage` (growth baseline),
  `companion` (a pair's off-hand piece, on the main piece), `pair_off` (this is the off piece),
  `is_artifact()`, `can_sell()`, `can_disenchant()` (**ask it** for the Disenchant
  entry and the all-Passed auto-disenchant), `greed_value()` = `ItemGenerator.artifact_greed_value`
  (5 x the Epic price of `item.wave`) for an Artifact.
- `ItemGenerator.from_artifact(data, wave)` / `generate_artifact(class_id, wave)` (no rng draw),
  `artifact_greed_value(wave)`; `generate(..., {rarity = ARTIFACT, usable_by | class_data |
  team_classes})` returns the class Artifact (a Legendary when none fits). `from_unique` now tops
  up random enchants only for rarity LEGENDARY (was `>=`), `_scaled_unique_stats` extracted.
- `Artifacts` (core/items/artifacts.gd): `grow(equipment)` / `grow_item`, `held`, `awake_count`,
  `is_awake`, `waves_left`, `property_rows(item, hero)` (tooltip rows with state
  AWAKE / ASLEEP / NEEDS_ABILITY), `effects_for(equipment)` (entries of the awake properties of the
  EQUIPPED Artifacts, tagged `id = "artifact:<id>:<index>"`), `SOURCE = &"artifact"`.
- `Equipment` pair rules: `target_slots(pair main) = [MAIN_HAND]` (needs `can_dual_wield` and the
  off weapon's proficiency; the off piece alone has no slot), `displaced_by` pulls both pieces of a
  displaced pair, `equip` puts only the main piece (never the off piece) back into the backpack and
  fills OFF_HAND with the companion, `unequip` / `take` / `is_last_weapon` treat the pair as one;
  new helpers `slot_of`, `is_equipped`, `pair_main_of`.

#### Drops (core/loot/loot_drops.gd)
- `roll_artifact(source, enemy, killer)`: only from wave 10; **one roll per enemy instance** (meta
  `artifact_rolled`, set when a roll is made); source = `kill_artifact_source` (highest of the call's
  source and BOSS if `enemy.is_boss()` / GOBLIN if `enemy is LootGoblin`; ELITE only from the
  call); `artifact_chance(source, killer)`; `pick_artifact_class(rng)`; `artifact_candidates`.
  Chances (`ARTIFACT_CHANCE_*`): boss 0.15 + `RunState.artifact_pity`, goblin 0.05, elite 0.02, normal
  `normal_chance()`, each x (1 + killer Fortune / 100), clamped to 1. **`ARTIFACT_CHANCE_NORMAL` (0.0005) is the SOLO
  rate; `LootDrops.normal_chance()` = it / `max(1, RunState.player_count)`** (1 player 0.05%, 2 0.025%, 4 0.0125%):
  the normal kills per wave grow with the party (spawn x `1 + 0.6 (n − 1)`), the bosses / goblins / elites barely,
  so the expected hits per 25-wave run stay ≈ 2.6–2.9 for 1–4 players (before: 2.9 / 4.3 / 7.1, and 84% of the 4p
  runs collected all five). The boss / goblin / elite chances, `ARTIFACT_PITY_STEP`, the 80 / 20 class rule and
  `artifact_chance_override` are untouched (the override is not divided). A hit appends to `RunState.artifact_classes`, `artifacts_dropped += 1`, `artifact_pity = 0`,
  spawns the bag (`_place_bag`, not counted against the wave cap; `RunState.add_team_loot` when
  there is no arena). A missed BOSS roll adds `ARTIFACT_PITY_STEP` to `RunState.artifact_pity`.
- **RNG draw order** (only when a roll is really made): chance `randf`; on a hit the 80/20
  `randf`, then `randi_range` among more than one candidate class. Nothing is drawn below wave 10,
  with chance 0, for an already-rolled enemy, or when every class got its Artifact.
- `artifact_roll_probe` (test hook) still short-circuits the roll (call sites observable);
  `artifact_chance_override` (`--artifact-chance`) replaces every chance (clamped 0..1).

#### Hero hooks
- `Player.create` connects `wave_ended` -> `_on_wave_ended_artifacts` (grow; emit
  `equipment.changed` when something grew so properties awaken). `Player.apply_equipment` sets the
  `&"artifact"` PlayerBonuses source from `Artifacts.effects_for` (skipped, no extra rebuild, for
  ordinary gear). `Player.pet_leech_pct` + `ProcSystem.deal_raw` (source `&"pet"`): heals the
  hero for that % of the pet damage dealt (uses `Player.heal(amount, slot)`).
- Ability params added with neutral defaults (so `BonusVocabulary.validate` accepts the mods):
  whirlwind `quake_duration / quake_pct / quake_tick`; charge `shockwave_radius / shockwave_stun`;
  blizzard `nth_cast / nth_radius_bonus`; word_of_glory `shield_max_hp_pct`. The effect scripts read
  them (`WarriorWhirlwind._spawn_quake`, `WarriorCharge._shockwave`, `BlizzardEffect.cast`,
  `PaladinWordOfGlory.grant_shield`). The Consecration heal (`heal_max_hp_pct`) and Vanish
  (`forced_crits`) are pure data (existing params).
- TalentEffect scripts (`scenes/artifacts/`): `ArtifactMageFrostShards` (on_kill),
  `ArtifactRogueFangsFan` (on_hit, `RogueFanOfKnives.throw_free`), `ArtifactWarlockSecondVoidwalker`
  (tick; `WarlockVoidwalker.spawn` with the Summon Voidwalker params of the hero, ward off),
  `ArtifactWarlockPetLeech` (sets `pet_leech_pct`). The +25% pet damage is a plain `damage`
  entry (`source: pet`).

#### UI / bots
- `ItemTooltip`: `_artifact_block` (pair note, property rows: awake gold `ARTIFACT_GOLD`, asleep
  `ARTIFACT_ASLEEP` + "Awakens in N wave(s)", `DIM` + "(needs X)" – the viewing hero is found through
  `viewer_equipment`, else the first hero of `viewer`'s class), no "Sell Price" for an Artifact, the
  pair counted in `total_stats` / `weapon_dps(..., with_companion)` / `equipped_for_compare`;
  `upgrade_direction`: a usable Artifact is always +1, an equipped Artifact is never replaced by an
  ordinary item (bots, loot-roll badge).
- `PlayerPanel`: Sell greyed ("Artifact" / `ARTIFACT_NO_SELL`) + `_do_sell` guard. `Intermission`:
  `_bot_make_room` never sells an Artifact; `_bots_make_room_for_artifacts(loot)` (called by
  `_start_loot`) makes room in the backpack of a bot whose class can use an Artifact in the loot.
  `LootRoll.bot_choice` needs the Artifact through `upgrade_direction`.
- `WeaponModel.RARITY_COLORS` has a 6th (gold) entry; the weapon colour of an Artifact comes from
  `ArtifactData.weapon_color` (the item's private weapon copy).

#### Known gaps

- A human with a full backpack cannot Need an Artifact ("Backpack full") – they must make room or
  Greed (775-ish gold); only bots auto-make room. No HUD banner on a drop (floating text + beam).
- A smoke run ends right after its last wave without that wave's `end_wave`, so a 7-wave run from
  wave 10 shows property 1 (wave 13) but property 2 (6th wave end) needs `--waves=8` or more.
- Hunter / Shaman Artifacts (M8) need their own `.tres` (+ `Galestrike Longbow` / `Fist of the
  Ancestors` properties); `Db.artifact_classes()` picks them up automatically.


#### Loot roll window, compact tooltip, smoke log

- `data/items/artifact_data.gd`: each property dictionary gets a `"short"` text (<= `Artifacts
  .SHORT_TEXT_MAX` = 72 chars) next to `"text"`; `Artifacts.validate` requires it;
  `Artifacts.property_rows` rows carry `"short"` (falls back to the full text).
- `ItemTooltip`: `shows_looted_tag(item)` (static; false for an Artifact – tooltip and
  `LootRollScreen` info row), `compact_artifact()` (an Artifact with `viewer_equipment`: short
  property text, no flavor / "Scales with" / own-class line, `COMPACT_ARTIFACT_SEPARATION` instead of
  `LINE_SEPARATION`, comparison differences in an `HFlowContainer` via `_delta_flow`).
- `LootRollScreen`: new public `frame`, `tooltip_fit`, `tooltip_room()`; `_fit_tooltip()` (called from
  `_fill_item`): tooltip widths `TOOLTIP_WIDTHS` (360 / 480 / 600) first, then a scale
  (`MIN_TOOLTIP_FIT` 0.5); the tooltip sits in a `_tip_box` Control sized to the scaled tooltip inside
  the `CenterContainer`. **The frame stays below the title block:** `frame_band() -> Vector2` = (top,
  bottom) in screen pixels, `max(FRAME_TOP_MARGIN, title_block_bottom + FRAME_TITLE_GAP)` to `chips_top -
  FRAME_CHIPS_GAP` (`TITLE_TOP` 22; the title block is measured from the `_top` vbox, so a subtitle change is
  picked up); `_centre_middle_row()` (called from `_fit_tooltip`) puts the middle row (queue, frame, log) on the
  middle of that band, and `tooltip_room()` is the band height minus the measured frame chrome and the
  two-line result reserve (`RESULT_RESERVE`, plus `BOTTOM_MARGIN`). (`MIDDLE_OFFSET` is gone: the old fixed
  centre let a tall frame cover the "Loot Roll" title and subtitle.) At 1920x1080 with 4 players the title
  block ends at y = 136 and the room is about 503 px (was 618); the five Artifact tooltips are 585–676 px tall at
  their widest width, so they show at a fit of 0.74–0.82 (was 0.91–1.0). Not done: hiding the title while the
  tooltip is tall (would give a bigger scale).
- Smoke log: `RunState.artifact_dropped(item, source: StringName)` (emitted by
  `LootDrops.roll_artifact` on a hit, `ItemGenerator.SOURCE_IDS`); `Main.artifact_lines` (cleared by
  `start_run`), `Main._on_artifact_dropped`, `Main._log_artifacts_held(hero)` (called from
  `open_intermission` after each hero's `end_wave`, i.e. after growth); line builders
  `Artifacts.drop_line` / `Artifacts.held_line`. The last wave of a smoke run has no wave end, so no
  `held` line for it.
- Tests: `test_m6_artifacts_fit` (roll window layout, Looted tag; `READABLE_FIT` 0.7, `_check_frame` also asserts
  "frame top >= title block bottom"; `test_the_frame_stays_below_the_title_block_for_every_artifact` (five
  Artifacts, 4 players), `..._with_a_greed_result` (the two-line result grows the frame both ways), `..._for_a_solo_hero`),
  `test_m6_artifacts_log` (smoke log),
  `test_ui_items_panel.test_artifact_tooltips_fit_the_4_player_panels` (corner panels),
  compact block tests in `test_m6_artifacts_ui`, short text tests in `test_m6_artifacts_core`,
  Shatterfrost data / reach tests in `test_m6_artifacts_props`.

### Enchanter and Arcane Dust

#### Rules: `core/items/enchanter.gd` (`Enchanter`, pure statics + the spending)

- `enum Action { REROLL, EMPOWER, IMBUE }`. Constants: `GOLD_SHARE 0.25`, `DUST_BY_RARITY [1,2,4,8,16]`
  (Artifact: none), `MAX_ENCHANTS [0,1,1,2,2,0]` per rarity, `MAX_DOUBLINGS 24`, `SPEND_KIND &"enchant"`,
  `BOT_FIRST_WAVE 12`, `BOT_MAX_ACTIONS 2`, the `REASON_*` strings shown by the UI.
- Dust from items: `dust_for(item)`, `can_disenchant` / `disenchant_blocked_reason`,
  `disenchant(eq, item, slot_index)` (a **backpack** item leaves through `Equipment.remove_from_backpack`, so
  the last-weapon guard applies; Dust to `RunState.add_dust`), `disenchant_lost_item(item)` (LootRoll: an item
  nobody wanted, no backpack involved).
- Prices: `multiplier(item)` = 2^`ItemInstance.enchant_uses` (capped), `gold_price(item, wave = -1)`
  (= `ItemGenerator.price_for(rarity, RunState.wave)` x 25% x multiplier, `roundi`, min 1), `dust_price(item)`,
  `price_text`, `afford_reason(item)`. The price is the same for every action on the item.
- Rules: `blocked_reason(item, action, index)` (rule only, wallet ignored), `is_enchantable`, `can_imbue`,
  `reroll_pool` / `imbue_pool` (every `Db.enchants` entry with weight > 0 that `ItemGenerator.enchant_fits` the
  item and the item does not carry), `pick(pool, rng, for_class)` (the generator's weighted pick incl.
  `power_enchant_weight`).
- `perform(eq, slot_index, item, action, index = -1, rng = null) -> Enchanter.Outcome`: checks ownership, the rule
  and **both** wallets before paying anything, decides the change (the only random draw: one `randf()` of
  `rng`, default `RunState.rng`, for Reroll / Imbue; Empower and prices draw nothing), then
  `RunState.try_spend_for(gold, slot, &"enchant", "<verb> <prefix> (<dust> Dust)")` and
  `try_spend_dust_for(dust, slot, &"enchant", "<verb> <prefix>")`, mutates the item (Reroll keeps the rank, Empower
  `rank += 1` up to `EnchantData.MAX_RANK`, Imbue appends at `ItemGenerator.enchant_rank(item.wave, item.looted)`),
  `enchant_uses += 1`, `RunState.enchants_done += 1`, `refresh_name` and finally `eq.changed.emit()` (so
  `Player.apply_equipment` rebuilds stats and procs, and every panel refreshes). A refused action changes and spends
  nothing and draws nothing. `Outcome` carries `ok, reason, action, item, index, before, after, gold, dust, label`.
- `refresh_name(item, old_prefix)`: a generated item's name starts with its first enchant prefix ("Blazing ..."); it
  is swapped after a change. Hand-made (`unique`) items, Forge-made Legendaries (`unique_effect`) and names that do
  not start with the old prefix stay as they are.
- Bots:
  - `best_weapon(eq)`: the best attacking weapon; **skips Artifacts** (rarity >= ARTIFACT) and returns null when only
    Artifacts are in hand (the Fangs pair counts as two).
  - `bot_target(eq) -> ItemInstance`: `best_weapon(eq)`, else the best equipped non-Artifact item of rarity >=
    `BOT_FALLBACK_MIN_RARITY` (EPIC) that is not an attacking weapon (armour, jewellery, a shield / tome) and for which
    `bot_plan(item, eq.class_data)` is not empty (rarity, then Item Level, then the lower `EquipSlot`); null if none.
  - `bot_plan(item, class)`: Reroll an off-class power enchant, else Imbue, else Empower the lowest rank (`{}` for an
    Artifact). `bot_enchant(slot, gold_budget, rng)` works on `bot_target` (it used `best_weapon`, so a bot wearing an
    Artifact weapon spent nothing at all).
  - `bot_disenchant_spare(slot, eq, dust_needed)`, `is_spare` (not an upgrade by the same test bots buy and Need with,
    never the last weapon). The pick is deterministic: no RNG change.

#### `EnchantData` / generator

- `RANK_MULT [1, 1.5, 2, 2.5, 3]`, `MAX_RANK 4`, `RANK_LABELS` / `rank_label(rank)` ("I".."V"),
  `MAX_GENERATED_RANK 2`. `ItemGenerator.enchant_rank` and `from_unique` cap at `MAX_GENERATED_RANK`, so the
  generated content is unchanged (a seeded run draws the same items); `EnchantRoll.rank_label()`;
  `tools/item_report.gd` prints I-V.

#### Loot roll

- `LootRoll.apply` outcome `&"pass"`: `dust = Enchanter.disenchant_lost_item(item)` (new field `LootRoll.dust`, 0 for an
  Artifact). `LootRollScreen` result line / log: solo "Disenchanted [X] into 8 Dust", party "Everyone passed on [X] –
  disenchanted into 8 Dust" (the old texts when `dust == 0`). The B prompt follows the current item
  (`LootRollScreen.pass_label(solo, item)`, the legend is rebuilt per item when the text changes): solo
  "Disenchant (8 Dust)" ("Leave" for an Artifact), party "Pass (all pass: 8 Dust)" ("Pass" for an Artifact); the
  revealed solo chip says "Disenchant" when `roll.dust > 0`.

#### UI (`scenes/ui/enchanter/`)

- `EnchanterTab` (the Trainer / Talents tab contract): `create(slot)`, `refresh()`, `set_focused`, `handle_input(input,
  delta) -> bool` (true = a press was used; B only counts while it cancels a hold or steps back from the enchants),
  `prompt_spec()`, `context_text()`, `is_modal()` (a hold runs), `tab_label()` ("Enchanter (12)"), signals
  `message`, `prompts_changed`, `label_changed` (team Dust changed, the panel relabels the tab). `Focus { ITEMS, ROWS }`.
  Items = equipped (slot order) then backpack; grid positions `grid_pos(i)` / `index_at(col, row)`; `rows` =
  one `EnchanterRow` per enchant + the Imbue row while a slot is free. Hold-to-confirm: `needs_hold(gold_price)`
  (`> RunState.gold * ShopPanel.HOLD_SHARE`), `ShopPanel.HOLD_TIME`; the button (A / X) must stay down; moving, B,
  letting go or a wallet change that makes the action unaffordable cancel it. While hidden, wallet changes only mark
  it stale (refresh when shown); the PlayerPanel's `refresh()` (on `Equipment.changed`) calls `refresh_if_shown()` (a hidden tab
  is only marked stale: it rebuilds up to 25 icons) and `set_tab` / `_catch_up` rebuild it when it is shown. An icon the
  Enchanter cannot use is dimmed except under the cursor (`Cell.refresh_alpha`).
- `EnchanterRow` (rank numeral, name, tooltip text at that rank, selection / hold fill), `DustIcon` (the drawn sparkle;
  `COLOR`, `COLOR_BRIGHT`, `text(n)`, `bbcode(n)`).
- `PlayerPanel`: `LOCKED_TABS = []` (mechanism kept), `enchanter: EnchanterTab`, `_enchanter_input` (LT / RT switch unless
  modal), `tab_text(ENCHANTER_TAB)`, the tab strip draws a `DustIcon` before the label, prompts via `_update_tab_prompts`,
  signal `item_disenchanted(item, dust)`; the backpack menu is `Equip / Forge / Sell / Disenchant / Trade / Cancel`
  (`_disenchant_entry`, detail "+8 Dust", greyed "Last weapon" for the last weapon, absent for an Artifact).
- `PurseBoard`: `dust_value`, `dust_icon`, `refresh_dust()` (connected to `RunState.dust_changed` while in the tree),
  `WIDTH 722`, `WALLET_WIDTH 124`, margins trimmed (`MARGIN_X 7`, `RULE_GAP 6`, `CAPTION_WIDTH 45`, `CAPTION_GAP 5`) so
  `text_column_width()` is still 520 and the board's height (74) is unchanged. `dust_text(n)` abbreviates from 1,000
  ("1.2k", "12k", "1.2M"); `_fit_wallet()` (called by `refresh_gold` / `refresh_dust`) picks the first of `WALLET_FONTS`
  (20/17, 18/15, 17/14, ...) whose coin + gold + sparkle + Dust row fits `WALLET_WIDTH` (measured with the labels' own
  font), so 99,999 gold + 999 Dust stays inside the column.
- `Intermission._bots_enchant()`: market after wave >= 12 (`cleared_wave`), called **first** in `_bots_shop` (after the
  equip / forge loop, before `_bots_buy`). The pot is `bot_enchant_budget(RunState.gold, bot_train_reserve(cleared_wave,
  bots))` = `BOT_ENCHANT_PURSE_SHARE` (0.3) of the purse above the Trainer reserve, computed once; bot k of n gets
  `pot / (n - k)` (floored) and the gold it spent leaves the pot, so an unspent share stays for the later bots (the
  Trainer's even split); `Enchanter.bot_enchant` per bot (target: the best attacking weapon, else the best
  non-Artifact Epic+ armour / off-hand, see "Bots" above).

### Consumables and the Black Market

**Data and rules**
- `data/consumables/*.tres` = the seven `ConsumableData` (Flask of Fury, Elixir of Ironskin /
  Swiftness / Fortune, Hearty Onion Stew, Spiced Onion Rings, Smoked Boar Ribs; icon id = id).
  Effects are BonusVocabulary entries with **one extension**: a `stats_pct` dictionary on a `stats`
  entry (`{"armor": 30.0}`, `{"max_hp": 15.0}` = Stamina) is resolved by
  `Consumables.resolve_effects(data, player)` into plain `stats` against the hero's *current* values
  (rounded to 0.1) before the engine sees it. `BonusVocabulary.validate` accepts the resolved entries.
- `core/items/consumables.gd` (`class_name Consumables`, pure statics): `price(data, wave)` (base x
  `1 + 0.08 (wave - 1)`), `pool()` (id order, by String: a StringName sorts by address), `roll_row(rng,
  count = ROW_SIZE)`, `queue(pending, data)` (the one-potion-one-food rule, returns the replaced one),
  `give(player, data)`, `apply(player)` / `clear(player)`, `resolve_effects`, `effect_lines`,
  `summary`, `kind_name`, `of_kind`. `resolve_effects` takes the percentage of `max(0, base)`: a
  `stats_pct` stat can only help (negative Armor stays as it is; Max HP is always >= 1).
- `Player`: `consumables_pending` / `consumables_active` (`Array[ConsumableData]`), signal
  `consumables_changed`, `fill_hp(amount)` (HP up without a heal: no number, nothing for the meter).
  `Player.create` connects `wave_began` -> `Consumables.apply` (pending -> active, one
  `PlayerBonuses.set_effects(&"consumable", entries)`, Max HP gain filled) and `wave_ended` ->
  `Consumables.clear` (source emptied). Nothing else clears it: the market never shows an expired buff.
  The effects survive `Player.apply_equipment` rebuilds (they are a normal bonus source).

**Shop (core/shop/shop.gd, core/shop/black_market.gd)**
- `Shop.consumables: Array[Shop.ConsumableOffer]` (`data`, `price`; unlimited stock: no sold / lock /
  ping), `Shop.black_market: Shop.Offer` (null before `BlackMarket.FIRST_WAVE` = 15), both next to
  (not in) `offers`. `consumable_at`, `buy_consumable` / `try_buy_consumable(index, slot) -> BuyResult`
  (OK / INVALID_OFFER / NO_PLAYER / NOT_ENOUGH_GOLD; spend kind `&"consumable"`;
  `RunState.consumables_bought`; `last_replaced`; signal `consumable_bought`).
- The Black Market offer is addressed by the index `Shop.BLACK_MARKET` (= -2) in `offer_at`,
  `try_buy` (spend kind `&"black_market"`, also for the forged variant; `RunState.black_market_bought`),
  `toggle_lock`, `toggle_ping`, `forges_on_buy`. `black_market_rerollable()`; `reroll_ready` is true
  when an item offer **or** the Black Market could change; a reroll redraws the row always and the
  Black Market when it is rerollable; a locked unsold Black Market offer survives `open_round`.
- **Side rng**: `Shop._side(base)` seeds a private rng once from `base.seed ^ SIDE_RNG_SALT` (base = the
  rng the first `open_round` gets, i.e. `RunState.rng`); the row and `BlackMarket.roll` draw only from
  it, so the item offers of a seeded run and the state of `RunState.rng` do not change
  (`test_the_row_does_not_touch_the_item_offers_or_the_main_rng`, `PlainShop` in the test).
- `BlackMarket` (pure): `is_open`, `price` (3 x `ItemGenerator.price_for(EPIC, wave)`), `roll(wave,
  slots, rng)`: one `randf` against `MAX_ROLL_CHANCE` (0.4) first, then the set piece
  (`set_piece_candidates`: team classes in slot order, pieces in set order, "missing" = not worn and not
  carried by a hero of the class) or the max-roll Epic (`ItemGenerator.generate(LOOT, ...,
  {rarity: EPIC, usable_by, class_data})`, rejecting hand-made items and set pieces until two enchants,
  at most `MAX_ROLL_TRIES`). The item's `buy_price` stays the normal Epic price. Set pieces are
  `ItemGenerator.from_unique(..., looted = false, ...)`: the loot budget (+25% stats, +1 enchant rank,
  +6 item level, the "Looted" tag) belongs to the max-roll Epic only.

**UI**
- `ShopPanel`: the cursor space is one flat list - item offers `0 .. n-1`, the consumables, the Black
  Market card (`slot_count`, `card_at`, `is_consumable_index`, `is_black_market_index`,
  `black_market_index`, `shop_index`, `consumable_at`, `offer_at` also for the Black Market). `cards`
  stays the item cards; `consumable_cards: Array[ConsumableCard]`, `black_market_card: ShopOfferCard`.
  The grid and the row live in one VBox in the counter; the row (`_extras`) is laid out by code
  (`ShopPanel.extras_layout(k, black_market)`, pure geometry, `ROW_WIDTH` 652) and hidden while
  the shop has no row and no Black Market (a `FakeShop` stall keeps its old shape). `try_buy(slot, index)`
  is the one entry for items, the Black Market and consumables (`try_buy_consumable`, signal
  `consumable_bought(slot_index, data)`; the Black Market is an `item_bought`). Holds carry a content key
  (item uid / consumable id hash) and the price; a reroll cancels them. X / R3 act on items and the Black
  Market only. Navigation: down from the last grid row and up from the row go to the card nearest in x
  (`_grid_card_x`, `_extra_x`), left / right inside the row.
- `ShopOfferCard` wide layout (Black Market): `NAME_LOCK_RESERVE` (28) is taken off the name label's
  width (the label no longer expands), so the padlock badge (`lock_badge_rect()`, radius
  `LOCK_BADGE_RADIUS`) never covers the name; `ping_tags() -> Array[Dictionary]` ({slot, text, rect}) is
  the one place that lays out the "P2 wants" tags (stacked card: column from (4, 14); wide card: one row
  at x >= `WIDE_PING_X` (66), y = 6 + `ICON_SIZE`, short "P2" text when the full row does not fit) and
  the overlay draws exactly those rects.
- `ConsumableCard` (96 high, flexible width), `ConsumableIcon` (procedural: round flask, vial, conical
  flask, bowl, rings, ribs; border blue for potions / orange for food), `ConsumableTooltip extends
  ItemTooltip` (so `layout_tooltips` places it like an item tooltip; a second tooltip per player,
  `_cons_tooltips`, `_shown_tooltip`), `ShopOfferCard.create_wide` (200x96, `gold_frame`, price at the
  bottom left, pips bottom right). `ShopOfferCard.CARD_SIZE` 124x176, `ICON_SIZE` 46, `NAME_HEIGHT` 44
  (two lines of the 16 px bold name need 44).
- Stall budget at 1920x1080 (counter 496 px; content 488 px): 2 x 176 + 10 (grid gap) + 10 (row gap)
  + 96 (row) + margins; body margins 22 / 8, column gap 6, log lines 22 px. `STALL_SIZE` is unchanged
  (the vertical room between the purse board and the ready chips is fixed).
- `UnitFrame`: `consumable_icons` (24 px `ConsumableIcon`s of `player.consumables_active` behind the class
  name, `shown_consumables()`), refreshed on `consumables_changed`.
- `PurseBoard`: `spend_label` brackets `&"black_market"` items like shop items, `merged_wants` and
  `_offer_item` include the Black Market offer; `Intermission.drop_shop_pings` drops its ping too.

**Bots (Intermission)**
- `_bots_consumables()` (from `cleared_wave >= BOT_CONSUMABLES_FROM_WAVE` = 6): per bot slot, potion then
  food (`bot_consumable_choice(shop, kind)`: `BOT_POTION_PRIORITY` / `BOT_FOOD_PRIORITY`), only while
  `gold - price >= bot_train_reserve`, never when the hero already holds a pending one of that kind;
  buys through `ShopPanel.try_buy` (feedback log included). The stock is unlimited and the choice does
  not depend on the bot, so all bots take the same best potion and the same best food. `_bots_black_market()`: the bot with the
  best `ItemTooltip.item_score` gain for whom the offer is an upgrade buys it when `gold - price >=
  BOT_BLACK_MARKET_RESERVE_MULT (2) x bot_train_reserve`, makes room, wears it. Neither draws from
  `RunState.rng`.

### Damage meter, end screen, run card

#### RunState (autoload/run_state.gd)

- New: `bosses_by_player: Dictionary[int, int]` (`record_special_kill(&"boss", killer)` counts it for the killer next to
  `bosses_killed`), `hero_results: Dictionary[int, Dictionary]` (slot index -> `{"alive": bool, "best_item":
  ItemInstance or null}`) and `record_hero_result(slot_index, alive, best_item := null)`. Both are reset by
  `start_run`. `Main.end_run` fills `hero_results` for every joined slot **before** the end screen opens (heroes are
  freed when the screen is left; `RunSummary.hero_entry` falls back to the live hero when no result was recorded).
- The foundation recorders (`record_heal / record_absorb / record_damage_taken / record_revive / record_down`) now have their
  callers (below).

#### Recording (who calls what)

- `Player.slot_index() -> int` (-1 without a slot) and `static Player.slot_index_of(p) -> int` (-1 for null / freed) are the
  id the meter credits.
- `Player.heal(amount, source_slot := -1)`: the **effective** gain (after the max-HP clamp, nothing while downed) goes to
  `RunState.record_heal(source_slot, ...)`; `-1` = the hero itself (regen, Leech, Life on Kill, self heals). **Every call
  site that heals someone else passes the caster's `slot_index()`**: Word of Glory, Lay on Hands, Divine Storm,
  Light's Hammer (Consecration), Holy Shock, Seal of Command, Unbreakable's ally heal, item `heal` / `smite_heal` procs,
  `AbilityArea` heals (`owner_player`), the bandage's heal ticks (`GeneralBuff.set_heal(total, ticks, interval,
  source_slot := -1)` stores `heal_source`). New healing effects (e.g. Dawnbreaker's Consecration heal) must
  pass the caster the same way, otherwise the target is credited.
- `Player.revive(hp_ratio, reviver_slots: Array[int] = [])`: records one revive for every distinct slot of
  `reviver_slots` after the revive happened (a hero that is not down records nothing). Callers: the teammate channel
  (`_update_revive` passes the living teammates inside the circle at the moment it completes), Word of Glory (the
  caster); the wave start, the Spirit Healer and the smoke runner pass none.
- `Player._go_down` -> `record_down`. `Player.take_damage`: `record_damage_taken(slot, hp_before - hp,
  _damage_source_id(attacker))` (HP really lost, no overkill, after armour / mults / shields / cheat-death; the source
  id is for the balance diagnostics, see "Balance pass"); a blocked hit records
  `record_absorb(slot, mitigated(raw) - mitigated(blocked))`. The mitigation chain moved into `Player._mitigated(amount,
  kind, source)` (pure) so it can be evaluated for the unblocked hit too.
- `ProcSystem.Shield` has `owner_slot`; `add_shield(amount, duration, source := &"", owner_slot := -1)` (-1 = the
  receiving hero's own slot). An entry is identified by `(source, owner_slot)`: shields of one source from different
  casters keep separate entries (and timers); `shield_of(source)` sums the casters. `absorb()` calls
  `record_absorb(s.owner_slot, taken)` for every shield that soaked something. Casters of other heroes' shields
  pass `slot_index()` (Word of Glory, Lay on Hands, Holy Shield, the `shield` proc).
- `WarriorExecute.strike`: the finishing blow `e.take_damage(e.hp, ...)` records `RunState.record_damage` first.

#### RunSummary (core/run_summary.gd) – the pure model

- `STAT_IDS` (damage, healing, absorbed, taken, revives, downs, kills, bosses), `STAT_LABELS`, `COUNT_STATS`, `AWARDS`
  (id, name, stat, rule `&"most"` / `&"least_alive"`), `MIN_HEROES_FOR_AWARDS = 2`.
- Reading the run: `stats_of(slot)`, `hero_entry(slot)`, `collect(victory)` (RunState + PlayerManager),
  `meter_dict()`. Pure: `build(run, heroes)` (adds `heroes[].awards`, `awards` [{id, name, slot}], `coop`, `time_text`),
  `awards_for(heroes)`, `rank(heroes, stat)`, `best_item(equipment)`, `class_color(data)` (onion colour with the
  luminance clamped to 0.28..0.58), `mode_label`, `format_value / format_amount / format_time`.
  `format_amount` moves to the "M" form as soon as the k form would read "1000.0k" (999,950 and up).
  `shown_value(v)` = `roundf(v)` is the number the meter shows: the "most" awards (value above 0), the dimmed
  zero bars (`MeterPage`) and the card's stat line (`RunCard`) all go by it, not by the raw value (0.4 reads "0").
- Hero entry: `{slot, label, color, class_id, class_name, class_color, alive, best_item, stats{id: float}}`.

#### End screen (scenes/ui/game_over.gd, meter_page.gd, meter_bar.gd)

- `GameOverScreen`: pages `Page.SUMMARY` / `Page.METER` (`page`, `set_page`, `switch_page(step)` – no wrap,
  `page_from_name`), a tab strip, both pages in one `page_box` (MarginContainer) that `_fit_pages()` sizes to the taller of the two
  pages after every `_fill()` (hidden pages still know their minimum size), so the panel keeps its height when the
  page turns (the old fixed `PAGE_HEIGHT` is gone; with 7 awards the Damage Meter was 87 px taller than the box).
  `summary_page` has `SIZE_SHRINK_CENTER`, so the shorter page floats in the middle of the box. `time_value`,
  `meter_page: MeterPage`, `status_label` (one line, `OVERRUN_TRIM_ELLIPSIS`: its text never widens or grows the panel).
  The page prompt row shows the pad glyphs and the keyboard keys (Q / E, the nav arrows) like the other two prompts. Input (after `INPUT_DELAY`, per slot, **bots skipped** because a bot's
  last stick push is a navigation edge): LB / RB or `nav_just_pressed().x` -> page, X -> `save_card()`, A / START ->
  `back_to_menu_requested` as before. `open()` swallows the human inputs (a stick still held from the fight does not
  turn the page) and always starts on the Summary.
- `MeterPage` builds one panel per stat (`rows[stat]`, `totals[stat]`) with a `MeterBar` per hero (`rank` order, class
  colour fill, player colour swatch, 0 = empty dimmed bar) and the Awards grid (hidden unless `summary.coop`).
- `GameOverScreen.save_card()` (coroutine): `RunCard.render` -> `RunCard.save_png` -> the status line
  `GameOverScreen.saved_text(absolute path)` ("Saved to <path>"; longer than `MAX_STATUS_CHARS` = 72 characters it
  becomes "Saved to ...<last folders>/<file name>", cut at a folder boundary; the full path is printed to the log) +
  signal `card_saved(path)` ("" = failed). `waves_cleared()` stays the one place that decides the waves cleared
  (`RunSummary.collect` calls it; the M6b modes edit it for Endless).

#### Run card (core/run_card.gd, scenes/ui/run_card_view.gd)

- `RunCard.model(summary) -> Dictionary` is pure (title, result, victory, mode, waves_text ("N / 25 waves"; on a defeat
  "Fell on wave N", N = `summary.wave`, else cleared + 1), time_text, up to 4
  `heroes` with label, class, colours, item line, award line, stat line); `RunCardView.create(model)` lays it out as
  Controls (1200 x 630, shared theme); `RunCard.render(host, model)` puts the view into a `SubViewport`
  (UPDATE_ONCE), awaits two `frame_post_draw` and returns the `Image` (null on the headless dummy renderer: it returns
  at once); `RunCard.save_png(image, datetime := {})` writes `user://cards/run_<yyyy-mm-dd_hh-mm-ss>.png`
  (`file_name`, `unique_path` add `_2`, `_3` for the same second). Pixels are verified by the xvfb screenshots, not in
  headless tests.

#### Command line / SMOKE

- `--end-page=summary|meter` (the page `--view=game_over|victory` opens on) and `--save-card` (saves the card as soon as
  the view is forced; prints `CARD <path>`): `LaunchOptions.end_page / save_card`, `Main._end_screen_extras()`.
- SMOKE_RESULT `meter`: `{ "<slot index>": {damage, healing, absorbed, taken (0.1 resolution), revives, downs, kills,
  bosses, class} }` (`RunSummary.meter_dict()`); the log prints one `SMOKE meter P1 warrior: damage ..., healing ...`
  line per hero before `SMOKE_RESULT` (`Main.meter_lines`).

### Cross-system contracts

The rules that hold between the features (found and pinned by `tests/test_m6_integration.gd`; the sections above
describe each side).

1. **Enemy ground hazards.** Everything an enemy lays on the ground that hurts heroes joins the group
   `&"enemy_hazards"` (`EnemyHazard.GROUP`). `WaveDirector.stop()` frees the whole group at the wave end
   (the bosses' circles / cones / fields / meteors and the Plague Ghoul's `PoisonPuddle` alike; the puddle is
   also in `&"ability_areas"`, which `Main.open_intermission()` sweeps for what lands during the "Wave
   cleared!" pause). `BotInput._hazard_steer` sums `hazard_push(from)` of every node in the group that has
   the method (weight `HAZARD_WEIGHT` 5, living bots only). An `EnemyHazard` gets `hazard_push` for free; the
   `PoisonPuddle` (a plain Node3D with its own lifecycle) implements `is_dangerous()` and `hazard_push()`
   itself, both through the shared statics `EnemyHazard.circle_push(centre, radius, from, margin)` and
   `EnemyHazard.escape_direction(from)`, so a bot leaves a puddle exactly like a boss circle (1..2 long
   inside radius + `BOT_MARGIN`, towards the arena's centre from the dead middle). A harmless (damage 0),
   expired or removed puddle pushes nothing.
2. **One Artifact roll per kill.** `LootDrops.roll_artifact` is called once per hero by the boss's
   `drop_special(BOSS, ...)` calls (the killer first, so his Fortune counts), once more by an elite's
   `on_enemy_killed`; the enemy meta `artifact_rolled` makes only the first call roll. A boss kill therefore
   drops at most ONE Artifact (never one per hero) and a missed boss roll adds ONE `ARTIFACT_PITY_STEP`.
   `kill_artifact_source` uses BOSS whatever source the call names. A boss's four-hero loot is
   `heroes.size()` items plus the optional Artifact bag. The normal-kill chance is divided by the party size
   (`LootDrops.normal_chance()`), the other sources are not.
3. **Boss and the Acolyte.** `Enemy._pick_support_target` never heals an enemy with `is_boss()` (the boss is
   always the most hurt one); the Acolyte may only top its shield up to 20% of max HP (refresh, no stacking).
   An injured add beside a boss is healed instead.
4. **Credit of new healing / shielding.** Any new effect that heals or shields someone else passes the caster:
   `Player.heal(amount, caster.slot_index())`, `ProcSystem.add_shield(amount, duration, source, caster_slot)`.
   Dawn's Embrace (`PaladinWordOfGlory.grant_shield`, source `&"dawn_embrace"`) is credited to the casting
   Paladin; the Dawnbreaker heal of the Consecration mod goes through the existing, already credited code.
   `shield_of(source)` sums the casters, so the 15% top-up rule holds across casters.
5. **Artifacts and the economy.** An Artifact is never sold (`ItemInstance.can_sell()`: the Sell entry is greyed
   "Artifact", bots never sell one), forged (`Forge.REASON_ARTIFACT`), disenchanted
   (`ItemInstance.can_disenchant()` is the one rule; `Enchanter.disenchant_blocked_reason` asks it, the menu
   has no Disenchant entry), turned into Dust by an all-Pass (`Enchanter.disenchant_lost_item` = 0), or
   enchanted (`Enchanter.REASON_ARTIFACT` for Reroll / Empower / Imbue; `MAX_ENCHANTS[ARTIFACT] = 0`). It
   keeps its two fixed enchants. The Enchanter tab lists an Artifact **greyed** (`Cell.enchantable` false),
   shows no enchant rows and says "Artifacts cannot be changed". A bot that wears an Artifact weapon enchants its
   best non-Artifact Epic+ armour / off-hand instead (`Enchanter.best_weapon` skips Artifacts, `Enchanter.bot_target`
   is the fallback; `bot_plan` still returns nothing for an Artifact).
6. **Purse board.** Every wallet spend goes through `RunState.try_spend_for`, so the Spent ticker shows the
   M6 kinds without any board code: `&"consumable"` (plain name), `&"black_market"` (`[Item]` in brackets, like
   shop items) and `&"enchant"` (label "Empower Blazing (8 Dust)"); their Dust part is on
   `RunState.dust_spend_log`.
7. **Damage meter.** A boss killed through `WeaponRunner.apply_hit` / `ProcSystem.deal_raw` is credited like
   any enemy (damage = the HP it really had left, no overkill) and `record_special_kill(&"boss", slot)` fills
   `bosses_by_player` for the killer; `RunSummary` / the SMOKE `meter` entry show both.
8. **Bot market order** (final): equip / forge, enchant (30% of the purse above the Trainer reserve, from wave
   12), buy, Black Market (from wave 15), consumables (from wave 6), Trainer, talents, reroll. A bot's hook
   sidestep (Flesh Golem) ends its `think()` early, before the rescue and loot steering; the hazard push is not
   mixed into it (a hook is a 0.8 s event).
9. **Determinism.** See "Determinism (M6a draw points)" below.

### Balance pass (levers, diagnostics, results)

Done on top of the merged M6a head (`4aa2c3e`), bots only: `godot --headless --fixed-fps 60 --path . -- --smoke
--waves=25 --allow-defeat --players=N --classes=... --seed=S`, two Godot processes at a time (the same build and
seed are bit-identical). Raw numbers: GDD chapter 9, "M6a mérés".

- **Method.** Baseline = the M6a head plus the diagnostics commit (no gameplay change). The matrix: 4p warrior /
  mage / paladin / rogue seeds 3 / 21 / 55 / 7, 2p warrior + mage seed 21 and paladin + rogue seed 34, 1p paladin 21 /
  mage 34 / warrior 7 / rogue 13, plus nine extra seeds (4p 5; 2p wm 5, wm 8, pr 8; 1p warrior 8, warrior 21, mage 7,
  paladin 13, rogue 34): 19 configurations, because one run per configuration is mostly noise (a solo hero's first
  down is the run). Three tuning rounds: round 1 the golem and the first Vor'thalax numbers, rounds 2 and 3
  Vor'thalax only (a change that touches only Vor'thalax cannot change a run before wave 25 - checked: identical
  downs per wave - so those rounds re-ran only the runs that reached wave 25). "TIMEOUT" = the smoke safety killed
  the boss 210 s after its arrival: the run is `completed`, but the boss was NOT beaten.
- **Baseline findings.**
  - Natural parties finished more often than the review feared: 4p 4 of 5 (the lost one: seed 5, wave 20), 2p 1 of
    5 (two duos died on wave 14, two lost to the final boss within 12-17 s), 1p 1 of 9 (three lost to the final
    boss, the rest died on waves 7-24; the M5 base also lost solo heroes on waves 8, 19 and 24 on the same seeds, so
    the early solo deaths are not an M6a regression).
  - **Flesh Golem = 38% of all damage taken from wave 10 on** (19 runs; 20-53% per run in waves 10-19) from ~2% of
    the spawned enemies. Axethrower 20-35%, Gurglers 10-20%, the rest < 8% each (Vor'thalax' own hits 6-12% of waves
    20+ in 4p). A wave-14 golem hit on a duo's warrior: 24.4 raw, 11.9 after armour, on a 43.7 HP hero.
  - **Wave 20 is a spike, not a wall**: 4p downs per run on wave 20 5.4 (2.0 / 2.4 on 18 / 19, 0.2 on 21); 2p 0.7. The
    one wipe (4p seed 5) already had 9 downs on 15-19.
  - **Vor'thalax died too fast for a full party and killed small parties at once**: 4p kills in 29 / 41 / 45 / 50 s
    (HP x3.25) at 3-7 downs each; the duos that did not win died 11.7 s and 17.3 s after its arrival, a solo mage
    25.7 s. At wave 25 the heroes have **59-109 HP** (wave 10: 16-56; mage 59-104, warrior 65-105, paladin 71-109,
    rogue 60-84) and the damage curve is x45: every hazard or contact hit one-shots a squishy hero (a wave-25
    meteor shared by a duo was 435 raw per hero). Solo DPS on the boss spans 0.8k/s (paladin) to 23k/s (rogue).
- **Levers (old -> new):**

  | Lever | Old | New | Why |
  |---|---|---|---|
  | `data/enemies/flesh_golem.tres` `contact_damage` | 4.0 | **2.5** | 38% of the damage taken from 2% of the enemies; the hook (1 x contact) follows. Before it 2 of 5 duos died on wave 14 and 4p seed 5 wiped on 20; after it neither does (golem share 28% in waves 10-19, 26% from 20). |
  | `data/bosses/vorthalax.tres` `coop_hp_per_player` | 0.75 | **2.0** | Boss HP x1 / x3 / x5 / x7 by party size (was x1 / x1.75 / x2.5 / x3.25): party DPS grows faster than the party (items, 5 Artifacts, focus). A first try at +300% (x10 at 4p, a 110 s fight) wiped 3 of 4 full parties and every duo, so it went back to +200%. |
  | `data/bosses/vorthalax.tres` `contact_damage` | 4.0 | **1.5** | Every hazard of the boss is a multiple of it (Fire Fields 1x, Meteor 8x / 4x, contact). Not on the agreed lever list: the fight's length is bounded by how long a party survives, and at 4 / 2 it one-shot most heroes. 4 -> 2 in round 2, 2 -> 1.5 in round 3. |
  | Morvain, the wave-20 rule, the puddle, the Acolyte heal, `COOP_DAMAGE_MULTS`, the golem's cooldown / spawn weight | - | **unchanged** | Morvain kills 19-97 s (medians 63 s 4p / 55 s 2p / 59 s 1p; target 40-90 s). Wave 20 is a clear spike once the golem is soft. Puddles are 3-6% of the damage, the Acolyte's heal does not show in the data. The duo / solo mid-game is already thin after the golem nerf (0 downs on 10-19), so the damage table stays. |

- **Diagnostics added** (no gameplay): `RunState.damage_taken_by_source` (`{source id: {wave: float}}`, cleared by
  `start_run`) fed by `record_damage_taken(player_index, amount, source_id := &"")`; `Player.take_damage` passes
  `_damage_source_id(attacker)` = the attacker's `EnemyData.id` (a boss's hazards carry the boss as `source`, so they
  book under the boss id; an add books under its own id) or `&"environment"` for a hit without an enemy (the poison
  puddle) - dodged / parried / blocked-away / absorbed damage is not booked (it is HP taken). SMOKE_RESULT
  `taken_by_source` = `RunSummary.source_damage_dict()`: `{source id: {"wave": damage rounded to 0.1}}` (string
  keys; the analysis scripts sum it per wave band). A boss arrival prints a second smoke line `SMOKE heroes: P1
  warrior 98 HP (takes 32% of a raw hit), ...` (`Main.heroes_defence_text`; HP = `Stats.max_hp`, "takes" =
  `CombatMath.incoming_damage(100, ...)` for a melee hit, i.e. after Armor, Versatility, Avoidance).
- **Results** (19 runs; before -> after):

  | Target | Measured |
  |---|---|
  | 4p: no downs on waves 1-4 | 0 in every run (0) |
  | 4p: occasional downs from ~8-13, regular from ~15 | first downs on waves 8 / 10 / 12 / 16 / 18 (8 / 10 / 12 / 13 / 14); downs on 15-19 per run 2.8 (7.0) |
  | 4p: most seeds clear 25, wipes <= ~1 in 4 and not before ~18 | 4 of 5 clear (4 of 5); the loss is the final boss (166 s, 29% HP left, 46 downs in the run); waves 20-24 downs per run 3 / 5 / 12 / 12 / 21 (11 / 21 / 11 / 7 / 14) |
  | 2p: most seeds reach 20+, <= ~1 in 3 wipe | all 5 reach wave 20; 3 of 5 clear (1 of 5; two died on wave 14 before); losses: wave 20 (wm seed 8) and the final boss (wm seed 5, 28 s) |
  | 1p: median death wave ~20+, >= 1 of ~4 clears | median death wave 25 (24); 2 real clears (both rogue) + 2 TIMEOUT "clears" (paladin) of 9 (1 clear); deaths on waves 7 / 20 / 22 / 23 / 25 |
  | Morvain ~40-90 s | medians 63 s (4p) / 55 s (2p) / 59 s (1p), unchanged |
  | Vor'thalax ~90-180 s | 4p 36 / 64 / 97 / 102 s (29 / 41 / 45 / 50 s), median 80 s; 2p 43 / 58 / 108 s (58 s); 1p rogue 9 / 20 s, solo mage 64 s (lost, 35% HP left), solo paladin never (TIMEOUT at 210 s, alive, 0 downs) |
  | Wave 20 a spike, not a wall | 4p 5.4 downs per run on wave 20 vs 0.8 on 19 and 21 (before 5.4 vs 2.4 / 0.2); 2p 2.4 vs 0.0; no wipe on it except 2p wm seed 8 (2 downs = a duo wipe) |

  Requested matrix (before -> after; downs 1-4 / 5-9 / 10-14 / 15-19 / 20-25 in `downs`):

  | run | before | after |
  |---|---|---|
  | 4p s3 | clear, downs 0/0/4/3/15, Vor 29 s | clear, 0/0/0/2/3, Vor 64 s |
  | 4p s21 | clear, 0/0/3/20/24, Vor 41 s | clear, 0/0/1/1/5, Vor 102 s |
  | 4p s55 | clear, 0/0/2/2/15, Vor 45 s | clear, 0/0/0/4/14, Vor 36 s |
  | 4p s7 | clear, 0/0/1/1/14, Vor 50 s | lost to the boss at 166 s (29% HP left), 0/0/1/2/43 |
  | 4p s5 (extra) | wiped on wave 20 | clear, Vor 97 s |
  | 2p wm s21 | died on wave 14 | clear, Vor 108 s |
  | 2p pr s34 | clear, Vor 58 s | clear, Vor 58 s, 0 downs |
  | 2p wm s5 (extra) | died on wave 14 | lost to the boss at 28 s |
  | 2p wm s8 (extra) | lost to the boss at 12 s | died on wave 20 |
  | 2p pr s8 (extra) | lost to the boss at 17 s | clear, Vor 43 s |
  | 1p paladin s21 | lost to the boss (197 s) | TIMEOUT |
  | 1p mage s34 | lost to the boss (26 s) | lost to the boss (64 s) |
  | 1p warrior s7 | died on wave 7 | died on wave 7 (the M5 base also lost solo heroes on 8 / 19 / 24 on these seeds) |
  | 1p rogue s13 | clear, Vor 9 s | clear, Vor 20 s |

  Golem share of the damage taken: waves 10-19 38% -> 28%, waves 20-25 38% -> 26% (the Axethrower is now the biggest
  single source in most 4p runs).
- **Open problems** (for the M6b final balance):
  - Vor'thalax is a class lottery: DPS on the boss spans 0.8k/s (a solo paladin never kills it) to 23k/s (rogue). One
    duo (warrior + mage) lost 28 s into the fight with 74% HP left, a full party with a weak seed (4p seed 7, 46 downs
    in the run) lost at 166 s with 29% left. If the 4p median (80 s) should reach 90-180 s: 4p x7 -> x8-9
    (`coop_hp_per_player` 2.0 -> 2.4), but the weaker parties are at the edge already; or lower the Paladin / Warrior
    bot's boss targeting.
  - Hero HP vs the damage curve at wave 25 (60-110 HP, hits x45): the final boss, wave 20 and the golem's hook one-shot
    the mage / rogue whatever the multiplier is; a hero-HP growth term (per level, per Item Level) is the principled fix.
  - Duos and solo heroes have almost no mid-game pressure after the golem nerf (0 downs on waves 10-19 in 1p / 2p),
    while a solo first down on waves 7-23 ends the run (1p warrior seed 7 dies on wave 7 on the M5 base too).
    `COOP_DAMAGE_MULTS` was deliberately not touched.
  - Re-run the 4p / 2p matrix on the head with the supply fix (fewer Artifacts in 4p / 2p: less late weapon damage)
    and the bot Enchanter fix: these numbers are on `4aa2c3e` plus the balance commits only.
  - A smoke "clear" does not prove the boss is beatable (2 solo paladin runs): count the `TIMEOUT` lines when
    reading a matrix.
  - Single-seed before / after pairs are noisy (one data-only change moved 1p mage seed 7 from wave 24 to wave 20);
    the conclusions rest on the totals.

### Determinism (M6a draw points)

Everything goes through `RunState.rng` or a private rng seeded from the run seed; `--fixed-fps 60` smokes stay
bit-identical per seed.

- The seeded `--fixed-fps 60 --smoke --waves=6 --seed=5` differs from the pre-M6 base only through the enemy data fixes
  (Marsh Gurgler group 4-6, Greedy 5% / +1 gold, which shift the RNG stream): 587 kills, 2 goblins, 195.1 s run time
  instead of 595 kills / 0 goblins; every other feature alone was identical to the base. The follow-ups (the Artifact
  threshold, the bot Enchanter target, the market header, the loot roll layout, the golem / Vor'thalax numbers and the
  diagnostics) change nothing in those six waves: same 587 kills.
- Boss wave start: eligible list -> (no elite schedule) -> first group pick -> `wave_started` (the GoblinSpawner draws
  nothing on a boss wave) -> opening group -> the boss point. Waves 1-9, 11-19 and 21-24 draw what they drew before.
  Wave 20: one affix draw per enemy that is not a due real elite (`roll_affix`).
- Enemy `create` / `setup`: one extra draw for SUPPORT and BRUTE (the staggered first cooldown, like RANGED). The
  Fire Fields (Fisher-Yates over the heroes) and the Meteor target draw from `RunState.rng`; the puddle, the
  hook line, the hazards' pushes, the boss model and the HUD draw nothing; a bot's hook dodge uses the bot's own rng.
- Artifact roll: only when a roll is really made (from wave 10, not for an already rolled enemy, chance above 0, a
  class still free): the chance `randf`, on a hit the 80 / 20 `randf`, then a `randi_range` among more than one
  class. The normal-kill threshold changed with the party size, not the draw order.
- Shop: the consumables row and the Black Market draw only from `Shop._side` (seeded from the run seed and
  `SIDE_RNG_SALT`), so the item offers of a seeded run and `RunState.rng` do not move.
- Enchanter: one `randf()` per Reroll / Imbue (`Enchanter.pick`), Empower and the prices draw nothing; the bot target
  pick (`bot_target`) is deterministic; no change before wave 12.
- Bots: the consumables and Black Market passes draw nothing; the golem hook dodge is decided once per golem and hook
  by the bot's own rng.
- Meter, end screen, run card: no RNG.

### Validation and balance data points

#### The merged M6a head (before the balance pass and the fixes)


Validation of the merged M6a (six feature branches merged plus three integration commits, before the balance pass
and the fixes). All runs `--fixed-fps 60` (bit-identical for the same seed), headless, GL Compatibility.

**Suite.** 2183 passed, 0 failed (after each merge: bosses 1765, enemies 1832, Artifacts 1943 + 1 fixed, Enchanter
2025, shop sinks 2081, meter 2165, integration tests +18). The one `ERROR` line in the log is the intentional
`ProcSystem.shield_hp is read-only` test.

**Seed-5 smoke** (`--smoke --waves=6 --seed=5`): exit 0, 0 errors, 0 warnings, 587 kills, 2 goblins, 211.9 s game
time (195.1 s run time), level 7. The pre-M6 base gave 595 kills / 0 goblins / 215.9 s game time: the difference comes only from
the enemy data fixes (Marsh Gurgler group 4-6, Greedy 5% / +1 gold; they shift the RNG stream); every other
feature alone was identical to the base, and the enemies alone gave exactly these 587 / 195.1 s.

**Natural 25-wave runs** (`--smoke --waves=25 --allow-defeat`, bots only, nothing set up):

| | 4 players, seed 5 | 2 players, seed 21 | 1 player, seed 8 |
|---|---|---|---|
| Result | defeat on wave 20 (the party was wiped there), waves 1-19 cleared | defeat on wave 14 (both heroes down within 5 s), waves 1-13 cleared | defeat on wave 20, waves 1-19 cleared |
| Morvain (wave 10) | 18,214 HP, killed after 52.2 s (phase 2, enrage 0, 19 casts), 2 downs / 2 revives | 9,807 HP, killed after 72.4 s, 0 downs | 5,604 HP, killed after 93.0 s (enrage level 1), 0 downs |
| Vor'thalax (wave 25) | not reached | not reached | not reached |
| Downs, waves 1-9 / 10-19 / 20+ | 2 / 10 / 14 (26 in all, 22 revives) | 0 / 2 / 0 | 0 / 0 / 1 |
| Artifacts | 5 (every class once): Skull (warlock, wave 10, boss), Staff (mage, 11, elite), Dawnbreaker (paladin, 17, elite), Earthsplitter (warrior, 19, elite), Fangs (rogue, 19, loot) | 1: Earthsplitter (wave 14, loot) | 0 |
| Consumables / Black Market / enchants | 64 / 1 / 12 | 14 / 0 / 4 | 21 / 0 / 7 |
| Dust earned / spent | 119 / 116 | 29 / 24 | 63 / 62 |
| Gold at the last shop (after wave 19 / 13 / 19) | 307 | 41 | 191 |
| Gold spent, Greed gold | 13,043, 3,377 | 2,789, 738 | 4,475, 881 |
| Items bought / looted / forged | 96 / 109 / 10 | 38 / 36 / 1 | 22 / 38 / 2 |
| Run time (game / real) | 1,492.9 s / 460 s | 744.3 s / 100 s | 1,528.6 s / 144 s |
| Errors / warnings | 0 / 0 | 0 / 0 | 0 / 0 |

For comparison the pre-M6 base (M5 gameplay) plays the 2-player seed-21 run to the end: completed, 25 waves, 16
downs, gold at the last shop 1,876 (nothing to spend it on), no consumables / Dust. The M6 sinks work: the purse is
emptied by consumables, enchants and the Black Market (gold at the last shop 41-307).

**What kills the bots** (before the balance pass; a debug copy printed every hit by source, the numbers equal the runs above): the **Flesh Golem**
is the biggest damage dealer from wave 12 on: 42% (4 players) / 50% (1) / 37% (2) of all damage taken in waves 10-19
(hook + melee), then the Troll Axethrower (25-32%); 7 of the 10 downs of waves 10-19 and 11 of the 14 downs of wave 20 in
the 4-player run came from golem hits (wave 19 alone: 6 downs). **Wave 20** (every enemy carries an elite affix, HP x1.5)
is a wall for the smoke bots at every party size: golems with Shielding / Vampiric affixes and enraged / frenzied
axethrowers. The 2-player party loses at wave 14 because nobody is left to revive. Sourceless ground damage (the poison puddles)
is 4-6% of the damage taken; Morvain's own attacks are 5% (1 player) to 13% (2 players) of waves 10-19.
Disabling the bots' puddle avoidance on the 2-player seed made it worse (defeat on wave 12, Morvain 169.6 s): the
avoidance is not what loses the run.

**Boss kill times** are in the table (Morvain 52-93 s, 1-4 players); Vor'thalax was never reached naturally in these
three runs, his numbers are the leveled-up experiments of the boss-fight data below (450 base HP); the balance pass
ran him naturally.


#### After the follow-ups (two branches on the merged head, validated separately)

- **Fixes** (market header, bot Enchanter target, Artifact supply, two pinned clauses, loot roll frame): full suite
  2198 passed, 0 failed (baseline 2183, +15); `--fixed-fps 60 --smoke --waves=6 --seed=5` exit 0, 0 errors, 0 warnings,
  587 kills, 2 goblins. Artifact supply runs (start level 40, `--boss-hp=0.05`, seed 5, 0 errors / warnings): the 1p
  run completed with 4,671 kills and 5 Artifacts, the 4p run completed with 13,101 kills and 4 Artifacts; the 2p run
  was defeated on wave 20, so the 2p row of the GDD 5.5 supply table is an interpolation, not a completed run. The
  expected Artifacts per 25-wave run (Fortune 0) are in GDD 5.5 (≈ 2.8 / 2.5 / 2.6 for 1 / 2 / 4 players).
- **Balance pass:** full suite 2190 passed, 0 failed (+7 over 2183); the same seed-5 smoke, identical to the M6a head
  (587 kills, 0 errors, 0 warnings). The 19-run matrix is in "Balance pass".
- The combination of the two (and the 4p / 2p matrix on it) is not measured yet.

#### Boss-fight data points (before the balance pass: contact 4, `coop_hp_per_player` 0.75; `--fixed-fps 60`, natural runs from wave 1)


Command: `godot --headless --fixed-fps 60 --path . -- --smoke --waves=25 [--allow-defeat] --seed=S
--players=N` (the 3 / 1 player runs use the first N classes: warrior, mage, paladin).
Wave-25 downs = downs at the end minus the cumulative downs after wave 24.

Vor'thalax before the balance pass (base HP 450, contact 4; boss HP = base x wave growth x (1 + 0.75 (n - 1))):

| Players, seed | Boss HP | `--allow-defeat` (natural defeat ends the run) | Smoke default (a wipe revives everybody) |
|---|---|---|---|
| 4, seed 9 | 670,754 | killed after 118.5 s, 4 / 4 standing, 17 wave-25 downs, no wipe | same (no wipe) |
| 3, seed 6 | 515,965 | party wiped at 154.3 s with 2% HP left (26 downs) | killed after 156.5 s, 1 wipe, 27 downs, 2 / 3 standing |
| 1, seed 4 | 206,386 | the lone bot dies on wave 13 (before any boss) | killed after 199.7 s, 17 wipes, 17 downs |

Other base HPs tried (same seeds, same history up to wave 25; the data was edited in a scratch
copy or `--boss-hp` was used, which also scales Morvain):

- 4 / seed 9: base 1200: 38% HP left at 210 s (safety kill); 650: the party wipes at 134.7 s with
  21% left (18 downs); 450: kill 118.5 s; 420: kill 94.8 s (1 / 4 standing, 13 downs); `--boss-hp=0.55`
  (base 358): the party wipes at 49 s with 48% left.
- 3 / seed 6: base 1200: 55% left at 210 s; 450: wipe at 154 s, 2% left; 420: wipe at 148 s, 20% left;
  360: wipe at 131 s, 19% left (18 downs). The 3-player party keeps wiping around 130-155 s (enrage
  level 2-3), so even 360 does not give a kill without revives; its DPS is only ~2.6-3.3k / s.
- 1 / seed 4 (smoke revives): base 1200: 67% left at 210 s; 450: kill 199.7 s; 250: kill 130 s (4 wipes).
- Bot team damage against Vor'thalax at wave 25: ~0.9k / s (1 bot), ~3k / s (3), ~6k / s (4), i.e.
  faster than the boss co-op HP factor (1 : 2.5 : 3.25), so one base HP cannot give 120-150 s at every
  party size: 450 fits 4 players (118 s) and is about right for 3 (156 s with one revive); the lone bot
  needs ~200 s (and 17 revives). Lowering `coop_hp_per_player` (or the boss damage) is the lever if
  solo / duo should be shorter; the base HP stays tuned to the 4-bot smoke (the balance pass then raised k to 2.0 and
  cut the contact damage to 1.5, see "Balance pass").
- Morvain (wave 10, 18,214 HP with 4 players): killed after 51-56 s, 1-2 downs; 3 players (14,011 HP)
  43 s, 0 downs; 1 player (5,604 HP) 57-92 s, 0 downs (enrage level 1 at 90 s).
- `--start-wave=9 --start-level=12` / `--start-wave=24 --start-level=24` heroes have NO gear and no
  abilities (0 kills in wave 24): they cannot kill a boss; those runs end through the smoke safety
  kill (and complete with exit 0).

### M6a tests

The M6a tests (each new behaviour has a test that fails without it; the new tests were mutation-checked, e.g. deleting `and hazard == Vector2.ZERO` in the rescue stand, the `_bots_black_market()` call in `_bots_reroll`, or the `_damage_source_id` argument fails a test):

| File | Covers |
|---|---|
| `tests/test_m6_foundation.gd` | the foundation hooks: Dust wallet, meter recorders and credit, run clock, boss kind of `record_special_kill`, SUPPORT / BRUTE dispatch, death-effect virtual, `BossData`, the Db dirs, `ConsumableData`, the Enchanter tab, the `roll_artifact` wiring, the bot-pass order, the SMOKE keys and the launch flags |
| `tests/test_m6_enemies.gd`, `test_m6_enemies_player.gd` | the three enemies' data, the puddle, the Acolyte (distance, heal / shield, interruptions, priority target, never heals a boss), the golem's hook, `take_hook` / `pull_toward` on real heroes, the bots' hook dodge per golem |
| `tests/test_m6_bosses.gd` | boss data and rules, the scheduler, the hazards, rewards, director boss waves, smoke safety, elite wave 20 / lite affix, the HUD frame, the bots' hazard steering, Main's boss flow and victory; `test_visuals_camera.gd`: boss framing |
| `tests/test_m6_artifacts_core.gd`, `_props.gd`, `_ui.gd`, `_fit.gd`, `_log.gd` | the five Artifacts: data and validation, growth / awakening, the pair rule, drops (one roll per kill; `test_chances_by_source_and_fortune` for the 2-player run, `test_normal_kill_chance_is_divided_by_the_party_size` for 1-4 players), Need / Greed, the ten properties on real heroes, tooltips, the loot roll window fit (`READABLE_FIT` 0.7; the frame below the title block for every Artifact, with a two-line Greed result and for a solo hero), the corner-panel fit, the smoke log |
| `tests/test_enchanter.gd`, `test_ui_enchanter.gd`, `test_loot_roll.gd`, `test_ui_market_loot.gd` | ranks I-V, Dust, Disenchant, prices, Reroll / Empower / Imbue, the tab, the hold rule, the purse board Dust, the loot roll Pass -> Dust and the B prompts, the bots' Enchanter pass |
| `tests/test_m6_shopsinks_core.gd`, `_ui.gd` | the seven consumables, the stall row and the Black Market (side rng, prices, set pieces), the layout at 1920x1080 and 1280x720, the bots |
| `tests/test_m6_meter.gd`, `_credit.gd`, `_ui.gd` | the recorders, the caster credit at every heal / shield / revive call site through the real code, the end screen, the awards, the run card |
| `tests/test_m6_followup.gd` | the follow-up fixes: the market header names no seconds before a boss wave (waves 10 and 25, the other waves keep their line, the open market screen), `Enchanter.best_weapon` skipping Artifacts and `bot_target` (the weapon, else the best Epic+ armour / off-hand; the Fangs pair counts as two Artifacts; a bot holding an Artifact enchants its armour; a bot with a normal weapon still enchants the weapon first), the rescue stand beside a downed teammate (`test_a_bot_beside_a_downed_teammate_*`: stands still without a hazard, leaves a puddle / a boss circle it stands in, ignores a far one), a bot reroll that redraws an affordable Black Market upgrade buys it |
| `tests/test_m6_balance.gd` | 7 tests: `record_damage_taken` keeps source and wave, `start_run` clears it, a hit on a hero is booked under the golem / `environment`, the `taken_by_source` format, the golem pins (contact 2.5, hook still 1 x, a duo's wave-14 hit < 16 raw), the Vor'thalax pins (contact 1.5, k = 2, x1 / x3 / x5 / x7, Morvain unchanged, a duo's meteor share < 170 raw), `Main.heroes_defence_text`; `test_m6_enemies.gd` (golem contact) and `test_m6_bosses.gd` (Vor'thalax contact) were updated |
| `tests/test_m6_integration.gd` | the cross-package contracts of 2.8: the puddle as a bot hazard and `WaveDirector.stop()`, the Acolyte beside a real boss, a boss kill in the meter, one Artifact roll per boss, Dawn's Embrace credit, consumable / Black Market / enchant spends in the purse board, Artifacts never sold / disenchanted / enchanted / dusted, the Enchanter tab greying them |
