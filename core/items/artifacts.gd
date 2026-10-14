class_name Artifacts
extends RefCounted
## The Artifact rules of a hero's gear (M6 ARTIFACTS, GDD 5.5): growth, awakening and the
## engine entries of the two special properties. Pure rules on [Equipment] / [ItemInstance] –
## the drop roll lives in LootDrops.roll_artifact, the item in ItemGenerator.from_artifact, the
## pair rule (Fangs of the Shadow) in Equipment.
##
## Growth ([method grow], called by Player on wave_ended): every Artifact the hero holds –
## equipped or in the backpack, a pair once – gains GROWTH_ITEM_LEVEL Item Level and
## GROWTH_DAMAGE_PCT % of its base weapon damage (linear on ItemInstance.artifact_base_damage),
## and counts one more wave end held (ItemInstance.artifact_waves).
## Properties: property i awakens when artifact_waves >= ArtifactData.unlock_after(i) (3 and 6
## wave ends). An equipped Artifact's awake properties are bonus-vocabulary entries
## ([method effects_for]) set as the &"artifact" source of PlayerBonuses by
## Player.apply_equipment (so growth re-applies the equipment: [signal Equipment.changed]).
## A property whose ability the hero has not learned stays dormant in the engine (the entry's
## "requires" {"knows": ...}) and shows greyed "(needs Whirlwind)" in the tooltip.

## The PlayerBonuses source of every Artifact entry.
const SOURCE := &"artifact"
## The longest "short" text of a property (two tooltip lines): the compact tooltip of a hero's
## panel or the shop shows it instead of the full text so it fits a 4-player corner panel.
const SHORT_TEXT_MAX := 72
## Item Level gained per wave end held (GDD 5.5).
const GROWTH_ITEM_LEVEL := 3
## Weapon damage gained per wave end held, in % of the damage at pickup (GDD 5.5).
const GROWTH_DAMAGE_PCT := 4.0

## property_state() values.
const STATE_AWAKE := &"awake"
const STATE_ASLEEP := &"asleep"
## Awake, but the hero has not learned the ability the property needs.
const STATE_NEEDS_ABILITY := &"needs_ability"


## The ArtifactData of [param item] (null for anything that is not an Artifact).
static func data_of(item: ItemInstance) -> ArtifactData:
	if item == null or not item.is_artifact():
		return null
	return Db.get_artifact(item.source_id)


## The Artifacts [param equipment] holds, a pair counted once (its main-hand piece): equipped
## first (main hand, off hand), then the backpack.
static func held(equipment: Equipment) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	if equipment == null:
		return out
	for s in [Items.EquipSlot.MAIN_HAND, Items.EquipSlot.OFF_HAND]:
		var item := equipment.get_item(s)
		if item != null and item.is_artifact() and not item.pair_off and item not in out:
			out.append(item)
	for item in equipment.backpack:
		if item != null and item.is_artifact() and not item.pair_off and item not in out:
			out.append(item)
	return out


## One wave end held: +3 Item Level, +4% of the pickup damage, one more wave counted (a pair's
## off-hand piece too). Returns false for a non-Artifact.
static func grow_item(item: ItemInstance) -> bool:
	if item == null or not item.is_artifact():
		return false
	item.artifact_waves += 1
	item.item_level += GROWTH_ITEM_LEVEL
	if item.weapon != null and item.artifact_base_damage > 0.0:
		item.weapon.base_damage = item.artifact_base_damage * (1.0 + GROWTH_DAMAGE_PCT / 100.0 * item.artifact_waves)
	if item.companion != null:
		grow_item(item.companion)
	return true


## A wave ended for the hero who owns [param equipment]: every held Artifact grows. Returns how
## many Artifacts grew (the caller re-applies the equipment when > 0: properties may awaken).
static func grow(equipment: Equipment) -> int:
	var n := 0
	for item in held(equipment):
		if grow_item(item):
			n += 1
	return n


## Number of properties of [param item] that are awake (0..2).
static func awake_count(item: ItemInstance) -> int:
	var data := data_of(item)
	if data == null:
		return 0
	var n := 0
	for i in data.properties.size():
		if is_awake(item, i):
			n += 1
	return n


## Whether property [param index] of [param item] has awakened.
static func is_awake(item: ItemInstance, index: int) -> bool:
	var data := data_of(item)
	return data != null and index >= 0 and index < data.properties.size() \
			and item.artifact_waves >= data.unlock_after(index)


## Wave ends until property [param index] awakens (0 = awake or no such property).
static func waves_left(item: ItemInstance, index: int) -> int:
	var data := data_of(item)
	if data == null or index < 0 or index >= data.properties.size():
		return 0
	return maxi(0, data.unlock_after(index) - item.artifact_waves)


## "Awakens in 3 waves" / "Awakens in 1 wave" (the tooltip's line of a sleeping property).
static func awakens_text(waves: int) -> String:
	return "Awakens in %d wave%s" % [waves, "" if waves == 1 else "s"]


## The ability a property needs ("" = none), by id.
static func needs_of(property: Dictionary) -> StringName:
	return StringName(str(property.get("needs", "")))


## Display name of an ability id ("Whirlwind"); the capitalised id when unknown.
static func ability_name(ability_id: StringName) -> String:
	var a := Db.get_ability(ability_id)
	return a.display_name if a != null else String(ability_id).capitalize().replace("_", " ")


## One property of [param item] as the tooltip shows it: {"index", "name", "text", "short" (the
## compact tooltip's text of a viewer's tooltip; the full text when the data has none), "state"
## (STATE_*), "waves_left", "needs" (ability display name, "" = none)}. [param hero] (may be
## null: then nothing counts as missing) decides STATE_NEEDS_ABILITY.
static func property_rows(item: ItemInstance, hero: Player = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data := data_of(item)
	if data == null:
		return out
	for i in data.properties.size():
		var p := data.properties[i]
		var needs := needs_of(p)
		var state := STATE_AWAKE
		if not is_awake(item, i):
			state = STATE_ASLEEP
		elif needs != &"" and hero != null and not hero_knows(hero, needs):
			state = STATE_NEEDS_ABILITY
		out.append({
			"index": i,
			"name": str(p.get("name", "")),
			"text": str(p.get("text", "")),
			"short": str(p.get("short", p.get("text", ""))),
			"state": state,
			"waves_left": waves_left(item, i),
			"needs": ability_name(needs) if needs != &"" else "",
		})
	return out


## Whether [param hero] has the ability [param ability_id] in one of its slots.
static func hero_knows(hero: Player, ability_id: StringName) -> bool:
	return hero != null and hero.abilities != null and hero.abilities.knows(ability_id)


## The bonus-vocabulary entries of every awake property of the Artifacts [param equipment] has
## EQUIPPED (the weapon in the hand: a backpack Artifact gives nothing), each with "id"
## ("artifact:<artifact id>:<property index>") and "label" (the property's name) – what
## Player.apply_equipment hands to PlayerBonuses.set_effects(SOURCE, ...).
static func effects_for(equipment: Equipment) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if equipment == null:
		return out
	for item in held(equipment):
		if not equipment.is_equipped(item):
			continue
		var data := data_of(item)
		for i in data.properties.size():
			if not is_awake(item, i):
				continue
			var p := data.properties[i]
			for entry: Variant in p.get("effects", []):
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				var e: Dictionary = (entry as Dictionary).duplicate(true)
				e["id"] = "artifact:%s:%d" % [data.id, i]
				e["label"] = str(p.get("name", ""))
				out.append(e)
	return out


## The smoke log line of an Artifact that just dropped ("artifact drop: Earthsplitter (warrior) on
## wave 10 from boss, item level 65"; Main prints it behind "SMOKE ").
static func drop_line(item: ItemInstance, source: StringName, wave: int) -> String:
	var data := data_of(item)
	return "artifact drop: %s (%s) on wave %d from %s, item level %d" % [
		item.display_name, data.class_id if data != null else item.class_restriction, wave, source, item.item_level]


## The smoke log line of an Artifact a hero holds at a wave end ("artifact held: P1 warrior
## Earthsplitter after wave 12, waves held 3, item level 74, properties awake 1/2, equipped").
## [param equipped]: in the hand (the properties only work then), else in the backpack.
static func held_line(slot_label: String, item: ItemInstance, wave: int, equipped: bool) -> String:
	var data := data_of(item)
	return "artifact held: %s %s %s after wave %d, waves held %d, item level %d, properties awake %d/%d, %s" % [
		slot_label, data.class_id if data != null else item.class_restriction, item.display_name, wave,
		item.artifact_waves, item.item_level, awake_count(item), data.properties.size() if data != null else 0,
		"equipped" if equipped else "in the backpack"]


## The content check of one Artifact's data ("" = valid, else the first problem): a class and a
## weapon of that class, 2 properties with a name, a text, a short text and valid entries, unlock waves in
## order, a pair weapon the class can use, fixed enchants that exist.
static func validate(data: ArtifactData) -> String:
	if data == null:
		return "no data"
	var cls := Db.get_class_data(data.class_id)
	if cls == null:
		return "unknown class '%s'" % data.class_id
	if data.rarity != Items.Rarity.ARTIFACT:
		return "rarity must be Artifact"
	if data.class_restriction != data.class_id:
		return "class_restriction must be the class"
	if data.weapon == null or not cls.can_use(data.weapon):
		return "the weapon must be usable by %s" % data.class_id
	if data.is_pair() and (not cls.can_use(data.pair_weapon) or not cls.can_dual_wield()):
		return "a pair needs a dual-wield class and usable weapons"
	if data.properties.size() != 2 or data.unlock_waves.size() != 2:
		return "needs exactly 2 properties and 2 unlock waves"
	if data.unlock_waves[0] >= data.unlock_waves[1] or data.unlock_waves[0] < 1:
		return "unlock waves must be increasing"
	for id in data.enchant_ids + data.pair_enchant_ids:
		if Db.get_enchant(id) == null:
			return "unknown enchant '%s'" % id
	for i in data.properties.size():
		var p := data.properties[i]
		if str(p.get("name", "")) == "" or str(p.get("text", "")) == "":
			return "property %d needs a name and a text" % i
		var short := str(p.get("short", ""))
		if short == "" or short.length() > SHORT_TEXT_MAX:
			return "property %d needs a short text of at most %d characters (the compact tooltip)" % [i, SHORT_TEXT_MAX]
		var needs := needs_of(p)
		if needs != &"" and Db.get_ability(needs) == null:
			return "property %d needs unknown ability '%s'" % [i, needs]
		var effects: Variant = p.get("effects", [])
		if typeof(effects) != TYPE_ARRAY or (effects as Array).is_empty():
			return "property %d has no effects" % i
		for entry: Variant in effects:
			if typeof(entry) != TYPE_DICTIONARY:
				return "property %d: an effect is not a dictionary" % i
			var error := BonusVocabulary.validate(entry, data.class_id)
			if error != "":
				return "property %d: %s" % [i, error]
	return ""
