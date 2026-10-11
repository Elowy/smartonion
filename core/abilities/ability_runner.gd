class_name AbilityRunner
extends Node
## A player's abilities, class resources and Mastery (GDD 3, 6). Child node "Abilities".
##
## Slots (GDD 6.2): 0 = RT, 1 = LT (the class's two core abilities), 2 = RB, 3 = LB (learned
## Active abilities), 4..7 = learned Auto-cast abilities (fire by themselves when ready).
## Input edges are read in _process (PlayerInput rule); cooldowns, resources and effects
## tick in _physics_process. Auto-cast slots – and every slot of a bot (BotInput) – cast when
## AbilityEffect.wants_auto_cast. All targeting is automatic.
##
## Ranks I–V (AbilityRanks): free rank-ups from level-up cards, paid ones from the Trainer;
## a rank's changes are part of [method params_for]. Learning: [method learn] /
## [method free_slot] / [method forget] (GDD 6.1–6.3).
##
## Charges: the "charges" param (default 1, item mods: "charges_add") lets an ability be cast
## that many times in a row; spent charges come back one per cooldown, in sequence. With one
## charge this is the plain cooldown.

signal ability_cast(slot_index: int, ability: AbilityData)
signal slots_changed
## An ability's rank or Rank V specialisation changed.
signal ranks_changed(ability_id: StringName)

const CORE_SLOTS := 2
## Slots cast by a button (RT, LT, RB, LB); the rest are auto-cast.
const INPUT_SLOTS := 4
const MAX_SLOTS := 8
const ACTIVE_SLOTS: Array[int] = [2, 3]
const AUTO_SLOTS: Array[int] = [4, 5, 6, 7]
## Auto-cast slots (and bots) re-check their abilities this often (s); the players' passes
## are staggered across the interval.
const AUTO_CAST_INTERVAL := 0.25
## Default cluster radius for DENSEST_CLUSTER targeting (m).
const CLUSTER_RADIUS := 3.0

var player: Player
var slots: Array[AbilityData] = []
## Ability id -> rank (1 = Rank I .. 5); missing = Rank I.
var ranks: Dictionary[StringName, int] = {}
## Ability id -> chosen Rank V specialisation (index into AbilityData.specs).
var specs: Dictionary[StringName, int] = {}
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
## Ability id -> the context handed to that effect's tick(), refreshed every tick instead of
## allocated (effects never keep a ctx); cleared when the slots change.
var _tick_contexts: Dictionary[StringName, AbilityContext] = {}
## Seconds until the next auto-cast pass; staggered by player slot at every wave start.
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
	_tick_contexts.clear()
	invalidate_params()
	slots_changed.emit()


func get_resource(id: StringName) -> ClassResource:
	return resources.get(id)


func primary_resource() -> ClassResource:
	return resources.get(resource_order[0]) if not resource_order.is_empty() else null


func effect_for(ability: AbilityData) -> AbilityEffect:
	return _effects.get(ability.id) if ability != null else null


# --- Learning and ranks (GDD 6.1–6.3) -------------------------------------------------------

func rank_of(ability_id: StringName) -> int:
	return ranks.get(ability_id, 1)


func spec_of(ability_id: StringName) -> int:
	return specs.get(ability_id, -1)


## The slot holding [param ability_id] (-1 if not slotted).
func slot_of(ability_id: StringName) -> int:
	for i in MAX_SLOTS:
		if slots[i] != null and slots[i].id == ability_id:
			return i
	return -1


func knows(ability_id: StringName) -> bool:
	return slot_of(ability_id) >= 0


## Slot indices that take abilities of [param kind] (CORE: 0..1, ACTIVE: 2..3, AUTO: 4..7).
static func slots_for_kind(kind: AbilityData.Kind) -> Array[int]:
	match kind:
		AbilityData.Kind.ACTIVE:
			return ACTIVE_SLOTS
		AbilityData.Kind.AUTO:
			return AUTO_SLOTS
	return [0, 1] as Array[int]


## The first empty slot for [param kind] (-1 = all full).
func free_slot(kind: AbilityData.Kind) -> int:
	for i in slots_for_kind(kind):
		if slots[i] == null:
			return i
	return -1


## Learns [param ability] at Rank I into the first free slot of its kind, or into
## [param replace_index] (a slot of the same kind; the old ability is forgotten and its
## refund returned via [param refund_out]). Returns the slot index, -1 if impossible.
func learn(ability: AbilityData, replace_index: int = -1) -> int:
	if ability == null or not ability.is_learned_kind() or knows(ability.id):
		return -1
	var index := replace_index
	if index < 0:
		index = free_slot(ability.kind)
	if index < 0 or index not in slots_for_kind(ability.kind):
		return -1
	if slots[index] != null:
		forget(index)
	ranks[ability.id] = 1
	set_slot(index, ability)
	return index


## Removes the learned ability in [param index]; returns the gold refund (50 % of its ranks'
## value at the current wave). Core slots cannot be emptied.
func forget(index: int) -> int:
	if index < CORE_SLOTS or index >= MAX_SLOTS or slots[index] == null:
		return 0
	var a := slots[index]
	var refund := AbilityRanks.replace_refund(rank_of(a.id), RunState.wave)
	var effect: AbilityEffect = _effects.get(a.id)
	if effect != null:
		effect.end_wave(_light_context(a))
	_effects.erase(a.id)
	_tick_contexts.erase(a.id)
	_cooldown_left.erase(a.id)
	_charges_spent.erase(a.id)
	ranks.erase(a.id)
	specs.erase(a.id)
	slots[index] = null
	invalidate_params()
	slots_changed.emit()
	return refund


func can_rank_up(ability_id: StringName) -> bool:
	return knows(ability_id) and rank_of(ability_id) < AbilityRanks.MAX_RANK


## +1 rank (max V). Reaching Rank V needs a specialisation: [method needs_spec].
func rank_up(ability_id: StringName) -> bool:
	if not can_rank_up(ability_id):
		return false
	ranks[ability_id] = rank_of(ability_id) + 1
	invalidate_params()
	ranks_changed.emit(ability_id)
	return true


## True at Rank V without a chosen specialisation (the UI asks the player).
func needs_spec(ability_id: StringName) -> bool:
	var i := slot_of(ability_id)
	return i >= 0 and rank_of(ability_id) >= AbilityRanks.MAX_RANK and spec_of(ability_id) < 0 \
			and not slots[i].specs.is_empty()


func set_spec(ability_id: StringName, index: int) -> bool:
	var i := slot_of(ability_id)
	if i < 0 or rank_of(ability_id) < AbilityRanks.MAX_RANK or index < 0 or index >= slots[i].specs.size():
		return false
	specs[ability_id] = index
	invalidate_params()
	ranks_changed.emit(ability_id)
	return true


## Gold for the next rank of [param ability_id] at the current wave (0 = max rank).
func trainer_price(ability_id: StringName) -> int:
	return AbilityRanks.trainer_price(rank_of(ability_id), RunState.wave) if knows(ability_id) else 0


## Full cooldown: the "cooldown" param (after item mods, from [param ctx] when given), then
## Haste (half effect) and Cooldown Reduction.
func cooldown_of(ability: AbilityData, ctx: AbilityContext = null) -> float:
	if ability == null:
		return 0.0
	return _cooldown_from(ability, ctx.params if ctx != null else params_for(ability))


## [method cooldown_of] for an explicit params dict (e.g. [method params_at_rank] previews).
func cooldown_from_params(ability: AbilityData, params: Dictionary) -> float:
	return _cooldown_from(ability, params) if ability != null else 0.0


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


## Uses up one charge of [param ability] as a cast would (the recharge starts if it is not
## already running) – for passives that trigger themselves (Cheat Death).
func spend_charge(ability: AbilityData, ctx: AbilityContext = null) -> void:
	if ability == null:
		return
	var full := cooldown_of(ability, ctx)
	if full <= 0.0:
		return
	_charges_spent[ability.id] = int(_charges_spent.get(ability.id, 0)) + 1
	if _cooldown_left.get(ability.id, 0.0) <= 0.0:
		_cooldown_left[ability.id] = full


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
	spend_charge(a, ctx)
	ability_cast.emit(index, a)
	return true


## Resolves targets and the params (with item mods + rank) for a cast of [param ability].
func build_context(ability: AbilityData) -> AbilityContext:
	var ctx := AbilityContext.new()
	ctx.player = player
	ctx.ability = ability
	ctx.rank = rank_of(ability.id)
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


## Context without target resolution (cost checks, wave hooks).
func _light_context(ability: AbilityData) -> AbilityContext:
	return _fill_light_context(AbilityContext.new(), ability)


## The per-tick context of [param ability]: one object per ability id, refreshed (rank,
## params, position) on every call – an effect must not keep it past its tick().
func _tick_context(ability: AbilityData) -> AbilityContext:
	var ctx: AbilityContext = _tick_contexts.get(ability.id)
	if ctx == null:
		ctx = AbilityContext.new()
		_tick_contexts[ability.id] = ctx
	return _fill_light_context(ctx, ability)


func _fill_light_context(ctx: AbilityContext, ability: AbilityData) -> AbilityContext:
	ctx.player = player
	ctx.ability = ability
	ctx.rank = rank_of(ability.id)
	ctx.rng = RunState.rng
	ctx.params = params_for(ability)
	ctx.target = null
	ctx.point = player.global_position if player != null and player.is_inside_tree() else Vector3.ZERO
	ctx.direction = player.facing if player != null else Vector3.FORWARD
	return ctx


## The ability's params with "cooldown", "cost", "charges" (1) and "power" (1.0) filled in
## (unless the params set them), then its rank's changes (AbilityRanks) and the player's item
## mods applied – so "cooldown_add": -5 works on any ability. Effects scale their damage /
## heal / shield amounts by "power".
## Cached per ability and read-only: effects copy it before changing anything; equipment
## changes (Player.apply_equipment) and set_slot call [method invalidate_params].
func params_for(ability: AbilityData) -> Dictionary:
	var cached: Variant = _params_cache.get(ability.id)
	if cached != null:
		return cached
	var out := params_at_rank(ability, rank_of(ability.id), spec_of(ability.id))
	out.make_read_only()
	_params_cache[ability.id] = out
	return out


## [method params_for] as it would be at [param rank] with specialisation [param spec]
## (previews: level-up rank-up cards, the Trainer). Not cached, a fresh dictionary.
## Three passes: the rank (II–IV), the Rank V specialisation, the item mods – each pass's
## "_pct" keys scale the result of the one before.
func params_at_rank(ability: AbilityData, rank: int, spec: int = -1) -> Dictionary:
	var base := {"cooldown": ability.cooldown, "cost": ability.cost, "charges": 1, "power": 1.0}
	base.merge(ability.params, true)
	var r := clampi(rank, 1, AbilityRanks.MAX_RANK)
	var ranked := apply_mods(base, AbilityRanks.mods_for(ability, r))
	ranked = apply_mods(ranked, AbilityRanks.spec_mods(ability, r, spec))
	return apply_mods(ranked, player.ability_mods(ability.id) if player != null else {})


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


## Applies item / rank mods to [param base] params. Keys: "<param>_add" adds (missing = 0),
## "<param>_pct" scales an existing <param> by (1 + v / 100); a "_pct" key whose <param> does
## not exist sets that key itself (so {"slow_pct": 40} sets a "slow_pct" param); anything else
## replaces / sets (flags, new params).
static func apply_mods(base: Dictionary, mods: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: String in mods:
		var v: Variant = mods[key]
		var numeric := typeof(v) in [TYPE_INT, TYPE_FLOAT]
		if key.ends_with("_add") and numeric:
			var p := key.trim_suffix("_add")
			out[p] = float(out.get(p, 0.0)) + float(v)
		elif key.ends_with("_pct") and numeric and out.has(key.trim_suffix("_pct")):
			var p := key.trim_suffix("_pct")
			out[p] = float(out[p]) * (1.0 + float(v) / 100.0)
		else:
			out[key] = v
	return out


# --- Player hooks ----------------------------------------------------------------------------

func begin_wave() -> void:
	_cooldown_left.clear()
	_charges_spent.clear()
	_stagger_auto_timer()
	for id in resource_order:
		resources[id].reset()
	for a in slots:
		if a != null and _effects.has(a.id):
			_effects[a.id].begin_wave(_light_context(a))
	if mastery != null:
		mastery.begin_wave()


## Each player's auto-cast pass on its own tick (P1–P4: first passes on ticks 1 / 4 / 8 / 12
## of the wave at 60 Hz, then every 15) instead of all heroes' targeting and casts landing on
## the same one. Deterministic: by slot index only.
func _stagger_auto_timer() -> void:
	var index := player.slot.index if player != null and player.slot != null else 0
	_auto_timer = AUTO_CAST_INTERVAL * float(index % PlayerManager.MAX_PLAYERS) / float(PlayerManager.MAX_PLAYERS)


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


## The player is about to be freed: every slotted effect ends what it started (buffs on
## allies, pets, areas) like at a wave end, then the Mastery tears down.
func teardown() -> void:
	for a in slots:
		if a != null and _effects.has(a.id):
			_effects[a.id].end_wave(_light_context(a))
	if mastery != null:
		mastery.teardown()


# --- Frame updates ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if player == null or player.slot == null or not player.is_alive() or auto_cast:
		return
	var input := player.slot.input
	for i in INPUT_SLOTS:
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
			_effects[a.id].tick(_tick_context(a), delta)
	_auto_timer -= delta
	if _auto_timer <= 0.0:
		# += keeps the period exact (15 ticks at 60 Hz, not 16); a delta longer than the
		# interval (a hitch, a test's big step) resyncs instead of running passes back to back.
		_auto_timer += AUTO_CAST_INTERVAL
		if _auto_timer <= 0.0:
			_auto_timer = AUTO_CAST_INTERVAL
		for i in MAX_SLOTS:
			# Auto-cast slots fire for everybody; bots also "press" the button slots.
			if (i < INPUT_SLOTS and not auto_cast) or not _cheap_ready(i):
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
	var reach_sq := reach * reach
	# gather_around returns whole grid cells (a square grown by the enemy radius): keep only
	# centres within the cast range, as NEAREST_ENEMY does.
	for node in EnemyGrid.gather_around(tree, here, reach):
		var e := node as Enemy
		if e == null or e.is_dead() or WeaponRunner.flat(e.global_position - here).length_squared() > reach_sq:
			continue
		var count := EnemyGrid.count_around(tree, e.global_position, radius)
		if count > best_count:
			best_count = count
			best = e
	return best


## The nearest downed teammate in range (if [param prefer_downed]) that the Spirit Healer does
## not revive within PaladinWordOfGlory.HEALER_SOON seconds anyway ([method _healer_raises_soon]),
## else the most hurt living teammate, else the player itself.
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
			if prefer_downed and dist < downed_dist and not _healer_raises_soon(p):
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


## A ghost the Spirit Healer's pulse revives (at full HP) within PaladinWordOfGlory.HEALER_SOON
## seconds: a revive goes to another ghost instead (the same rule Word of Glory checks).
static func _healer_raises_soon(p: Player) -> bool:
	return PaladinWordOfGlory.healer_raises_soon(p)
