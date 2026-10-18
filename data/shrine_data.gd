class_name ShrineData
extends Resource
## A shrine (GDD 16.1, M6b SHRINES): a boon-and-bane offer the whole party votes on at a break. Instances
## live in res://data/shrines/ (loaded by Db into Db.shrines); the rules around them (the roll, the vote
## results, the effects) are the static helpers of [Shrines].
##
## Two kinds, told apart by [member waves]:
##   - a TIMED shrine (waves > 0) runs over the next [member waves] waves: the percentages below scale the
##     pickups (gold, XP) and every enemy that spawns in those waves, [member hero_effects] go to each hero
##     as the PlayerBonuses source [constant Shrines.SOURCE];
##   - an INSTANT shrine (waves == 0) does its thing once, the moment the party accepts: a free Epic item
##     for every hero, a share of the purse lost or won.
## Every number is data; the card texts are generated from them ([method Shrines.boon_lines] /
## [method Shrines.bane_lines]), so a card can never promise another number than the one that applies.

@export var id: StringName
@export var display_name := ""
## One flavour line under the name on the card.
@export_multiline var description := ""
## Waves a timed shrine runs for (counted from the next wave); 0 = instant.
@export var waves := 3
## Icon id for the card and the HUD (ShrineIcon draws a picture per id).
@export var icon_id: StringName
## The shrine's colour (card border, icon, backdrop glow).
@export var color := Color(0.9, 0.75, 0.3)
## Bots vote Accept for this shrine (else Decline).
@export var bot_accepts := true

# --- Timed effects (percent; 0 = none) ---------------------------------------------------------
## Gold the pickups give (+30 = x1.3).
@export var gold_pct := 0.0
## XP the pickups give.
@export var xp_pct := 0.0
## Contact / projectile damage of every enemy that spawns while the shrine runs.
@export var enemy_damage_pct := 0.0
## Max HP of every enemy that spawns while the shrine runs.
@export var enemy_hp_pct := 0.0
## Walking speed of every enemy that spawns while the shrine runs.
@export var enemy_speed_pct := 0.0
## BonusVocabulary entries every hero gets while the shrine runs (PlayerBonuses source
## [constant Shrines.SOURCE]); the "stats_pct" extension of the consumables works here too
## ({"max_hp": -20.0} = 20% less Max HP).
@export var hero_effects: Array[Dictionary] = []

# --- Instant effects ---------------------------------------------------------------------------
## Every hero gets a free Epic item (into the backpack; a full backpack sells it for the Greed value).
@export var give_epic := false
## The purse loses this share at once (spend kind &"shrine").
@export var purse_loss_pct := 0.0
## A gamble on the purse: this chance (0..1; 0 = no gamble) to win [member gamble_win_pct] of it, else
## to lose [member gamble_lose_pct] of it.
@export var gamble_chance := 0.0
@export var gamble_win_pct := 0.0
@export var gamble_lose_pct := 0.0


func is_timed() -> bool:
	return waves > 0


func is_instant() -> bool:
	return waves <= 0
