class_name CaravanCart
extends Enemy
## The Goblin Caravan's cart (GDD 16.1, M6b mid-wave event): a heavy cart that rolls straight across the
## arena from one edge to the other in about [constant CROSS_TIME] s. Its HP is [constant HP_MULT] x a
## Skeleton Grunt's at the wave ([method hp_for]); three guards ([EventGuards]) walk with it until a hero
## comes close, then they fight like any enemy.
##
## - It is an [Enemy] (group &"enemies", hit by every weapon and ability like one) built from an in-code
##   EnemyData ([method cart_data]: the grunt's growth with x40 HP, no contact damage, immune to knockback
##   and stuns; slows work, so Frost Nova / Blizzard hold it back). It never attacks ([method
##   deals_contact_damage] is false) and ignores taunt and fear, like the Loot Goblin.
## - Killed: [constant GOLD_MULT] x the wave's average enemy gold as coins ([method reward_gold]) and one
##   Rare item (a loot bag, [method LootDrops.drop_event_item]) – no normal drop roll, no Artifact roll;
##   [signal plundered].
## - Reaching the far end of its route: [signal escaped], it rolls out of the arena (despawn, nothing
##   paid). A wave that ends first simply frees it (WaveDirector.stop()).
## - The look is a [CartModel] with a name tag and an HP bar. The camera frames it ([method
##   event_frame_points]); bots chase it when no enemy is near (BotInput).
## No rng of its own (Enemy.setup's usual draws at creation).

signal plundered(cart: CaravanCart, killer: Player)
signal escaped(cart: CaravanCart)

const DATA_ID := &"caravan_cart"
const HP_MULT := 40.0
## Seconds the crossing takes (shortened by the spawner when the wave would end first, never below MIN).
const CROSS_TIME := 25.0
const MIN_CROSS_TIME := 15.0
const GOLD_MULT := 40.0
const GOLD_PILES := 10
const GOLD_RING := 1.6
## Body radius (m), the route's distance (m) from the walls, and the guards' count.
const BODY_RADIUS := 1.0
const EDGE_MARGIN := 1.8
const GUARD_COUNT := 3
## It escapes this close (m) to the end of its route.
const ESCAPE_REACH := 0.4
const NAME_TEXT := "Goblin Caravan"
const BAG_OFFSET := Vector3(0.0, 0.0, 1.8)

## Where it started, where it is headed and how fast it goes (m/s).
var route_from := Vector3.ZERO
var route_to := Vector3.ZERO
var cross_time := CROSS_TIME
## The escort's node (a child).
var guards: EventGuards

var _escaped := false
var _bar: MeshInstance3D
var _label: Label3D


## The cart's EnemyData: the Skeleton Grunt's HP growth with [constant HP_MULT] x its base HP, no contact
## damage, not a spawn candidate. A fresh Resource each call (Db is not touched).
static func cart_data() -> EnemyData:
	var grunt := Db.get_enemy(EventSpawner.GRUNT_ID)
	var d: EnemyData = grunt.duplicate() as EnemyData if grunt != null else EnemyData.new()
	d.id = DATA_ID
	d.display_name = NAME_TEXT
	d.behavior = EnemyData.Behavior.CHASE
	d.max_hp = (grunt.max_hp if grunt != null else 4.0) * HP_MULT
	d.contact_damage = 0.0
	d.projectile_damage = 0.0
	d.radius = BODY_RADIUS
	d.knockback_resist = 1.0
	d.stun_resist = 1.0
	d.death_effect = &""
	d.priority_target = false
	d.first_wave = 99
	d.spawn_weight = 0.0
	d.gold = 0
	d.xp = 0
	d.model_style = &"goblin"
	d.model_scale = 1.0
	return d


## A cart for wave [param p_wave] that will roll from [param p_from] to [param p_to] in [param p_cross_time]
## s, not in the tree yet.
static func create_route(p_wave: int, p_from: Vector3, p_to: Vector3, p_cross_time: float = CROSS_TIME) -> CaravanCart:
	var c := setup(CaravanCart.new(), cart_data(), p_wave) as CaravanCart
	c.route_from = Vector3(p_from.x, 0.0, p_from.z)
	c.route_to = Vector3(p_to.x, 0.0, p_to.z)
	c.cross_time = maxf(1.0, p_cross_time)
	c.move_speed = c.route_length() / c.cross_time
	c.add_to_group(EventSpawner.GROUP)
	c.guards = EventGuards.new()
	c.guards.name = "Guards"
	c.add_child(c.guards)
	# The stock model is a skeleton: swap in the cart.
	c.remove_child(c.model)
	c.model.free()
	var cart_model := CartModel.new()
	cart_model.name = "Model"
	c.model = cart_model
	c.add_child(cart_model)
	cart_model.setup(c.data)
	cart_model.roll_speed = c.move_speed
	c.model.set_facing(c.route_dir())
	c._build_hud()
	return c


## The cart's HP at [param p_wave]: [constant HP_MULT] x [method EventSpawner.grunt_hp].
static func hp_for(p_wave: int) -> float:
	return HP_MULT * EventSpawner.grunt_hp(p_wave)


## Gold the killed cart pays: [constant GOLD_MULT] x the average enemy gold of [param p_wave] (rounded).
static func reward_gold(p_wave: int) -> int:
	return roundi(GOLD_MULT * LootGoblin.average_gold(p_wave))


## Where the escort stands, in world axes, for a cart rolling along [param dir] (unit, XZ): two behind it
## at the sides and the rest in a line behind.
static func escort_offsets(count: int, dir: Vector3) -> Array[Vector3]:
	var back := -Vector3(dir.x, 0.0, dir.z).normalized()
	var side := Vector3(-back.z, 0.0, back.x)
	var out: Array[Vector3] = []
	for i in count:
		match i % 3:
			0:
				out.append(back * 2.6 + side * 1.5)
			1:
				out.append(back * 2.6 - side * 1.5)
			_:
				out.append(back * (4.0 + float(floori(float(i) / 3.0)) * 1.2))
	return out


# --- Queries -----------------------------------------------------------------------------

func route_length() -> float:
	return Vector2(route_to.x - route_from.x, route_to.z - route_from.z).length()


## The unit direction of the route (XZ).
func route_dir() -> Vector3:
	var d := Vector3(route_to.x - route_from.x, 0.0, route_to.z - route_from.z)
	return d.normalized() if d.length_squared() > 0.000001 else Vector3(1.0, 0.0, 0.0)


## Metres of the route still ahead of [param here].
func distance_left(here: Vector3) -> float:
	return maxf(0.0, (route_to - here).dot(route_dir()))


func has_escaped() -> bool:
	return _escaped


## Ground points the camera frames while the cart rolls.
func event_frame_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if is_inside_tree() and not is_dead() and not _escaped and not is_queued_for_deletion():
		out.append(global_position)
	return out


# --- Enemy overrides ---------------------------------------------------------------------

## Never hurts on touch.
func deals_contact_damage() -> bool:
	return false


## Taunts and fear do not work on it.
func apply_taunt(_target: Node3D, _duration: float) -> void:
	pass


func apply_fear(_duration: float, _from: Vector3) -> void:
	pass


func is_boss() -> bool:
	return false


## Takes the hit like any enemy; an attack on the cart alerts its escort.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null,
		knockback: Vector3 = Vector3.ZERO) -> void:
	var landed := not is_dead() and amount > 0.0
	super(amount, is_crit, attacker, knockback)
	if landed and guards != null:
		guards.alert()
	_update_bar()


func _physics_process(delta: float) -> void:
	super(delta)
	if is_dead() or data == null or not is_inside_tree() or _escaped:
		return
	if distance_left(global_position) <= ESCAPE_REACH:
		_escape()


## Rolls straight along the route (a push or a crowd nudge is corrected towards the far end).
func _think(delta: float, here: Vector3, _feared: bool) -> void:
	var to := Vector3(route_to.x - here.x, 0.0, route_to.z - here.z)
	var dir := to.normalized() if to.length_squared() > 0.0001 else route_dir()
	_steer(dir * walk_speed(), delta)
	_facing = dir


func _escape() -> void:
	if _escaped or is_dead():
		return
	_escaped = true
	var pos := global_position if is_inside_tree() else position
	Vfx.pickup_sparkle(pos + Vector3.UP * 1.0)
	escaped.emit(self)
	despawn()


## The kill rewards (see the class notes) – replaces the normal gold / XP pickup and drop roll.
func _death_loot(pos: Vector3, attacker: Node3D) -> void:
	var killer := attacker as Player if attacker != null and is_instance_valid(attacker) else null
	EventFx.burst(_world_parent(), pos, reward_gold(wave), 0, GOLD_PILES, GOLD_RING)
	LootDrops.drop_event_item(ItemGenerator.Source.LOOT, pos + BAG_OFFSET, killer, Items.Rarity.RARE)
	Vfx.explosion(pos + Vector3.UP * 0.6, 2.2, Color(1.0, 0.82, 0.3))
	Vfx.pickup_sparkle(pos + Vector3.UP * 1.0)
	plundered.emit(self, killer)


# --- Look --------------------------------------------------------------------------------

func _build_hud() -> void:
	_bar = EventFx.bar(self, "HpBar", 2.15, Color(0.95, 0.75, 0.2), 1.0)
	_label = EventFx.label(self, "NameTag", NAME_TEXT, 2.7, UiTheme.GOLD)


func _update_bar() -> void:
	if _bar != null:
		Mats.set_cast_bar(_bar, Color(0.95, 0.75, 0.2), clampf(hp / maxf(1.0, max_hp), 0.0, 1.0))
