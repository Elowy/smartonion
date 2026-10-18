class_name DefendTotem
extends Node3D
## The Defend-the-Totem event's totem (GDD 16.1, M6b mid-wave event): an allied target the enemies go for.
## It has [member max_hp] HP ([constant HP_MULT] x a Skeleton Grunt's HP at the wave, party HP factor
## included – [method hp_for]) and must stay alive [constant SURVIVE_TIME] s.
##
## - Every [constant LURE_INTERVAL] s every enemy within [constant LURE_RADIUS] m is taunted onto the totem
##   ([method Enemy.apply_taunt]: it walks to the totem instead of the heroes; touching a hero on the way
##   still hurts). Left alone: bosses, the Loot Goblin and the caravan (they ignore taunts), and enemies
##   taunted onto something else that is alive – a hero's Challenging Charge, a pet, a decoy.
## - Enemies that reach it bite: an enemy overlapping the totem whose contact cooldown is over hits it for
##   its contact damage (the same number it would hit a hero for) and starts the cooldown, exactly like a
##   hit on a hero ([method bite]).
## - HELD: the clock ran out with the totem alive – [signal held] (the [EventSpawner] pays the team
##   buff and the XP). The totem then stands inert (no lure, no bites) until the wave ends.
## - FALLEN: HP 0 – [signal fell], the totem crumbles and frees itself; nothing is paid.
##
## Group [constant EventSpawner.GROUP] (WaveDirector.stop() frees it with the wave). The camera frames it
## while it is ACTIVE ([method event_frame_points]); bots stay within [constant GUARD_RADIUS] of it
## (BotInput). No rng.

signal held(totem: DefendTotem)
signal fell(totem: DefendTotem)

enum State { ACTIVE, HELD, FALLEN }

const HP_MULT := 30.0
const SURVIVE_TIME := 20.0
## Enemies this close (m) are lured; bots keep within GUARD_RADIUS.
const LURE_RADIUS := 8.0
const GUARD_RADIUS := 6.0
const LURE_INTERVAL := 0.25
## A lure lasts a little longer than the interval, so a hiccup does not free an enemy.
const LURE_TAUNT := 0.6
## Hit-box radius (m): an enemy bites when its body overlaps this.
const BODY_RADIUS := 0.7
## Reward (the spawner pays it): +BUFF_PCT % damage for every hero for the rest of the wave and this many
## times the wave's average enemy XP.
const BUFF_PCT := 15.0
const XP_MULT := 25.0
const XP_PILES := 8
const XP_RING := 1.6
const NAME_TEXT := "Totem"
## How much larger than the modelled 3 m the pole is drawn.
const VISUAL_SCALE := 1.25
const COLOR := Color(0.3, 0.85, 0.9)

const WOOD := Color(0.46, 0.3, 0.17)
const WOOD_DARK := Color(0.3, 0.19, 0.1)
const STONE := Color(0.5, 0.5, 0.52)
const PAINT := Color(0.18, 0.62, 0.68)
const GOLD := Color(1.0, 0.8, 0.22)

var wave := 1
var max_hp := 1.0
var hp := 1.0
## Seconds it still has to stand.
var time_left := SURVIVE_TIME
var state := State.ACTIVE
## Damage the enemies did to it so far.
var damage_taken := 0.0
## Bites landed (tests).
var bites := 0

var _lure_left := 0.0
var _time := 0.0
var _flash := 0.0
var _body: Node3D
var _orb: MeshInstance3D
var _bar: MeshInstance3D
var _ring: MeshInstance3D
var _label: Label3D
var _shown_text := ""


## A totem for wave [param p_wave], not in the tree yet.
static func create(p_wave: int) -> DefendTotem:
	var t := DefendTotem.new()
	t.name = "DefendTotem"
	t.wave = maxi(1, p_wave)
	t.max_hp = hp_for(t.wave)
	t.hp = t.max_hp
	t.add_to_group(EventSpawner.GROUP)
	t._build_visual()
	return t


## The totem's HP at [param p_wave]: [constant HP_MULT] x [method EventSpawner.grunt_hp].
static func hp_for(p_wave: int) -> float:
	return HP_MULT * EventSpawner.grunt_hp(p_wave)


## XP the held totem pays: [constant XP_MULT] x the average enemy XP of [param p_wave] (rounded).
static func reward_xp(p_wave: int) -> int:
	return roundi(XP_MULT * LootGoblin.average_xp(p_wave))


# --- Queries ---------------------------------------------------------------------------

func is_active() -> bool:
	return state == State.ACTIVE


func hp_ratio() -> float:
	return clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)


## Ground points the camera frames while the totem is being defended.
func event_frame_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if state == State.ACTIVE and is_inside_tree() and not is_queued_for_deletion():
		out.append(global_position)
	return out


# --- Damage ----------------------------------------------------------------------------

## The totem takes [param amount] damage (ACTIVE only); at 0 HP it falls.
func take_damage(amount: float) -> void:
	if state != State.ACTIVE or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	damage_taken += amount
	_flash = 1.0
	if hp <= 0.0:
		_fall()


func _fall() -> void:
	if state == State.FALLEN:
		return
	state = State.FALLEN
	var here := global_position if is_inside_tree() else position
	Vfx.death_puff(here + Vector3.UP * 0.9, WOOD, 1.8)
	Vfx.explosion(here + Vector3.UP * 0.5, 1.4, COLOR)
	fell.emit(self)
	queue_free()


func _hold() -> void:
	if state != State.ACTIVE:
		return
	state = State.HELD
	time_left = 0.0
	var here := global_position if is_inside_tree() else position
	Vfx.explosion(here + Vector3.UP * 1.0, 2.4, COLOR)
	Vfx.pickup_sparkle(here + Vector3.UP * 1.6)
	held.emit(self)


# --- Frame update ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	if state == State.ACTIVE and is_inside_tree():
		time_left = maxf(0.0, time_left - delta)
		_lure_left -= delta
		if _lure_left <= 0.0:
			_lure_left = LURE_INTERVAL
			lure()
		bite()
		if state == State.ACTIVE and time_left <= 0.0:
			_hold()
	_update_visual(delta)


## Taunts every enemy within LURE_RADIUS onto the totem. Returns how many were lured (tests).
func lure() -> int:
	var n := 0
	for e in EventFx.enemies_within(get_tree(), global_position, LURE_RADIUS):
		if e.is_boss() or e is LootGoblin or e is CaravanCart:
			continue
		if e.is_taunted() and e.taunt_target != self:
			continue
		e.apply_taunt(self, LURE_TAUNT)
		n += 1
	return n


## Every enemy overlapping the totem with its contact cooldown over hits it once (contact damage x the
## enemy's damage multiplier, e.g. an elite's) and starts the cooldown. Stunned / feared enemies and
## those that never touch (the Loot Goblin) do not. Returns the damage dealt.
func bite() -> float:
	var dealt := 0.0
	for e in EventFx.enemies_within(get_tree(), global_position, BODY_RADIUS, true):
		if e.contact_cooldown_left > 0.0 or e.is_stunned() or e.is_feared() or not e.deals_contact_damage():
			continue
		e.contact_cooldown_left = Enemy.CONTACT_COOLDOWN * e.attack_cooldown_mult
		var amount := e.contact_damage * e.damage_mult
		if e.model != null:
			e.model.play_attack()
		bites += 1
		dealt += amount
		take_damage(amount)
		if state != State.ACTIVE:
			break
	return dealt


# --- Look ------------------------------------------------------------------------------

func _update_visual(_delta: float) -> void:
	if _body == null:
		return
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - _delta / 0.15)
	var squash := 1.0 + 0.06 * _flash
	_body.scale = Vector3(squash, 1.0 / squash, squash)
	var pulse := 1.0 + 0.12 * sin(_time * 5.0)
	_orb.scale = Vector3.ONE * pulse
	_orb.position.y = 2.55 + 0.05 * sin(_time * 2.4)
	var active := state == State.ACTIVE
	_bar.visible = active
	if active:
		var r := hp_ratio()
		Mats.set_cast_bar(_bar, Color(0.25, 0.9, 0.35).lerp(Color(0.95, 0.3, 0.2), 1.0 - r), r)
	var ring_color := COLOR if active else GOLD
	Mats.set_ring(_ring, Color(ring_color.r, ring_color.g, ring_color.b, 0.55 if active else 0.0), 0.992, 1.0, 0.0)
	var text := _label_text()
	if text != _shown_text:
		_shown_text = text
		_label.text = text


func _label_text() -> String:
	match state:
		State.ACTIVE:
			return "%s\nHold %d s" % [NAME_TEXT, ceili(time_left)]
		State.HELD:
			return "%s\n+%d%% damage" % [NAME_TEXT, roundi(BUFF_PCT)]
	return ""


func _build_visual() -> void:
	# Drawn VISUAL_SCALE times the modelled size so it reads from the camera's distance.
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.scale = Vector3.ONE * VISUAL_SCALE
	add_child(visual)
	_body = Node3D.new()
	_body.name = "Body"
	visual.add_child(_body)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	pole.mesh = MeshKit.cached("event:totem_pole", func() -> Mesh: return _pole_mesh())
	pole.material_override = Mats.toon_vc()
	_body.add_child(pole)
	_orb = MeshInstance3D.new()
	_orb.name = "Orb"
	_orb.mesh = MeshKit.cached("event:totem_orb", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.2
		s.height = 0.4
		s.radial_segments = 12
		s.rings = 6
		return s)
	_orb.material_override = Mats.glow(COLOR, 2.6)
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.position.y = 2.55
	_body.add_child(_orb)
	_ring = EventFx.ring(self, "LureRing", LURE_RADIUS, COLOR, 0.992, 1.0)
	_bar = EventFx.bar(self, "HpBar", 3.95, Color(0.25, 0.9, 0.35), 1.0)
	_label = EventFx.label(self, "NameTag", _label_text(), 4.2, COLOR.lightened(0.3))


## The carved pole: a stone foot, three stacked wooden faces with painted bands, wings and a crest.
static func _pole_mesh() -> Mesh:
	var k := MeshKit.new()
	k.add_cylinder(0.78, 0.9, 0.22, MeshKit.xf(Vector3(0.0, 0.11, 0.0)), STONE, 14)
	k.add_cylinder(0.55, 0.62, 0.16, MeshKit.xf(Vector3(0.0, 0.3, 0.0)), STONE.lightened(0.1), 12)
	for i in 3:
		var y := 0.38 + 0.7 * float(i)
		var wood := WOOD if i % 2 == 0 else WOOD.lightened(0.08)
		k.add_cylinder(0.34, 0.38, 0.66, MeshKit.xf(Vector3(0.0, y + 0.33, 0.0)), wood, 12)
		k.add_torus(0.3, 0.4, MeshKit.xf(Vector3(0.0, y + 0.05, 0.0)), PAINT, 12, 4)
		# A carved face towards the camera (+Z): brows, eyes, a beak.
		var z := 0.36
		k.add_box(Vector3(0.36, 0.06, 0.06), MeshKit.xf(Vector3(0.0, y + 0.47, z), Vector3(0.0, 0.0, 0.0)), WOOD_DARK)
		for sx: float in [-0.1, 0.1]:
			k.add_sphere(0.06, MeshKit.xf(Vector3(sx, y + 0.38, z + 0.01)), Color(0.95, 0.92, 0.7), 8, 4)
			k.add_sphere(0.028, MeshKit.xf(Vector3(sx, y + 0.38, z + 0.06)), Color(0.08, 0.05, 0.04), 6, 3)
		k.add_segment(Vector3(0.0, y + 0.32, z + 0.02), Vector3(0.0, y + 0.18, z + 0.2), 0.07, 0.01, GOLD.darkened(0.1), 6)
		# Wings out to the sides, painted.
		for sx: float in [-1.0, 1.0]:
			k.add_box(Vector3(0.42, 0.12, 0.05), MeshKit.xf(Vector3(0.42 * sx, y + 0.4, 0.0), Vector3(0.0, 0.0, -18.0 * sx)), PAINT)
	k.add_cylinder(0.12, 0.3, 0.3, MeshKit.xf(Vector3(0.0, 2.35, 0.0)), WOOD_DARK, 10)
	return k.build()
