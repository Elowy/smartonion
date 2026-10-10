class_name PaladinAuraOfDevotion
extends MasteryEffect
## Aura of Devotion (GDD 3.3 Mastery): living heroes within [constant RADIUS] of a living
## Paladin – the Paladin included – gain Armor and HP regeneration (Spirit) per Mastery point.
##
## Implemented as a StatBlock source ([method source_key], e.g. &"aura:paladin0") on every
## hero inside, refreshed every [constant REFRESH_INTERVAL] seconds; heroes that leave the
## circle or go down lose it, and everybody loses it when the Paladin goes down or leaves.
## Several Paladins stack (one source each).

const RADIUS := 6.0
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


## Heroes currently inside the aura (tests, UI).
func affected() -> Array[Player]:
	var out: Array[Player] = []
	for id: int in _affected:
		var v: Variant = _affected[id]
		if is_instance_valid(v):
			out.append(v as Player)
	return out


## Re-evaluates who is inside and updates their stat sources.
func refresh() -> void:
	var key := source_key()
	var mods := aura_mods()
	var inside: Dictionary = {}
	if player != null and is_instance_valid(player) and player.is_alive() and player.is_inside_tree() \
			and not mods.is_empty():
		var here := player.global_position
		for node in player.get_tree().get_nodes_in_group(&"players"):
			var p := node as Player
			if p == null or not p.is_alive() or not p.is_inside_tree():
				continue
			var d := p.global_position - here
			if Vector2(d.x, d.z).length() > RADIUS:
				continue
			inside[p.get_instance_id()] = p
			if not _same_mods(p.stats.get_source(key), mods):
				p.stats.set_source(key, mods)
	for id: int in _affected:
		if inside.has(id):
			continue
		var v: Variant = _affected[id]
		if is_instance_valid(v):
			(v as Player).stats.remove_source(key)
	_affected = inside


## Removes the aura from everybody.
func clear() -> void:
	var key := source_key()
	for id: int in _affected:
		var v: Variant = _affected[id]
		if is_instance_valid(v):
			(v as Player).stats.remove_source(key)
	_affected.clear()


func tick(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_INTERVAL
		refresh()


func begin_wave() -> void:
	_timer = 0.0


func teardown() -> void:
	clear()


func describe() -> String:
	var mods := aura_mods()
	return "Aura of Devotion: allies within %d m (you included) gain +%s Armor and +%s HP per 5 sec." % [
		int(RADIUS), _fmt(float(mods.get(Stats.ARMOR, 0.0))),
		_fmt(float(mods.get(Stats.SPIRIT, 0.0)) / 15.0 * 5.0)]


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
