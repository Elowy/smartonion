class_name TalentBot
extends RefCounted
## Bot talent spending (M5, T-CORE-A): Intermission._bots_talents() calls
## [method spend_all] for every bot hero after training.
##
## P0 stub – the behaviour (tree order from slot_index % trees, capstone first, then the
## modifier, then (tier, column); deferral of talents whose effects all need an unmet weapon /
## ability; no resets, no RNG) is T-CORE-A's (architecture §2.2).


## Spends every free talent point of [param player] (bot [param slot_index]). Returns the
## points spent.
static func spend_all(_player: Player, _slot_index: int) -> int:
	return 0
