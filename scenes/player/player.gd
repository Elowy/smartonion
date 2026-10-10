class_name Player
extends CharacterBody3D
## STUB – owned by the "player" module.
## A local co-op hero (GDD 1, 2, 3). Group &"players". Collision layer 2 ("players"),
## mask 1 ("world") – enemies do NOT physically block players; they deal contact damage.
## Moves on the XZ plane: input Vector2(x, y) -> world Vector3(x, 0, y).

signal hp_changed(hp: float, max_hp: float)
signal downed_changed(is_downed: bool)

const RADIUS := 0.45
## Height (metres) where projectiles / damage numbers originate.
const CHEST_HEIGHT := 0.7
const REVIVE_RADIUS := 1.8
const REVIVE_TIME := 3.0
const INVULNERABLE_AFTER_HIT := 0.35

var slot: PlayerSlot
var stats := StatBlock.new()
var hp := 10.0
var downed := false
var model: OnionModel
## Last non-zero movement direction (XZ, normalised); weapons fall back to it.
var facing := Vector3.FORWARD


## Creates and configures a player for [param p_slot]. Not yet in the tree.
static func create(p_slot: PlayerSlot) -> Player:
	var p := Player.new()
	p.slot = p_slot
	return p


func max_hp() -> float:
	return stats.max_hp()


func is_alive() -> bool:
	return not downed


## Wave start: living players heal to full; downed players come back at 50% HP (GDD 1).
func begin_wave() -> void:
	pass


## Called by enemies / enemy projectiles. Rolls dodge and block, applies armour etc.
## [param kind] is one of CombatMath.KIND_*.
func take_damage(raw: float, kind: StringName = CombatMath.KIND_MELEE, source: Node3D = null) -> void:
	pass


func heal(amount: float) -> void:
	pass


## Called by this player's weapons after each successful hit (leech etc.).
func on_hit_dealt(damage: float, target: Node3D) -> void:
	pass
