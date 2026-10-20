class_name ShamanMastery
extends MasteryEffect
## Shaman class hooks (M8, design_shaman.md): the Mastery "Storm Echo", the Surge gain of every cast and
## the hubs the Stormweaving talents plug into.
##
## Surge: +5 per weapon hit is the resource's own rule (ResourceData.gain_on_hit); the +5 per ability
## cast has no ResourceData field, so [method tick] connects the runner's ability_cast signal once
## (the runner does not exist yet when setup() runs) and [method _on_ability_cast] gives the cast the
## same gain ([method ClassResource.on_weapon_hit]: the Surge gain incl. talent bonuses, and the decay
## timer restarts – casting without melee never decays). It fires after the cast was paid.
##
## Storm Echo (pseudo ability id [constant ECHO_MOD_ID], numbers [constant ECHO_BASE] merged with
## player.ability_mods and cached until the bonuses / equipment change): every direct hit of a Shaman
## ability that is Fire or has the lightning tag ([method ShamanKit.strike] with echo = true) rolls ONE
## RunState.rng draw (only when the chance is above 0): chance = Mastery x chance_per_mastery, at most
## max_chance. On success the target takes echo_pct % of the hit once more ([method roll_echo]); an
## echo never echoes.
##
## Elemental Surge hub (the Stormweaving capstone's script feeds it, neutral until then):
## [method grant_empower] sets the charges, [method take_empower] (ShamanKit.empower) consumes one.
## Charges end with the wave and when the Shaman goes down.

const ECHO_MOD_ID := &"shaman_echo"
## Storm Echo before talent / item mods.
const ECHO_BASE := {
	## % echo chance per point of Mastery.
	"chance_per_mastery": 1.5,
	## % of the hit the echo deals.
	"echo_pct": 50.0,
	## The chance never exceeds this %.
	"max_chance": 60.0,
}

## Echoes dealt so far (tests, stats).
var echoes := 0
## The last Forking Bolt: {"point": Vector3, "damage": float} (ShamanKit.last_fork).
var last_fork: Dictionary = {}
## Elemental Surge: damaging casts still empowered and the bonus (%) they get.
var empower_charges := 0
var empower_pct := 0.0

var _runner: AbilityRunner
var _bonuses: PlayerBonuses
var _equipment: Equipment
## echo_params() result (read-only), dropped when the bonuses / equipment change.
var _echo_params: Dictionary = {}


func tick(_delta: float) -> void:
	_hook_runner()
	if player != null and player.downed and empower_charges > 0:
		clear_empower()


func begin_wave() -> void:
	clear_empower()
	last_fork = {}


func end_wave() -> void:
	clear_empower()


func teardown() -> void:
	if _runner != null and is_instance_valid(_runner) and _runner.ability_cast.is_connected(_on_ability_cast):
		_runner.ability_cast.disconnect(_on_ability_cast)
	_runner = null
	if _bonuses != null and is_instance_valid(_bonuses) and _bonuses.changed.is_connected(invalidate_echo_params):
		_bonuses.changed.disconnect(invalidate_echo_params)
	_bonuses = null
	if _equipment != null and is_instance_valid(_equipment) and _equipment.changed.is_connected(invalidate_echo_params):
		_equipment.changed.disconnect(invalidate_echo_params)
	_equipment = null
	invalidate_echo_params()
	clear_empower()


func describe() -> String:
	return "Storm Echo: %s%% echo" % _fmt(echo_chance())


# --- Surge -------------------------------------------------------------------------------------

func _on_ability_cast(_slot_index: int, _ability: AbilityData) -> void:
	var res := ShamanKit.surge(player)
	if res != null:
		res.on_weapon_hit(false)


# --- Storm Echo --------------------------------------------------------------------------------

## The Storm Echo numbers: [constant ECHO_BASE] with the talent / item mods of [constant ECHO_MOD_ID].
func echo_params() -> Dictionary:
	_hook_signals()
	if not _echo_params.is_empty():
		return _echo_params
	var mods: Dictionary = player.ability_mods(ECHO_MOD_ID) if player != null else {}
	var out := AbilityRunner.apply_mods(ECHO_BASE, mods) if not mods.is_empty() else ECHO_BASE.duplicate()
	out.make_read_only()
	_echo_params = out
	return out


## The chance (0..max_chance, %) that an eligible hit echoes: Mastery x chance_per_mastery.
func echo_chance() -> float:
	var p := echo_params()
	return clampf(mastery() * float(p.get("chance_per_mastery", 0.0)), 0.0, float(p.get("max_chance", 0.0)))


## The Storm Echo roll of one eligible hit of [param amount] (before the outgoing multipliers) on
## [param target]: one RunState.rng draw while the chance is above 0; on success the target takes
## echo_pct % of it once more (no target bonuses, never echoes). Returns the echo's damage dealt.
func roll_echo(target: Enemy, amount: float, school: StringName) -> float:
	if player == null or player.procs == null or amount <= 0.0:
		return 0.0
	var chance := echo_chance()
	if chance <= 0.0 or RunState.rng.randf() * 100.0 >= chance:
		return 0.0
	if not ShamanKit.is_live(target):
		return 0.0
	var pct := maxf(0.0, float(echo_params().get("echo_pct", 0.0)))
	echoes += 1
	var at := target.global_position + Vector3.UP * WeaponRunner.DAMAGE_TEXT_HEIGHT
	var dealt := player.procs.deal_raw(target, amount * pct / 100.0, school, false, &"ability")
	Vfx.hit_spark(ShamanKit.chest(target), ShamanKit.LIGHTNING_COLOR if school != ShamanKit.FIRE else ShamanKit.FIRE_COLOR)
	Vfx.floating_text(at + Vector3.UP * 0.35, "Echo", ShamanKit.TEXT_COLOR, 0.7, 1.0)
	return dealt


func invalidate_echo_params() -> void:
	_echo_params = {}


# --- Elemental Surge hub ------------------------------------------------------------------------

## Sets the empowered casts to [param casts] (never adds) with [param pct] % more damage each.
func grant_empower(casts: int, pct: float) -> void:
	empower_charges = maxi(0, casts)
	empower_pct = maxf(0.0, pct)


## Consumes one charge: the multiplier (1 + pct / 100) of the cast that asked, 1.0 without a charge.
func take_empower() -> float:
	if empower_charges <= 0:
		return 1.0
	empower_charges -= 1
	return 1.0 + empower_pct / 100.0


func clear_empower() -> void:
	empower_charges = 0
	empower_pct = 0.0


# --- Wiring ------------------------------------------------------------------------------------

func _hook_runner() -> void:
	if player == null or player.abilities == null:
		return
	if _runner != player.abilities:
		_runner = player.abilities
		if not _runner.ability_cast.is_connected(_on_ability_cast):
			_runner.ability_cast.connect(_on_ability_cast)
	_hook_signals()


## Connects to the player's PlayerBonuses / Equipment (neither exists yet when setup() runs): talent /
## set / item changes drop the cached Storm Echo numbers.
func _hook_signals() -> void:
	if player == null:
		return
	if player.bonuses != null and _bonuses != player.bonuses:
		if _bonuses != null and is_instance_valid(_bonuses) and _bonuses.changed.is_connected(invalidate_echo_params):
			_bonuses.changed.disconnect(invalidate_echo_params)
		_bonuses = player.bonuses
		_bonuses.changed.connect(invalidate_echo_params)
		invalidate_echo_params()
	if player.equipment != null and _equipment != player.equipment:
		if _equipment != null and is_instance_valid(_equipment) and _equipment.changed.is_connected(invalidate_echo_params):
			_equipment.changed.disconnect(invalidate_echo_params)
		_equipment = player.equipment
		_equipment.changed.connect(invalidate_echo_params)
		invalidate_echo_params()


static func _fmt(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else "%.1f" % v
