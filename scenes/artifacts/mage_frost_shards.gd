class_name ArtifactMageFrostShards
extends TalentEffect
## Shatterfrost – property 2 of the Staff of the Frostwyrm (GDD 5.5): an enemy the Mage kills
## while it is slowed or frozen bursts into frost shards that slow every enemy within radius
## (3) m by slow (40) % for duration (2) s. "Slowed" is Enemy.is_slowed (a Blizzard, a Frost
## Nova, the ghost slow ...), "frozen" is MageFrozen.is_frozen (the ice of a freeze); the corpse
## is still in the tree when the kill is reported, so both read true. No RNG, no damage.
##
## Params (not rank-scaled): radius (m), slow (%), duration (s).

const SHARD_COLOR := Color(0.62, 0.88, 1.0)

## Bursts so far (tests).
var bursts := 0


func on_kill(enemy: Node3D) -> void:
	var e := enemy as Enemy
	if e == null or not is_instance_valid(e) or player == null or not is_instance_valid(player):
		return
	if not e.is_slowed() and not MageFrozen.is_frozen(e):
		return
	burst(e.global_position if e.is_inside_tree() else e.position)


## The shards at [param center]: every living enemy near it is slowed.
func burst(center: Vector3) -> void:
	if not player.is_inside_tree():
		return
	var radius := maxf(0.5, num("radius", 3.0))
	var slow := num("slow", 40.0)
	var duration := num("duration", 2.0)
	bursts += 1
	for e in MageSpell.enemies_in(player.get_tree(), center, radius):
		e.apply_slow(slow, duration)
	Vfx.explosion(Vector3(center.x, 0.2, center.z), radius * 0.6, SHARD_COLOR)
	Vfx.hit_spark(Vector3(center.x, 0.7, center.z), SHARD_COLOR)


func describe() -> String:
	return "Enemies killed while slowed or frozen burst into frost shards."
