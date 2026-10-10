class_name ResourceData
extends Resource
## A class resource (GDD 3): Rage, Mana, Energy, Holy Power, Soul Shards, Combo Points.
## Instances live in res://data/resources/. Generation rules are data; classes with special
## rules add them in their MasteryEffect / AbilityEffects via ClassResource.add().

enum Display { BAR, PIPS }

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE
@export var display: Display = Display.BAR
@export var max_value: float = 100.0
## Value at the start of every wave.
@export var start_value: float = 0.0
## Per second, always (Mana, Energy). Scaled by Haste for Mana / Energy-like resources via
## regen_uses_haste, and by the Resource Regen stat.
@export var regen_per_second: float = 0.0
@export var regen_uses_haste: bool = false
## Per second after [member decay_delay] seconds without dealing or taking a hit (Rage).
@export var decay_per_second: float = 0.0
@export var decay_delay: float = 2.0
## Gains (all scaled by the Resource Regen stat).
@export var gain_on_hit: float = 0.0
@export var gain_on_damage_taken: float = 0.0
@export var gain_on_crit: float = 0.0
## +[member gain_per_hits_amount] every [member gain_per_hits] weapon hits (Holy Power: 5 / 1).
@export var gain_per_hits: int = 0
@export var gain_per_hits_amount: float = 1.0
## +[member gain_per_kills_amount] every [member gain_per_kills] kills (Soul Shards: 12 / 1).
@export var gain_per_kills: int = 0
@export var gain_per_kills_amount: float = 1.0
