class_name Forge
extends RefCounted
## Weapon forging (GDD 4.1, M5): two generated weapons with the same base (source_id) and
## rarity become one new weapon of the next rarity, freshly rolled (architecture §2.3). Used by
## the PlayerPanel "Forge" entry, the shop's auto-forge (full backpack) and the bots
## (Intermission._bots_shop).
##
## P0 stub: nothing is forgeable – blocked_reason says "Forging is not available yet", the rest
## returns false / null / 0 / "" / []. FORGE implements it.

## Reason shown on the disabled panel entry while the stub is in place.
const NOT_AVAILABLE := "Forging is not available yet"


## A generated weapon below Legendary (never hand-made / Artifact).
static func is_forgeable(_item: ItemInstance) -> bool:
	return false


## The partner [param _item] would be forged with (backpack first, then main / off hand); null
## when there is none.
static func partner_for(_eq: Equipment, _item: ItemInstance) -> ItemInstance:
	return null


## Why [param _item] cannot be forged right now ("" = it can).
static func blocked_reason(_eq: Equipment, _item: ItemInstance) -> String:
	return NOT_AVAILABLE


## The rarity a forge of [param _item] produces.
static func forged_rarity(_item: ItemInstance) -> int:
	return 0


## Menu detail of the Forge entry ("→ Rare").
static func result_text(_item: ItemInstance) -> String:
	return ""


## Forges [param _item] with its partner in [param _eq]; the result (null = refused).
static func forge(_eq: Equipment, _item: ItemInstance, _rng: RandomNumberGenerator = null) -> ItemInstance:
	return null


## Shop auto-forge: [param _offer_item] (bought, never in the backpack) with its partner.
static func forge_with_offer(_eq: Equipment, _offer_item: ItemInstance, _rng: RandomNumberGenerator = null) -> ItemInstance:
	return null


## The forged weapon of [param _a] + [param _b] (pure, tests).
static func make_result(_a: ItemInstance, _b: ItemInstance, _rng: RandomNumberGenerator) -> ItemInstance:
	return null


## Slot indices of the players for whom [param _offer_item] has a forge partner (anvil pips).
static func offer_forge_slots(_offer_item: ItemInstance, _slots: Array[PlayerSlot]) -> Array[int]:
	var out: Array[int] = []
	return out


## Bot forging between waves; returns the forges done.
static func bot_forge_all(_slot: PlayerSlot) -> int:
	return 0
