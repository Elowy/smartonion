class_name ShamanWellspringElderSpirits
extends TalentEffect
## Elder Spirits and Gift of the Elders – the Shaman Wellspring revive talents (design_shaman.md 4.4, M8): both
## entries use this script with different params, so every talent is its own instance.
##   speed_pct  Elder Spirits: allies the Shaman helps revive get up speed_pct x rank % faster
##   hp_pct     Gift of the Elders: they return with hp_pct x rank % more of their Max HP
## The numbers go onto the hero's reviver fields (Player.revive_speed_pct / revive_hp_pct): the downed ally's
## Player._update_revive sums the fields of every living hero in its revive circle (capped at
## REVIVE_SPEED_PCT_CAP / REVIVE_HP_PCT_CAP) – two Shamans stack. Call of Valor's instant revive and the Grave
## Tender are not revives by a hero in the circle and stay as they were. teardown() (undo, rank change,
## the hero is freed) takes the numbers away again. No RNG, no nodes. Passive for bots.
##
## Params (not rank-scaled, the rank multiplies them here): speed_pct, hp_pct.

var _speed := 0.0
var _hp := 0.0


func setup(p_player: Player, p_rank: int, p_params: Dictionary) -> void:
	super(p_player, p_rank, p_params)
	_speed = maxf(0.0, num("speed_pct")) * float(rank)
	_hp = maxf(0.0, num("hp_pct")) * float(rank)
	if player != null:
		player.revive_speed_pct += _speed
		player.revive_hp_pct += _hp


func teardown() -> void:
	if player != null and is_instance_valid(player):
		player.revive_speed_pct = _settle(player.revive_speed_pct - _speed)
		player.revive_hp_pct = _settle(player.revive_hp_pct - _hp)
	_speed = 0.0
	_hp = 0.0


func describe() -> String:
	var parts: Array[String] = []
	if _speed > 0.0:
		parts.append("revives %s%% faster" % TalentData.format_number(_speed))
	if _hp > 0.0:
		parts.append("revived allies return with %s%% more HP" % TalentData.format_number(_hp))
	return "Elder Spirits: " + ", ".join(parts) if not parts.is_empty() else ""


## A sum that went back to (about) zero is exactly zero.
static func _settle(v: float) -> float:
	return 0.0 if absf(v) < 0.0001 else maxf(0.0, v)
