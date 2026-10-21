class_name CosmeticData
extends Resource
## One Wardrobe cosmetic (M9 WARDROBE, design_m9 section 7): a Tabard, a Hat variant, a Glow or a Dye. Instances live in
## res://data/cosmetics/ (loaded by Db into [member Db.cosmetics]); the looks of items are NOT data (they are derived
## from EquipLook, see [Wardrobe]).
##
## The shape of a cosmetic is procedural (OnionArmor builds it, keyed by [member style]); this resource only names it and
## holds its colours. A Dye has no shape: its [member color] tints the Tabard and the Glow of the hero that picks it.
##
## Ownership is the profile's: a cosmetic is locked until the profile owns it (Meta.is_unlocked(&"cosmetic", id)) –
## the level cosmetics come with the Class Level (LEVELS), the others with an achievement, a Dye can also be bought.

const KIND_TABARD := &"tabard"
const KIND_HAT := &"hat"
const KIND_GLOW := &"glow"
const KIND_DYE := &"dye"
## The kinds in the order the Wardrobe lists them (and the keys of a loadout's cosmetic selection).
const KINDS: Array[StringName] = [KIND_TABARD, KIND_HAT, KIND_GLOW, KIND_DYE]

## Permanent id: "cos_<class>_tabard|hat|glow", "cos_gala_tabard", "cos_salt_crystal_glow", "dye_<name>".
@export var id: StringName
@export var display_name: String
## One of [constant KINDS].
@export var kind: StringName = KIND_TABARD
## The class the cosmetic is the level reward of (&"" = an achievement / shop cosmetic). Informational: every hero may wear it.
@export var class_id: StringName
## The procedural variant: the tabard's emblem ("star", "sun" ...), the hat's shape ("bullhorn" ...), the glow's style
## ("halo_sun", "embers" ...). Empty for a dye.
@export var style: StringName
## Tabard: the cloth. Glow: the light. Dye: the tint it paints on both. Hat: the main material.
@export var color := Color.WHITE
## Tabard: the trim and emblem. Hat: the second colour. (Unused by glows and dyes.)
@export var trim := Color.WHITE
## Seeds price in The Onion Patch (0 = not sold, an achievement / a level gives it).
@export var price := 0
## List position inside its kind (the Wardrobe sorts by it).
@export var order := 0


func is_dye() -> bool:
	return kind == KIND_DYE


## True for a cosmetic that changes the model's shape or light (everything but a dye).
func has_shape() -> bool:
	return kind != KIND_DYE
