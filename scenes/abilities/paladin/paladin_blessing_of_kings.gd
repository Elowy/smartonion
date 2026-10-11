class_name PaladinBlessingOfKings
extends AbilityEffect
## Blessing of Kings (GDD 6.4, Paladin Auto): every living hero – the Paladin included – gains
## [code]stat_pct[/code] (5) % x power of their own stats for [code]duration[/code] (10) seconds.
##
## Implemented as a named StatBlock source on each hero ([method source_key], e.g.
## &"kings:paladin0") computed at the cast from that hero's current stats ([method blessing_mods]):
## the share of Max HP (as Stamina, the base 10 HP included), the primary stats, Armor, Spirit,
## the secondary ratings and Attack / Spell Power – positive values only, every Kings source
## left out (no compounding, several Paladins stack side by side). A living hero's HP rises with
## the Max HP gained (a full hero stays full).
##
## The blessing ends – the source is removed – after the duration, for a hero that goes down,
## for everybody when the Paladin goes down or leaves the tree, at wave start / end (the market
## shows everybody's own stats) and when the ability is forgotten. A recast refreshes it.
##
## Params also: might (spec "Blessing of Might": blessed heroes deal +% damage,
## Player.damage_mults) and sanctuary (spec "Blessing of Sanctuary": blessed heroes take
## -% damage, Player.damage_taken_mults), both x power, under the same key.

## Stats that grow by stat_pct (Stamina is handled through Max HP).
const STATS: Array[StringName] = [
	Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT, Stats.ARMOR, Stats.SPIRIT,
	Stats.CRIT, Stats.HASTE, Stats.MASTERY, Stats.VERSATILITY, Stats.ATTACK_POWER, Stats.SPELL_POWER,
]
const SOURCE_PREFIX := "kings"
## Paladin slots whose Kings sources are left out of the computation.
const MAX_PALADINS := 4
## Auto-cast: only in a fight (an enemy within this many metres of the Paladin).
const AUTO_ENEMY_RANGE := 14.0
## Auto-cast: recast only when the running blessing has less than this left.
const AUTO_REFRESH_LEFT := 1.0
## The Sanctuary reduction never goes beyond this (%).
const MAX_SANCTUARY := 60.0

var _player: Player
var _key: StringName = &""
var _left := 0.0
## Instance id -> blessed Player (values may be freed).
var _blessed: Dictionary = {}
## Instance id -> PaladinVfx mark under that hero.
var _marks: Dictionary = {}


## The stat source / buff key of [param paladin]'s blessing (unique per Paladin).
static func source_key(paladin: Player) -> StringName:
	return PaladinKit.buff_key(paladin, SOURCE_PREFIX)


## What [param who] gains at [param pct] %: stat -> value, from their stats without any Kings
## source ([param own_key] is left out as well).
static func blessing_mods(who: Player, pct: float, own_key: StringName = &"") -> Dictionary:
	var out := {}
	if who == null or pct <= 0.0:
		return out
	var kings := _kings_sources(who, own_key)
	var f := pct / 100.0
	for stat in STATS:
		var v := who.stats.get_raw(stat) - _sum(kings, stat)
		if v > 0.0:
			out[stat] = v * f
	var own_max_hp := Stats.BASE_MAX_HP + who.stats.get_raw(Stats.STAMINA) - _sum(kings, Stats.STAMINA)
	if own_max_hp > 0.0:
		out[Stats.STAMINA] = own_max_hp * f
	return out


static func _kings_sources(who: Player, own_key: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys: Array[StringName] = []
	for i in MAX_PALADINS:
		keys.append(StringName("%s:paladin%d" % [SOURCE_PREFIX, i]))
	if own_key != &"" and own_key not in keys:
		keys.append(own_key)
	for key in keys:
		if who.stats.has_source(key):
			out.append(who.stats.get_source(key))
	return out


static func _sum(sources: Array[Dictionary], stat: StringName) -> float:
	var total := 0.0
	for s in sources:
		total += float(s.get(stat, 0.0))
	return total


## Seconds the running blessing has left (0 = none).
func time_left() -> float:
	return _left


## Heroes holding this Paladin's blessing (tests, UI).
func blessed() -> Array[Player]:
	var out: Array[Player] = []
	for id: int in _blessed:
		var v: Variant = _blessed[id]
		if is_instance_valid(v):
			out.append(v as Player)
	return out


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.player != null and ctx.player.is_inside_tree()


## In a fight (an enemy near) and the blessing is not running (or about to end).
func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or _left > AUTO_REFRESH_LEFT:
		return false
	return EnemyGrid.nearest(p.get_tree(), p.global_position, AUTO_ENEMY_RANGE) != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	_bind(p)
	var power := ctx.num("power", 1.0)
	var pct := ctx.num("stat_pct", 5.0) * power
	var might := ctx.num("might") * power
	var sanctuary := minf(MAX_SANCTUARY, ctx.num("sanctuary") * power)
	var duration := ctx.num("duration", 10.0)
	var heroes := PaladinKit.living_heroes(p.get_tree())
	if heroes.is_empty():
		return false
	# A recast replaces each hero's blessing in place (no HP gain from re-adding Max HP).
	var keep := {}
	for hero in heroes:
		keep[hero.get_instance_id()] = true
	for id: int in _blessed.keys():
		if not keep.has(id):
			_unbless(id)
	_left = duration
	for hero in heroes:
		_bless(hero, pct, might, sanctuary, duration)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		clear()
		return
	# Heroes that went down (or left) lose it.
	for id: int in _blessed.keys():
		var v: Variant = _blessed[id]
		if not is_instance_valid(v) or not (v as Player).is_alive() or not (v as Player).is_inside_tree():
			_unbless(id)


## Removes the blessing from everybody.
func clear() -> void:
	for id: int in _blessed.keys():
		_unbless(id)
	_blessed.clear()
	_marks.clear()
	_left = 0.0


func begin_wave(_ctx: AbilityContext) -> void:
	clear()


func end_wave(_ctx: AbilityContext) -> void:
	clear()


func _bless(hero: Player, pct: float, might: float, sanctuary: float, duration: float) -> void:
	var mods := blessing_mods(hero, pct, _key)
	var old := hero.stats.get_source(_key)
	# Raise the HP first: set_source clamps HP to the new max and refreshes the HP bar.
	var gained := float(mods.get(Stats.STAMINA, 0.0)) - float(old.get(Stats.STAMINA, 0.0))
	if gained > 0.0 and hero.is_alive():
		hero.hp += gained
	hero.stats.set_source(_key, mods)
	if might > 0.0:
		hero.damage_mults[_key] = 1.0 + might / 100.0
	else:
		hero.damage_mults.erase(_key)
	if sanctuary > 0.0:
		hero.damage_taken_mults[_key] = 1.0 - sanctuary / 100.0
	else:
		hero.damage_taken_mults.erase(_key)
	var id := hero.get_instance_id()
	_blessed[id] = hero
	PaladinVfx.crown(hero)
	PaladinVfx.finish(_marks.get(id))
	_marks[id] = PaladinVfx.kings_mark(hero, duration)


func _unbless(id: int) -> void:
	var v: Variant = _blessed.get(id)
	_blessed.erase(id)
	if is_instance_valid(v):
		var hero := v as Player
		hero.stats.remove_source(_key)
		hero.damage_mults.erase(_key)
		hero.damage_taken_mults.erase(_key)
	PaladinVfx.finish(_marks.get(id))
	_marks.erase(id)


func _bind(p: Player) -> void:
	if _player == p:
		return
	_player = p
	_key = source_key(p)
	PaladinKit.connect_once(p.downed_changed, _on_downed_changed)
	PaladinKit.connect_once(p.tree_exiting, clear)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		clear()
