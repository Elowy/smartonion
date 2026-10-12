class_name TalentBot
extends RefCounted
## Bot talent spending (M5, GDD 7.3, architecture §2.2): Intermission._bots_talents() calls
## [method spend_all] for every bot hero after training.
##
## One point at a time while points are free. The trees are walked in tab order starting at
## [code]slot_index % trees.size()[/code] (P1 the first tree, P2 the second …, wrapping), and
## the first tree that offers a talent gets the point:
##   1. its capstone, if it can be added;
##   2. else its modifier, if it can be added;
##   3. else its first addable talent by (tier, column).
## Pass 1 skips DEFERRED talents ([method is_deferred]: every effect needs a weapon / ability
## the hero lacks right now, or a modifier whose ability is not slotted). Only when no tree
## offers anything in pass 1 does pass 2 repeat the walk with deferred talents allowed – so a
## deferred talent is taken only when nothing else is addable anywhere. With the 13-point
## capstone rule a bot takes its modifier at point 7 (unless deferred) and its capstone at
## point 13. Bots never reset; no RNG (the order only depends on the hero's state), so smoke
## runs stay reproducible.

## Safety cap on points one call spends (a tree holds 22, a class 66).
const MAX_POINTS_PER_CALL := 200


## Spends every free talent point of [param player] (bot [param slot_index]). Returns the
## points spent.
static func spend_all(player: Player, slot_index: int) -> int:
	if player == null or player.talents == null:
		return 0
	var state := player.talents
	var spent := 0
	while spent < MAX_POINTS_PER_CALL and state.points_free() > 0:
		var pick := next_talent(player, slot_index)
		if pick == null or not state.add(pick.id):
			break
		spent += 1
	return spent


## The talent [method spend_all] would add next for [param player] (bot [param slot_index]),
## null when none can be added.
static func next_talent(player: Player, slot_index: int) -> TalentData:
	if player == null or player.talents == null:
		return null
	var state := player.talents
	var trees := state.trees()
	if trees.is_empty() or state.points_free() <= 0:
		return null
	var start := posmod(slot_index, trees.size())
	for allow_deferred in [false, true]:
		for i in trees.size():
			var pick := _pick_in_tree(player, state, trees[(start + i) % trees.size()], allow_deferred)
			if pick != null:
				return pick
	return null


## True when a bot should wait with [param talent]: it is a MODIFIER whose ability is not
## slotted, or every one of its effects carries a "requires" that does not hold for
## [param player] right now (PlayerBonuses.requirement_met: weapon / knows). A talent without
## effects, or with one unconditional / met effect, is never deferred.
static func is_deferred(player: Player, talent: TalentData) -> bool:
	if talent == null:
		return false
	if talent.kind == TalentData.Kind.MODIFIER and talent.ability != &"":
		if player == null or player.abilities == null or not player.abilities.knows(talent.ability):
			return true
	if talent.effects.is_empty():
		return false
	for e in talent.effects:
		var req: Variant = e.get("requires")
		if typeof(req) != TYPE_DICTIONARY or (req as Dictionary).is_empty():
			return false
		if PlayerBonuses.requirement_met(player, req):
			return false
	return true


## The talent [param tree] offers (capstone, else modifier, else the first addable by tier and
## column), skipping deferred ones unless [param allow_deferred].
static func _pick_in_tree(player: Player, state: TalentState, tree: TalentTreeData, allow_deferred: bool) -> TalentData:
	var ok := func(t: TalentData) -> bool:
		return t != null and state.can_add(t.id) and (allow_deferred or not is_deferred(player, t))
	# The capstone is never deferred (architecture 2.2: point 13 in every tree).
	for t in tree.talents:
		if t != null and t.kind == TalentData.Kind.CAPSTONE and state.can_add(t.id):
			return t
	for t in tree.talents:
		if t != null and t.kind == TalentData.Kind.MODIFIER and ok.call(t):
			return t
	for tier in range(1, TalentState.TIER_POINTS.size() + 1):
		for t in tree.talents_in_tier(tier):
			if ok.call(t):
				return t
	return null
