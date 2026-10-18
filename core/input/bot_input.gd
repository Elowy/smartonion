class_name BotInput
extends ScriptedInput
## Small kiting AI used by smoke runs (--smoke) and screenshot / demo mode.
## - Keeps its distance from enemies: ranged heroes at KITE_DISTANCE, melee heroes just
##   inside their weapon reach (they close in on the nearest enemy).
## - Walks to dropped loot, keeps away from the arena walls (no corner traps), stays near
##   its teammates and drifts back towards the centre.
## - Revives (GDD 1): a downed bot (ghost) walks straight to the arena's Spirit Healer and
##   waits inside its circle for the next 10 s pulse (full HP; with Resurrection Sickness or
##   without a healer it drifts towards the
##   nearest living teammate). A living bot only runs to a downed teammate within
##   RESCUE_RANGE and stands next to it until the revive is done – farther ghosts use the
##   healer while the bot keeps fighting.
## - Loot Goblin (M5, GDD 8 "Botok"): a [LootGoblin] is never a threat (no kiting, no crowd,
##   no rescue panic); with no other enemy within CROWD_RADIUS and HP at or above
##   RETREAT_HP_RATIO a living bot chases the nearest goblin within ENGAGE_DISTANCE up to its
##   keep distance (melee: inside its reach, ranged: KITE_DISTANCE). No RNG.
## - Enemy hazards (M6, GDD 8 "Botok"): a living bot steps out of the telegraphed circles and
##   cones and the burning fields the bosses lay down ([method _hazard_steer]: every node of the
##   group &"enemy_hazards" with a hazard_push(from) method says which way to go; a team of bots
##   gathers in a Meteor circle, whose damage is shared). The push outweighs everything but
##   the walls' ([constant HAZARD_WEIGHT]) and also ends a rescue stand inside a hazard.
## - Priority targets (M6, GDD 8 "elsődleges célpont"): a living, healthy bot with fewer than
##   CROWD_COUNT enemies around goes for the nearest Cultist Acolyte within
##   PRIORITY_ENGAGE_DISTANCE (chases it up to its keep distance), and its weapons shoot an
##   Acolyte in reach before the nearest enemy ([method priority_enemy], used by
##   WeaponRunner.find_target). No RNG.
## - Flesh Golem hook (M6): a living bot standing in a telegraphed hook line sidesteps out of
##   it – for HOOK_DODGE_CHANCE of the hooks (decided once per hook with the bot's own RNG; the
##   others catch it like a human who looked away).
## - Mid-wave events (M6b, GDD 16.1 "Botok"; [method _event_steer], nodes of the group
##   EventSpawner.GROUP): the guards of a Guarded Chest / the caravan's escort are enemies like any
##   other; a bot without an enemy around walks up to the locked chest's camp (CHEST_CAMP_DISTANCE),
##   goes to the opened-up chest as soon as its guards are dead and stands on it until it opens
##   (a hazard still moves it); it keeps within DefendTotem.GUARD_RADIUS of the Defend-the-Totem
##   totem; and it chases the [CaravanCart] like a Loot Goblin (never a threat), from
##   CART_ENGAGE_DISTANCE. No RNG.

## Ranged bots keep this far (m) from enemies.
const KITE_DISTANCE := 6.0
## Melee bots keep this share of their weapon reach (m) from enemies ...
const MELEE_KEEP_RATIO := 0.7
## ... but at least this much (contact damage starts at about 0.9 m).
const MIN_KEEP_DISTANCE := 1.3
## Weapons with a shorter reach (m) count as melee: the bot closes in.
const MELEE_REACH := 4.0
## Melee bots look for a fight within this distance (m) ...
const ENGAGE_DISTANCE := 12.0
## ... unless their HP ratio is below this or CROWD_COUNT enemies are within CROWD_RADIUS m:
## then they kite like ranged heroes.
const RETREAT_HP_RATIO := 0.45
const CROWD_COUNT := 4
const CROWD_RADIUS := 3.0
## Walls closer than this (m) push the bot back into the arena.
const WALL_AVOID_DISTANCE := 3.0
## Bots farther than this (m) from their living teammates' centre drift back to them.
const COHESION_DISTANCE := 4.0
## A bot stops this close (m) to the teammate it revives / is revived by
## (Player.REVIVE_RADIUS is 1.8 m).
const RESCUE_DISTANCE := 1.1
## Downed teammates farther away than this (m) are not worth a rescue run: they walk to the
## Spirit Healer instead.
const RESCUE_RANGE := 5.0
## A ghost bot stops this close (m) to the Spirit Healer – well inside its HEAL_RADIUS.
const HEALER_STOP_DISTANCE := SpiritHealer.HEAL_RADIUS * 0.5
## Without a Spirit Healer a ghost bot looks for living teammates within this range (m).
const HELP_RANGE := 30.0
## While reviving, an enemy closer than this (m) makes the bot step away after all.
const RESCUE_PANIC_DISTANCE := 1.6
## No rescue run into a crowd: more than RESCUE_MAX_THREATS enemies within
## RESCUE_THREAT_RADIUS m of the ghost, or a rescuer below RESCUE_MIN_HP_RATIO, waits
## (the ghost walks out of the crowd on its own).
const RESCUE_THREAT_RADIUS := 3.5
const RESCUE_MAX_THREATS := 2
const RESCUE_MIN_HP_RATIO := 0.35
## Steering weight of a goblin chase (loot pickups weigh 1.5, a melee engage 1.2).
const GOBLIN_CHASE_WEIGHT := 2.0
## Steering weight of the enemy hazards' push (each hazard pushes 1..2 long, a Meteor pull is 3).
const HAZARD_WEIGHT := 5.0
## A priority target (Cultist Acolyte) within this distance (m) is chased, with this weight.
const PRIORITY_ENGAGE_DISTANCE := 14.0
const PRIORITY_CHASE_WEIGHT := 1.8
## Share of the Flesh Golem's hooks a bot sidesteps, and how far (m) beyond the line's edge
## it counts as being in the line.
const HOOK_DODGE_CHANCE := 0.6
const HOOK_DODGE_MARGIN := 0.8
## Events (M6b): a locked chest pulls a bot without an enemy around until it is this close (m) – inside the
## guards' aggro (EventGuards.AGGRO_RADIUS) – with CAMP_PULL_WEIGHT; a READY chest pulls with
## CHEST_PULL_WEIGHT and a bot that is within CHEST_HOLD_DISTANCE of it stands still (the chest opens
## after 1.5 s within GuardedChest.OPEN_RADIUS).
const CHEST_CAMP_DISTANCE := 7.0
const CAMP_PULL_WEIGHT := 2.0
const CHEST_PULL_WEIGHT := 3.0
const CHEST_HOLD_DISTANCE := 1.0
## The totem's guards start to be pulled back this far (m) inside DefendTotem.GUARD_RADIUS, with
## TOTEM_PULL_BASE + the excess (m) x TOTEM_PULL_SLOPE, at most TOTEM_PULL_MAX.
const TOTEM_PULL_MARGIN := 1.0
const TOTEM_PULL_BASE := 3.0
const TOTEM_PULL_SLOPE := 2.0
const TOTEM_PULL_MAX := 8.0
## The cart is chased from this far (m), with this weight (a goblin chase weighs GOBLIN_CHASE_WEIGHT).
const CART_ENGAGE_DISTANCE := 40.0
const CART_CHASE_WEIGHT := 2.0

var body: Node3D
var _wander := Vector2.ZERO
var _wander_timer := 0.0
var _rng := RandomNumberGenerator.new()
## Per telegraphed hook, whether the bot sidesteps it: golem instance id -> Enemy.hook_serial of
## the hook decided about, and golem instance id -> the decision. Kept per golem so several golems
## aiming at the bot at once do not re-roll each other every tick; pruned in [method think].
var _hook_serials: Dictionary[int, int] = {}
var _hook_dodges: Dictionary[int, bool] = {}
## Set by [method _event_steer]: the bot stands on an openable chest and holds still.
var _event_hold := false


func _init(p_key: String = "bot", p_seed: int = 0) -> void:
	super(p_key)
	_rng.seed = p_seed


func get_device_name() -> String:
	return "Bot"


## The bot's decisions (movement), once per unpaused physics tick: see PlayerInput.think().
func think(delta: float) -> void:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		move = Vector2.ZERO
		return
	var tree := body.get_tree()
	var pos := Vector2(body.global_position.x, body.global_position.z)
	var alive := _is_alive(body)
	var enemies: Array[Vector2] = []
	var nearest_enemy := INF
	var to_nearest := Vector2.ZERO
	var crowd := 0
	var goblin_dist := INF
	var to_goblin := Vector2.ZERO
	var cart_dist := INF
	var to_cart := Vector2.ZERO
	var priority_dist := INF
	var to_priority := Vector2.ZERO
	var hook_escape := Vector2.ZERO
	for e in tree.get_nodes_in_group(&"enemies"):
		var n := e as Node3D
		if n == null:
			continue
		var d := pos - Vector2(n.global_position.x, n.global_position.z)
		var dist := d.length()
		if dist < 0.001:
			continue
		if n is LootGoblin:
			# Harmless and worth a fortune: a chase target, never a threat.
			if dist < goblin_dist:
				goblin_dist = dist
				to_goblin = -d / dist
			continue
		if n is CaravanCart:
			# The caravan's cart (M6b): never hurts, worth a fortune – a chase target, not a threat.
			if dist < cart_dist:
				cart_dist = dist
				to_cart = -d / dist
			continue
		var enemy := n as Enemy
		if enemy != null:
			if enemy.is_priority_target() and dist < priority_dist:
				priority_dist = dist
				to_priority = -d / dist
			if enemy.ai_state == Enemy.AiState.HOOK:
				var out := enemy.hook_escape_dir(body.global_position, HOOK_DODGE_MARGIN)
				if out != Vector3.ZERO and _wants_dodge(enemy):
					hook_escape += Vector2(out.x, out.z)
		enemies.append(d)
		if dist < CROWD_RADIUS:
			crowd += 1
		if dist < nearest_enemy:
			nearest_enemy = dist
			to_nearest = -d / dist
	if not _hook_serials.is_empty():
		_prune_hook_decisions()
	var melee := _reach() < MELEE_REACH and _hp_ratio() >= RETREAT_HP_RATIO and crowd < CROWD_COUNT
	var keep := clampf(_reach() * MELEE_KEEP_RATIO, MIN_KEEP_DISTANCE, KITE_DISTANCE) if melee else KITE_DISTANCE
	var steer := Vector2.ZERO
	for d in enemies:
		var dist := d.length()
		if dist < keep:
			# Same push at the keep distance's edge whatever the keep distance is.
			steer += d / dist * (keep - dist) * (KITE_DISTANCE / keep)
	var hazard := _hazard_steer(pos) if alive else Vector2.ZERO
	steer += hazard * HAZARD_WEIGHT
	# A ghost walks straight to the Spirit Healer (enemies ignore ghosts) and waits there.
	# With Resurrection Sickness the healer cannot help yet: drift to a living teammate.
	var sick := body is Player and (body as Player).res_sickness_left > 0.0
	if not alive and not sick:
		var healer := _healer_point()
		if healer.is_finite():
			var to_healer := healer - pos
			var gap := to_healer.length()
			move = to_healer / gap if gap > HEALER_STOP_DISTANCE else Vector2.ZERO
			return
	# A living bot inside a golem's telegraphed hook line steps out of it first.
	if alive and hook_escape != Vector2.ZERO:
		move = hook_escape.normalized()
		return
	# Living bots go to downed teammates close by, ghosts (no healer) to living ones (GDD 1).
	var buddy := _nearest_teammate(pos, not alive, RESCUE_RANGE if alive else HELP_RANGE)
	if buddy.is_finite() and alive and not _safe_rescue(pos, buddy, enemies):
		buddy = Vector2.INF
	if buddy.is_finite():
		var to := buddy - pos
		var gap := to.length()
		if gap > RESCUE_DISTANCE:
			var avoid := steer.limit_length(2.0) * 0.5 if alive else Vector2.ZERO
			move = (avoid + to / gap * 2.5).normalized()
			return
		if not alive or (nearest_enemy > RESCUE_PANIC_DISTANCE and hazard == Vector2.ZERO):
			move = Vector2.ZERO
			return
	if alive and melee and nearest_enemy > keep and nearest_enemy < ENGAGE_DISTANCE:
		steer += to_nearest * 1.2
	if alive and priority_dist < PRIORITY_ENGAGE_DISTANCE and crowd < CROWD_COUNT \
			and _hp_ratio() >= RETREAT_HP_RATIO:
		var priority_keep := clampf(_reach() * MELEE_KEEP_RATIO, MIN_KEEP_DISTANCE, KITE_DISTANCE)
		if priority_dist > priority_keep:
			steer += to_priority * PRIORITY_CHASE_WEIGHT
	if alive and crowd == 0 and _hp_ratio() >= RETREAT_HP_RATIO and goblin_dist < ENGAGE_DISTANCE:
		var chase_keep := clampf(_reach() * MELEE_KEEP_RATIO, MIN_KEEP_DISTANCE, KITE_DISTANCE)
		if goblin_dist > chase_keep:
			steer += to_goblin * GOBLIN_CHASE_WEIGHT
	if alive and crowd == 0 and _hp_ratio() >= RETREAT_HP_RATIO and cart_dist < CART_ENGAGE_DISTANCE:
		var cart_keep := clampf(_reach() * MELEE_KEEP_RATIO, MIN_KEEP_DISTANCE, KITE_DISTANCE)
		if cart_dist > cart_keep:
			steer += to_cart * CART_CHASE_WEIGHT
	# Mid-wave events: the chest, the totem (a bot standing on an openable chest stays put unless a
	# hazard moves it).
	_event_hold = false
	if alive:
		steer += _event_steer(pos, crowd)
	if _event_hold and hazard == Vector2.ZERO:
		move = Vector2.ZERO
		return
	var best_loot := Vector2.ZERO
	var best_dist := 9.0
	for p in tree.get_nodes_in_group(&"pickups"):
		var n := p as Node3D
		if n == null:
			continue
		var d := Vector2(n.global_position.x, n.global_position.z) - pos
		if d.length() < best_dist:
			best_dist = d.length()
			best_loot = d.normalized()
	steer += best_loot * 1.5
	steer += -pos * 0.04  # drift back to the centre
	steer += _wall_push(pos)
	steer += _cohesion(pos)
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(0.8, 2.0)
		_wander = Vector2.from_angle(_rng.randf() * TAU) * 0.6
	steer += _wander
	move = steer.normalized() if steer.length() > 0.05 else Vector2.ZERO


## The push away from the dangerous ground effects of the enemies around [param pos] (XZ): the
## sum of every &"enemy_hazards" node's hazard_push(from) (EnemyHazard: telegraphed circles and
## cones, burning fields; a harmless or faded hazard answers zero; the Meteor pulls a team in).
## Zero when none is near.
func _hazard_steer(pos: Vector2) -> Vector2:
	var out := Vector2.ZERO
	var from := Vector3(pos.x, 0.0, pos.y)
	for node in body.get_tree().get_nodes_in_group(EnemyHazard.GROUP):
		if node.has_method(&"hazard_push"):
			out += node.call(&"hazard_push", from) as Vector2
	return out


## The pull of the mid-wave events' objects (nodes of EventSpawner.GROUP) on a living bot at
## [param pos] (XZ), with [param crowd] enemies within CROWD_RADIUS of it: a locked [GuardedChest] draws a
## bot with nobody around and enough HP up to CHEST_CAMP_DISTANCE; an openable one draws it all the way
## and, within CHEST_HOLD_DISTANCE, sets [member _event_hold] (the bot stands still while it opens); the
## [DefendTotem] draws a bot that strays beyond DefendTotem.GUARD_RADIUS - TOTEM_PULL_MARGIN back
## (the harder the further out). Zero when no event object is around.
func _event_steer(pos: Vector2, crowd: int) -> Vector2:
	_event_hold = false
	var tree := body.get_tree()
	if tree.get_node_count_in_group(EventSpawner.GROUP) == 0:
		return Vector2.ZERO
	var out := Vector2.ZERO
	for node in tree.get_nodes_in_group(EventSpawner.GROUP):
		if not is_instance_valid(node) or not (node as Node).is_inside_tree():
			continue
		var chest := node as GuardedChest
		if chest != null and not chest.is_open():
			out += _chest_pull(chest, pos, crowd)
			continue
		var totem := node as DefendTotem
		if totem != null and totem.is_active():
			out += _totem_pull(totem, pos)
	return out


func _chest_pull(chest: GuardedChest, pos: Vector2, crowd: int) -> Vector2:
	var to := Vector2(chest.global_position.x, chest.global_position.z) - pos
	var dist := to.length()
	if chest.is_ready():
		if dist <= CHEST_HOLD_DISTANCE:
			_event_hold = true
			return Vector2.ZERO
		return to / dist * CHEST_PULL_WEIGHT
	if crowd == 0 and _hp_ratio() >= RETREAT_HP_RATIO and dist > CHEST_CAMP_DISTANCE:
		return to / dist * CAMP_PULL_WEIGHT
	return Vector2.ZERO


func _totem_pull(totem: DefendTotem, pos: Vector2) -> Vector2:
	var to := Vector2(totem.global_position.x, totem.global_position.z) - pos
	var dist := to.length()
	var limit := DefendTotem.GUARD_RADIUS - TOTEM_PULL_MARGIN
	if dist <= limit or dist < 0.001:
		return Vector2.ZERO
	return to / dist * minf(TOTEM_PULL_BASE + (dist - limit) * TOTEM_PULL_SLOPE, TOTEM_PULL_MAX)


## The nearest living priority target (Cultist Acolyte) whose centre is within [param reach] m of
## [param pos] (XZ); null when there is none. Allocation-free when no Acolyte is alive.
static func priority_enemy(tree: SceneTree, pos: Vector3, reach: float) -> Enemy:
	if tree == null or tree.get_node_count_in_group(&"priority_targets") == 0:
		return null
	var best: Enemy = null
	var best_d := reach * reach
	for node in tree.get_nodes_in_group(&"priority_targets"):
		var e := node as Enemy
		if e == null or not e.is_inside_tree() or not e.is_priority_target():
			continue
		var dx := e.global_position.x - pos.x
		var dz := e.global_position.z - pos.z
		var d := dx * dx + dz * dz
		if d <= best_d and (best == null or d < best_d):
			best_d = d
			best = e
	return best


## Whether the bot sidesteps [param golem]'s current hook (one roll per golem and hook).
func _wants_dodge(golem: Enemy) -> bool:
	var id := golem.get_instance_id()
	if not _hook_serials.has(id) or _hook_serials[id] != golem.hook_serial:
		_hook_serials[id] = golem.hook_serial
		_hook_dodges[id] = _rng.randf() < HOOK_DODGE_CHANCE
	return _hook_dodges[id]


## Forgets the decisions of golems that are gone or no longer aiming the hook they were made for.
func _prune_hook_decisions() -> void:
	for id: int in _hook_serials.keys():
		var golem := instance_from_id(id) as Enemy
		if golem == null or golem.ai_state != Enemy.AiState.HOOK \
				or golem.hook_serial != _hook_serials[id]:
			_hook_serials.erase(id)
			_hook_dodges.erase(id)


static func _is_alive(node: Node) -> bool:
	return not node.has_method(&"is_alive") or bool(node.call(&"is_alive"))


## Attack reach (m) of the body's main-hand weapon; KITE_DISTANCE when unknown.
func _reach() -> float:
	var weapon := body.get(&"main_hand") as WeaponData
	if weapon == null or not weapon.attacks():
		return KITE_DISTANCE
	return weapon.attack_range


## True when a rescue run to [param ghost] looks survivable: the rescuer is healthy enough
## and few enemies stand near the ghost. [param enemies] holds (pos - enemy position).
func _safe_rescue(pos: Vector2, ghost: Vector2, enemies: Array[Vector2]) -> bool:
	if _hp_ratio() < RESCUE_MIN_HP_RATIO:
		return false
	var threats := 0
	for d in enemies:
		if (pos - d).distance_to(ghost) < RESCUE_THREAT_RADIUS:
			threats += 1
			if threats > RESCUE_MAX_THREATS:
				return false
	return true


## The body's HP / max HP (1 when unknown).
func _hp_ratio() -> float:
	var hp: Variant = body.get(&"hp")
	if not body.has_method(&"max_hp") or typeof(hp) != TYPE_FLOAT:
		return 1.0
	var m := float(body.call(&"max_hp"))
	return float(hp) / m if m > 0.0 else 1.0


## Pushes away from the walls of Arena.current (stronger the closer they are).
func _wall_push(pos: Vector2) -> Vector2:
	var arena := Arena.current
	if arena == null or not is_instance_valid(arena):
		return Vector2.ZERO
	var b := arena.get_bounds()
	var push := Vector2.ZERO
	push.x += maxf(0.0, WALL_AVOID_DISTANCE - (pos.x - b.position.x))
	push.x -= maxf(0.0, WALL_AVOID_DISTANCE - (b.end.x - pos.x))
	push.y += maxf(0.0, WALL_AVOID_DISTANCE - (pos.y - b.position.y))
	push.y -= maxf(0.0, WALL_AVOID_DISTANCE - (b.end.y - pos.y))
	return push


## Pulls towards the centre of the living teammates when the bot strays too far.
func _cohesion(pos: Vector2) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for node in body.get_tree().get_nodes_in_group(&"players"):
		var n := node as Node3D
		if n == null or n == body or not n.is_inside_tree() or not _is_alive(n):
			continue
		sum += Vector2(n.global_position.x, n.global_position.z)
		count += 1
	if count == 0:
		return Vector2.ZERO
	var to := sum / float(count) - pos
	var dist := to.length()
	if dist <= COHESION_DISTANCE:
		return Vector2.ZERO
	return to / dist * minf((dist - COHESION_DISTANCE) * 0.15, 1.0)


## Position (XZ) of the nearest other player that is alive ([param want_alive]) or downed,
## within [param max_range] m; Vector2.INF when there is none.
func _nearest_teammate(pos: Vector2, want_alive: bool, max_range: float) -> Vector2:
	var best := Vector2.INF
	var best_dist := max_range
	for node in body.get_tree().get_nodes_in_group(&"players"):
		var n := node as Node3D
		if n == null or n == body or not n.is_inside_tree() or _is_alive(n) != want_alive:
			continue
		var p := Vector2(n.global_position.x, n.global_position.z)
		var dist := p.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = p
	return best


## Ground position (XZ) of Arena.current's Spirit Healer; Vector2.INF when there is none.
static func _healer_point() -> Vector2:
	var arena := Arena.current
	if arena == null or not is_instance_valid(arena):
		return Vector2.INF
	var healer := arena.spirit_healer
	if healer == null or not is_instance_valid(healer) or not healer.is_inside_tree():
		return Vector2.INF
	return Vector2(healer.global_position.x, healer.global_position.z)
