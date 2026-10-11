class_name Trainer
extends RefCounted
## The class Trainer (GDD 6.3), a tab of the between-waves panel: buy the next rank of a
## slotted ability (core ones included) from the shared wallet.

## Buys the next rank of [param ability_id] for [param player]. Rank V then needs a
## specialisation (AbilityRunner.needs_spec).
static func try_buy_rank(player: Player, ability_id: StringName) -> bool:
	var runner := player.abilities if player != null else null
	if runner == null or not runner.can_rank_up(ability_id):
		return false
	var price := runner.trainer_price(ability_id)
	if not RunState.try_spend(price):
		return false
	runner.rank_up(ability_id)
	return true


## Bot use (smoke / demo): rank up its cheapest ability while the wallet keeps at least
## [param reserve] gold; Rank V picks the first specialisation. Returns ranks bought.
static func bot_train(player: Player, reserve: int) -> int:
	var runner := player.abilities if player != null else null
	if runner == null:
		return 0
	var bought := 0
	while true:
		var best: StringName = &""
		var best_price := 0
		for a in runner.slots:
			if a == null or not runner.can_rank_up(a.id):
				continue
			var price := runner.trainer_price(a.id)
			if best == &"" or price < best_price:
				best = a.id
				best_price = price
		if best == &"" or RunState.gold - best_price < reserve or not try_buy_rank(player, best):
			break
		if runner.needs_spec(best):
			runner.set_spec(best, 0)
		bought += 1
	return bought
