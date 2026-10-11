class_name GeneralSprint
extends AbilityEffect
## Sprint (GDD 6.4, general Active): +speed % movement Speed for duration seconds – the named
## stat source [constant KEY] of a [GeneralBuff] (dust + wind ring look), removed on expiry,
## when the hero goes down and with the wave.
##
## Params (rank / spec / item mods change them):
##   speed, duration   +% Speed (x power) and seconds
##   dodge             +% Dodge while sprinting (x power; Rank III: +20)
##   allies, ally_range  Rallying Sprint (spec): living teammates within ally_range m sprint too
##   trail             Trailblazer (spec): the sprinter leaves a dust trail – small AbilityAreas
##   trail_slow, trail_radius, trail_duration   (slow % x power, m, s) every TRAIL_SPACING s
##   auto_hp           bots sprint away below this % of max HP with an enemy within
##                     AUTO_DANGER_RADIUS m, when crowded (BotInput.CROWD_COUNT enemies within
##                     BotInput.CROWD_RADIUS m – the bot kites then) and towards a downed
##                     teammate within rescue range

const KEY := &"general_sprint"
const TRAIL_SPACING := 0.25
const TRAIL_TICK := 0.25
const TRAIL_COLOR := Color(0.86, 0.74, 0.5, 0.4)
const TEXT_COLOR := Color(1.0, 0.92, 0.6)
const AUTO_DANGER_RADIUS := 3.0
## A downed teammate at least this far away (and within BotInput.RESCUE_RANGE) is worth a sprint.
const AUTO_RESCUE_MIN := 2.5

var _player: Player
var _trail_left := 0.0
var _trail_timer := 0.0
var _trail_slow := 0.0
var _trail_radius := 1.2
var _trail_duration := 2.0
## Trail areas still on the ground (tests).
var trail_areas: Array[AbilityArea] = []


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive() or not player.is_inside_tree():
		return false
	if GeneralBuff.find(player, KEY) != null:
		return false
	# Escape: hurt with an enemy at the throat, or crowded (bots kite away in both cases).
	if GeneralKit.hp_ratio(player) < ctx.num("auto_hp", 45.0) / 100.0 \
			and not GeneralKit.enemies_near(player, AUTO_DANGER_RADIUS).is_empty():
		return true
	if GeneralKit.enemies_near(player, BotInput.CROWD_RADIUS).size() >= BotInput.CROWD_COUNT:
		return true
	# Rescue: bots run to a downed teammate close by – get there faster.
	var ghost := GeneralKit.downed_ally_near(player, BotInput.RESCUE_RANGE)
	return ghost != null and GeneralKit.flat_distance(ghost.global_position, player.global_position) >= AUTO_RESCUE_MIN


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_alive():
		return false
	var duration := maxf(0.1, ctx.num("duration", 3.0))
	var mods := buff_stats(ctx)
	var heroes: Array[Player] = [player]
	if ctx.flag("allies"):
		heroes.append_array(GeneralKit.allies_near(player, ctx.num("ally_range", 8.0)))
	for p in heroes:
		GeneralBuff.apply(p, KEY, duration, mods, 1.0, GeneralAuraVfx.Style.SPRINT)
	if ctx.flag("trail"):
		_player = player
		_trail_left = duration
		_trail_timer = 0.0
		_trail_slow = clampf(ctx.num("trail_slow", 40.0) * ctx.num("power", 1.0), 0.0, 90.0)
		_trail_radius = maxf(0.3, ctx.num("trail_radius", 1.2))
		_trail_duration = maxf(0.2, ctx.num("trail_duration", 2.0))
		if not player.downed_changed.is_connected(_on_downed_changed):
			player.downed_changed.connect(_on_downed_changed)
	if player.is_inside_tree():
		Vfx.floating_text(player.self_text_position(1.0), "Sprint", TEXT_COLOR,
				Player.SELF_TEXT_SIZE, 1.0)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if _trail_left <= 0.0:
		return
	if _player == null or not is_instance_valid(_player) or not _player.is_alive():
		_trail_left = 0.0
		return
	_trail_timer -= delta
	if _trail_timer <= GeneralKit.TIME_EPSILON:
		_trail_timer += TRAIL_SPACING
		_drop_trail()
	_trail_left -= delta


func begin_wave(ctx: AbilityContext) -> void:
	_stop(ctx)


func end_wave(ctx: AbilityContext) -> void:
	_stop(ctx)


func is_trailing() -> bool:
	return _trail_left > 0.0


## The stat source a cast gives: Speed and Dodge, both x power.
static func buff_stats(ctx: AbilityContext) -> Dictionary:
	var power := ctx.num("power", 1.0)
	var mods := {Stats.SPEED: ctx.num("speed", 50.0) * power}
	var dodge := ctx.num("dodge") * power
	if dodge > 0.0:
		mods[Stats.DODGE] = dodge
	return mods


func _drop_trail() -> void:
	if not _player.is_inside_tree():
		return
	var area := AbilityArea.spawn(_player, _player.global_position, _trail_radius, _trail_duration, TRAIL_COLOR)
	if not area.is_inside_tree():
		area.free()
		return
	area.tick_interval = TRAIL_TICK
	area.slow_pct = _trail_slow
	_prune()
	trail_areas.append(area)


func _prune() -> void:
	for i in range(trail_areas.size() - 1, -1, -1):
		if not is_instance_valid(trail_areas[i]) or trail_areas[i].is_queued_for_deletion():
			trail_areas.remove_at(i)


func _stop(ctx: AbilityContext) -> void:
	_trail_left = 0.0
	for i in trail_areas.size():
		if is_instance_valid(trail_areas[i]) and not trail_areas[i].is_queued_for_deletion():
			trail_areas[i].queue_free()
	trail_areas.clear()
	var player := ctx.player
	if player != null and is_instance_valid(player):
		if player.is_inside_tree():
			GeneralBuff.clear(player.get_tree(), KEY)
		else:
			GeneralBuff.clear_on(player, KEY, false)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_trail_left = 0.0
