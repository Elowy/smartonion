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
