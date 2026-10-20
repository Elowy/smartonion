class_name ArtifactShamanThunderpost
extends TalentEffect
## Thunderpost – property 1 of the Fist of the Ancestors (M8): every Forking Bolt also plants a storm
## totem ([ShamanTotem], element &"storm") where the bolt first struck. For [code]duration[/code] (4) s the post
## zaps the nearest enemy within [code]range[/code] (8) m of itself every [code]interval[/code] (0.8) s for
## [code]damage_pct[/code] (40) % of that bolt's first hit (ShamanKit.last_fork: the amount before the
## outgoing multipliers, Elemental Surge baked in) as Nature ability damage; the zaps do not roll Storm Echo.
## At most [code]max_posts[/code] (2) stand at once, the oldest is freed first; the duration counts the
## Shaman's totem mods (the Totemkeeper's Mail 2-piece bonus) but none of the other Totem Rite numbers (an
## Ancestral Chorus aura belongs to the Rite totems only). Every post vanishes with the wave (begin / end)
## and when the property goes away. No RNG; the posts are no targets.
##
## Params (not rank-scaled): duration (s), interval (s), damage_pct (%), range (m), max_posts.

## Posts planted so far (tests).
var planted := 0
## The standing posts (may hold freed nodes: use [method standing]).
var posts: Array[ShamanTotem] = []


func on_cast(_slot_index: int, ability: AbilityData) -> void:
	if ability == null or ability.id != &"forking_bolt" or player == null or not is_instance_valid(player):
		return
	var fork := ShamanKit.last_fork(player)
	if fork.is_empty():
		return
	plant(fork["point"], float(fork["damage"]))


## Plants one post at [param point] that zaps for damage_pct % of [param bolt_damage]. Null when the arena
## has no place for it.
func plant(point: Vector3, bolt_damage: float) -> ShamanTotem:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return null
	var duration := float(ShamanKit.totem_params(player, {"duration": num("duration", 4.0)}).get("duration", 4.0))
	var post := ShamanTotem.plant(player, &"storm", {
		"storm_interval": num("interval", 0.8),
		"storm_range": num("range", 8.0),
		"storm_damage": maxf(0.0, bolt_damage) * num("damage_pct", 40.0) / 100.0,
	}, point, maxf(0.5, duration))
	if not post.is_inside_tree():
		post.free()
		return null
	standing()
	while posts.size() >= maxi(1, roundi(num("max_posts", 2.0))):
		var oldest: ShamanTotem = posts.pop_front()
		oldest.dismiss(true)
	posts.append(post)
	planted += 1
	return post


## The standing, live posts (freed ones pruned), oldest first.
func standing() -> Array[ShamanTotem]:
	for i in range(posts.size() - 1, -1, -1):
		if not is_instance_valid(posts[i]) or posts[i].dismissed or posts[i].is_queued_for_deletion():
			posts.remove_at(i)
	var out: Array[ShamanTotem] = []
	out.assign(posts)
	return out


func begin_wave() -> void:
	_clear()


func end_wave() -> void:
	_clear()


func teardown() -> void:
	_clear()


func describe() -> String:
	return "Forking Bolt plants a Thunderpost that zaps nearby enemies."


func _clear() -> void:
	for i in posts.size():
		if is_instance_valid(posts[i]):
			posts[i].dismiss(true)
	posts.clear()
