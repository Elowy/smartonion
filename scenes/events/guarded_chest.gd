class_name GuardedChest
extends Node3D
## The Guarded Chest (GDD 16.1, M6b mid-wave event): a locked chest with [constant GUARD_COUNT] guards
## around it (the [EventGuards] child; the [EventSpawner] builds them: eligible enemy types, x2 HP, no
## affix). While one of them lives the chest is LOCKED. Once they are all dead it is READY: a living hero
## who stands within [constant OPEN_RADIUS] of it for [constant OPEN_TIME] s opens it (the progress
## drains at the same speed while nobody is there, so a step aside does not start over) and it pays out
## once: one Rare+ item ([method LootDrops.drop_event_item]: a loot bag that goes through the Need /
## Greed / Pass roll like any drop – outside the wave's drop limit) and [constant GOLD_MULT] x the wave's
## average enemy gold as coins ([method reward_gold]). An unopened chest is freed with the wave
## (WaveDirector.stop(), group [constant EventSpawner.GROUP]).
##
## The look is a procedural wooden chest with a hinged lid; a red ground ring says "locked", a gold one
## "open me" and its arc fills with the progress. The camera frames it ([method event_frame_points]) and
## bots read [method is_ready] / [method is_locked] (BotInput). Deterministic: nothing here draws from an
## rng except the item (RunState.rng, inside the generator).

## The hero opened it (or [method open] was called). [param opener] may be null.
signal opened(chest: GuardedChest, opener: Player)

enum State { LOCKED, READY, OPEN }

const GUARD_COUNT := 4
const GUARD_HP_MULT := 2.0
## Seconds a hero has to stand at a READY chest.
const OPEN_TIME := 1.5
## Distance (m, centre to centre) within which a hero counts as standing at the chest.
const OPEN_RADIUS := 2.0
## Gold paid out: this many times the wave's average enemy gold, in GOLD_PILES coins on a ring.
const GOLD_MULT := 10.0
const GOLD_PILES := 8
const GOLD_RING := 1.4
## Where the guards stand (m from the chest) and where the item bag drops (in front, towards the camera).
const POST_RADIUS := 2.8
const BAG_OFFSET := Vector3(0.0, 0.0, 1.5)
const NAME_TEXT := "Guarded Chest"
## How much larger than the modelled 1.5 m the chest is drawn.
const VISUAL_SCALE := 1.3

const WOOD := Color(0.5, 0.31, 0.16)
const WOOD_DARK := Color(0.34, 0.2, 0.1)
const IRON := Color(0.34, 0.34, 0.4)
const GOLD := Color(1.0, 0.8, 0.22)
const LOCKED_COLOR := Color(0.95, 0.25, 0.2, 0.55)
const READY_COLOR := Color(1.0, 0.84, 0.3, 0.95)
## The lid's angle (degrees, about X) once open.
const LID_OPEN_DEG := -112.0
const LID_SPEED := 7.0

var wave := 1
var state := State.LOCKED
## Seconds a hero has stood at the chest (0..OPEN_TIME).
var progress := 0.0
## Who opened it (null until then, or when opened by code).
var opener: Player
## The guards' node (a child; its guards are built by the spawner).
var guards: EventGuards

var _lid: Node3D
var _treasure: Node3D
var _lock_ring: MeshInstance3D
var _progress_ring: MeshInstance3D
var _bar: MeshInstance3D
var _label: Label3D
var _lid_angle := 0.0
var _time := 0.0
var _shown_text := ""


## A chest for wave [param p_wave], not in the tree yet.
static func create(p_wave: int) -> GuardedChest:
	var c := GuardedChest.new()
	c.name = "GuardedChest"
	c.wave = maxi(1, p_wave)
	c.guards = EventGuards.new()
	c.guards.name = "Guards"
	c.add_child(c.guards)
	c.add_to_group(EventSpawner.GROUP)
	c._build_visual()
	return c


## Gold the chest pays: [constant GOLD_MULT] x the average enemy gold of [param p_wave] (rounded).
static func reward_gold(p_wave: int) -> int:
	return roundi(GOLD_MULT * LootGoblin.average_gold(p_wave))


## The guards' post offsets: [param count] points on a ring of POST_RADIUS m, evenly spread.
static func post_offsets(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in count:
		var a := TAU * (float(i) + 0.5) / float(maxi(1, count))
		out.append(Vector3(cos(a), 0.0, sin(a)) * POST_RADIUS)
	return out


# --- Queries ---------------------------------------------------------------------------

func is_locked() -> bool:
	return state == State.LOCKED


func is_ready() -> bool:
	return state == State.READY


func is_open() -> bool:
	return state == State.OPEN


## Ground points the camera frames while the chest still matters (CameraRig.event_points).
func event_frame_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if state != State.OPEN and is_inside_tree() and not is_queued_for_deletion():
		out.append(global_position)
	return out


## The nearest living hero standing within OPEN_RADIUS (null when nobody does).
func hero_at_chest() -> Player:
	if not is_inside_tree():
		return null
	var best: Player = null
	var best_sq := OPEN_RADIUS * OPEN_RADIUS
	var here := global_position
	for p in Enemy.cached_players(get_tree()):
		if not Enemy.is_living_player(p):
			continue
		var dx := p.global_position.x - here.x
		var dz := p.global_position.z - here.z
		var d_sq := dx * dx + dz * dz
		if d_sq <= best_sq:
			best_sq = d_sq
			best = p
	return best


# --- Frame update ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	if state != State.OPEN:
		_update_state(delta)
	_update_visual(delta)


func _update_state(delta: float) -> void:
	var locked := guards != null and not guards.all_dead()
	if locked:
		state = State.LOCKED
		progress = 0.0
		return
	state = State.READY
	var hero := hero_at_chest()
	if hero != null:
		progress = minf(OPEN_TIME, progress + delta)
		opener = hero
	else:
		progress = maxf(0.0, progress - delta)
	if progress >= OPEN_TIME - 0.0001:
		open(opener)


## Opens the chest now (normally from the physics tick): the pay-out, the lid, [signal opened].
## Only once.
func open(by: Player = null) -> void:
	if state == State.OPEN:
		return
	state = State.OPEN
	progress = OPEN_TIME
	opener = by
	var here := global_position if is_inside_tree() else position
	LootDrops.drop_event_item(ItemGenerator.Source.ELITE, here + BAG_OFFSET, by)
	var parent: Node = Arena.current.entities if Arena.current != null and is_instance_valid(Arena.current) \
			and is_instance_valid(Arena.current.entities) else get_parent()
	EventFx.burst(parent, here, reward_gold(wave), 0, GOLD_PILES, GOLD_RING)
	Vfx.explosion(here + Vector3.UP * 0.6, 1.8, GOLD)
	Vfx.pickup_sparkle(here + Vector3.UP * 0.9)
	Vfx.floating_text(here + Vector3.UP * 2.2, "Chest opened!", UiTheme.GOLD, 1.3)
	Audio.play(&"chest_open")
	opened.emit(self, by)


# --- Look ------------------------------------------------------------------------------

func _update_visual(delta: float) -> void:
	if _lid == null:
		return
	var want_deg := LID_OPEN_DEG if state == State.OPEN else 0.0
	_lid_angle = lerpf(_lid_angle, want_deg, 1.0 - exp(-LID_SPEED * delta))
	_lid.rotation_degrees.x = _lid_angle
	_treasure.visible = state == State.OPEN
	_lock_ring.visible = state == State.LOCKED
	_progress_ring.visible = state == State.READY
	if state == State.READY:
		var pulse := 0.65 + 0.3 * sin(_time * 4.0)
		Mats.set_ring(_progress_ring, Color(READY_COLOR.r, READY_COLOR.g, READY_COLOR.b, pulse),
				0.86, 0.98, 0.1, maxf(0.04, progress / OPEN_TIME))
	_bar.visible = state == State.READY and progress > 0.0
	if _bar.visible:
		Mats.set_cast_bar(_bar, GOLD, progress / OPEN_TIME)
	var text := _label_text()
	if text != _shown_text:
		_shown_text = text
		_label.text = text
	_label.visible = state != State.OPEN


func _label_text() -> String:
	match state:
		State.LOCKED:
			var n := guards.alive_count() if guards != null else 0
			return "%s\n%d %s left" % [NAME_TEXT, n, "guard" if n == 1 else "guards"]
		State.READY:
			return "%s\nStand here to open" % NAME_TEXT
	return ""


func _build_visual() -> void:
	# The chest is drawn VISUAL_SCALE times life size so it reads from the camera's distance.
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.scale = Vector3.ONE * VISUAL_SCALE
	add_child(visual)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = MeshKit.cached("event:chest_body", func() -> Mesh: return _body_mesh())
	body.material_override = Mats.toon_vc()
	visual.add_child(body)
	_lid = Node3D.new()
	_lid.name = "LidPivot"
	_lid.position = Vector3(0.0, 0.62, -0.475)
	visual.add_child(_lid)
	var lid := MeshInstance3D.new()
	lid.name = "Lid"
	lid.mesh = MeshKit.cached("event:chest_lid", func() -> Mesh: return _lid_mesh())
	lid.material_override = Mats.toon_vc()
	_lid.add_child(lid)
	_treasure = Node3D.new()
	_treasure.name = "Treasure"
	_treasure.position = Vector3(0.0, 0.6, 0.0)
	_treasure.visible = false
	visual.add_child(_treasure)
	var gold := MeshInstance3D.new()
	gold.name = "Gold"
	gold.mesh = MeshKit.cached("event:chest_gold", func() -> Mesh: return _gold_mesh())
	gold.material_override = Mats.toon_vc_glow(GOLD, 1.2)
	gold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_treasure.add_child(gold)
	_lock_ring = EventFx.ring(self, "LockRing", OPEN_RADIUS, LOCKED_COLOR, 0.9, 0.99, 0.05)
	_progress_ring = EventFx.ring(self, "ProgressRing", OPEN_RADIUS, READY_COLOR, 0.86, 0.98, 0.1, 0.05)
	_progress_ring.visible = false
	_bar = EventFx.bar(self, "OpenBar", 2.1, GOLD, 0.0)
	_bar.visible = false
	_label = EventFx.label(self, "NameTag", _label_text(), 2.35, UiTheme.GOLD)
	_label.visible = true


static func _body_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_box(Vector3(1.5, 0.62, 0.95), MeshKit.xf(Vector3(0.0, 0.31, 0.0)), WOOD)
	# Plank seams and a darker foot.
	k.add_box(Vector3(1.56, 0.1, 1.01), MeshKit.xf(Vector3(0.0, 0.05, 0.0)), WOOD_DARK)
	for y: float in [0.22, 0.42]:
		k.add_box(Vector3(1.52, 0.015, 0.97), MeshKit.xf(Vector3(0.0, y, 0.0)), WOOD_DARK)
	# Iron straps and gold corner studs.
	for sx: float in [-0.5, 0.5]:
		k.add_box(Vector3(0.12, 0.66, 1.0), MeshKit.xf(Vector3(sx, 0.31, 0.0)), IRON)
		for sz: float in [-0.5, 0.5]:
			k.add_sphere(0.05, MeshKit.xf(Vector3(sx, 0.6, sz)), GOLD, 8, 4)
			k.add_sphere(0.05, MeshKit.xf(Vector3(sx, 0.06, sz)), GOLD, 8, 4)
	# The lock plate on the front (+Z, towards the camera).
	k.add_box(Vector3(0.2, 0.26, 0.04), MeshKit.xf(Vector3(0.0, 0.5, 0.49)), GOLD.darkened(0.15))
	k.add_cylinder(0.04, 0.04, 0.05, MeshKit.xf(Vector3(0.0, 0.48, 0.51), Vector3(90.0, 0.0, 0.0)), Color(0.15, 0.1, 0.05), 8)
	return k.build()


## The arched lid in the hinge's local space (the hinge at the back edge; the lid reaches +Z).
static func _lid_mesh() -> Mesh:
	var k := MeshKit.new()
	var arch := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		var t := PI * float(i) / float(steps)
		arch.append(Vector2(cos(t) * 0.475, sin(t) * 0.3))
	# Extruded along local Z, turned so the depth runs along X.
	k.add_extrusion(arch, 1.5, MeshKit.xf(Vector3(0.0, 0.0, 0.475), Vector3(0.0, 90.0, 0.0)), WOOD, 0.98)
	for sx: float in [-0.5, 0.5]:
		var strap := PackedVector2Array()
		for i in steps + 1:
			var t := PI * float(i) / float(steps)
			strap.append(Vector2(cos(t) * 0.495, sin(t) * 0.32 - 0.01))
		k.add_extrusion(strap, 0.12, MeshKit.xf(Vector3(sx, 0.0, 0.475), Vector3(0.0, 90.0, 0.0)), IRON, 1.0)
	k.add_box(Vector3(0.14, 0.09, 0.05), MeshKit.xf(Vector3(0.0, 0.0, 0.96)), GOLD.darkened(0.15))
	return k.build()


static func _gold_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_box(Vector3(1.3, 0.1, 0.75), MeshKit.xf(Vector3(0.0, -0.04, 0.0)), GOLD.darkened(0.3))
	for p: Vector3 in [Vector3(-0.4, 0.05, -0.1), Vector3(-0.1, 0.1, 0.12), Vector3(0.25, 0.08, -0.05),
			Vector3(0.45, 0.04, 0.15), Vector3(0.0, 0.14, -0.15), Vector3(-0.3, 0.1, 0.2)]:
		k.add_sphere(0.17, MeshKit.xf(p, Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), GOLD, 10, 5)
	for p: Vector3 in [Vector3(0.05, 0.22, 0.0), Vector3(-0.25, 0.2, -0.05), Vector3(0.3, 0.17, 0.1)]:
		k.add_cylinder(0.07, 0.07, 0.02, MeshKit.xf(p, Vector3(70.0, 0.0, 20.0)), GOLD.lightened(0.2), 10)
	return k.build()
