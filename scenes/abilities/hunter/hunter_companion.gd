class_name HunterCompanion
extends Node3D
## The Hunter's permanent animal companion (GDD 3.7, M8): a Wolf, a Boar or an Owl, chosen per
## player in the lobby ([member Player.companion_id]). Spawned by [HunterMastery] under the arena's
## entity root (or next to the Hunter), it survives waves, hides while the Hunter is downed and is
## freed in the Mastery's teardown. It is not targetable and has no health: enemies never attack
## it, so there is nothing to revive – it snaps back to the Hunter at every wave start.
##
## All damage is PET damage: ProcSystem.deal_raw(..., &"pet") on the Hunter (kill credit and the
## damage meter go to the Hunter, Beastbond and the other pet multipliers apply; no crits, no
## on-hit procs). One hit = the weapon hit "W" ([method GeneralKit.weapon_damage]) x
## [code]damage_pct[/code] % x (1 + [code]damage_bonus[/code] %) x the frenzy bonus. Attack speed =
## the Hunter's Haste and [code]haste[/code] % (and the frenzy's haste), at least
## [constant MIN_INTERVAL] s between hits.
##
## Numbers live in [constant BASE_PARAMS] (all keys always present, neutral = 0) plus the
## per-kind numbers of [constant KIND_PARAMS]; items and talents change them through ability_mod on
## the pseudo ability [constant MOD_ID] (Hauberk of the Loyal Heart: {"damage_bonus_add": 30,
## "haste_add": 10}; Keen Companion, Bonded Vigor, Feral Tempo, Kindred Instinct ...).
##   Wolf – chases the enemy nearest to it within [code]range[/code] (8) m of the Hunter and bites
##          every [code]interval[/code] (1.2) s for [code]damage_pct[/code] (38) %; every bite slows
##          the enemy by [code]slow[/code] (30) % for [code]slow_duration[/code] (1) s.
##   Boar – the same hunt with a heavier, slower bite (50 % / 2 s) and a CHARGE every
##          [code]charge_cooldown[/code] (7) s at the nearest enemy within [code]charge_range[/code]
##          (8) m: [code]charge_pct[/code] (55) % to everything in [constant CHARGE_RADIUS] m, then it
##          TAUNTS every enemy within [code]taunt_radius[/code] (4) m for [code]taunt_duration[/code]
##          (1.5) s (Enemy.apply_taunt, as the Gloomguard does).
##   Owl  – hovers [constant HOVER_HEIGHT] m up behind the Hunter's right shoulder and never chases;
##          every [code]interval[/code] (0.6) s it shoots a feather bolt ([HunterFeatherBolt]) for
##          [code]damage_pct[/code] (20) % at the enemy nearest to it within [code]attack_range[/code]
##          (8) m (and [code]range[/code] (9) m of the Hunter).
## Hunt Signal ([HunterHuntSignal]) sends it after the strongest enemies: [method command_strikes].
## Pack Frenzy (a talent) sets [member frenzy_left], [member frenzy_damage_pct] and
## [member frenzy_haste_pct]; the companion glows while the frenzy lasts.

const MOD_ID := &"hunter_companion"
const KINDS: Array[StringName] = [&"wolf", &"boar", &"owl"]
## Every number a mod may name, with its neutral value (talents / items validate against these).
const BASE_PARAMS := {
	"damage_pct": 0.0,
	"interval": 1.2,
	"range": 8.0,
	"reach": 0.55,
	"attack_range": 0.0,
	"speed": 9.0,
	"haste": 0.0,
	"damage_bonus": 0.0,
	"heal_pct": 0.0,
	"slow": 0.0,
	"slow_duration": 1.0,
	"taunt_radius": 0.0,
	"taunt_duration": 1.5,
	"charge_pct": 0.0,
	"charge_cooldown": 7.0,
	"charge_range": 8.0,
	"bolt_speed": 20.0,
}
const KIND_PARAMS := {
	&"wolf": {"damage_pct": 38.0, "interval": 1.2, "range": 8.0, "slow": 30.0, "slow_duration": 1.0},
	&"boar": {"damage_pct": 50.0, "interval": 2.0, "range": 7.0, "speed": 9.0, "charge_pct": 55.0,
		"charge_cooldown": 7.0, "charge_range": 8.0, "taunt_radius": 4.0, "taunt_duration": 1.5},
	&"owl": {"damage_pct": 20.0, "interval": 0.6, "range": 9.0, "attack_range": 8.0},
}
## Preferred distance to the Hunter (m) and how far apart it may be before it pops back.
const FOLLOW_DISTANCE := 1.4
const TELEPORT_DISTANCE := 14.0
## Follow speed when it has nothing to hunt (m/s).
const FOLLOW_SPEED := 9.0
## Looks for a (new) target this often (s).
const RETARGET_INTERVAL := 0.25
## The first attack comes this soon after it reaches its prey / appears (s).
const FIRST_ATTACK_DELAY := 0.15
const MIN_INTERVAL := 0.2
## The owl's hover height (m) and where it floats: behind the Hunter's right shoulder.
const HOVER_HEIGHT := 1.6
const OWL_BACK := 0.6
const OWL_SIDE := -0.8
## The boar's charge: speed (m/s), the circle it hits (m) and how long it may run (s).
const CHARGE_SPEED := 14.0
const CHARGE_RADIUS := 1.5
const CHARGE_REACH := 0.7
const CHARGE_MAX_TIME := 1.2
## Hunt Signal: the dash speed (m/s) and the longest a dash may take (s).
const SIGNAL_SPEED := 22.0
const SIGNAL_TIMEOUT := 1.5
const SPARK_COLOR := Color(1.0, 0.85, 0.5)
const SUMMON_COLOR := Color(0.95, 0.75, 0.4)

var owner_player: Player
var kind: StringName = &"wolf"
var model: HunterCompanionModel
## Bites / bolts / blows dealt, charges made, enemies taunted (counted per application), Hunt Signal blows (tests).
var attacks := 0
var charges_made := 0
var taunts_applied := 0
var signal_strikes := 0
## Pack Frenzy hooks (set by the talent script): seconds left and the bonus damage / attack speed (%).
var frenzy_left := 0.0
var frenzy_damage_pct := 0.0
var frenzy_haste_pct := 0.0
## The enemy it hunts (untyped: it may be freed meanwhile – see [method current_target]).
var target: Variant = null
## The last feather bolt (owl; tests); may be freed.
var last_bolt: HunterFeatherBolt

var _params: Dictionary = {}
var _attack_left := FIRST_ATTACK_DELAY
var _retarget_left := 0.0
var _hidden := false
var _look_dir := Vector3.FORWARD
var _charge_left := 0.0
var _charging := false
var _charge_time := 0.0
var _charge_target: Variant = null
var _signal_queue: Array = []
var _signal_blow: Dictionary = {}
var _signal_time := 0.0
var _speed_ratio := 0.0
var _frenzy_shown := false
var _gone := false


## The numbers of a companion of [param p_kind] before mods (BASE_PARAMS + the kind's numbers).
static func base_params(p_kind: StringName) -> Dictionary:
	var out := BASE_PARAMS.duplicate()
	out.merge(KIND_PARAMS.get(p_kind, {}), true)
	return out


## Creates the companion of [param p_owner] (kind: its Player.companion_id, else [param p_kind],
## else the Wolf) and adds it under the arena's entities next to the Hunter. Not in the tree when
## there is no such parent.
static func spawn(p_owner: Player, p_kind: StringName = &"") -> HunterCompanion:
	var c := HunterCompanion.new()
	var wanted := p_kind if p_kind != &"" else p_owner.companion_id
	c.kind = wanted if wanted in KINDS else &"wolf"
	c.name = "Companion"
	c.owner_player = p_owner
	c._params = base_params(c.kind)
	c._charge_left = float(c._params["charge_cooldown"]) * 0.5
	c.model = HunterCompanionModel.new()
	c.model.kind = c.kind
	c.add_child(c.model)
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(c)
		c.snap_to_owner()
		c._puff()
	return c


func is_hidden() -> bool:
	return _hidden


func is_frenzied() -> bool:
	return frenzy_left > 0.0


## True while a Hunt Signal dash is under way.
func is_signalling() -> bool:
	return not _signal_queue.is_empty()


## True while the boar charges.
func is_charging() -> bool:
	return _charging


## The companion's numbers with the Hunter's mods applied (items, talents, sets).
func current_params() -> Dictionary:
	var mods: Dictionary = owner_player.ability_mods(MOD_ID) if _owner_valid() else {}
	return AbilityRunner.apply_mods(base_params(kind), mods)


## Multiplier on every hit it deals: (1 + damage_bonus %) x (1 + frenzy damage %) while the frenzy lasts.
func damage_mult() -> float:
	var mult := 1.0 + float(_params.get("damage_bonus", 0.0)) / 100.0
	if frenzy_left > 0.0:
		mult *= 1.0 + frenzy_damage_pct / 100.0
	return maxf(0.0, mult)


## Damage of one hit worth [param pct] % of the weapon hit "W" for the Hunter's current stats,
## before Beastbond and the other multipliers deal_raw applies.
func hit_damage(pct: float) -> float:
	if not _owner_valid():
		return 0.0
	return GeneralKit.weapon_damage(owner_player, HunterKit.PHYSICAL) * pct / 100.0 * damage_mult()


## Seconds between two attacks: interval / (the Hunter's attack speed x the companion's haste and
## the frenzy's haste), at least MIN_INTERVAL.
func attack_interval() -> float:
	var haste_pct := float(_params.get("haste", 0.0))
	if frenzy_left > 0.0:
		haste_pct += frenzy_haste_pct
	var speed := owner_player.stats.attack_speed_mult() if _owner_valid() else 1.0
	return maxf(MIN_INTERVAL, float(_params.get("interval", 1.2)) / maxf(0.2, speed * (1.0 + haste_pct / 100.0)))


## Wave start: back next to the (teleported) Hunter, a short pause before the first attack.
func begin_wave() -> void:
	_clear_commands()
	snap_to_owner()
	_attack_left = FIRST_ATTACK_DELAY
	_charge_left = maxf(_charge_left, 1.0)
	_retarget_left = 0.0
	target = null


## Puts the companion at its spot next to the Hunter.
func snap_to_owner() -> void:
	if not _owner_valid() or not owner_player.is_inside_tree() or not is_inside_tree():
		return
	global_position = _home()


## Leaves now.
func dismiss() -> void:
	_gone = true
	target = null
	_clear_commands()
	queue_free()


func _physics_process(delta: float) -> void:
	step(delta)


## One physics step (tests drive it directly).
func step(delta: float) -> void:
	if _gone:
		return
	if not _owner_valid():
		_gone = true
		queue_free()
		return
	if not owner_player.is_inside_tree() or not is_inside_tree():
		return
	if frenzy_left > 0.0:
		frenzy_left = maxf(0.0, frenzy_left - delta)
	_show_frenzy(frenzy_left > 0.0)
	var hide_now := owner_player.downed
	if hide_now != _hidden:
		_hidden = hide_now
		visible = not hide_now
		_clear_commands()
		if not hide_now:
			snap_to_owner()
			_puff()
			_attack_left = FIRST_ATTACK_DELAY
	if _hidden:
		return
	_retarget_left -= delta
	if _retarget_left <= 0.0:
		_retarget_left = RETARGET_INTERVAL
		_params = current_params()
		if _signal_queue.is_empty() and not _charging:
			target = _find_target()
	_attack_left = maxf(0.0, _attack_left - delta)
	if not _signal_queue.is_empty():
		_run_signal(delta)
		return
	if kind == &"boar":
		_charge_left -= delta
		if _charging:
			_run_charge(delta)
			return
	var prey := current_target()
	if kind == &"owl":
		_hover(delta, prey)
		return
	if prey != null:
		if kind == &"boar" and _charge_left <= 0.0 and float(_params.get("charge_pct", 0.0)) > 0.0 \
				and _flat_distance(prey) <= float(_params.get("charge_range", 8.0)):
			_start_charge(prey)
			return
		_hunt(prey, delta)
	else:
		_follow(delta)


## The hunted enemy while it is still a valid target (else null).
func current_target() -> Enemy:
	return target as Enemy if _target_ok(target) else null


# --- Hunting ---------------------------------------------------------------------------------

func _hunt(prey: Enemy, delta: float) -> void:
	var here := _flat(global_position)
	var to := _flat(prey.global_position) - here
	var dist := to.length()
	var reach := prey.radius + float(_params.get("reach", 0.55))
	var dir := to / dist if dist > 0.001 else _flat(owner_player.facing)
	_look_dir = dir
	if dist > reach:
		var step_len := minf(float(_params.get("speed", 9.0)) * delta, dist - reach * 0.8)
		global_position = _clamp(here + dir * step_len)
		_attack_left = maxf(_attack_left, FIRST_ATTACK_DELAY * 0.5)
		_animate(dir, 1.0)
		return
	_animate(dir, 0.0)
	if _attack_left <= 0.0:
		_bite(prey)


## A bite / blow of the wolf and the boar at [param e].
func _bite(e: Enemy) -> void:
	_attack_left = attack_interval()
	if owner_player.procs == null or not _target_ok(e):
		return
	var dealt := owner_player.procs.deal_raw(e, hit_damage(float(_params.get("damage_pct", 0.0))),
			HunterKit.PHYSICAL, true, &"pet")
	attacks += 1
	# The bite slow is the Wolf's gift (Kindred Instinct adds to it): the Boar's heavy bite and the Owl never slow.
	var slow := float(_params.get("slow", 0.0)) if kind == &"wolf" else 0.0
	if slow > 0.0 and HunterKit.is_live(e):
		e.apply_slow(minf(slow, 90.0), float(_params.get("slow_duration", 1.0)))
	_heal_owner(dealt)
	if model != null:
		model.play_attack()
	if is_instance_valid(e) and e.is_inside_tree():
		Vfx.hit_spark(e.global_position + Vector3.UP * 0.5, SPARK_COLOR)


## The owl: floats at its spot behind the Hunter and shoots at the nearest enemy in reach.
func _hover(delta: float, prey: Enemy) -> void:
	var here := _flat(global_position)
	var home := _home()
	var to := home - here
	var dist := to.length()
	if dist > TELEPORT_DISTANCE:
		snap_to_owner()
		_animate(owner_player.facing, 0.0)
		return
	var moving := 0.0
	if dist > 0.05:
		var step_len := minf(FOLLOW_SPEED * delta, dist)
		global_position = _clamp(here + to / dist * step_len)
		moving = clampf(dist / 1.0, 0.0, 1.0)
	if prey != null:
		_look_dir = _flat(prey.global_position - global_position).normalized()
		_animate(_look_dir, moving)
		if _attack_left <= 0.0:
			_shoot(prey)
	else:
		_animate(owner_player.facing, moving)


## The owl shoots a feather bolt at [param e].
func _shoot(e: Enemy) -> void:
	_attack_left = attack_interval()
	if not _target_ok(e):
		return
	var here := global_position
	var dir := HunterKit.dir_to(here, e.global_position, _look_dir)
	_look_dir = dir
	var reach := float(_params.get("attack_range", 8.0))
	last_bolt = HunterFeatherBolt.fire(owner_player, Vector3(here.x, HOVER_HEIGHT * 0.8, here.z) + dir * 0.3, dir,
			hit_damage(float(_params.get("damage_pct", 0.0))), reach + 1.5, float(_params.get("bolt_speed", 20.0)),
			float(_params.get("heal_pct", 0.0)))
	attacks += 1
	if model != null:
		model.set_facing(dir)
		model.play_attack()


func _follow(delta: float) -> void:
	var here := _flat(global_position)
	var home := _home()
	var to := home - here
	var dist := to.length()
	if dist > TELEPORT_DISTANCE:
		snap_to_owner()
		_animate(owner_player.facing, 0.0)
		return
	if dist < 0.08:
		_animate(owner_player.facing, 0.0)
		return
	var step_len := minf(FOLLOW_SPEED * delta, dist)
	global_position = _clamp(here + to / dist * step_len)
	_animate(to / dist if dist > 0.3 else owner_player.facing, clampf(dist / 1.0, 0.0, 1.0))


## The enemy nearest to the companion among those within range of the Hunter (the owl: and within
## its own attack range). Ties: the first in group order.
func _find_target() -> Enemy:
	var reach := float(_params.get("range", 8.0))
	var master := _flat(owner_player.global_position)
	var best: Enemy = null
	var best_d := INF
	for node in EnemyGrid.gather_around(get_tree(), master, reach):
		if not _target_ok(node):
			continue
		var e := node as Enemy
		if GeneralKit.flat_distance(e.global_position, master) > reach:
			continue
		var d := GeneralKit.flat_distance(e.global_position, global_position)
		if kind == &"owl" and d > float(_params.get("attack_range", 8.0)):
			continue
		if d < best_d:
			best_d = d
			best = e
	return best


func _target_ok(candidate: Variant) -> bool:
	if not HunterKit.is_live(candidate) or not _owner_valid():
		return false
	var e := candidate as Enemy
	var leash := float(_params.get("range", 8.0)) + 1.0
	if GeneralKit.flat_distance(e.global_position, owner_player.global_position) > leash:
		return false
	if kind == &"owl" and GeneralKit.flat_distance(e.global_position, global_position) > float(_params.get("attack_range", 8.0)) + 1.0:
		return false
	return true


# --- The boar's charge -----------------------------------------------------------------------

func _start_charge(prey: Enemy) -> void:
	_charging = true
	_charge_time = 0.0
	_charge_target = prey


func _run_charge(delta: float) -> void:
	_charge_time += delta
	var prey := _charge_target as Enemy if HunterKit.is_live(_charge_target) else null
	if prey == null:
		prey = _find_target()
		_charge_target = prey
	if prey == null:
		_impact()
		return
	var here := _flat(global_position)
	var to := _flat(prey.global_position) - here
	var dist := to.length()
	var reach := prey.radius + CHARGE_REACH
	if dist > reach and _charge_time < CHARGE_MAX_TIME:
		var dir := to / dist
		_look_dir = dir
		global_position = _clamp(here + dir * minf(CHARGE_SPEED * delta, dist - reach * 0.8))
		_animate(dir, 1.0)
		return
	_impact()


## The charge lands: damage in a small circle, then the taunt.
func _impact() -> void:
	_charging = false
	_charge_target = null
	_charge_left = float(_params.get("charge_cooldown", 7.0))
	_attack_left = maxf(_attack_left, FIRST_ATTACK_DELAY)
	charges_made += 1
	var at := global_position
	var damage := hit_damage(float(_params.get("charge_pct", 0.0)))
	if owner_player.procs != null:
		for e in GeneralKit.enemies_around(get_tree(), at, CHARGE_RADIUS):
			var dealt := owner_player.procs.deal_raw(e, damage, HunterKit.PHYSICAL, true, &"pet")
			_heal_owner(dealt)
	var taunt_radius := float(_params.get("taunt_radius", 0.0)) * CombatMath.area_mult(owner_player.stats)
	var duration := float(_params.get("taunt_duration", 1.5))
	if taunt_radius > 0.0 and duration > 0.0:
		for e in GeneralKit.enemies_around(get_tree(), at, taunt_radius):
			e.apply_taunt(self, duration)
			taunts_applied += 1
	Vfx.explosion(at + Vector3.UP * 0.1, CHARGE_RADIUS, SPARK_COLOR)
	Vfx.death_puff(at + Vector3.UP * 0.3, Color(0.8, 0.7, 0.5), 0.9)
	if model != null:
		model.play_attack()


# --- Hunt Signal -----------------------------------------------------------------------------

## Hunt Signal: the companion dashes to each enemy of [param targets] in turn and strikes it with
## [param blow]: pct (% of "W"), the kind's rider (wolf_slow, wolf_slow_duration, boar_stun,
## owl_bonus), splash_radius, splash_pct, bleed_pct, bleed_duration, on_kill (a Callable taking the
## enemy killed by the blow). False when it is hidden or has no target.
func command_strikes(targets: Array, blow: Dictionary) -> bool:
	if _hidden or _gone or targets.is_empty():
		return false
	_signal_queue = []
	for t in targets:
		if HunterKit.is_live(t):
			_signal_queue.append(t)
	if _signal_queue.is_empty():
		return false
	_signal_blow = blow.duplicate()
	_signal_time = 0.0
	_charging = false
	_charge_target = null
	if model != null:
		model.set_diving(kind == &"owl")
	return true


func _run_signal(delta: float) -> void:
	while not _signal_queue.is_empty() and not HunterKit.is_live(_signal_queue[0]):
		_signal_queue.pop_front()
		_signal_time = 0.0
	if _signal_queue.is_empty():
		_end_signal()
		return
	var prey := _signal_queue[0] as Enemy
	_signal_time += delta
	var here := _flat(global_position)
	var to := _flat(prey.global_position) - here
	var dist := to.length()
	var reach := prey.radius + float(_params.get("reach", 0.55)) + 0.15
	var dir := to / dist if dist > 0.001 else _flat(owner_player.facing)
	_look_dir = dir
	if dist > reach:
		global_position = _clamp(here + dir * minf(SIGNAL_SPEED * delta, dist - reach * 0.8))
		_animate(dir, 1.0)
		if _signal_time > SIGNAL_TIMEOUT:
			_signal_queue.pop_front()
			_signal_time = 0.0
		return
	_signal_queue.pop_front()
	_signal_time = 0.0
	_land_blow(prey)
	if _signal_queue.is_empty():
		_end_signal()


func _end_signal() -> void:
	_signal_blow = {}
	_attack_left = maxf(_attack_left, FIRST_ATTACK_DELAY)
	if model != null:
		model.set_diving(false)


## One blow of Hunt Signal on [param prey].
func _land_blow(prey: Enemy) -> void:
	var blow := _signal_blow
	var damage := hit_damage(float(blow.get("pct", 0.0)))
	if kind == &"owl":
		damage *= 1.0 + float(blow.get("owl_bonus", 0.0)) / 100.0
	signal_strikes += 1
	var at := prey.global_position
	var dealt := 0.0
	if owner_player.procs != null:
		dealt = owner_player.procs.deal_raw(prey, damage, HunterKit.PHYSICAL, true, &"pet")
	_heal_owner(dealt)
	if HunterKit.is_live(prey):
		match kind:
			&"wolf":
				prey.apply_slow(minf(90.0, float(blow.get("wolf_slow", 0.0))), float(blow.get("wolf_slow_duration", 0.0)))
			&"boar":
				if float(blow.get("boar_stun", 0.0)) > 0.0:
					prey.apply_stun(float(blow.get("boar_stun", 0.0)))
	var splash := float(blow.get("splash_radius", 0.0)) * CombatMath.area_mult(owner_player.stats)
	if splash > 0.0 and owner_player.procs != null:
		var splash_damage := damage * float(blow.get("splash_pct", 60.0)) / 100.0
		for e in GeneralKit.enemies_around(get_tree(), at, splash):
			if e != prey:
				_heal_owner(owner_player.procs.deal_raw(e, splash_damage, HunterKit.PHYSICAL, true, &"pet"))
		Vfx.explosion(Vector3(at.x, 0.1, at.z), splash, SPARK_COLOR)
	var bleed := float(blow.get("bleed_pct", 0.0))
	if bleed > 0.0 and HunterKit.is_live(prey):
		HunterBleed.apply(prey, owner_player, damage * bleed / 100.0, float(blow.get("bleed_duration", 4.0)),
				&"hunt_signal", &"pet")
	if is_instance_valid(prey) and prey.is_inside_tree():
		Vfx.hit_spark(prey.global_position + Vector3.UP * 0.6, SPARK_COLOR, HunterKit.PHYSICAL, true)
	if model != null:
		model.play_attack()
	if (not is_instance_valid(prey) or prey.is_dead()) and blow.has("on_kill"):
		var callback: Callable = blow["on_kill"]
		if callback.is_valid():
			callback.call(prey)


func _clear_commands() -> void:
	_signal_queue = []
	_signal_blow = {}
	_signal_time = 0.0
	_charging = false
	_charge_target = null
	if model != null:
		model.set_diving(false)


# --- Helpers ---------------------------------------------------------------------------------

func _heal_owner(dealt: float) -> void:
	var heal_pct := float(_params.get("heal_pct", 0.0))
	if heal_pct > 0.0 and dealt > 0.0 and _owner_valid() and not owner_player.downed:
		owner_player.heal(dealt * heal_pct / 100.0)


## The companion's spot beside the Hunter: behind its left shoulder (the Wolf and the Boar, on the
## ground) or behind its right shoulder (the Owl, whose model hovers at HOVER_HEIGHT).
func _home() -> Vector3:
	var facing := _flat(owner_player.facing)
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var left := Vector3(facing.z, 0.0, -facing.x)
	var spot := Vector2(0.75, 0.65)
	if kind == &"owl":
		spot = Vector2(OWL_BACK, OWL_SIDE)
	var offset := (-facing * spot.x + left * spot.y).normalized() * FOLLOW_DISTANCE
	return _flat(owner_player.global_position) + offset


func _animate(dir: Vector3, moving: float) -> void:
	if model != null:
		model.set_facing(dir)
		model.set_moving(moving)
	_speed_ratio = moving


func _show_frenzy(on: bool) -> void:
	if on == _frenzy_shown:
		return
	_frenzy_shown = on
	if model != null:
		model.set_frenzy(on)


func _flat_distance(e: Enemy) -> float:
	return GeneralKit.flat_distance(e.global_position, global_position)


func _clamp(pos: Vector3) -> Vector3:
	var arena := Arena.current
	if arena != null and is_instance_valid(arena):
		return arena.clamp_point(pos, 0.4)
	return pos


func _owner_valid() -> bool:
	return owner_player != null and is_instance_valid(owner_player) and not owner_player.is_queued_for_deletion()


func _puff() -> void:
	if is_inside_tree():
		Vfx.hit_spark(global_position + Vector3.UP * 0.6, SUMMON_COLOR)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
