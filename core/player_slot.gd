class_name PlayerSlot
extends RefCounted
## One joined local player: which device drives it, which class it plays, its colour.

var index: int
var input: PlayerInput
var class_data: ClassData
var color: Color
## Lobby "ready" flag; also reused by the between-wave screen.
var ready := false
## The spawned Player node during a run (null outside of a run).
var player: Node3D
## The companion picked in the lobby (an id of ClassData.companion_choices; &"" = none picked).
## Read the effective choice through [method companion_id]: it stays valid when the class changes.
var companion: StringName = &""
## M9 meta selections of the lobby (the main profile's Seasonings, Heirloom and Wardrobe looks), empty until a
## later package fills them: the Seasonings picked for this hero (ids), the Heirloom it starts with (&"" = none) and
## the look override per visible armour slot (Profile.LOOK_SLOTS -> look id). The hero receives them when the run
## starts (Player.seasonings / heirloom_id / look_overrides); the lobby keeps them per class (Meta.apply_loadout).
var seasonings: Array[StringName] = []
var heirloom: StringName = &""
var looks: Dictionary[StringName, StringName] = {}
## --- Wardrobe (M9) --- The cosmetics picked for this hero (Profile.COSMETIC_KEYS -> CosmeticData id: "tabard", "hat",
## "glow", "dye"); a missing key = none. Cosmetic only, like [member looks]; the hero receives it as Player.cosmetic_overrides.
var cosmetics: Dictionary[StringName, StringName] = {}
## M9 LEVELS: the hero starts with its class's alternative weapon (Class Level 12, ClassPathData) instead of the
## standard one. The lobby toggles it ([method Lobby.toggle_alt_weapon]); Main drops it for a class that has not
## unlocked it (Meta.enforce_alt_weapons).
var alt_weapon := false


func _init(p_index: int, p_input: PlayerInput, p_color: Color) -> void:
	index = p_index
	input = p_input
	color = p_color


func label() -> String:
	return "P%d" % (index + 1)


func is_bot() -> bool:
	return input is ScriptedInput


## The companion this player gets (Player.companion_id): [member companion] when the class offers
## it, else the class's first choice; &"" for a class without companions.
func companion_id() -> StringName:
	return class_data.pick_companion(companion) if class_data != null else &""


## Picks the next ([param step] 1) or previous (-1) companion of the class (wraps) and returns it;
## &"" and no change for a class without companions.
func cycle_companion(step: int = 1) -> StringName:
	if class_data == null or class_data.companion_choices.is_empty():
		return &""
	var choices := class_data.companion_choices
	var at := choices.find(companion_id())
	companion = choices[wrapi(at + step, 0, choices.size())]
	return companion


## The meta selections as one dictionary ({"seasonings", "heirloom", "looks"}, see [method Profile.loadout]).
func meta_loadout() -> Dictionary:
	var l := {"seasonings": seasonings, "heirloom": heirloom, "looks": looks, "alt_weapon": alt_weapon}
	l.merge(cosmetics)  # (Wardrobe: "tabard" / "hat" / "glow" / "dye")
	return Profile.normalize_loadout(l)


## Sets the meta selections from [param loadout] (the shape of [method meta_loadout]); missing keys clear them.
func set_meta_loadout(loadout: Dictionary) -> void:
	var l := Profile.normalize_loadout(loadout)
	seasonings = l["seasonings"]
	heirloom = l["heirloom"]
	looks = l["looks"]
	alt_weapon = l["alt_weapon"]
	cosmetics = {}  # (Wardrobe: only the picked ones are kept)
	for key in Profile.COSMETIC_KEYS:
		if l[key] != &"":
			cosmetics[key] = l[key]


## True when a meta selection is made (never by default, nor in an automated run).
func has_meta_selection() -> bool:
	return not (seasonings.is_empty() and heirloom == &"" and looks.is_empty() and not alt_weapon and cosmetics.is_empty())
