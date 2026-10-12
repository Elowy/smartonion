class_name LootGoblin
extends Enemy
## The Loot Goblin (GDD 8 "Loot Goblin", M5, architecture §2.6): a rare treasure runner the
## [GoblinSpawner] brings into a wave. Data: res://data/enemies/loot_goblin.tres
## (spawn_weight 0, so the WaveDirector never picks it; gold / XP 0 – its rewards are custom).
##
## - Built with [method Enemy.setup] on its own instance ([method create]); a gold "Loot Goblin"
##   Label3D floats above it (own node, no depth test).
## - Never attacks: [method deals_contact_damage] is false. It flees ([method _think]): away
##   from the living, visible players weighted by inverse distance (closer ones push harder),
##   steering around the arena walls (it probes FLEE_DIRECTIONS headings FLEE_LOOKAHEAD m ahead
##   and takes the one that runs away best without entering the wall margin, so a cornered
##   goblin breaks out along a wall), with a random jink of up to JINK_ANGLE every
##   JINK_MIN..JINK_MAX s in the open (near a wall it keeps its line along the wall). Without
##   a visible player (all stealthed or downed) it jogs at CALM_SPEED_RATIO, turning by each
##   jink once and holding that heading until the next one (walls still steer it).
## - Stuns, freezes, slows (the ghost slow of a downed hero's revive circle too) and
##   knockback work (co-op crowd control); taunt and fear do not ([method apply_taunt] /
##   [method apply_fear] are ignored).
## - Every damaging hit spills a 1-gold coin ([Pickup]) next to it – at most one per
##   COIN_INTERVAL s, MAX_COINS per goblin.
## - At [member escape_time] s of age (GoblinSpawner.ESCAPE_TIME, the age counts while stunned
##   too) it stops and opens a [GoblinPortal] for PORTAL_TIME s – still killable – then
##   escapes: RunState.goblins_escaped += 1, [signal escaped], [method Enemy.despawn] (no loot).
## - Killed: [method kill_gold] gold and [method kill_xp] XP in KILL_PILES pickups around the
##   body, a guaranteed item through [method LootDrops.drop_special] (Source.GOBLIN: Rare+, 25%
##   Epic+, the killer's Fortune, not counted against the wave's drop cap),
##   RunState.record_special_kill(&"goblin", killer) and a coin burst. No normal drop roll.
## - [method is_elite] is true (Slayer and elite-first targeting) but it has no elite affix, so
##   it never gets elite rewards; [method is_boss] is false (Execute kills it like a normal
##   enemy below the threshold).
##
## Determinism: [method Enemy.setup]'s draws at creation, then two RunState.rng draws per jink
## (interval, angle) in its physics tick. Coins and reward piles are placed without draws
## (golden-angle / ring offsets).

## Emitted once when it escapes through its portal (the GoblinSpawner announces it).
signal escaped(goblin: LootGoblin)

## Db id of the goblin's EnemyData.
const DATA_ID := &"loot_goblin"
## Seconds the portal takes to open before the goblin is gone.
const PORTAL_TIME := 1.2
## Coins per hit: gold per coin, minimum seconds between two coins, coins per goblin.
const COIN_GOLD := 1
const COIN_INTERVAL := 0.15
const MAX_COINS := 30
## Coins land this far (m) from the goblin, spread by the golden angle.
const COIN_DROP_DISTANCE := 0.6
const GOLDEN_ANGLE := 2.399963
## Kill rewards: these multiples of the wave's average enemy gold / XP, in KILL_PILES pickups
## on a ring of PILE_RADIUS m.
const KILL_GOLD_MULT := 30.0
const KILL_XP_MULT := 25.0
const KILL_PILES := 8
const PILE_RADIUS := 1.0
## Flight: headings probed when the straight escape route runs into the wall margin.
const FLEE_DIRECTIONS := 16
## Metres ahead a heading is probed.
const FLEE_LOOKAHEAD := 3.0
## Probe points closer than this (m, beyond the radius) to a wall are penalised.
const WALL_MARGIN := 1.0
## Weight of the wall penalty against the escape score (1 = straight away from the players).
const WALL_WEIGHT := 2.0
## Near walls: bonus for keeping the heading it actually moved in last tick (breaks the tie
## between running left or right along a wall, so a jink does not make it dither; a goblin
## pressed into a wall does not move, so it gets no bonus for pressing on).
const HEADING_INERTIA := 0.35
## Players nearer than this (m) count as this near (keeps the weights finite).
const MIN_THREAT_DISTANCE := 0.5
## Random direction changes: every JINK_MIN..JINK_MAX s, up to ± JINK_ANGLE (rad, 70°) off.
const JINK_MIN := 0.6
const JINK_MAX := 1.2
const JINK_ANGLE := 1.2217
## Speed share while no player is visible (all downed / stealthed).
const CALM_SPEED_RATIO := 0.5
## Overhead name tag.
const LABEL_TEXT := "Loot Goblin"
const LABEL_COLOR := Color(1.0, 0.84, 0.3)
const LABEL_OUTLINE := Color(0.2, 0.12, 0.02)
const LABEL_LIFT := 0.3
const LABEL_PIXEL_SIZE := 0.00042
const LABEL_FONT_SIZE := 40
## Coin burst / sparkle colour.
const COIN_COLOR := Color(1.0, 0.82, 0.3)

## Seconds of age at which the portal opens (tests may shorten it).
var escape_time := GoblinSpawner.ESCAPE_TIME
## Coins spilled so far (at most MAX_COINS).
var coins_dropped := 0
## The opening portal (a child), null before.
var portal: GoblinPortal
## Seconds until the portal is open and the goblin gone; < 0 = not opening yet.
var portal_left := -1.0
## The overhead "Loot Goblin" tag.
var label: Label3D

var _last_coin_age := -INF
var _jink_left := 0.0
var _jink_angle := 0.0
var _escaped := false
## Where the last AI step started and the unit direction it actually moved since (zero when
## it did not move).
var _last_here := Vector3.INF
var _heading := Vector3.ZERO


## A goblin of [param p_data] (normally [method goblin_data]) at wave [param p_wave], not in
## the tree yet.
static func create(p_data: EnemyData, p_wave: int) -> LootGoblin:
	var g := setup(LootGoblin.new(), p_data, p_wave) as LootGoblin
	g.add_to_group(&"loot_goblins")
	g._build_label()
	return g


## The goblin's EnemyData from Db (null when missing).
static func goblin_data() -> EnemyData:
	return Db.get_enemy(DATA_ID)


## Spawn-weight average gold of the enemies the director may pick at [param wave].
static func average_gold(wave: int) -> float:
	return _weighted_average(wave, true)


## Spawn-weight average XP of the enemies the director may pick at [param wave].
static func average_xp(wave: int) -> float:
	return _weighted_average(wave, false)


## Gold a goblin killed in [param wave] leaves: KILL_GOLD_MULT x [method average_gold].
static func kill_gold(wave: int) -> int:
	return roundi(KILL_GOLD_MULT * average_gold(wave))


## XP a goblin killed in [param wave] leaves: KILL_XP_MULT x [method average_xp].
static func kill_xp(wave: int) -> int:
	return roundi(KILL_XP_MULT * average_xp(wave))


static func _weighted_average(wave: int, gold: bool) -> float:
	var total := 0.0
	var sum := 0.0
	for d in WaveDirector.eligible_enemies(wave):
		total += d.spawn_weight
		sum += d.spawn_weight * float(d.gold if gold else d.xp)
	return sum / total if total > 0.0 else 0.0


# --- Enemy overrides -------------------------------------------------------------------

## Counts as an elite for Slayer and elite-first targeting (it has no affix: no elite rewards).
func is_elite() -> bool:
	return true


func is_boss() -> bool:
	return false


## Never hurts on touch.
func deals_contact_damage() -> bool:
	return false


## Taunts do not work on it.
func apply_taunt(_target: Node3D, _duration: float) -> void:
	pass


## Fear does not work on it (it is always running away anyway).
func apply_fear(_duration: float, _from: Vector3) -> void:
	pass


## Takes the hit like any enemy, then spills a coin (see [method _drop_coin]).
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
		knockback: Vector3 = Vector3.ZERO) -> void:
	var landed := not is_dead() and amount > 0.0
	super(amount, is_crit, attacker, knockback)
	if landed:
		_drop_coin()


## True while the escape portal opens.
func is_opening_portal() -> bool:
	return portal_left >= 0.0


func has_escaped() -> bool:
	return _escaped


func _physics_process(delta: float) -> void:
	super(delta)
	if is_dead() or data == null or not is_inside_tree():
		return
	_update_escape(delta)


## Flight (see the class notes); stands still while the portal opens. Fleeing, the current
## jink is an offset from the escape direction on every tick; calm (no visible player), the
## heading turns by a jink only on the tick it is drawn and is kept in between.
func _think(delta: float, here: Vector3, _feared: bool) -> void:
	if is_opening_portal():
		_move_velocity = Vector3.ZERO
		return
	_track_heading(here)
	_jink_left -= delta
	var new_jink := false
	if _jink_left <= 0.0:
		var rng := RunState.rng
		_jink_left = rng.randf_range(JINK_MIN, JINK_MAX)
		_jink_angle = rng.randf_range(-JINK_ANGLE, JINK_ANGLE)
		new_jink = true
	var away := flee_vector(here)
	var speed := walk_speed()
	var dir: Vector3
	if away.length_squared() > 0.0000001:
		var base := away.normalized()
		dir = best_heading(here, base.rotated(Vector3.UP, _jink_angle), base)
	else:
		speed *= CALM_SPEED_RATIO
		var calm := _facing.rotated(Vector3.UP, _jink_angle) if new_jink else _facing
		dir = best_heading(here, calm, calm)
	_steer(dir * speed, delta)
	_facing = dir


## Sum over the living, visible players of (here - player) / distance² (XZ): points away from
## them, closer players weigh more. Zero without players. Reads the LivingPlayers snapshot
## of this tick.
func flee_vector(here: Vector3) -> Vector3:
	var out := Vector3.ZERO
	var n := LivingPlayers.count
	var xs := LivingPlayers.pos_x
	var zs := LivingPlayers.pos_z
	var hidden := LivingPlayers.stealthed
	var min_sq := MIN_THREAT_DISTANCE * MIN_THREAT_DISTANCE
	for i in n:
		if hidden[i] != 0:
			continue
		var dx := here.x - xs[i]
		var dz := here.z - zs[i]
		var d_sq := maxf(dx * dx + dz * dz, min_sq)
		out += Vector3(dx / d_sq, 0.0, dz / d_sq)
	return out


## [param want] (unit, XZ: the jinked escape direction) when its probe point FLEE_LOOKAHEAD m
## ahead stays out of the wall margin; else the best of FLEE_DIRECTIONS headings by escape
## score (dot with the un-jinked [param flee] – no jink near walls, so it does not dither)
## + HEADING_INERTIA x dot with the heading it moved in - WALL_WEIGHT x wall penetration.
func best_heading(here: Vector3, want: Vector3, flee: Vector3) -> Vector3:
	var pen := _wall_penalty(here + want * FLEE_LOOKAHEAD)
	if pen <= 0.0:
		return want
	var best := want
	var best_score := want.dot(flee) + HEADING_INERTIA * want.dot(_heading) - WALL_WEIGHT * pen
	for k in FLEE_DIRECTIONS:
		var a := TAU * float(k) / float(FLEE_DIRECTIONS)
		var d := Vector3(cos(a), 0.0, sin(a))
		var score := d.dot(flee) + HEADING_INERTIA * d.dot(_heading) \
				- WALL_WEIGHT * _wall_penalty(here + d * FLEE_LOOKAHEAD)
		if score > best_score:
			best_score = score
			best = d
	return best


## Updates the realized heading from the move since the last AI step.
func _track_heading(here: Vector3) -> void:
	_heading = Vector3.ZERO
	if _last_here.is_finite():
		var moved := Vector3(here.x - _last_here.x, 0.0, here.z - _last_here.z)
		if moved.length_squared() > 0.000025:
			_heading = moved.normalized()
	_last_here = here


## How far (in FLEE_LOOKAHEAD units) [param p] lies inside the wall margin of the arena.
func _wall_penalty(p: Vector3) -> float:
	var b := Arena.current.get_bounds() if Arena.current != null and is_instance_valid(Arena.current) \
			else Rect2(-Arena.SIZE / 2.0, Arena.SIZE)
	var safe := b.grow(-(radius + WALL_MARGIN))
	var pen := maxf(0.0, safe.position.x - p.x) + maxf(0.0, p.x - safe.end.x) \
			+ maxf(0.0, safe.position.y - p.z) + maxf(0.0, p.z - safe.end.y)
	return pen / FLEE_LOOKAHEAD


# --- Escape --------------------------------------------------------------------------

func _update_escape(delta: float) -> void:
	if portal_left < 0.0:
		if _age >= escape_time - TIMER_EPSILON:
			_open_portal()
		return
	portal_left -= delta
	if portal != null:
		portal.set_progress(1.0 - portal_left / PORTAL_TIME)
	if portal_left <= TIMER_EPSILON:
		_escape()


func _open_portal() -> void:
	portal_left = PORTAL_TIME
	_move_velocity = Vector3.ZERO
	portal = GoblinPortal.create()
	add_child(portal)


func _escape() -> void:
	if _escaped or is_dead():
		return
	_escaped = true
	RunState.goblins_escaped += 1
	var pos := global_position if is_inside_tree() else position
	Vfx.pickup_sparkle(pos + Vector3.UP * 0.8)
	escaped.emit(self)
	despawn()


# --- Loot ----------------------------------------------------------------------------

## A 1-gold coin next to the goblin (interval and cap, see the constants).
func _drop_coin() -> void:
	if coins_dropped >= MAX_COINS or _age - _last_coin_age < COIN_INTERVAL - TIMER_EPSILON:
		return
	var parent := _world_parent()
	if parent == null:
		return
	_last_coin_age = _age
	coins_dropped += 1
	var a := float(coins_dropped) * GOLDEN_ANGLE
	var pos := global_position if is_inside_tree() else position
	Pickup.drop(parent, COIN_GOLD, 0, _ground_point(pos + Vector3(cos(a), 0.0, sin(a)) * COIN_DROP_DISTANCE))


## Kill rewards (see the class notes) – replaces the normal gold / XP pickup and drop roll.
func _death_loot(pos: Vector3, attacker: Node3D) -> void:
	var killer := attacker if attacker != null and is_instance_valid(attacker) else null
	_drop_reward_piles(pos)
	LootDrops.drop_special(ItemGenerator.Source.GOBLIN, self, killer)
	var killer_index := -1
	var player := killer as Player
	if player != null and player.slot != null:
		killer_index = player.slot.index
	RunState.record_special_kill(&"goblin", killer_index)
	Vfx.explosion(pos + Vector3.UP * 0.4, 1.4, COIN_COLOR)
	Vfx.pickup_sparkle(pos + Vector3.UP * 0.9)


## [method kill_gold] and [method kill_xp] of this goblin's wave, split over KILL_PILES pickups
## on a ring around [param pos] (piles without gold and XP are skipped).
func _drop_reward_piles(pos: Vector3) -> void:
	var parent := _world_parent()
	if parent == null:
		return
	var gold := kill_gold(wave)
	var xp := kill_xp(wave)
	for i in KILL_PILES:
		var g := floori(float(gold) / KILL_PILES) + (1 if i < gold % KILL_PILES else 0)
		var x := floori(float(xp) / KILL_PILES) + (1 if i < xp % KILL_PILES else 0)
		if g <= 0 and x <= 0:
			continue
		var a := TAU * float(i) / float(KILL_PILES)
		Pickup.drop(parent, g, x, _ground_point(pos + Vector3(cos(a), 0.0, sin(a)) * PILE_RADIUS))


## [param p] on the ground, inside the arena.
func _ground_point(p: Vector3) -> Vector3:
	var at := Vector3(p.x, 0.0, p.z)
	if Arena.current != null and is_instance_valid(Arena.current):
		at = Arena.current.clamp_point(at, 0.3)
	return at


# --- Look ----------------------------------------------------------------------------

func _build_label() -> void:
	label = Label3D.new()
	label.name = "NameTag"
	label.text = LABEL_TEXT
	label.font_size = LABEL_FONT_SIZE
	label.outline_size = 12
	label.pixel_size = LABEL_PIXEL_SIZE
	label.modulate = LABEL_COLOR
	label.outline_modulate = LABEL_OUTLINE
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = 24
	label.outline_render_priority = 23
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := model.head_height if model != null else 1.0
	label.position = Vector3(0.0, top + LABEL_LIFT, 0.0)
	add_child(label)
