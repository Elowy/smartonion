class_name ArtifactWarlockPetLeech
extends TalentEffect
## Soul Siphon (the leech half) – property 2 of the Skull of the Damned (GDD 5.5): the Warlock
## heals for [code]pct[/code] (10) % of the damage its pets deal (every ProcSystem.deal_raw with
## the source &"pet": the Imp, the Voidwalkers, the Infernal, the Spirit Wolf). Sets
## Player.pet_leech_pct, which deal_raw reads; the +25% pet damage is a plain "damage" entry of
## the same property. Healing counts as the Warlock's own (Player.heal with its slot).
##
## Params (not rank-scaled): pct.


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	player.pet_leech_pct = maxf(0.0, num("pct", 10.0))


func teardown() -> void:
	if player != null and is_instance_valid(player):
		player.pet_leech_pct = 0.0


func describe() -> String:
	return "Heal for %d%% of your pets' damage." % roundi(num("pct", 10.0))
