class_name EnchantRoll
extends RefCounted
## One enchantment rolled on an item, with its rank (0 = I, 1 = II, 2 = III).

var enchant: EnchantData
var rank := 0


func _init(p_enchant: EnchantData = null, p_rank: int = 0) -> void:
	enchant = p_enchant
	rank = clampi(p_rank, 0, EnchantData.RANK_MULT.size() - 1)


func mult() -> float:
	return EnchantData.rank_mult(rank)


## EQUIP enchants: their stat bonuses at this rank.
func equip_stats() -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	if enchant == null or enchant.kind != EnchantData.Kind.EQUIP:
		return out
	for stat in enchant.equip_stats:
		out[stat] = _scaled_stat(stat, enchant.equip_stats[stat])
	return out


## Rank-scaled stat value; counts (Stats.INTEGER_STATS) are rounded down (rank II of a
## "+1 Pierce" is still +1, rank III is +2).
func _scaled_stat(stat: StringName, base: float) -> float:
	var v := base * mult()
	return floorf(v + 0.0001) if stat in Stats.INTEGER_STATS else v


## A numeric parameter at this rank (non-numeric values are returned unchanged).
func param(key: String, default: Variant = 0.0) -> Variant:
	if enchant == null or not enchant.params.has(key):
		return default
	var v: Variant = enchant.params[key]
	if typeof(v) in [TYPE_INT, TYPE_FLOAT] and not key.ends_with("_fixed"):
		return float(v) * mult()
	return v


## The green tooltip line with numbers filled in.
func description() -> String:
	if enchant == null:
		return ""
	var text := enchant.description
	for key in enchant.params:
		var v: Variant = param(key)
		text = text.replace("{%s}" % key, _fmt(v))
	for stat in enchant.equip_stats:
		text = text.replace("{%s}" % stat, _fmt(_scaled_stat(stat, enchant.equip_stats[stat])))
	return text


static func _fmt(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		var f := float(v)
		return str(int(roundf(f))) if absf(f - roundf(f)) < 0.05 else "%.1f" % f
	return str(v)
