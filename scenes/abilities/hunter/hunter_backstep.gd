class_name HunterBackstep
extends AbilityEffect
## Backstep (GDD 3.7, Hunter LT, 8 s): a quick leap of [code]distance[/code] (5) m away from the
## nearest enemy within [constant AWAY_RANGE] m (opposite the facing when none is near), in
## [code]dash_time[/code] (0.18) s, with [code]invulnerable[/code] (0.2) s of invulnerability.
## The way is limited like a walk (arena, shared screen, walls); a leap of less than
## [constant MIN_DISTANCE] m is refused. At the moment of the leap the enemies within
## [code]slow_radius[/code] (3) m of where the Hunter stood are slowed by [code]slow[/code] (40) %
## x "power" (at most 90) for [code]slow_duration[/code] (2) s.
## Charges: [code]charges[/code] (Rank III +1; the runner keeps them).
## Ranks (M4): Rank V "Caltrop Trail" ([code]trail_duration[/code] 3: caltrops stay along the leap
## and slow enemies crossing them by [code]trail_slow[/code] %) or "Parting Volley"
## ([code]volley_arrows[/code] 3: as the Hunter lands it looses arrows at the nearest enemy, each
## [code]volley_pct[/code] % x "power" of the weapon hit "W").
## The leap ends (no volley) when the Hunter goes down; the wave hooks stop it too.
## Bots leap when two enemies are within 3 m, or one is within 2 m while below half health.

const AWAY_RANGE := 6.0
const MIN_DISTANCE := 0.5
const SLOW_CAP := 90.0
const AUTO_RADIUS := 3.0
const AUTO_ENEMIES := 2
const AUTO_CLOSE := 2.0
const AUTO_HP_RATIO := 0.5
const VOLLEY_RANGE := 11.0
const VOLLEY_SPEED := 24.0
const DUST := Color(0.8, 0.72, 0.55)
const TRAIL_COLOR := Color(0.62, 0.5, 0.34, 0.4)
## Distance between two caltrop patches as a share of their radius.
const TRAIL_STEP := 1.3

var _player: Player
var _dashing := false
var _from := Vector3.ZERO
var _dest := Vector3.ZERO
var _speed := 0.0
var _volley_arrows := 0
var _volley_pct := 0.0
var _volley_params: Dictionary = {}
## Leaps made this wave and the arrows the last Parting Volley loosed (tests).
var leaps := 0
var last_volley: Array[HunterArrow] = []
var last_trail: Array[AbilityArea] = []


func is_dashing() -> bool:
	return _dashing


func can_cast(_ctx: AbilityContext) -> bool:
	return not _dashing


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	# A bot reviving a teammate stays put (the leap would break the revive).
	if player == null or not player.is_inside_tree() or player.is_reviving() or _dashing:
		return false
	var tree := player.get_tree()
	var here := player.global_position
	if HunterKit.enemies_near_point(tree, here, AUTO_RADIUS).size() >= AUTO_ENEMIES:
		return true
	var hurt := player.max_hp() > 0.0 and player.hp < player.max_hp() * AUTO_HP_RATIO
	return hurt and not HunterKit.enemies_near_point(tree, here, AUTO_CLOSE).is_empty()


func cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	if player == null or not player.is_inside_tree() or _dashing:
		return false
	var here := player.global_position
	var dir := away_direction(player)
	var dest := HunterKit.landing(player, here, dir, ctx.num("distance", 5.0))
	if GeneralKit.flat_distance(dest, here) < MIN_DISTANCE:
		return false
	_player = player
	_from = here
	_dest = dest
	var power := ctx.num("power", 1.0)
	var dash_time := maxf(0.02, ctx.num("dash_time", 0.18))
	_speed = GeneralKit.flat_distance(dest, here) / dash_time
	_volley_arrows = maxi(0, roundi(ctx.num("volley_arrows", 0.0)))
	_volley_pct = ctx.num("volley_pct", 100.0) * power
	_volley_params = ctx.params
	player.velocity = Vector3.ZERO
	player.invulnerable_left = maxf(player.invulnerable_left, ctx.num("invulnerable", 0.2))
	_dashing = true
	leaps += 1
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)
	# The slow lands where the Hunter stood.
	var slow := minf(SLOW_CAP, ctx.num("slow", 0.0) * power)
	var radius := ctx.num("slow_radius", 3.0) * CombatMath.area_mult(player.stats)
	if slow > 0.0:
		for e in GeneralKit.enemies_around(player.get_tree(), here, radius):
			e.apply_slow(slow, ctx.num("slow_duration", 2.0))
	Vfx.death_puff(here + Vector3.UP * 0.2, DUST, 0.9)
	var trail := ctx.num("trail_duration", 0.0)
	last_trail = []
	if trail > 0.0:
		last_trail = _lay_trail(player, here, dest, trail, ctx.num("trail_radius", 1.8), ctx.num("trail_slow", 40.0) * power)
	return true


func tick(_ctx: AbilityContext, delta: float) -> void:
	if not _dashing:
		return
	var player := _player
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		_dashing = false
		return
	var here := player.global_position
	var to := _dest - here
	to.y = 0.0
	var dist := to.length()
	var step := minf(_speed * delta, dist)
	player.velocity = Vector3.ZERO
	if step > 0.0:
		player.global_position = here + to / dist * step
	if dist - step <= 0.01:
		_land(player)


## The leap ends: the Parting Volley, if the spec is chosen.
func _land(player: Player) -> void:
	_dashing = false
	player.velocity = Vector3.ZERO
	Vfx.death_puff(player.global_position + Vector3.UP * 0.2, DUST, 0.7)
	last_volley = []
	if _volley_arrows <= 0:
		return
	var target := EnemyGrid.nearest(player.get_tree(), player.global_position, VOLLEY_RANGE)
	if target == null:
		return
	var dir := HunterKit.dir_to(player.global_position, target.global_position, -player.facing)
	var damage := HunterKit.hit_damage(player, HunterKit.PHYSICAL) * _volley_pct / 100.0
	last_volley = HunterArrow.fan(player, dir, _volley_arrows, HunterArrow.VOLLEY_SPREAD, damage, VOLLEY_SPEED,
			VOLLEY_RANGE, 0, target)


func begin_wave(_ctx: AbilityContext) -> void:
	_stop()
	leaps = 0


func end_wave(_ctx: AbilityContext) -> void:
	_stop()


func _stop() -> void:
	_dashing = false


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		_dashing = false


## Away from the nearest enemy within AWAY_RANGE (unit, XZ); opposite the facing when none is near.
static func away_direction(player: Player) -> Vector3:
	var here := player.global_position
	var enemy := EnemyGrid.nearest(player.get_tree(), here, AWAY_RANGE) if player.is_inside_tree() else null
	if enemy != null:
		return -HunterKit.dir_to(here, enemy.global_position, player.facing)
	var back := -WeaponRunner.flat(player.facing)
	return back.normalized() if back.length_squared() > 0.0001 else Vector3.BACK


## Caltrop Trail: slowing patches along the leap from [param from] to [param to].
func _lay_trail(player: Player, from: Vector3, to: Vector3, duration: float, radius: float, slow: float) -> Array[AbilityArea]:
	var out: Array[AbilityArea] = []
	var span := GeneralKit.flat_distance(from, to)
	var patches := maxi(2, ceili(span / maxf(0.5, radius * TRAIL_STEP)) + 1)
	for i in patches:
		var t := float(i) / float(patches - 1)
		var area := AbilityArea.spawn(player, from.lerp(to, t), radius, duration, TRAIL_COLOR)
		if not area.is_inside_tree():
			area.free()
			continue
		area.tick_interval = 0.25
		area.slow_pct = clampf(slow, 0.0, SLOW_CAP)
		out.append(area)
	return out
