class_name WarriorBattleShout
extends AbilityEffect
## Battle Shout (GDD 6.4, Warrior Auto-cast): every living hero within [code]radius[/code] of
## the Warrior – the Warrior included – deals [code]bonus[/code] % more damage (times "power")
## for [code]duration[/code] seconds: a Player.damage_mults entry under [method buff_key]
## (one key per Warrior, so two Warriors' shouts stack; a recast refreshes it).
##
## Params (AbilityData.params; items and ranks change them):
##   bonus (% damage), duration (Rank III +3 s), radius (m)
##   guard          Rank V "Commanding Shout": the buffed heroes also take this % less damage
##                  (Player.damage_taken_mults, times "power", at most MAX_GUARD)
##   fear, fear_radius   Rank V "Intimidating Shout": enemies within fear_radius m flee for
##                  fear seconds (Enemy.apply_fear)
##
## The buff ends early – on everyone – when the Warrior goes down or leaves the tree, at wave
## end / start and when the ability is forgotten. Auto-cast: an enemy within AUTO_ENEMY_RANGE
## and the Warrior's own buff is not running.

const AUTO_ENEMY_RANGE := 7.0
const MAX_GUARD := 60.0
const TEXT_COLOR := Color(1.0, 0.5, 0.25)

var _player: Player
var _key: StringName = &""
var _left := 0.0
## Instance id -> buffed hero (values may be freed: untyped on purpose).
var _affected: Dictionary = {}
## Buff marks under the heroes (may be freed with their hero).
var _marks: Array = []


## Damage-buff key of [param player]'s shout ("battle_shout:<slot>").
static func buff_key(player: Player) -> StringName:
	if player != null and player.slot != null:
		return StringName("battle_shout:%d" % player.slot.index)
	return StringName("battle_shout:%d" % (player.get_instance_id() if player != null else 0))


func is_active() -> bool:
	return _left > 0.0


func time_left() -> float:
	return maxf(0.0, _left)


## Heroes holding the buff right now (tests, UI).
func affected() -> Array[Player]:
	var out: Array[Player] = []
	for id: int in _affected:
		var v: Variant = _affected[id]
		if is_instance_valid(v):
			out.append(v as Player)
	return out


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree() or is_active():
		return false
	return EnemyGrid.nearest(p.get_tree(), p.global_position, AUTO_ENEMY_RANGE) != null


func cast(ctx: AbilityContext) -> bool:
	var p := ctx.player
	if p == null or not p.is_inside_tree():
		return false
	clear()
	_player = p
	_key = buff_key(p)
	_connect(p)
	var power := ctx.num("power", 1.0)
	var mult := 1.0 + maxf(0.0, ctx.num("bonus", 10.0) * power) / 100.0
	var guard := clampf(ctx.num("guard") * power, 0.0, MAX_GUARD)
	var radius := ctx.num("radius", 10.0)
	var here := p.global_position
	var tint := WarriorShoutVfx.GUARD_COLOR if guard > 0.0 else WarriorShoutVfx.MARK_COLOR
	for node in p.get_tree().get_nodes_in_group(&"players"):
		var hero := node as Player
		if hero == null or not hero.is_alive() or not hero.is_inside_tree():
			continue
		if hero != p and WeaponRunner.flat(hero.global_position - here).length() > radius:
			continue
		hero.damage_mults[_key] = mult
		if guard > 0.0:
			hero.damage_taken_mults[_key] = 1.0 - guard / 100.0
		_affected[hero.get_instance_id()] = hero
		var mark := WarriorShoutVfx.spawn_mark(hero, tint)
		if mark != null:
			_marks.append(mark)
	_left = maxf(0.1, ctx.num("duration", 6.0))
	var fear := ctx.num("fear")
	if fear > 0.0:
		var fear_radius := ctx.num("fear_radius", 6.0) * CombatMath.area_mult(p.stats)
		for e in WarriorKit.enemies_within(p, fear_radius):
			e.apply_fear(fear, here)
	WarriorShoutVfx.spawn_wave(here, radius, tint)
	WarriorKit.shout_text(p, ctx.ability.display_name, TEXT_COLOR)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		clear()


func begin_wave(_ctx: AbilityContext) -> void:
	clear()


## The market shows everybody's own damage (also when the ability is forgotten).
func end_wave(_ctx: AbilityContext) -> void:
	clear()


## Removes the buff (and its marks) from everybody.
func clear() -> void:
	_left = 0.0
	if _key != &"":
		for id: int in _affected:
			var v: Variant = _affected[id]
			if is_instance_valid(v):
				(v as Player).damage_mults.erase(_key)
				(v as Player).damage_taken_mults.erase(_key)
	_affected.clear()
	for v: Variant in _marks:
		if is_instance_valid(v) and not (v as Node).is_queued_for_deletion():
			(v as WarriorShoutVfx).dismiss()
	_marks.clear()


func _connect(p: Player) -> void:
	if not p.downed_changed.is_connected(_on_downed_changed):
		p.downed_changed.connect(_on_downed_changed)
	if not p.tree_exiting.is_connected(clear):
		p.tree_exiting.connect(clear)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		clear()
