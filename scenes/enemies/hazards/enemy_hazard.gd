class_name EnemyHazard
extends Node3D
## Base of the ground attacks the bosses lay down (GDD 8 "Bossok", M6): a telegraph (a marker
## that fills up, [member telegraph_time] seconds), then a strike ([method _strike]) and / or a
## burning stage ([method _tick]). Group [constant GROUP] (&"enemy_hazards"): the bots read
## [method hazard_push] to step out of danger, and WaveDirector.stop() frees the whole group at
## the wave end (other enemy hazards, such as the Plague Ghoul's poison puddle, join it too –
## the group name is the contract, this base class is optional).
##
## Damage goes through [method Player.take_damage] with the damage kind AOE (Avoidance applies,
## Dodge / Block / absorb shields work like against any hit) and the boss as the source. The
## damage number is fixed when the hazard is laid down (the boss's contact damage x the
## ability's multiple x its enrage multiplier then).
## Visual only apart from that: a flat marker on the ground ([method _ring]) and a few shared
## meshes; no physics bodies (nothing here may switch Enemy's open-field fast path off).
## Subclasses: [FrostCircle], [FrostBreath], [FireField], [MeteorStrike].

const GROUP := &"enemy_hazards"
## Marker height above the ground (m); the ring shader draws without depth write.
const GROUND_Y := 0.05
## A hero counts as inside a circle when its centre is within radius + this share of its body.
const HERO_REACH := Player.RADIUS * 0.5
## Bots keep this far (m) outside a dangerous hazard.
const BOT_MARGIN := 0.9
## Final balance 2: one hit of a ground attack (a Fire Fields tick, a Meteor's share, a Frost Circle or Breath) takes
## at most this share of the hero's Max HP (after armour etc.), so a hero at full health always survives one: the
## hits were 70-140% of a Rogue's or Mage's HP (a lone Meteor 135%, Morvain's Frost Breath 70-85%) and every such
## hit was a death, not a lesson.
const MAX_HIT_SHARE := 0.4

enum Stage { TELEGRAPH, ACTIVE, DONE }

## Who deals the damage (the boss; may be null or freed by the time it strikes).
var source: Node3D
var radius := 2.0
## Seconds between the marker appearing and the strike.
var telegraph_time := 1.0
## Damage of one hit / tick (to one hero).
var damage := 0.0
var color := Color(1.0, 0.3, 0.2)
var stage := Stage.TELEGRAPH
## Seconds since it was laid down.
var age := 0.0

var _fade := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_build()
	_update_telegraph(0.0)


func _physics_process(delta: float) -> void:
	age += delta
	match stage:
		Stage.TELEGRAPH:
			if age >= telegraph_time - 0.0001:
				stage = Stage.ACTIVE
				_strike()
			else:
				_update_telegraph(age / maxf(0.001, telegraph_time))
		Stage.ACTIVE:
			_update_active(delta)
		Stage.DONE:
			_fade -= delta
			_update_fade(clampf(_fade / fade_time(), 0.0, 1.0))
			if _fade <= 0.0:
				queue_free()


# --- Queries (bots, tests) ---------------------------------------------------------------

func is_telegraphing() -> bool:
	return stage == Stage.TELEGRAPH


## Seconds of the telegraph left (0 once it struck).
func telegraph_left() -> float:
	return maxf(0.0, telegraph_time - age) if stage == Stage.TELEGRAPH else 0.0


## Whether standing here can hurt: the telegraph (the strike is coming) or the burning stage.
## A hazard that struck and only fades out is harmless.
func is_dangerous() -> bool:
	return stage != Stage.DONE


## Whether the ground point [param p] (a hero's centre) is hit by this hazard, with
## [param margin] m of slack around the shape.
func contains(p: Vector3, margin: float = 0.0) -> bool:
	var d := Vector2(p.x - global_position.x, p.z - global_position.z)
	var reach := radius + margin
	return d.length_squared() <= reach * reach


## The steering a bot should add when standing at [param from]: a vector (XZ, ground plane)
## pointing out of the hazard, 1..2 long inside the shape plus [param margin], zero outside or
## when the hazard is harmless. Circles push radially (from the middle: towards the arena's
## centre); [FrostBreath] sidesteps, [MeteorStrike] may pull instead.
func hazard_push(from: Vector3, margin: float = BOT_MARGIN) -> Vector2:
	if not is_dangerous():
		return Vector2.ZERO
	return circle_push(global_position, radius, from, margin)


## The bots' push out of a circle ([param center], [param radius]) for a hero at [param from]:
## 1..2 long inside radius + [param margin], radially away from the middle (towards the arena's
## centre when [param from] is the middle itself), zero outside. The one rule of [method
## hazard_push] for every circular hazard, also the poison puddle ([method
## PoisonPuddle.hazard_push]).
static func circle_push(center: Vector3, radius: float, from: Vector3, margin: float = BOT_MARGIN) -> Vector2:
	var d := Vector2(from.x - center.x, from.z - center.z)
	var reach := radius + margin
	var dist := d.length()
	if dist >= reach:
		return Vector2.ZERO
	var dir := d / dist if dist > 0.01 else escape_direction(from)
	return dir * (1.0 + (reach - dist) / reach)


# --- Hooks for the subclasses ------------------------------------------------------------

## The telegraph ended: do the hit (or start burning). Set [member stage] to DONE with
## [method finish] when nothing remains.
func _strike() -> void:
	finish()


## Every tick of the ACTIVE stage (persistent hazards).
func _update_active(_delta: float) -> void:
	finish()


## Marker animation while telegraphing; [param progress] runs 0..1.
func _update_telegraph(_progress: float) -> void:
	pass


## Builds the marker nodes.
func _build() -> void:
	pass


## Fade-out animation after the strike; [param amount] runs 1..0.
func _update_fade(_amount: float) -> void:
	pass


## Seconds the fade-out takes.
func fade_time() -> float:
	return 0.4


## Ends the hazard: it stays [method fade_time] seconds as an animation, harmless.
func finish() -> void:
	if stage == Stage.DONE:
		return
	stage = Stage.DONE
	_fade = fade_time()


# --- Helpers -------------------------------------------------------------------------------

## The living heroes (a snapshot list of the shared per-tick player cache).
func living_heroes() -> Array[Player]:
	var out: Array[Player] = []
	if not is_inside_tree():
		return out
	for p in Enemy.cached_players(get_tree()):
		if Enemy.is_living_player(p):
			out.append(p)
	return out


## The living heroes whose centre lies in the circle of [member radius] around this node.
func heroes_in_circle() -> Array[Player]:
	var out: Array[Player] = []
	for p in living_heroes():
		if contains(p.global_position, HERO_REACH):
			out.append(p)
	return out


## Hurts [param hero] for [param amount] (AOE kind, the boss as the source when it still
## exists), at most [constant MAX_HIT_SHARE] of its Max HP.
func hit_hero(hero: Player, amount: float) -> void:
	if hero == null or not is_instance_valid(hero) or amount <= 0.0:
		return
	var from: Node3D = source if source != null and is_instance_valid(source) else null
	hero.take_damage(amount, CombatMath.KIND_AOE, from, MAX_HIT_SHARE)
	LivingPlayers.mark_dirty()


## Where a bot standing in the dead centre of the hazard should run: towards the arena's middle
## (up the screen when it stands in the middle itself).
static func escape_direction(from: Vector3) -> Vector2:
	var away := Vector2(-from.x, -from.z)
	if away.length_squared() < 0.0001:
		return Vector2.UP
	return away.normalized()


## A flat ground ring / disc (quad on XZ, own ring material) of [param diameter] m, child of
## this node. Configure with Mats.set_ring.
func _ring(node_name: String, diameter: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.cached("hazard:quad", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1.0, 1.0)
		return q)
	mi.material_override = Mats.ring()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = GROUND_Y
	mi.scale = Vector3(diameter, 1.0, diameter)
	add_child(mi)
	return mi


## Lays a hazard node [param h] on the ground at [param pos] under [param parent].
static func place(parent: Node, h: EnemyHazard, pos: Vector3) -> void:
	if parent == null:
		h.free()
		return
	parent.add_child(h)
	h.global_position = Vector3(pos.x, 0.0, pos.z)
