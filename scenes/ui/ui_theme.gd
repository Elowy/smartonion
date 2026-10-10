class_name UiTheme
extends RefCounted
## STUB – owned by the "ui" module.
## WoW-like UI look (GDD 12): dark stone / leather panels with gold borders, parchment
## tooltips, item-quality colours. Built in code so it needs no imported assets.

const GOLD := Color(1.0, 0.82, 0.25)
const TEXT := Color(0.95, 0.92, 0.85)
const TEXT_DIM := Color(0.7, 0.66, 0.6)
const HP_GREEN := Color(0.2, 0.8, 0.25)
const XP_PURPLE := Color(0.58, 0.3, 0.85)
## WoW item quality colours, indexed by rarity (0 Common .. 5 Artifact).
const RARITY_COLORS: Array[Color] = [
	Color(1, 1, 1), Color(0.12, 1.0, 0.0), Color(0.0, 0.44, 0.87),
	Color(0.64, 0.21, 0.93), Color(1.0, 0.5, 0.0), Color(0.9, 0.8, 0.5),
]
const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact"]


static func get_theme() -> Theme:
	return Theme.new()
