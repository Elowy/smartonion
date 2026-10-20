class_name ClassLevelTable
extends Resource
## The Class Level curve and reward path (M9 LEVELS, design 1): the XP each level costs, the formulas that turn a
## finished run into Class XP and Seeds, and the list of rewards (what each level gives). One instance,
## data/meta/class_levels.tres, loaded by Db ([member Db.class_levels]); [ClassLevels] applies it.
## Retuning a number here needs no save migration: the profile stores total XP and the level reached, the unlocks
## of the levels are re-granted from this table when a profile is loaded ([method ClassLevels.sync_unlocks]).

@export var max_level := 30

@export_group("Curve")
## XP from level n to n + 1; entry 0 is level 1 -> 2 (max_level - 1 entries).
@export var xp_to_next := PackedInt32Array()
## Seeds gift when a level is reached: gift_base + level, times empty_level_gift_mult on a level without a reward.
@export var level_gift_base := 5
@export var empty_level_gift_mult := 2

@export_group("Class XP per run")
## Per cleared wave: wave_xp_base + wave_xp_per_wave * min(wave, wave_xp_wave_cap).
@export var wave_xp_base := 6.0
@export var wave_xp_per_wave := 0.5
@export var wave_xp_wave_cap := 30
## Per kill of the class's own heroes.
@export var kill_xp := 0.03
## Per elite killed by the team, up to elite_xp_cap in all.
@export var elite_xp := 1.5
@export var elite_xp_cap := 60.0
## Per boss killed by the team (every hero of the party gets it) and once for the final boss.
@export var boss_xp := 40.0
@export var final_boss_xp := 150.0
## A class that is catchup_gap levels (or more) below the profile's best class, and below catchup_below_level, earns
## catchup_mult times the XP.
@export var catchup_gap := 10
@export var catchup_below_level := 20
@export var catchup_mult := 1.5
## Flat XP for the first final-boss kill of a class on a tier (no multipliers), by difficulty id.
@export var first_win_bonus: Dictionary[StringName, int] = {}

@export_group("Seeds per run")
@export var seeds_per_wave := 1.5
@export var seeds_per_boss := 12.0
@export var seeds_final_boss := 40.0
## One Seed per this many team kills.
@export var seeds_kills_per := 400
@export var seeds_cap := 400
## +10% per player beyond the first.
@export var seeds_party_bonus := 0.1

@export_group("Rewards")
## What each level gives, in reading order: {"level": int, "kind": String, ...}. Kinds:
##   ability {index}       the class's index-th locked learnable ability joins the level-up deck (ClassPathData.deck_abilities)
##   capstone {index}      the class's index-th capstone tree opens (ClassPathData.capstone_trees)
##   seasoning_slot        one more Seasoning slot (Meta.seasoning_slots)
##   seasoning_tier {tier} Seasonings of the tier (1 .. 5) can be bought (seasoning_tier_level)
##   heirloom_slot         the Heirloom slot (Meta.heirloom_slots)
##   heirloom_gift         the class's gift Heirloom (ClassPathData.gift_heirloom) is owned
##   alt_weapon            the alternative starting weapon (ClassPathData.alt_main_hand / alt_off_hand)
##   cosmetic {slot}       a cosmetic of ClassPathData.cosmetics (tabard / hat / glow)
##   title                 the class title (ClassPathData.title_id)
##   gold {amount}         + starting gold per hero          primary_pct {amount}  + % of the primary stat
##   reroll {amount}       + free shop rerolls per run       backpack {amount}     + backpack slots
@export var rewards: Array[Dictionary] = []
