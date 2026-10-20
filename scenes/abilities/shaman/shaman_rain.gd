class_name ShamanRain
extends AbilityArea
## The ground area of Soothing Downpour (M8): every [member tick_interval] seconds each living hero inside
## heals [member heal] + [member heal_max_hp_pct] % of its Max HP (+ Spell Power x heal_sp_scale per second of
## the tick, x power, x the caster's Healing Done: [method ShamanKit.heal_amount]), credited to the caster's
## healing meter. Thundercloud: with [member strike_damage] > 0 the lightning also hits every enemy inside on
## every tick (ability damage; not Storm Echo eligible). The area may follow a hero ([member follow]).

var heal := 0.3
var heal_max_hp_pct := 2.0
var heal_sp_scale := 0.5
## The rank multiplier of the heal (and of strike_damage, which is baked already).
var power := 1.0
## Nature damage per tick to every enemy inside (0 = a plain rain).
var strike_damage := 0.0
## Heals given and enemies struck so far (tests).
var heals_given := 0
var strikes := 0


## Opens the rain at [param center] (the same rules as [method AbilityArea.spawn]). Not in the tree without
## a parent.
static func open(p_owner: Player, center: Vector3, p_radius: float, p_duration: float, p_color: Color) -> ShamanRain:
	var area := ShamanRain.new()
	area.owner_player = p_owner
	area.radius = maxf(0.3, p_radius * (1.0 + (p_owner.stats.get_raw(Stats.AREA_SIZE) / 100.0 if p_owner != null else 0.0)))
	area.duration = p_duration
	area.color = p_color
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent == null:
		return area
	parent.add_child(area)
	area.global_position = Vector3(center.x, 0.0, center.z)
	return area


func _ready() -> void:
	super._ready()
	ShamanAreaFx.attach(self, ShamanAreaFx.Kind.RAIN)


func _tick() -> void:
	if not is_inside_tree() or owner_player == null or not is_instance_valid(owner_player):
		return
	var tree := get_tree()
	var centre := global_position
	var slot := Player.slot_index_of(owner_player)
	for hero in ShamanKit.heroes_around(tree, centre, radius):
		var amount := ShamanKit.heal_amount(owner_player, hero, heal, heal_max_hp_pct, heal_sp_scale * tick_interval, power)
		if amount > 0.0 and ShamanKit.is_hurt(hero):
			heals_given += 1
		hero.heal(amount, slot)
	if strike_damage > 0.0 and owner_player.procs != null:
		for e in ShamanKit.enemies_around(tree, centre, radius):
			if owner_player.procs.deal_raw(e, strike_damage, ShamanKit.NATURE, true, &"ability") > 0.0:
				strikes += 1
				ProcVfx.beam(Vector3(e.global_position.x, 5.0, e.global_position.z), ShamanKit.chest(e), ShamanKit.LIGHTNING_COLOR)
