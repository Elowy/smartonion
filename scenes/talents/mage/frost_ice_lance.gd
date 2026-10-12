class_name MageFrostIceLance
extends TalentEffect
## Ice Lance – the Mage Frost capstone (GDD 7.5, talents_mage.md 3.3): frozen enemies take
## critical damage from everything the Mage does.
##
## "Frozen" = the enemy carries live [MageFrozen] ice of ANY Mage (Frost Nova, Frost Blink,
## Shattering Barrier, Deep Freeze, Flash Freeze, an allied Mage's freezes), checked with the
## O(1) [method MageFrozen.is_frozen] – plain stuns do not count (Chilled to the Bone's job).
##   [method crit_forced]: every weapon hit on a frozen enemy crits (wand / staff / melee,
##     extra attacks; the crits feed Ignite and every on-crit effect). It does not consume
##     Player.forced_crits; null → false.
##   [method damage_mult]: hits that cannot crit – the sources &"ability", &"dot" and &"pet",
##     every school (Blizzard ticks, Frost Nova's Shatter while the ice is still on, burns,
##     Living Bomb, Spirit Wolf) – deal spell_mult + Critical Damage % times their damage to
##     a frozen enemy (the crit multiplier, at least 1). Weapon hits get their x2 from the
##     forced crit, and &"proc" damage is derived from a weapon hit whose base amount already
##     carries it (vocabulary §3.6), so neither is multiplied again.
## Hot path: one dictionary lookup; the stat is read only for frozen targets. Optional look: a
## frosty spark on a crit against a frozen enemy, at most every fx_icd s. No RNG, no state to
## clean up besides the VFX timer. Passive for bots.
##
## Params (not rank-scaled; capstone, rank 1): spell_mult, fx_icd (s).

## Frosty sparks shown (tests).
var sparks := 0

var _spell_mult := 2.0
var _fx_icd := 0.15
var _fx_left := 0.0


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_spell_mult = maxf(1.0, num("spell_mult", 2.0))
	_fx_icd = maxf(0.0, num("fx_icd", 0.15))


func crit_forced(target: Node3D) -> bool:
	return MageFrozen.is_frozen(target)


func damage_mult(target: Node3D, _school: StringName, source: StringName) -> float:
	if source == &"weapon" or source == &"proc" or not MageFrozen.is_frozen(target):
		return 1.0
	return crit_mult()


## The multiplier for non-weapon damage to frozen enemies: spell_mult + Critical Damage %.
func crit_mult() -> float:
	var bonus := player.stats.get_raw(Stats.CRIT_DAMAGE) / 100.0 if player != null and player.stats != null else 0.0
	return maxf(1.0, _spell_mult + bonus)


func on_hit(target: Node3D, _damage: float, is_crit: bool, _first: bool) -> void:
	if not is_crit or _fx_left > 0.0 or not MageFrozen.is_frozen(target) or not target.is_inside_tree():
		return
	_fx_left = _fx_icd
	sparks += 1
	Vfx.hit_spark(target.global_position + Vector3.UP * Enemy.BODY_CENTER_HEIGHT, MageSpell.FROST_COLOR)


func tick(delta: float) -> void:
	if _fx_left > 0.0:
		_fx_left -= delta


func begin_wave() -> void:
	_fx_left = 0.0


func teardown() -> void:
	_fx_left = 0.0


func describe() -> String:
	return "Ice Lance: frozen enemies take x%s from your spells and burns" % TalentData.format_number(crit_mult())
