class_name RogueSubtletyShadowDance
extends TalentEffect
## Shadow Dance – the Rogue Subtlety capstone (GDD 7.5, talents_rogue.md 3.4): a real Vanish
## cast (TalentEffect.on_cast with the vanish ability – not Cheat Death's Shadow Escape or
## Killing Spree's Untouchable shroud) opens a window of duration (5) s in which every weapon
## hit of the Rogue is a critical strike: [method crit_forced] answers true for any target
## (null included), which WeaponRunner asks for auto-attacks, ripostes, counters and extra
## attacks, and the Rogue kit for Fan of Knives knives, Shuriken Toss stars, Killing Spree and
## the Shadowstep Ambush (RogueUtil.bonus_crit). Ability damage never crits. The other living
## heroes within ally_radius (8) m at the cast gain ally_crit (10) % crit for the window (a
## stat source per Rogue, "rogue_subtlety_shadow_dance:<slot>").
## A window opens at most once every icd (12) s (GDD deviation: Vanish cooldown items and
## Restless Blades would make it near-permanent). A banked guaranteed crit (Vanish,
## Premeditation, Find Weakness) is still used first by WeaponRunner inside the window – known
## redundancy, accepted (judge B15).
## Ends (ally sources removed, glow freed) when the window runs out, the Rogue goes down, at
## wave start / end and on teardown. No RNG. Bots: the Subtlety talents' Vanish auto_offense
## makes bots open windows in packs.
##
## Params (not rank-scaled; capstone): duration, icd, ally_radius, ally_crit.

const KEY_PREFIX := "rogue_subtlety_shadow_dance"
const TEXT := "Dusk Waltz!"
const GLOW_RADIUS := 1.3
const GLOW_ALPHA := 0.45
## The ground glow pulses this many times per second between GLOW_ALPHA x (1 - GLOW_PULSE)
## and GLOW_ALPHA.
const GLOW_RATE := 2.0
const GLOW_PULSE := 0.4

## Windows opened (tests).
var dances := 0

var _duration := 5.0
var _icd := 12.0
var _ally_radius := 8.0
var _ally_crit := 10.0
var _ally_key := StringName(KEY_PREFIX)
## Seconds left of the window (0 = closed) and until the next one may open.
var _left := 0.0
var _ready_in := 0.0
var _allies: Array[Player] = []
var _glow: MeshInstance3D
var _glow_time := 0.0


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_duration = maxf(0.0, num("duration", 5.0))
	_icd = maxf(0.0, num("icd", 12.0))
	_ally_radius = maxf(0.0, num("ally_radius", 8.0))
	_ally_crit = num("ally_crit", 10.0)
	var index := player.slot.index if player != null and player.slot != null else 0
	_ally_key = StringName("%s:%d" % [KEY_PREFIX, index])


## Hot path: one compare, no allocation.
func crit_forced(_target: Node3D) -> bool:
	return _left > 0.0


func on_cast(_slot_index: int, ability: AbilityData) -> void:
	if ability == null or ability.id != &"vanish" or _ready_in > 0.0 or _duration <= 0.0:
		return
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return
	_end()
	_left = _duration
	_ready_in = _icd
	dances += 1
	_buff_allies()
	_show()


func tick(delta: float) -> void:
	_ready_in = maxf(0.0, _ready_in - delta)
	if _left <= 0.0:
		return
	if player == null or not is_instance_valid(player) or not player.is_alive():
		_end()
		return
	_left -= delta
	if _left <= 0.0:
		_end()
		return
	if _glow != null and is_instance_valid(_glow):
		_glow_time += delta
		var pulse := 1.0 - GLOW_PULSE * (0.5 + 0.5 * sin(_glow_time * TAU * GLOW_RATE))
		RogueVfx.set_ring_alpha(_glow, RogueVfx.SHADOW_COLOR, GLOW_ALPHA * pulse)


func begin_wave() -> void:
	_end()
	_ready_in = 0.0


func end_wave() -> void:
	_end()


func teardown() -> void:
	_end()


func describe() -> String:
	if _left > 0.0:
		return "Dusk Waltz: %.1f s" % _left
	if _ready_in > 0.0:
		return "Dusk Waltz: ready in %d s" % ceili(_ready_in)
	return "Dusk Waltz: ready"


## True while the window is open (tests, UI).
func is_dancing() -> bool:
	return _left > 0.0


## Seconds until a Vanish may open the next window (0 = ready).
func ready_in() -> float:
	return _ready_in


## Heroes given the crit for the current window (tests).
func buffed_allies() -> Array[Player]:
	return _allies.duplicate()


func _buff_allies() -> void:
	if not player.is_inside_tree():
		return
	var here := player.global_position
	var r_sq := _ally_radius * _ally_radius
	for node in player.get_tree().get_nodes_in_group(&"players"):
		var ally := node as Player
		if ally == null or ally == player or not ally.is_inside_tree() or not ally.is_alive():
			continue
		var d := ally.global_position - here
		if d.x * d.x + d.z * d.z > r_sq:
			continue
		ally.stats.set_source(_ally_key, {Stats.CRIT: _ally_crit})
		_allies.append(ally)
		Vfx.hit_spark(ally.get_chest_position(), RogueVfx.SHADOW_COLOR)


func _show() -> void:
	if not player.is_inside_tree():
		return
	var feet := player.global_position
	Vfx.explosion(Vector3(feet.x, 0.1, feet.z), _ally_radius, RogueVfx.SHADOW_COLOR)
	Vfx.floating_text(player.self_text_position(1.0), TEXT, RogueVfx.SHADOW_COLOR, Player.SELF_TEXT_SIZE, 1.0)
	_glow = RogueVfx.ring(player, RogueVfx.SHADOW_COLOR, GLOW_RADIUS, GLOW_ALPHA)
	_glow_time = 0.0
	if _glow != null:
		_glow.name = "ShadowDanceGlow"


func _end() -> void:
	_left = 0.0
	for ally in _allies:
		if is_instance_valid(ally):
			ally.stats.remove_source(_ally_key)
	_allies.clear()
	if _glow != null and is_instance_valid(_glow):
		_glow.queue_free()
	_glow = null
