class_name BlizzardEffect
extends AbilityEffect
## Mage ability Blizzard (GDD 3.2): hail on the densest group of enemies within reach – an
## [AbilityArea] of frost that ticks spell damage and slows everything inside for a few
## seconds. The numbers are params of data/abilities/mage_blizzard.tres:
##   radius (m), duration (s), tick (s), damage + int_scaling x Intellect (per tick, base;
##   x "power" from ranks II / IV), slow (%). Items change them through ability_mod (e.g.
##   Frostweave Cowl: radius_pct +30).
## Ranks (GDD 6.3): Rank III duration_add +1 s; Rank V "Wandering Storm" (follow: the storm
## follows the enemy it was cast on) or "Permafrost" (freeze: the hail freezes each enemy
## once – AbilityArea.stun).
##
## Talent hooks (M5, Frost tree, talents_mage.md 4.2), neutral by default:
##   end_freeze (s, 0 = off – the "Deep Freeze" modifier): when a storm ends, every living enemy
##     within its radius of its last centre is frozen ([method MageSpell.freeze]) – once per
##     storm.
##   tick_freeze_chance (%, 0 = off – "Flash Freeze") / tick_freeze (s): on every tick of a storm
##     (its "tick" interval, the first right after the cast) each living enemy inside that is
##     not frozen yet ([method MageFrozen.is_frozen], group order) rolls
##     RunState.rng.randf() * 100 < tick_freeze_chance and is frozen for tick_freeze s. These
##     are the effect's only RNG draws, made only while the chance is above 0.
## Artifact hook (Staff of the Frostwyrm, "Frostwyrm's Breath"): nth_cast (0 = off) /
## nth_radius_bonus (1.0 = +100%): every nth Blizzard of this Mage (a cast that landed; the
## count is the effect's, it runs through waves) has its radius multiplied by 1 + nth_radius_bonus.
## Only casts with one of them get a [Storm] record (numbers copied from the cast's context,
## never the context itself), counted down in [method tick]; the centre / radius follow the
## area while it exists (Wandering Storm moves it). Kit effects do not tick while the Mage is
## down, so going down drops the pending storms (Player.downed_changed); wave start / end clear
## them too (no finale on an empty arena).

const FROST := &"frost"
const AREA_COLOR := Color(0.55, 0.85, 1.0, 0.35)
const DEFAULT_RADIUS := 3.5
const DEFAULT_DURATION := 3.0
const DEFAULT_TICK := 0.5
## Bots only cast on a group this big.
const BOT_MIN_CLUSTER := 4
## Bots do not stack a new Blizzard on one that still covers this share of the new radius.
const OVERLAP_SHARE := 0.6
const EPSILON := 0.0001


## One storm of this Mage tracked for the talent hooks (Deep Freeze, Flash Freeze).
class Storm extends RefCounted:
	## The storm's area (may be freed – check is_instance_valid before use).
	var area: Object
	## Seconds of hail left / until the next Flash Freeze roll; the tick interval.
	var left := 0.0
	var tick_left := 0.0
	var tick := 0.5
	## Last known centre and radius (Area Size applied).
	var centre := Vector3.ZERO
	var radius := 0.0
	var end_freeze := 0.0
	var chance := 0.0
	var tick_freeze := 1.0


## My running areas (bots check them so they do not stack Blizzards on one spot).
var _areas: Array[AbilityArea] = []
## Storms waiting for their Deep Freeze finale / Flash Freeze ticks (talent hooks).
var storms: Array[Storm] = []
## Enemies frozen by the finales / the tick rolls (tests).
var finale_freezes := 0
var tick_freezes := 0

## Instance id of the Mage whose downed_changed is connected (0 = none yet).
var _downed_hooked_id := 0
## Blizzards cast while the nth_cast hook was on (Frostwyrm's Breath).
var _nth_casts := 0


func can_cast(ctx: AbilityContext) -> bool:
	return ctx.target != null


func cast(ctx: AbilityContext) -> bool:
	if ctx.target == null or ctx.player == null:
		return false
	var follow := ctx.flag("follow")
	var center := ctx.target.global_position if follow else cluster_center(ctx)
	var radius := ctx.num("radius", DEFAULT_RADIUS)
	var nth := roundi(ctx.num("nth_cast"))
	var big := nth > 0 and (_nth_casts + 1) % nth == 0
	if big:
		radius *= 1.0 + maxf(0.0, ctx.num("nth_radius_bonus"))
	var area := AbilityArea.spawn(ctx.player, center, radius, ctx.num("duration", DEFAULT_DURATION), AREA_COLOR)
	if not area.is_inside_tree():
		area.free()
		return false
	if nth > 0:
		_nth_casts += 1
	area.school = FROST
	area.tick_interval = maxf(0.05, ctx.num("tick", DEFAULT_TICK))
	area.damage_per_tick = tick_damage(ctx)
	area.slow_pct = ctx.num("slow", 0.0)
	area.stun = maxf(0.0, ctx.num("freeze", 0.0))
	if follow:
		area.follow = ctx.target
	BlizzardShards.attach(area)
	_areas.append(area)
	_track(ctx, area)
	return true


## Records [param area] for the talent hooks when the cast has one (zero cost otherwise).
func _track(ctx: AbilityContext, area: AbilityArea) -> void:
	var end_freeze := maxf(0.0, ctx.num("end_freeze", 0.0))
	var chance := maxf(0.0, ctx.num("tick_freeze_chance", 0.0))
	if end_freeze <= 0.0 and chance <= 0.0:
		return
	_hook_downed(ctx.player)
	var s := Storm.new()
	s.area = area
	s.left = area.duration
	s.tick = area.tick_interval
	s.tick_left = 0.0
	s.centre = area.global_position
	s.radius = area.radius
	s.end_freeze = end_freeze
	s.chance = chance
	s.tick_freeze = maxf(0.0, ctx.num("tick_freeze", 1.0))
	storms.append(s)


func tick(ctx: AbilityContext, delta: float) -> void:
	if storms.is_empty():
		return
	var player := ctx.player
	var i := 0
	while i < storms.size():
		var s := storms[i]
		if is_instance_valid(s.area) and (s.area as Node3D).is_inside_tree():
			var area := s.area as AbilityArea
			s.centre = area.global_position
			s.radius = area.radius
		if s.chance > 0.0:
			s.tick_left -= delta
			if s.tick_left <= EPSILON and s.left > EPSILON:
				s.tick_left = maxf(s.tick_left + s.tick, EPSILON)
				_flash_freeze(player, s)
		s.left -= delta
		if s.left <= EPSILON:
			storms.remove_at(i)
			_deep_freeze(player, s)
			continue
		i += 1


## "Flash Freeze": each enemy inside that is not frozen yet rolls the chance once per tick.
func _flash_freeze(player: Player, s: Storm) -> void:
	if player == null or not player.is_inside_tree() or s.tick_freeze <= 0.0:
		return
	for e in MageSpell.enemies_in(player.get_tree(), s.centre, s.radius):
		if MageFrozen.is_frozen(e):
			continue
		if RunState.rng.randf() * 100.0 < s.chance:
			if MageSpell.freeze(e, player, s.tick_freeze) != null:
				tick_freezes += 1


## "Deep Freeze": the storm's finale freezes everything still inside.
func _deep_freeze(player: Player, s: Storm) -> void:
	if s.end_freeze <= 0.0 or player == null or not player.is_inside_tree():
		return
	for e in MageSpell.enemies_in(player.get_tree(), s.centre, s.radius):
		if MageSpell.freeze(e, player, s.end_freeze) != null:
			finale_freezes += 1
	MageFx.frost_nova(WeaponRunner.flat(s.centre), s.radius)


func begin_wave(_ctx: AbilityContext) -> void:
	storms.clear()


func end_wave(_ctx: AbilityContext) -> void:
	storms.clear()


## Going down drops the pending storms (kit effects do not tick while downed: no late finale).
func _hook_downed(player: Player) -> void:
	if player == null or _downed_hooked_id == player.get_instance_id():
		return
	_downed_hooked_id = player.get_instance_id()
	if not player.downed_changed.is_connected(_on_downed_changed):
		player.downed_changed.connect(_on_downed_changed)


func _on_downed_changed(is_downed: bool) -> void:
	if is_downed:
		storms.clear()


func wants_auto_cast(ctx: AbilityContext) -> bool:
	if ctx.target == null or not ctx.target.is_inside_tree():
		return false
	var radius := ctx.num("radius", DEFAULT_RADIUS)
	var center := ctx.target.global_position if ctx.flag("follow") else cluster_center(ctx)
	if cluster_size(ctx.target.get_tree(), center, radius) < BOT_MIN_CLUSTER:
		return false
	_prune()
	for a in _areas:
		if a.global_position.distance_to(center) < a.radius * OVERLAP_SHARE:
			return false
	return true


## Damage of one tick (Frost spell: base + Intellect scaling, Spell Power, Versatility,
## school %; x the rank's power).
static func tick_damage(ctx: AbilityContext) -> float:
	var base := ctx.num("damage") + ctx.num("int_scaling") * ctx.player.stats.get_raw(Stats.INTELLECT)
	return CombatMath.proc_damage(base, FROST, ctx.player.stats) * ctx.num("power", 1.0)


## Where the hail falls: the centroid of the enemies around the targeted one – or that
## enemy's own position when it covers more of them.
static func cluster_center(ctx: AbilityContext) -> Vector3:
	var target := ctx.target
	if target == null or not target.is_inside_tree():
		return ctx.point
	var tree := target.get_tree()
	var radius := ctx.num("radius", DEFAULT_RADIUS)
	var sum := Vector3.ZERO
	var count := 0
	for node in EnemyGrid.gather_around(tree, target.global_position, radius):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		sum += e.global_position
		count += 1
	if count == 0:
		return target.global_position
	var centroid := Vector3(sum.x / count, 0.0, sum.z / count)
	var on_target := Vector3(target.global_position.x, 0.0, target.global_position.z)
	if cluster_size(tree, on_target, radius) > cluster_size(tree, centroid, radius):
		return on_target
	return centroid


## Living enemies within [param radius] of [param center].
static func cluster_size(tree: SceneTree, center: Vector3, radius: float) -> int:
	var n := 0
	for node in EnemyGrid.gather_around(tree, center, radius):
		var e := node as Enemy
		if e != null and not e.is_dead() and e.global_position.distance_to(center) <= radius:
			n += 1
	return n


func _prune() -> void:
	for i in range(_areas.size() - 1, -1, -1):
		# Check validity on the element itself: a freed area must not be copied to a typed var.
		if not is_instance_valid(_areas[i]) or not _areas[i].is_inside_tree():
			_areas.remove_at(i)
