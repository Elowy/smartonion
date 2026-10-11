class_name LevelCard
extends RefCounted
## One level-up card (GDD 6.1): learn a new ability, rank up a known one, or take stats.

enum Kind { NEW_ABILITY, RANK_UP, STAT }

var kind: Kind = Kind.STAT
var ability: AbilityData
## Items.Rarity of a stat card (COMMON..EPIC); rank-up / ability cards use the rank's look.
var rarity := 0
var stats: Dictionary[StringName, float] = {}


static func new_ability(p_ability: AbilityData) -> LevelCard:
	var c := LevelCard.new()
	c.kind = Kind.NEW_ABILITY
	c.ability = p_ability
	return c


static func rank_up(p_ability: AbilityData) -> LevelCard:
	var c := LevelCard.new()
	c.kind = Kind.RANK_UP
	c.ability = p_ability
	return c


static func stat(p_rarity: int, p_stats: Dictionary[StringName, float]) -> LevelCard:
	var c := LevelCard.new()
	c.kind = Kind.STAT
	c.rarity = p_rarity
	c.stats = p_stats
	return c


func is_ability_card() -> bool:
	return kind != Kind.STAT


func title() -> String:
	match kind:
		Kind.NEW_ABILITY, Kind.RANK_UP:
			return ability.display_name if ability != null else "?"
	return "%s Training" % Items.RARITY_NAMES[clampi(rarity, 0, Items.RARITY_NAMES.size() - 1)]


## Short lines for the card body; [param runner] gives the current rank for rank-up cards.
func lines(runner: AbilityRunner = null) -> PackedStringArray:
	var out := PackedStringArray()
	match kind:
		Kind.NEW_ABILITY:
			out.append("New %s ability" % ("auto-cast" if ability.kind == AbilityData.Kind.AUTO else "active"))
		Kind.RANK_UP:
			var rank := runner.rank_of(ability.id) if runner != null else 1
			out.append("Rank %s -> %s" % [roman(rank), roman(rank + 1)])
			out.append(AbilityRanks.rank_text(ability, rank + 1))
		Kind.STAT:
			for s: StringName in stats:
				out.append("%s %s" % [Stats.format_value(s, stats[s]), Stats.display_name(s)])
	return out


static func roman(rank: int) -> String:
	return ["I", "II", "III", "IV", "V"][clampi(rank, 1, 5) - 1]
