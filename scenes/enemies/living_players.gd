class_name LivingPlayers
extends RefCounted
## Shared per-tick snapshot of the living players for the hot per-entity loops – enemy
## targeting / contact damage and idle pickups looking for a collector – no autoload, only
## static state. Instead of every enemy and every pickup walking the players and calling into
## them each tick, the first user of a tick copies the living players' positions and pickup
## ranges into packed arrays that everybody reads.
##
## Rebuilt when the physics frame changes, when the players group changes (also after
## [method Enemy.invalidate_player_cache]), after [method mark_dirty] (a player was hit and may
## have gone down – enemy contact hits and enemy projectiles call it) and when a consumer asks
## again for the snapshot it already used (a new tick within the same physics frame: nodes
## stepped by hand in tests). Users re-check the player they act on
## ([method Enemy.is_living_player]) before hurting it or flying to it.
##
## Read-only for users: [member count] entries in [member players], [member pos_x],
## [member pos_z] and [member pickup_range_sq]. The arrays are replaced (not modified) by a
## rebuild, so a local reference stays valid while a loop calls into players.

static var serial := 0
static var count := 0
static var players: Array[Player] = []
static var pos_x := PackedFloat64Array()
static var pos_z := PackedFloat64Array()
## Squared [method StatBlock.pickup_range] of each player.
static var pickup_range_sq := PackedFloat64Array()

static var _frame := -1
static var _group_count := -1
static var _dirty := true


## The next [method refresh] rebuilds the snapshot.
static func mark_dirty() -> void:
	_dirty = true


## Makes the snapshot current for [param consumer] (a node in the tree) that last used
## snapshot [param last_serial] (-1 if never) and returns the serial it should remember.
static func refresh(consumer: Node, last_serial: int) -> int:
	var frame := Engine.get_physics_frames()
	if not _dirty and frame == _frame and last_serial != serial:
		return serial  # fast path: already built this tick
	var tree := consumer.get_tree() if consumer != null else null
	if tree == null:
		if count > 0:
			_clear()
		return serial
	var group_count := tree.get_node_count_in_group(&"players")
	if _dirty or frame != _frame or group_count != _group_count or last_serial == serial:
		_rebuild(tree, frame, group_count)
	return serial


static func _rebuild(tree: SceneTree, frame: int, group_count: int) -> void:
	serial += 1
	_frame = frame
	_group_count = group_count
	_dirty = false
	var list: Array[Player] = []
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var ranges := PackedFloat64Array()
	for p in Enemy.cached_players(tree):
		if not Enemy.is_living_player(p):
			continue
		var pos := p.global_position
		var reach := p.stats.pickup_range() if p.stats != null else 0.0
		list.append(p)
		xs.append(pos.x)
		zs.append(pos.z)
		ranges.append(reach * reach)
	players = list
	pos_x = xs
	pos_z = zs
	pickup_range_sq = ranges
	count = list.size()


static func _clear() -> void:
	serial += 1
	_frame = -1
	_group_count = -1
	players = []
	pos_x = PackedFloat64Array()
	pos_z = PackedFloat64Array()
	pickup_range_sq = PackedFloat64Array()
	count = 0
