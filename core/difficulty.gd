class_name Difficulty
extends RefCounted
## The difficulty ladder (GDD 9.1, M9 ACHIEVE-DIFF): Normal, Pungent, Tear-Jerker – [DifficultyData] in
## data/difficulties/, chosen in the lobby (the party's cap is the lowest tier its classes have unlocked) or with
## --difficulty, stored in [member RunState.difficulty] for the run.
##
## Every system that scales with the tier asks here, so there is one place to read:
##   [method enemy_hp_mult] / [method enemy_damage_mult]   Enemy.setup, Boss.create
##   [method spawn_mult]                                    WaveDirector.spawn_budget_per_second
##   [method elite_mult]                                    Main.start_run (EliteAffixes.rate_mult)
##   [method price]                                         the shop offers, the Trainer, the Enchanter, the
##                                                          consumables row and the Black Market (never a reroll)
##   [method xp_mult_of] / [method seeds_mult_of]           the Class XP and Seeds a run pays (the Class Level
##                                                          package reads them; RunState.difficulty_xp_mult())
## The enemy and spawn multipliers include the Tear-Jerker pressure modifier of the running wave ([Pressure]); a Normal
## run multiplies by exactly 1.0 everywhere, so it plays bit for bit as before.
##
## Unlocking: a tier above Normal opens per class ([method Meta.is_difficulty_unlocked]) – the class-pair achievements
## ("Win with the class" opens Pungent for it, "Win on Pungent with it" opens Tear-Jerker) record the unlock in the
## profile. The party can play the highest tier that every hero's class has open ([method party_cap]).

const NORMAL := &"normal"

## A stand-in for a run without data (a unit test before Db loaded, an unknown id): every multiplier 1.
static var _neutral: DifficultyData


# --- The ladder ---------------------------------------------------------------------------------

## The tier ids, Normal first.
static func ids() -> Array[StringName]:
	return Db.difficulty_ids.duplicate()


static func is_valid(id: StringName) -> bool:
	return Db.difficulties.has(id)


## 0 for Normal, 1 for Pungent ... -1 for an unknown id.
static func tier_index(id: StringName) -> int:
	return Db.difficulty_ids.find(id)


## The tier [param id] (Normal's data for an unknown id; a neutral stand-in when there is no data at all).
static func data_of(id: StringName) -> DifficultyData:
	var d := Db.get_difficulty(id)
	if d != null:
		return d
	d = Db.get_difficulty(NORMAL)
	if d != null:
		return d
	if _neutral == null:
		_neutral = DifficultyData.new()
		_neutral.id = NORMAL
		_neutral.display_name = "Normal"
	return _neutral


## The tier of the run in progress (RunState.difficulty).
static func current() -> DifficultyData:
	return data_of(RunState.difficulty)


static func name_of(id: StringName) -> String:
	var d := Db.get_difficulty(id)
	return d.display_name if d != null else String(id).capitalize()


static func color_of(id: StringName) -> Color:
	return data_of(id).color


## [param id] when it is a tier, else Normal.
static func sanitize(id: StringName) -> StringName:
	return id if is_valid(id) else NORMAL


## The tier after [param id] in [param step] (+1 / -1) among [param allowed] (wraps); [param id] itself when it is
## the only one. [param allowed] defaults to every tier.
static func cycle(id: StringName, step: int, allowed: Array[StringName] = []) -> StringName:
	var list: Array[StringName] = allowed if not allowed.is_empty() else ids()
	if list.is_empty():
		return id
	var at := list.find(id)
	if at < 0:
		return list[0]
	return list[wrapi(at + step, 0, list.size())]


# --- Multipliers (1.0 on Normal) ----------------------------------------------------------------

static func enemy_hp_mult() -> float:
	return current().enemy_hp_mult * Pressure.enemy_hp_mult()


static func enemy_damage_mult() -> float:
	return current().enemy_damage_mult * Pressure.enemy_damage_mult()


## The WaveDirector's spawn budget on a normal wave (the tier's density times the wave's pressure; the adds of a boss
## wave keep their rate).
static func spawn_mult() -> float:
	return current().spawn_density_mult * Pressure.spawn_mult()


## The tier's share of EliteAffixes.rate_mult (the pressure's own part is applied per wave, Pressure.elite_mult()).
static func elite_mult() -> float:
	return current().elite_rate_mult


## A gold price [param base] as the run's tier charges it (unchanged on Normal; at least 1 gold otherwise).
static func price(base: int) -> int:
	var m := current().shop_price_mult
	if base <= 0 or is_equal_approx(m, 1.0):
		return base
	return maxi(1, roundi(base * m))


static func xp_mult_of(id: StringName) -> float:
	return data_of(id).xp_mult


static func seeds_mult_of(id: StringName) -> float:
	return data_of(id).seeds_mult


# --- Selection ----------------------------------------------------------------------------------

## The highest tier every class of [param class_ids] has open (the lobby's cap; the highest tier for an empty list).
static func party_cap(class_ids: Array[StringName]) -> StringName:
	return Meta.party_difficulty_cap(class_ids)


## The tiers a party of [param class_ids] may play, Normal first.
static func selectable(class_ids: Array[StringName]) -> Array[StringName]:
	var cap := tier_index(party_cap(class_ids))
	var out: Array[StringName] = []
	for i in ids().size():
		if i <= cap:
			out.append(ids()[i])
	return out


## Why [param tier] is closed to a party of [param class_ids] ("" = open): the first step that is missing, "Win a run on
## Normal with the Mage" – the tier below the lowest one a class has not opened yet, and that class.
static func lock_reason(tier: StringName, class_ids: Array[StringName]) -> String:
	var all := ids()
	for at in range(1, tier_index(tier) + 1):
		for id in class_ids:
			if not Meta.is_difficulty_unlocked(all[at], id):
				var data := Db.get_class_data(id)
				return "Win a run on %s with the %s" % [name_of(all[at - 1]), data.display_name if data != null else String(id).capitalize()]
	return ""


# --- Texts --------------------------------------------------------------------------------------

## The multipliers of [param id] as short lines for the lobby and the HUD tooltip ("Enemy HP +30%").
static func effect_lines(id: StringName) -> Array[String]:
	var d := data_of(id)
	var out: Array[String] = []
	_add_pct(out, "Enemy HP", d.enemy_hp_mult)
	_add_pct(out, "Enemy damage", d.enemy_damage_mult)
	_add_pct(out, "Enemy numbers", d.spawn_density_mult)
	_add_pct(out, "Elites", d.elite_rate_mult)
	_add_pct(out, "Shop prices", d.shop_price_mult)
	if d.pressure:
		out.append("A pressure on most waves")
	return out


static func _add_pct(out: Array[String], label: String, mult: float) -> void:
	if not is_equal_approx(mult, 1.0):
		out.append("%s %s%d%%" % [label, "+" if mult > 1.0 else "-", roundi(absf(mult - 1.0) * 100.0)])
