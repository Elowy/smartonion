class_name AbilityRunner
extends Node
## A player's abilities, class resources and Mastery (GDD 3, 6). Child node "Abilities".
##
## Slots: 0 = RT, 1 = LT (the class's two core abilities), 2 = RB, 3 = LB (learned actives, M4).
## Input edges are read in _process (PlayerInput rule); cooldowns, resources and effects
## tick in _physics_process. Bots (BotInput) auto-cast when AbilityEffect.wants_auto_cast.
## All targeting is automatic.
##
## Charges: the "charges" param (default 1, item mods: "charges_add") lets an ability be cast
## that many times in a row; spent charges come back one per cooldown, in sequence. With one
## charge this is the plain cooldown.

signal ability_cast(slot_index: int, ability: AbilityData)
signal slots_changed

const CORE_SLOTS := 2
const MAX_SLOTS := 4
## Bots re-check their abilities this often (s).
const AUTO_CAST_INTERVAL := 0.25
## Default cluster radius for DENSEST_CLUSTER targeting (m).
const CLUSTER_RADIUS := 3.0

var player: Player
var slots: Array[AbilityData] = []
## Ability id -> rank (0 = Rank I). M4 raises ranks.
var ranks: Dictionary[StringName, int] = {}
## Resource id -> state; [member resource_order] keeps the class's order (primary first).
var resources: Dictionary[StringName, ClassResource] = {}
var resource_order: Array[StringName] = []
var mastery: MasteryEffect
var auto_cast := false

var _effects: Dictionary[StringName, AbilityEffect] = {}
## Ability id -> seconds until the next spent charge comes back.
var _cooldown_left: Dictionary[StringName, float] = {}
## Ability id -> charges spent and not yet back.
var _charges_spent: Dictionary[StringName, int] = {}
## Ability id -> params_for result (read-only); cleared by invalidate_params.
var _params_cache: Dictionary[StringName, Dictionary] = {}
var _auto_timer := 0.0


static func create(p_player: Player) -> AbilityRunner:
	var r := AbilityRunner.new()
	r.name = "Abilities"
	r.player = p_player
	r.slots.resize(MAX_SLOTS)
	# Only real bots (BotInput) auto-cast; tests drive ScriptedInput like a human.
	if p_player != null and p_player.slot != null:
		r.auto_cast = p_player.slot.input is BotInput
	if p_player != null and p_player.class_data != null:
		r.setup_from_class(p_player.class_data)
	return r


func setup_from_class(class_data: ClassData) -> void:
	resources.clear()
	resource_order.clear()
	for data in class_data.resources:
		if data != null:
			resources[data.id] = ClassResource.new(data)
			resource_order.append(data.id)
	for i in class_data.abilities.size():
		if i < CORE_SLOTS:
			set_slot(i, class_data.abilities[i])
	if class_data.mastery != null:
		mastery = class_data.mastery.new() as MasteryEffect
		if mastery != null and player != null:
			mastery.setup(player)


func set_slot(index: int, ability: AbilityData) -> void:
	if index < 0 or index >= MAX_SLOTS:
		return
	slots[index] = ability
	if ability != null and not _effects.has(ability.id) and ability.effect != null:
		_effects[ability.id] = ability.effect.new() as AbilityEffect
	invalidate_params()
	slots_changed.emit()


func get_resource(id: StringName) -> ClassResource:
	return resources.get(id)


func primary_resource() -> ClassResource:
	return resources.get(resource_order[0]) if not resource_order.is_empty() else null


func effect_for(ability: AbilityData) -> AbilityEffect:
	return _effects.get(ability.id) if ability != null else null


## Full cooldown: the "cooldown" param (after item mods, from [param ctx] when given), then
## Haste (half effect) and Cooldown Reduction.
func cooldown_of(ability: AbilityData, ctx: AbilityContext = null) -> float:
	if ability == null:
		return 0.0
	return _cooldown_from(ability, ctx.params if ctx != null else params_for(ability))


func _cooldown_from(ability: AbilityData, params: Dictionary) -> float:
	var base := float(params.get("cooldown", ability.cooldown))
	if base <= 0.0:
		return 0.0
	var cdr := clampf(player.stats.get_raw(Stats.COOLDOWN_REDUCTION), 0.0, 60.0) if player != null else 0.0
	var mult := player.stats.cooldown_mult() if player != null else 1.0
	return base * mult * (1.0 - cdr / 100.0)


## Seconds until slot [param index] can be cast again (0 while a charge is left).
func remaining(index: int) -> float:
	var a := slots[index] if index >= 0 and index < MAX_SLOTS else null
	if a == null or charges_available(a) > 0:
		return 0.0
	return _cooldown_left.get(a.id, 0.0)


func charges_max(ability: AbilityData) -> int:
	if ability == null:
		return 0
	return maxi(1, roundi(float(params_for(ability).get("charges", 1.0))))


## Casts of [param ability] possible right now, ignoring the resource (HUD pips).
func charges_available(ability: AbilityData) -> int:
	if ability == null:
		return 0
	return maxi(0, charges_max(ability) - int(_charges_spent.get(ability.id, 0)))


## Sets the running recharge of [param ability] (effects that shorten / reset a cooldown).
func set_cooldown(ability: AbilityData, seconds: float) -> void:
	if ability == null:
		return
	if seconds <= 0.0:
		_cooldown_left.erase(ability.id)
		_charges_spent.erase(ability.id)
	else:
		_cooldown_left[ability.id] = seconds
		_charges_spent[ability.id] = maxi(1, int(_charges_spent.get(ability.id, 0)))


## 0..1 share of the cooldown still running (HUD sweep).
func cooldown_ratio(index: int) -> float:
	var a := slots[index] if index >= 0 and index < MAX_SLOTS else null
	var full := cooldown_of(a)
	return clampf(remaining(index) / full, 0.0, 1.0) if full > 0.0 else 0.0


## Resource cost: the "cost" param after item mods (from [param ctx] when given).
func cost_of(ability: AbilityData, ctx: AbilityContext = null) -> float:
	if ability == null:
		return 0.0
	var params := ctx.params if ctx != null else params_for(ability)
	return maxf(0.0, float(params.get("cost", ability.cost)))


func can_afford(ability: AbilityData, ctx: AbilityContext = null) -> bool:
	if ability == null or ability.resource == &"":
		return true
	var res := get_resource(ability.resource)
	return res != null and res.can_afford(cost_of(ability, ctx))


## Everything the HUD shows for slot [param index] from one params lookup: charges,
## charges_max, left (s until castable), ratio (0..1 of the running recharge), ready
## (alive, castable now and affordable) and cost. Empty for an empty slot.
func slot_state(index: int) -> Dictionary:
	var a := slots[index] if index >= 0 and index < MAX_SLOTS else null
	if a == null:
		return {}
	var params := params_for(a)
	var cmax := maxi(1, roundi(float(params.get("charges", 1.0))))
	var charges := maxi(0, cmax - int(_charges_spent.get(a.id, 0)))
	var left := 0.0 if charges > 0 else float(_cooldown_left.get(a.id, 0.0))
	var full := _cooldown_from(a, params)
	var cost := maxf(0.0, float(params.get("cost", a.cost)))
	var res := get_resource(a.resource) if a.resource != &"" else null
	var affordable := a.resource == &"" or (res != null and res.can_afford(cost))
	return {
		"charges": charges,
		"charges_max": cmax,
		"left": left,
		"ratio": clampf(left / full, 0.0, 1.0) if full > 0.0 else 0.0,
		"ready": left <= 0.0 and player != null and player.is_alive() and affordable,
		"cost": cost,
	}


## Cheap readiness for the HUD: equipped, alive, off cooldown and affordable (no targeting).
func is_ready(index: int) -> bool:
	var a := slots[index] if index >= 0 and index < MAX_SLOTS else null
	if a == null or player == null or not player.is_alive() or remaining(index) > 0.0:
		return false
	return can_afford(a, _light_context(a))


## Ready = equipped, alive, off cooldown, affordable and the effect agrees.
func can_cast(index: int) -> bool:
	if not _cheap_ready(index):
		return false
	return effect_for(slots[index]).can_cast(build_context(slots[index]))


func try_cast(index: int) -> bool:
	if not _cheap_ready(index):
		return false
	var ctx := build_context(slots[index])
	if not effect_for(slots[index]).can_cast(ctx):
		return false
	return _cast_with(index, ctx)


## Equipped, alive, off cooldown, has an effect and is affordable – everything but the
## targeting (which scans the enemies) and the effect's own conditions.
func _cheap_ready(index: int) -> bool:
	var a := slots[index] if index >= 0 and index < MAX_SLOTS else null
	if a == null or player == null or not player.is_alive() or remaining(index) > 0.0:
		return false
	return effect_for(a) != null and can_afford(a, _light_context(a))


## Casts slot [param index] with an already resolved [param ctx] (cost, cooldown / charge).
func _cast_with(index: int, ctx: AbilityContext) -> bool:
	var a := slots[index]
	var effect := effect_for(a)
	if not effect.cast(ctx):
		return false
	if a.resource != &"":
		get_resource(a.resource).spend(cost_of(a, ctx))
	var full := cooldown_of(a, ctx)
	if full > 0.0:
		_charges_spent[a.id] = int(_charges_spent.get(a.id, 0)) + 1
		if _cooldown_left.get(a.id, 0.0) <= 0.0:
			_cooldown_left[a.id] = full
	ability_cast.emit(index, a)
	return true


## Resolves targets and the params (with item mods + rank) for a cast of [param ability].
func build_context(ability: AbilityData) -> AbilityContext:
	var ctx := AbilityContext.new()
	ctx.player = player
	ctx.ability = ability
	ctx.rank = ranks.get(ability.id, 0)
	ctx.rng = RunState.rng
	ctx.params = params_for(ability)
	var here := player.global_position if player != null and player.is_inside_tree() else Vector3.ZERO
	ctx.point = here
	ctx.direction = player.facing if player != null else Vector3.FORWARD
	var reach := ability.cast_range
	match ability.targeting:
		AbilityData.Targeting.NEAREST_ENEMY:
			ctx.target = _nearest_enemy(here, reach)
		AbilityData.Targeting.DENSEST_CLUSTER:
			ctx.target = _densest_cluster(here, reach, ctx.num("radius", CLUSTER_RADIUS))
		AbilityData.Targeting.MOVE_DIRECTION:
			var move := player.slot.input.get_move() if player != null and player.slot != null else Vector2.ZERO
			if move.length() > 0.2:
				ctx.direction = Vector3(move.x, 0.0, move.y).normalized()
			ctx.point = here + ctx.direction * reach
			ctx.target = _nearest_enemy(here, reach)
		AbilityData.Targeting.ALLY:
			ctx.target = _ally_target(here, reach, ctx.flag("prefer_downed"))
		AbilityData.Targeting.SELF:
			ctx.target = player
	if ability.targeting != AbilityData.Targeting.MOVE_DIRECTION and ctx.target != null:
		ctx.point = ctx.target.global_position
		var d := ctx.point - here
		d.y = 0.0
		if d.length() > 0.01:
			ctx.direction = d.normalized()
	return ctx


## Context without target resolution (per-frame ticks, cost checks).
func _light_context(ability: AbilityData) -> AbilityContext:
	var ctx := AbilityContext.new()
	ctx.player = player
	ctx.ability = ability
	ctx.rank = ranks.get(ability.id, 0)
	ctx.rng = RunState.rng
	ctx.params = params_for(ability)
	ctx.point = player.global_position if player != null and player.is_inside_tree() else Vector3.ZERO
	ctx.direction = player.facing if player != null else Vector3.FORWARD
	return ctx


## The ability's params with "cooldown", "cost" and "charges" (1) filled in (unless the params
## set them) and the player's item mods applied – so "cooldown_add": -5 works on any ability.
## Cached per ability and read-only: effects copy it before changing anything; equipment
## changes (Player.apply_equipment) and set_slot call [method invalidate_params].
func params_for(ability: AbilityData) -> Dictionary:
	var cached: Variant = _params_cache.get(ability.id)
	if cached != null:
		return cached
	var base := {"cooldown": ability.cooldown, "cost": ability.cost, "charges": 1}
	base.merge(ability.params, true)
	var out := apply_mods(base, player.ability_mods(ability.id) if player != null else {})
	out.make_read_only()
	_params_cache[ability.id] = out
	return out


## Drops the cached params (item mods or ranks changed).
func invalidate_params() -> void:
	_params_cache.clear()


## +[param amount] class resource from an item proc (Soulreaping): whole points for the first
## pip resource (Holy Power, Soul Shards, Combo Points), else 10 % of the primary bar per point.
func gain_from_proc(amount: float) -> void:
	for id in resource_order:
		var res := resources[id]
		if res.data != null and res.data.display == ResourceData.Display.PIPS:
			res.add(amount, false)
			return
	var primary := primary_resource()
	if primary != null:
		primary.add(amount * primary.max_value() * 0.1, false)


## Applies item mods to [param base] params. Keys: "<param>_add" adds, "<param>_pct" scales
## by (1 + v / 100), anything else replaces / sets (flags, new params).
static func apply_mods(base: Dictionary, mods: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: String in mods:
		var v: Variant = mods[key]
		if key.ends_with("_add") and typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			var p := key.trim_suffix("_add")
			out[p] = float(out.get(p, 0.0)) + float(v)
		elif key.ends_with("_pct") and typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			var p := key.trim_suffix("_pct")
			out[p] = float(out.get(p, 0.0)) * (1.0 + float(v) / 100.0)
		else:
			out[key] = v
	return out


# --- Player hooks ----------------------------------------------------------------------------

func begin_wave() -> void:
	_cooldown_left.clear()
	_charges_spent.clear()
	for id in resource_order:
		resources[id].reset()
	for a in slots:
		if a != null and _effects.has(a.id):
			_effects[a.id].begin_wave(_light_context(a))
	if mastery != null:
		mastery.begin_wave()


## Wave cleared (before the intermission): effects and the Mastery drop what must not show
## in the market (auras, buffs).
func end_wave() -> void:
	for a in slots:
		if a != null and _effects.has(a.id):
			_effects[a.id].end_wave(_light_context(a))
	if mastery != null:
		mastery.end_wave()


func on_weapon_hit(target: Node3D, damage: float, is_crit: bool) -> void:
	for id in resource_order:
		resources[id].on_weapon_hit(is_crit)
	if mastery != null:
		mastery.on_hit(target, damage, is_crit)


func on_damage_taken(amount: float) -> void:
	for id in resource_order:
		resources[id].on_damage_taken()
	if mastery != null:
		mastery.on_damage_taken(amount)


func on_kill(enemy: Node3D) -> void:
	for id in resource_order:
		resources[id].on_kill()
	if mastery != null:
		mastery.on_kill(enemy)


func teardown() -> void:
	if mastery != null:
		mastery.teardown()


# --- Frame updates ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if player == null or player.slot == null or not player.is_alive() or auto_cast:
		return
	var input := player.slot.input
	for i in MAX_SLOTS:
		if input.ability_just_pressed(i):
			try_cast(i)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_tick_cooldowns(delta)
	var regen := 1.0 + player.stats.get_raw(Stats.RESOURCE_REGEN) / 100.0
	var haste := player.stats.attack_speed_mult()
	for id in resource_order:
		resources[id].gain_mult = maxf(0.0, regen)
		resources[id].tick(delta, haste)
	# The Mastery ticks while downed too (its DoTs keep burning like item DoTs; pets / auras
	# check player.is_alive() themselves).
	if mastery != null:
		mastery.tick(delta)
	if not player.is_alive():
		return
	for a in slots:
		if a != null and _effects.has(a.id):
			_effects[a.id].tick(_light_context(a), delta)
	if auto_cast:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_auto_timer = AUTO_CAST_INTERVAL
			for i in MAX_SLOTS:
				if not _cheap_ready(i):
					continue
				# One targeting pass per decision (DENSEST_CLUSTER scans the enemies).
				var ctx := build_context(slots[i])
				var effect := effect_for(slots[i])
				if effect.can_cast(ctx) and effect.wants_auto_cast(ctx):
					_cast_with(i, ctx)


## Recharges: the timer runs while charges are spent; each expiry returns one charge and
## restarts the timer (with the current cooldown) while more are missing.
func _tick_cooldowns(delta: float) -> void:
	for id in _cooldown_left.keys():
		var left: float = _cooldown_left[id] - delta
		if left > 0.0:
			_cooldown_left[id] = left
			continue
		var spent := int(_charges_spent.get(id, 0)) - 1
		var ability := _slot_ability(id)
		if spent > 0 and ability != null:
			_charges_spent[id] = spent
			_cooldown_left[id] = maxf(0.001, cooldown_of(ability) + left)
		else:
			_charges_spent.erase(id)
			_cooldown_left.erase(id)


func _slot_ability(id: StringName) -> AbilityData:
	for a in slots:
		if a != null and a.id == id:
			return a
	return null


# --- Targeting -------------------------------------------------------------------------------

func _nearest_enemy(here: Vector3, reach: float) -> Node3D:
	if player == null or not player.is_inside_tree():
		return null
	return EnemyGrid.nearest(player.get_tree(), here, reach)


func _densest_cluster(here: Vector3, reach: float, radius: float) -> Node3D:
	if player == null or not player.is_inside_tree():
		return null
	var tree := player.get_tree()
	var best: Node3D = null
	var best_count := 0
	for node in EnemyGrid.gather_around(tree, here, reach):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		var count := EnemyGrid.count_around(tree, e.global_position, radius)
		if count > best_count:
			best_count = count
			best = e
	return best


## The nearest downed teammate in range (if [param prefer_downed]), else the most hurt
## living teammate, else the player itself.
func _ally_target(here: Vector3, reach: float, prefer_downed: bool) -> Node3D:
	if player == null or not player.is_inside_tree():
		return player
	var best: Player = null
	var best_ratio := 2.0
	var downed: Player = null
	var downed_dist := INF
	for node in player.get_tree().get_nodes_in_group(&"players"):
		var p := node as Player
		if p == null or p == player or not p.is_inside_tree():
			continue
		var dist := WeaponRunner.flat(p.global_position - here).length()
		if dist > reach:
			continue
		if p.downed:
			if prefer_downed and dist < downed_dist:
				downed_dist = dist
				downed = p
			continue
		var ratio := p.hp / p.max_hp() if p.max_hp() > 0.0 else 1.0
		if ratio < best_ratio:
			best_ratio = ratio
			best = p
	if downed != null:
		return downed
	return best if best != null else player
