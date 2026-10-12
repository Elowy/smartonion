class_name PaladinAuraOfDevotion
extends MasteryEffect
## Aura of Devotion (GDD 3.3 Mastery): living heroes within [constant RADIUS] of a living
## Paladin – the Paladin included – gain Armor and HP regeneration (Spirit) per Mastery point.
##
## Implemented as a StatBlock source ([method source_key], e.g. &"aura:paladin0") on every
## hero inside, refreshed every [constant REFRESH_INTERVAL] seconds; heroes that leave the
## circle or go down lose it, and everybody loses it when the Paladin goes down or leaves.
## Several Paladins stack (one source each).
##
## M5 talents – pseudo ability id [constant PSEUDO_ID] (&"paladin_aura", registered in
## BonusVocabulary.PSEUDO_IDS for the Paladin): its params are [constant BASE] with the
## Paladin's talent / item mods applied ([method aura_params]: AbilityRunner.apply_mods(BASE,
## player.ability_mods(&"paladin_aura")), read on every refresh – not cached):
##   radius (m; Holy Aura Mastery "radius_add"), guard (% less damage taken for every hero
##   inside; Holy Divine Guardian "guard_add": Player.damage_taken_mults[source_key()] =
##   1 - guard / 100), might (% more damage for every hero inside; Retribution Sanctified
##   Retribution "might_add": Player.damage_mults[source_key()] = 1 + might / 100).
## Guard and might also work at 0 Mastery (the stat source then stays off). Both keys are set
## again on every refresh (Player.begin_wave clears the dictionaries) and erased whenever the
## stat source goes (a hero leaves, the Paladin goes down, wave end, teardown). Two Paladins
## stack multiplicatively (one key each).

const RADIUS := 6.0
## The pseudo ability id talents change the aura through (BonusVocabulary.PSEUDO_IDS).
const PSEUDO_ID := &"paladin_aura"
## The aura's params before talent / item mods (the contract of the "paladin_aura" mods).
const BASE := {"radius": RADIUS, "guard": 0.0, "might": 0.0}
## Guard is capped so the aura never makes anybody (nearly) immune.
const MAX_GUARD := 75.0
const REFRESH_INTERVAL := 0.5
const ARMOR_PER_POINT := 0.5
## Spirit regenerates HP (StatBlock.hp_regen_per_second: 15 Spirit = 1 HP per second).
const SPIRIT_PER_POINT := 1.0

var _timer := 0.0
## Instance id -> Player currently holding this aura's source (values may be freed).
var _affected: Dictionary = {}


func setup(p_player: Player) -> void:
	super.setup(p_player)
	if player != null and not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)


## Stat source name on the heroes inside the aura (unique per Paladin).
func source_key() -> StringName:
	if player != null and player.slot != null:
		return StringName("aura:paladin%d" % player.slot.index)
	return StringName("aura:paladin_%d" % (player.get_instance_id() if player != null else 0))


## Stats the aura grants at the current Mastery (empty at 0 Mastery).
func aura_mods() -> Dictionary:
	var m := mastery()
	if m <= 0.0:
		return {}
	return {Stats.ARMOR: m * ARMOR_PER_POINT, Stats.SPIRIT: m * SPIRIT_PER_POINT}


## The aura's params with the Paladin's talent / item mods ([constant BASE] keys: radius,
## guard, might).
func aura_params() -> Dictionary:
	if player == null:
		return BASE.duplicate()
	return AbilityRunner.apply_mods(BASE, player.ability_mods(PSEUDO_ID))


## Reach of the aura in metres (BASE radius + talents such as Aura Mastery).
func radius() -> float:
	return maxf(0.0, float(aura_params().get("radius", RADIUS)))


## Heroes currently inside the aura (tests, UI).
func affected() -> Array[Player]:
	var out: Array[Player] = []
	for id: int in _affected:
		var v: Variant = _affected[id]
		if is_instance_valid(v):
			out.append(v as Player)
	return out


## Re-evaluates who is inside and updates their stat sources (and the talents' guard / might
## multipliers).
func refresh() -> void:
	var key := source_key()
	var mods := aura_mods()
	var params := aura_params()
	var reach := maxf(0.0, float(params.get("radius", RADIUS)))
	var guard := clampf(float(params.get("guard", 0.0)), 0.0, MAX_GUARD)
	var might := maxf(0.0, float(params.get("might", 0.0)))
	var inside: Dictionary = {}
	if player != null and is_instance_valid(player) and player.is_alive() and player.is_inside_tree() \
			and (not mods.is_empty() or guard > 0.0 or might > 0.0):
		var here := player.global_position
		for node in player.get_tree().get_nodes_in_group(&"players"):
			var p := node as Player
			if p == null or not p.is_alive() or not p.is_inside_tree():
				continue
			var d := p.global_position - here
			if Vector2(d.x, d.z).length() > reach:
				continue
			inside[p.get_instance_id()] = p
			if mods.is_empty():
				if p.stats.has_source(key):
					p.stats.remove_source(key)
			elif not _same_mods(p.stats.get_source(key), mods):
				p.stats.set_source(key, mods)
			if guard > 0.0:
				p.damage_taken_mults[key] = 1.0 - guard / 100.0
			else:
				p.damage_taken_mults.erase(key)
			if might > 0.0:
				p.damage_mults[key] = 1.0 + might / 100.0
			else:
				p.damage_mults.erase(key)
	for id: int in _affected:
		if inside.has(id):
			continue
		var v: Variant = _affected[id]
		if is_instance_valid(v):
			_strip(v as Player, key)
	_affected = inside


## Removes the aura from everybody.
func clear() -> void:
	var key := source_key()
	for id: int in _affected:
		var v: Variant = _affected[id]
		if is_instance_valid(v):
			_strip(v as Player, key)
	_affected.clear()


## Takes this aura's stat source and talent multipliers off [param p].
static func _strip(p: Player, key: StringName) -> void:
	p.stats.remove_source(key)
	p.damage_taken_mults.erase(key)
	p.damage_mults.erase(key)


## Also runs while the Paladin is downed (MasteryEffect.tick): a downed Paladin grants
## nothing (_on_downed_changed already cleared the aura; this keeps it cleared).
func tick(delta: float) -> void:
	if player == null or not player.is_alive():
		if not _affected.is_empty():
			clear()
		_timer = 0.0  # (refresh at once after the revive)
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_INTERVAL
		refresh()


func begin_wave() -> void:
	_timer = 0.0


## The market shows everybody's own stats: the aura comes back with the next wave's first
## tick.
func end_wave() -> void:
	clear()
	_timer = 0.0


func teardown() -> void:
	clear()


func describe() -> String:
	var mods := aura_mods()
	var params := aura_params()
	var text := "Aura of Devotion: allies within %s m (you included) gain +%s Armor and +%s HP per 5 sec" % [
		_fmt(maxf(0.0, float(params.get("radius", RADIUS)))), _fmt(float(mods.get(Stats.ARMOR, 0.0))),
		_fmt(float(mods.get(Stats.SPIRIT, 0.0)) / 15.0 * 5.0)]
	var guard := clampf(float(params.get("guard", 0.0)), 0.0, MAX_GUARD)
	if guard > 0.0:
		text += "; -%s%% damage taken" % _fmt(guard)
	var might := maxf(0.0, float(params.get("might", 0.0)))
	if might > 0.0:
		text += "; +%s%% damage" % _fmt(might)
	return text + "."


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		clear()
	else:
		_timer = 0.0
		refresh()


static func _same_mods(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in b:
		if not a.has(key) or not is_equal_approx(float(a[key]), float(b[key])):
			return false
	return true


static func _fmt(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")
