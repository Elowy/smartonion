class_name BlinkEffect
extends AbilityEffect
## Mage ability Blink (GDD 3.2): teleports the hero a few metres in the movement direction
## (facing when standing still), clamped to the arena and the shared screen, with a short
## invulnerability and arcane flashes at both ends. Params (data/abilities/mage_blink.tres):
## distance (m), invulnerable (s, x "power" from ranks II / IV), charges.
##
## Charges (Band of the Blinking Star: charges_add +1; Rank III: +1) are kept by the
## AbilityRunner. Rank V: "Frost Blink" (nova_freeze s: enemies within nova_radius m of the
## spot you left are frozen – [method MageSpell.freeze]) or "Arcane Burst" (burst_damage +
## burst_int_scaling x Intellect as an Arcane spell x power to enemies within burst_radius m
## of where you arrive).

const DEFAULT_DISTANCE := 6.0
const DEFAULT_INVULNERABLE := 0.4
## A blink that would move the hero less than this (m) is refused (against a wall).
const MIN_DISTANCE := 0.5
## Bots blink away from at least this many enemies (1 when badly hurt) within ESCAPE_RADIUS ...
const ESCAPE_COUNT := 2
const ESCAPE_RADIUS := 1.8
const ESCAPE_HP_RATIO := 0.5
## ... and only to a spot that is at least this far (m) away.
const ESCAPE_MIN_DISTANCE := 2.5

var _player: Player
var _ability: AbilityData


func wants_auto_cast(ctx: AbilityContext) -> bool:
	var player := ctx.player
	# A bot reviving a teammate stays put (the blink would break the revive).
	if player == null or not player.is_inside_tree() or player.is_reviving():
		return false
	var here := player.global_position
	var tree := player.get_tree()
	var near := _crowd(tree, here)
	var hurt := player.hp < player.max_hp() * ESCAPE_HP_RATIO
	if near < ESCAPE_COUNT and not (near >= 1 and hurt):
		return false
	var dest := destination(here, ctx.direction, ctx.num("distance", DEFAULT_DISTANCE), player)
	if here.distance_to(dest) < ESCAPE_MIN_DISTANCE:
		return false
	return _crowd(tree, dest) < near


func cast(ctx: AbilityContext) -> bool:
	_player = ctx.player
	_ability = ctx.ability
	var player := ctx.player
	if player == null:
		return false
	var dir := Vector3(ctx.direction.x, 0.0, ctx.direction.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3(player.facing.x, 0.0, player.facing.z)
	var from := player.global_position
	var dest := destination(from, dir, ctx.num("distance", DEFAULT_DISTANCE), player)
	if Vector2(dest.x - from.x, dest.z - from.z).length() < MIN_DISTANCE:
		return false
	if player.is_inside_tree():
		player.global_position = dest
	else:
		player.position = dest
	player.invulnerable_left = maxf(player.invulnerable_left,
			ctx.num("invulnerable", DEFAULT_INVULNERABLE) * ctx.num("power", 1.0))
	MageVfx.blink(from, dest)
	if player.is_inside_tree():
		_frost_blink(ctx, from)
		_arcane_burst(ctx, dest)
	return true


## Rank V "Frost Blink": freezes the enemies around the spot the hero left.
func _frost_blink(ctx: AbilityContext, at: Vector3) -> void:
	var freeze := ctx.num("nova_freeze", 0.0)
	if freeze <= 0.0:
		return
	var radius := ctx.num("nova_radius", 3.0) * MageSpell.area_mult(ctx.player)
	for e in MageSpell.enemies_in(ctx.player.get_tree(), at, radius):
		MageSpell.freeze(e, ctx.player, freeze)
	MageFx.frost_nova(WeaponRunner.flat(at), radius)


## Rank V "Arcane Burst": Arcane damage around the spot the hero arrives at.
func _arcane_burst(ctx: AbilityContext, at: Vector3) -> void:
	if ctx.num("burst_damage", 0.0) <= 0.0 or ctx.player.procs == null:
		return
	var damage := MageSpell.damage_from(ctx, MageSpell.ARCANE, "burst_")
	var radius := ctx.num("burst_radius", 3.0) * MageSpell.area_mult(ctx.player)
	for e in MageSpell.enemies_in(ctx.player.get_tree(), at, radius):
		ctx.player.procs.deal_raw(e, damage, MageSpell.ARCANE, true, &"ability")
	Vfx.explosion(at + Vector3.UP * 0.3, radius, MageSpell.ARCANE_COLOR)


func tick(ctx: AbilityContext, _delta: float) -> void:
	_player = ctx.player
	_ability = ctx.ability


## Blinks available right now (0 or 1 without the extra charge).
func charges_available() -> int:
	return _player.abilities.charges_available(_ability) if _runner_known() else 1


func charges_max() -> int:
	return _player.abilities.charges_max(_ability) if _runner_known() else 1


func _runner_known() -> bool:
	return _player != null and is_instance_valid(_player) and _player.abilities != null and _ability != null


## Where a blink from [param from] along [param dir] lands: [param distance] metres, clamped
## into the arena (and the shared screen's walk rectangle) and stopped by solid obstacles.
static func destination(from: Vector3, dir: Vector3, distance: float, player: Player = null) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001 or distance <= 0.0:
		return from
	flat = flat.normalized()
	var margin := Player.RADIUS + Player.WALL_GAP
	var to := from + flat * distance
	var arena := Arena.current
	if arena != null:
		to = arena.clamp_point(to, margin)
		if player != null and is_instance_valid(arena.camera) and arena.camera.is_inside_tree():
			var walk := arena.camera.get_walk_rect(player)
			if walk.size.x >= 0.0:
				to = Player.keep_inside_from(from, to, walk)
	if player != null and player.is_inside_tree() and to.distance_squared_to(from) > 0.01:
		var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, to + Vector3.UP * 0.5,
				Player.COLLISION_MASK_WORLD)
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var stop: Vector3 = hit["position"]
			var back := flat * margin
			to = Vector3(stop.x - back.x, from.y, stop.z - back.z)
			if (to - from).dot(flat) < 0.0:
				to = from
	to.y = from.y
	return to


## Living enemies within ESCAPE_RADIUS of [param center].
static func _crowd(tree: SceneTree, center: Vector3) -> int:
	var n := 0
	for node in EnemyGrid.gather_around(tree, center, ESCAPE_RADIUS):
		var e := node as Enemy
		if e != null and not e.is_dead() and e.global_position.distance_to(center) <= ESCAPE_RADIUS:
			n += 1
	return n
