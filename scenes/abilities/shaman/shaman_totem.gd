class_name ShamanTotem
extends Node3D
## One totem of the Shaman (M8, design_shaman.md §3): planted by Totem Rite (and later by the Bond Totem
## capstone and the Thunderpost Artifact), it stands for [member life_left] seconds, is no target (no HP,
## not in the enemies group), keeps working while its Shaman is downed and is removed with the wave
## (the ability's begin_wave / end_wave) and when the Shaman is freed. Elements (fixed rules per totem):
##   fire   every fire_interval s (Haste of the owner shortens it, the first shot 0.3 s after planting) a
##          firebolt at the nearest enemy within fire_range of the totem: 4 + 0.7 Int + 1.0 SP x interval,
##          x power, Fire ability damage (no Storm Echo)
##   water  every water_interval s every living hero within water_radius heals (ShamanKit.heal_amount)
##   earth  every 0.25 s enemies within earth_radius are slowed by earth_slow x power % (at most 60)
##   air    every 0.25 s heroes within air_radius get the stat source "totem_air:<slot>" {haste: air_haste x
##          power (at most 40)}, removed when they leave, at the end and with the wave
##   bond / storm: look only (the Wellspring capstone and the Artifact drive them)
## Aura (Artifact property, aura_damage_pct > 0): heroes within aura_radius of ANY totem of the owner get
## the stat source "totem_aura:<slot>" {damage_pct}. Radii count the owner's Area Size.
## [param params] are the final Totem Rite numbers (rank / spec / item mods and the shaman_totems mods in).

const FIRST_SHOT_DELAY := 0.3
const FIELD_TICK := 0.25
const SLOW_LINGER := 0.4
const FADE_TIME := 0.2
const BOLT_SPEED := 14.0
const MAX_SLOW := 60.0
const MAX_HASTE := 40.0
const GROUP := &"shaman_totems"

var owner_player: Player
var element: StringName = &"fire"
var params: Dictionary = {}
var life_left := 10.0
var follows := false
var dismissed := false
var model: ShamanTotemModel
## Counters (tests): firebolts shot, heals given, slows applied.
var shots := 0
var heals := 0

## The owner's slot key for the stat sources ("0"), kept: the owner may be freed before the totem.
var _slot_key := ""
var _age := 0.0
var _duration := 10.0
var _fire_left := FIRST_SHOT_DELAY
var _water_left := 0.0
var _field_left := 0.0
var _aura_left := 0.0
## Instance id -> hero buffed by this totem's Air field / aura.
var _air_buffed: Dictionary[int, Player] = {}
var _aura_buffed: Dictionary[int, Player] = {}


## Plants a totem of [param p_element] for [param p_owner] at [param at] for [param p_duration] s under
## the arena's entity root (or next to its owner). Not in the tree without a parent.
static func plant(p_owner: Player, p_element: StringName, p_params: Dictionary, at: Vector3,
		p_duration: float, p_follows: bool = false) -> ShamanTotem:
	var t := ShamanTotem.new()
	t.name = "Totem" + String(p_element).capitalize()
	t.owner_player = p_owner
	t.element = p_element
	t.params = p_params.duplicate(true)
	t.life_left = p_duration
	t._duration = p_duration
	t.follows = p_follows
	t._slot_key = ShamanKit.slot_key(p_owner)
	t.model = ShamanTotemModel.new()
	t.model.setup(p_element)
	t.model.set_grow(0.0)
	t.add_child(t.model)
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(t)
		t.global_position = Vector3(at.x, 0.0, at.z)
	return t


func _ready() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	_release_buffs()


func _physics_process(delta: float) -> void:
	step(delta)


## Seconds left (0 once dismissed).
func time_left() -> float:
	return 0.0 if dismissed else maxf(0.0, life_left)


func is_active() -> bool:
	return not dismissed and life_left > 0.0


## Fades away now: the buffs end at once, the node is freed. [param quiet] has no visual difference (the
## model shrinks for FADE_TIME only when the time simply ran out).
func dismiss(_quiet: bool = true) -> void:
	if dismissed:
		return
	dismissed = true
	_release_buffs()
	remove_from_group(GROUP)
	queue_free()


## One physics step (tests drive it directly).
func step(delta: float) -> void:
	if dismissed:
		return
	if owner_player == null or not is_instance_valid(owner_player) or owner_player.is_queued_for_deletion():
		dismiss(true)
		return
	if not is_inside_tree():
		return
	_age += delta
	life_left -= delta
	if life_left <= 0.0:
		dismiss()
		return
	if model != null:
		model.set_grow(minf(_age / FADE_TIME, life_left / FADE_TIME))
	if follows:
		var o := owner_player.global_position
		global_position = Vector3(o.x, 0.0, o.z)
	match element:
		&"fire":
			_step_fire(delta)
		&"water":
			_step_water(delta)
		&"earth":
			_step_field(delta, false)
		&"air":
			_step_field(delta, true)
	if num("aura_damage_pct") > 0.0:
		_step_aura(delta)


# --- Elements ----------------------------------------------------------------------------------

func _step_fire(delta: float) -> void:
	_fire_left = maxf(0.0, _fire_left - delta)
	if _fire_left > 0.0:
		return
	var targets := ShamanKit.nearest_enemies(get_tree(), global_position, num("fire_range", 9.0), 1)
	if targets.is_empty():
		return
	var interval := fire_interval()
	_fire_left = interval
	var e := targets[0]
	var base_interval := maxf(0.1, num("fire_interval", 1.0))
	var amount := ShamanKit.spell_damage(owner_player.stats, {
		"damage": num("fire_damage", 4.0), "intellect_scale": num("fire_intellect_scale", 0.7),
		"spell_power_scale": num("fire_spell_power_scale", 1.0), "power": num("power", 1.0),
	}, ShamanKit.FIRE, base_interval)
	var from := global_position + Vector3.UP * (ShamanTotemModel.CROWN_Y + 0.1)
	ProcVfx.bolt(from, ShamanKit.chest(e), ShamanKit.FIRE_COLOR)
	Audio.play(&"cast_fire")
	owner_player.procs.deal_raw(e, amount, ShamanKit.FIRE, true, &"ability")
	shots += 1
	if is_instance_valid(e) and e.is_inside_tree():
		Vfx.hit_spark(ShamanKit.chest(e), ShamanKit.FIRE_COLOR)


## Seconds between firebolts: fire_interval, shortened by the owner's Haste.
func fire_interval() -> float:
	var haste := owner_player.stats.attack_speed_mult() if owner_player != null else 1.0
	return maxf(0.2, num("fire_interval", 1.0) / maxf(0.2, haste))


func _step_water(delta: float) -> void:
	_water_left -= delta
	if _water_left > 0.0:
		return
	var interval := maxf(0.1, num("water_interval", 1.0))
	_water_left += interval
	if _water_left <= 0.0:
		_water_left = interval
	var power := num("power", 1.0)
	for hero in ShamanKit.heroes_around(get_tree(), global_position, radius_of("water_radius", 6.0)):
		var amount := ShamanKit.heal_amount(owner_player, hero, num("water_heal", 0.5),
				num("water_heal_max_hp_pct", 2.5), num("water_spell_power_scale", 0.5) * interval, power)
		if ShamanKit.is_hurt(hero):
			heals += 1
		hero.heal(amount, Player.slot_index_of(owner_player))


## Earth slow / Air haste: re-checked every FIELD_TICK s.
func _step_field(delta: float, air: bool) -> void:
	_field_left -= delta
	if _field_left > 0.0:
		return
	_field_left += FIELD_TICK
	if _field_left <= 0.0:
		_field_left = FIELD_TICK
	if air:
		_apply_air()
		return
	var power := num("power", 1.0)
	var slow := minf(MAX_SLOW, num("earth_slow", 30.0) * power)
	if slow <= 0.0:
		return
	for e in ShamanKit.enemies_around(get_tree(), global_position, radius_of("earth_radius", 5.0)):
		e.apply_slow(slow, SLOW_LINGER)


func _apply_air() -> void:
	var haste := minf(MAX_HASTE, num("air_haste", 15.0) * num("power", 1.0))
	var key := _air_key()
	var inside: Dictionary[int, Player] = {}
	if haste > 0.0:
		for hero in ShamanKit.heroes_around(get_tree(), global_position, radius_of("air_radius", 6.0)):
			inside[hero.get_instance_id()] = hero
	for id in _air_buffed.keys():
		if not inside.has(id):
			var gone := _air_buffed[id]
			if is_instance_valid(gone):
				gone.stats.remove_source(key)
			_air_buffed.erase(id)
	for id in inside:
		var hero := inside[id]
		var had := _air_buffed.has(id)
		if not had or not is_equal_approx(float(hero.stats.get_source(key).get(Stats.HASTE, 0.0)), haste):
			hero.stats.set_source(key, {Stats.HASTE: haste})
		_air_buffed[id] = hero


## Aura: heroes in range of this totem get the damage bonus; ones that left lose it unless another totem
## of the owner still covers them.
func _step_aura(delta: float) -> void:
	_aura_left -= delta
	if _aura_left > 0.0:
		return
	_aura_left += FIELD_TICK
	if _aura_left <= 0.0:
		_aura_left = FIELD_TICK
	var pct := num("aura_damage_pct")
	var key := _aura_key()
	var inside: Dictionary[int, Player] = {}
	for hero in ShamanKit.heroes_around(get_tree(), global_position, radius_of("aura_radius", 6.0)):
		inside[hero.get_instance_id()] = hero
	for id in _aura_buffed.keys():
		if not inside.has(id):
			var gone := _aura_buffed[id]
			if is_instance_valid(gone) and not _covered_by_sibling(gone):
				gone.stats.remove_source(key)
			_aura_buffed.erase(id)
	for id in inside:
		var hero := inside[id]
		if not is_equal_approx(float(hero.stats.get_source(key).get(Stats.DAMAGE_PCT, 0.0)), pct):
			hero.stats.set_source(key, {Stats.DAMAGE_PCT: pct})
		_aura_buffed[id] = hero


func _covered_by_sibling(hero: Player) -> bool:
	for node in get_tree().get_nodes_in_group(GROUP):
		var t := node as ShamanTotem
		if t == null or t == self or t.dismissed or t.owner_player != owner_player or t.num("aura_damage_pct") <= 0.0:
			continue
		if ShamanKit.flat_distance(t.global_position, hero.global_position) <= t.radius_of("aura_radius", 6.0) + 0.001:
			return true
	return false


func _release_buffs() -> void:
	var air := _air_key()
	for id in _air_buffed:
		var hero := _air_buffed[id]
		if is_instance_valid(hero):
			hero.stats.remove_source(air)
	_air_buffed.clear()
	var aura := _aura_key()
	for id in _aura_buffed:
		var hero := _aura_buffed[id]
		if is_instance_valid(hero) and not (is_inside_tree() and _covered_by_sibling(hero)):
			hero.stats.remove_source(aura)
	_aura_buffed.clear()


func _air_key() -> StringName:
	return StringName("totem_air:" + _slot_key)


func _aura_key() -> StringName:
	return StringName("totem_aura:" + _slot_key)


# --- Params ------------------------------------------------------------------------------------

func num(key: String, default: float = 0.0) -> float:
	var v: Variant = params.get(key, default)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else default


## A radius param after the owner's Area Size.
func radius_of(key: String, default: float) -> float:
	var area := CombatMath.area_mult(owner_player.stats) if owner_player != null and is_instance_valid(owner_player) else 1.0
	return num(key, default) * area
