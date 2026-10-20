class_name EventGuards
extends Node3D
## The guards of a mid-wave event (M6b EVENTS): the 4 of the Guarded Chest and the 3 of the Goblin
## Caravan. A child of the event object ([GuardedChest], [CaravanCart]); it moves with it.
##
## A guard is an ordinary [Enemy] (the event spawner builds it), but until the group is alerted it
## STANDS ITS POST instead of hunting the heroes: every RESCAN s each living guard is taunted onto
## its own post marker ([method Enemy.apply_taunt] – the enemies chase a taunt target and stand still
## once they are on it; touching a hero still hurts), so a camp holds its place and a caravan's
## escort walks with the cart. The group is ALERTED – every guard released, for good – when a living
## hero comes within [constant AGGRO_RADIUS] of any guard, when a guard lost HP (a bolt from far away,
## an ability) or when [method alert] is called (the owner was hit). Nothing here draws from an rng.

## Seconds between two looks at the heroes (and the taunt refresh).
const RESCAN := 0.2
## A living hero this close (m) to a guard alerts the group.
const AGGRO_RADIUS := 9.0
## How long one taunt lasts: a little more than RESCAN, so a hiccup does not free a guard.
const POST_TAUNT := 0.5

## Emitted once when the group turns hostile.
signal alerted

var guards: Array[Enemy] = []
var posts: Array[Node3D] = []
var is_alerted := false

var _scan_left := 0.0


## Adds [param guard] (already in the tree or about to be) with a post at [param offset] (local to
## this node). Returns the post marker.
func add_guard(guard: Enemy, offset: Vector3) -> Node3D:
	var post := Node3D.new()
	post.name = "Post%d" % posts.size()
	post.position = offset
	add_child(post)
	guards.append(guard)
	posts.append(post)
	return post


## Builds one guard per entry of [param datas] at wave [param wave]: an [Enemy] with its HP times
## [param hp_mult] and no affix, standing at [param offsets][i] (world axes, from this node's
## position, clamped into the arena) on its own post, added under [param parent] (the arena's entity
## root; the guards need a node inside the tree). With a [param director] they count as spawned this
## wave and are announced through [signal WaveDirector.enemy_spawned]. Returns the guards. Draws from
## RunState.rng only inside Enemy.setup, like every enemy.
func spawn_guards(datas: Array[EnemyData], wave: int, offsets: Array[Vector3], hp_mult: float, parent: Node,
		director: WaveDirector = null) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if parent == null or not is_inside_tree():
		return out
	var here := global_position
	var parent_3d := parent as Node3D
	for i in datas.size():
		var data := datas[i]
		if data == null:
			continue
		var offset := offsets[i] if i < offsets.size() else Vector3.ZERO
		var e := Enemy.create(data, wave)
		e.max_hp *= hp_mult
		e.hp = e.max_hp
		var pos := Vector3(here.x + offset.x, 0.0, here.z + offset.z)
		if Arena.current != null and is_instance_valid(Arena.current):
			pos = Arena.current.clamp_point(pos, data.radius + 0.1)
		# The post is where the guard really stands (the wall may have moved it).
		add_guard(e, global_transform.affine_inverse() * pos)
		if parent_3d != null and parent_3d.is_inside_tree():
			e.position = parent_3d.global_transform.affine_inverse() * pos
		else:
			e.position = pos
		parent.add_child(e)
		e.play_spawn_in()
		out.append(e)
		if director != null and is_instance_valid(director):
			director.spawned_this_wave += 1
			director.enemy_spawned.emit(e)
	return out


## The guards still alive.
func alive() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for g in guards:
		if is_instance_valid(g) and not g.is_dead() and not g.is_queued_for_deletion():
			out.append(g)
	return out


func alive_count() -> int:
	return alive().size()


## Whether every guard is dead (also true without guards).
func all_dead() -> bool:
	return alive_count() == 0


## Turns the group hostile now: every post taunt ends.
func alert() -> void:
	if is_alerted:
		return
	is_alerted = true
	for i in guards.size():
		var g := guards[i]
		if is_instance_valid(g) and not g.is_dead():
			g.release_taunt(posts[i])
	alerted.emit()


func _physics_process(delta: float) -> void:
	if is_alerted:
		return
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = RESCAN
	scan()


## One look: alert the group when a hero is near or a guard was hurt, else keep every living guard
## on its post.
func scan() -> void:
	if is_alerted or not is_inside_tree():
		return
	var heroes := Enemy.living_player_positions(get_tree())
	var reach_sq := AGGRO_RADIUS * AGGRO_RADIUS
	for i in guards.size():
		var g := guards[i]
		if not is_instance_valid(g) or g.is_dead() or not g.is_inside_tree():
			continue
		if g.hp < g.max_hp - 0.0001:
			alert()
			return
		var here := g.global_position
		for h in heroes:
			var dx := h.x - here.x
			var dz := h.z - here.z
			if dx * dx + dz * dz <= reach_sq:
				alert()
				return
	for i in guards.size():
		var g := guards[i]
		if is_instance_valid(g) and not g.is_dead() and g.is_inside_tree():
			g.apply_taunt(posts[i], POST_TAUNT)
