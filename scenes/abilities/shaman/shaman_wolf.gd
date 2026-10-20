class_name ShamanWolf
extends GeneralSpiritWolfPet
## One ancestral wolf of the Shaman's Spirit Pack (M8): the Phantom Wolf's pet ([GeneralSpiritWolfPet]: hunts the
## nearest enemy around its master, bites for bite_pct % of the weapon hit as Nature PET damage through
## deal_raw(..., &"pet"), cannot be hurt, hides while the master is downed, dismissed with the wave) in a teal
## coat plus the Shaman extras:
##   surge_per_bite  every bite feeds the master that much Surge
##   arc_pct         Thunder Pack: every bite also arcs lightning to another enemy within arc_radius m for this %
##                   of the bite (pet damage)
##   taunt_radius    Pack Guardians: every TAUNT_INTERVAL s enemies within this many m of the wolf chase it for
##                   taunt_duration s (Enemy.apply_taunt)
##   empower         Elemental Surge baked at the cast: the multiplier of every bite and arc
## Params (on top of the Phantom Wolf's): surge_per_bite, arc_pct, arc_radius, taunt_radius, taunt_duration, empower.

## How often the Pack Guardians taunt is refreshed (s).
const TAUNT_INTERVAL := 0.5
const ARC_COLOR := Color(0.62, 0.84, 1.0)

var _taunt_left := 0.0
## Taunts applied and arcs landed so far (tests).
var taunts := 0
var arcs := 0


## Summons a wolf for [param p_owner] beside it (not in the tree without a parent).
static func summon(p_owner: Player, p_index: int, p_params: Dictionary, p_life: float,
		p_school: StringName = SCHOOL_DEFAULT) -> ShamanWolf:
	var w := ShamanWolf.new()
	w.name = "AncestralWolf"
	w.owner_player = p_owner
	w.pack_index = p_index
	w.params = p_params.duplicate()
	w.life_left = p_life
	w.school = p_school
	w.model = GeneralWolfModel.new()
	w.model.tint = ShamanKit.WOLF_COLOR
	w.add_child(w.model)
	var parent := WeaponRunner.effects_parent(p_owner)
	if parent != null:
		parent.add_child(w)
		w.snap_to_owner()
		w._puff()
	return w


## Damage of one bite: the Phantom Wolf's, times the Elemental Surge multiplier baked at the cast.
func bite_damage() -> float:
	return super.bite_damage() * float(params.get("empower", 1.0))


func step(delta: float) -> void:
	super.step(delta)
	if dismissed or not _owner_valid() or not is_inside_tree():
		return
	var radius := float(params.get("taunt_radius", 0.0))
	if radius > 0.0 and owner_player.is_inside_tree() and not owner_player.downed:
		_taunt_left -= delta
		if _taunt_left <= 0.0:
			_taunt_left = TAUNT_INTERVAL
			_taunt(radius)


func _bite(e: Enemy) -> void:
	var before := bites
	super._bite(e)
	if bites == before:
		return
	var surge := float(params.get("surge_per_bite", 0.0))
	if surge > 0.0:
		ShamanKit.add_surge(owner_player, surge)
	var arc := float(params.get("arc_pct", 0.0))
	if arc > 0.0:
		_arc(e, arc)


## Thunder Pack: the bite's lightning jumps to the nearest other enemy within arc_radius of the bitten one.
func _arc(from: Enemy, pct: float) -> void:
	if not is_instance_valid(from) or not from.is_inside_tree():
		return
	var radius := float(params.get("arc_radius", 3.0))
	var found := ShamanKit.nearest_enemies(get_tree(), from.global_position, radius, 1, [from])
	if found.is_empty():
		return
	var other := found[0]
	var amount := bite_damage() * pct / 100.0
	ProcVfx.beam(ShamanKit.chest(from), ShamanKit.chest(other), ARC_COLOR)
	if owner_player.procs.deal_raw(other, amount, ShamanKit.NATURE, true, &"pet") > 0.0:
		arcs += 1


## Pack Guardians: enemies near the wolf chase it.
func _taunt(radius: float) -> void:
	var duration := float(params.get("taunt_duration", 1.5))
	for e in ShamanKit.enemies_around(get_tree(), global_position, radius):
		if not (e.is_taunted() and e.taunt_target == self):
			taunts += 1
		e.apply_taunt(self, duration)
