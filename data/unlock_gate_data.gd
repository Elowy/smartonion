class_name UnlockGateData
extends Resource
## One piece of content that the main profile has to unlock before it is offered (M9 meta-progression).
## Instances live in res://data/unlocks/ (loaded by Db into [member Db.unlock_gates]); a content package can
## also register gates in code ([method Db.add_unlock_gate]). Content without a gate is available from the
## start: gating is opt-in, so the data of a class, ability, tree ... is never touched.
##
## [member kind] is one of Profile.KINDS (class, ability, capstone_tree, legendary, difficulty, seasoning,
## heirloom, cosmetic, title, look) and [member id] the permanent content id of that kind (a ClassData id, an
## AbilityData id, a TalentTreeData id ...). The profile records the unlock (Profile.unlock, done by a Class
## Level reward, an achievement reward or a purchase); [method Meta.is_unlocked] is the question the content
## pools ask.

@export var kind: StringName
@export var id: StringName
## The class this gate belongs to, for the hint's context only ("" = none / any class). Class-scoped kinds (the
## difficulty tiers) pass the class to [method Meta.is_unlocked] instead.
@export var class_id: StringName
## Shown where the content is locked ("Win a run with the Warrior"). English, player-visible.
@export var hint := ""


## The registry key of a (kind, id) pair.
static func key_for(p_kind: StringName, p_id: StringName) -> StringName:
	return StringName("%s/%s" % [p_kind, p_id])


func key() -> StringName:
	return key_for(kind, id)
