class_name ItemTooltip
extends PanelContainer
## WoW-style item tooltip (GDD 12) on a dark frame bordered in the item's rarity colour,
## top to bottom: name in rarity colour, "Looted" (not on an Artifact), "Item Level N", slot +
## armor / weapon type (right-aligned, red when the viewer cannot use it), weapon damage / speed /
## DPS, white stat lines, "Classes: X" (red if not the viewer's class), green enchant lines
## (EnchantRoll.description()), the unique effect line, the tier-set block (set name with
## "(n/5)" worn by [member viewer_equipment] – "(5 pieces)" without one –, the five pieces,
## bright when worn, then "(2) Set: …" / "(4) Set: …" green when active, grey otherwise;
## SetBonuses.describe), flavor text in gold quotes, the buy price (when given) and the sell
## value, and a comparison block against the viewer's equipped item ("If you replace this
## item:" +green / -red per stat).
## An Artifact (M6, rarity Artifact – gold name and frame) adds golden property lines: the two
## special properties awake in gold ("Earthquake" + text), asleep dim with "Awakens in N waves",
## and grey with "(needs Whirlwind)" when the viewing hero has not learned the ability; no sell
## price (an Artifact is never sold); a pair (Fangs of the Shadow) says it equips with its other
## piece. See Artifacts.property_rows. Shown to a viewer (viewer_equipment set: the player panels,
## the shop) the block is compact (compact_artifact).
## A set piece shown to a viewer (viewer_equipment set: the player panels, the shop) gets the
## compact set block – the pieces as their slot names on one line ("Head  Shoulders  Chest …")
## and no flavor text – so the tooltip stays readable inside a 4-player corner panel at 720p.
## Without a viewer (the loot roll) the pieces keep their full names.
## Static helpers (stat_delta, upgrade_direction, item_score, equipped_for_compare) are shared
## with the shop, the loot roll and bots. Weapons compare with everything they would push out:
## a two-hander with main + off hand together (an EquippedPair), an off-hand item or a
## dual-wield one-hander next to an equipped two-hander with that two-hander; nothing that
## would leave the hero without an attacking weapon is an upgrade.

const WIDTH := 360.0
const NAME_SIZE := 24
const BODY_SIZE := 20
const SMALL_SIZE := 18
## WoW tooltip colours.
const WHITE := Color(1, 1, 1)
const YELLOW := Color(1.0, 0.82, 0.0)
const ENCHANT_GREEN := Color(0.12, 1.0, 0.0)
const UNUSABLE_RED := Color(1.0, 0.18, 0.15)
const DELTA_GREEN := Color(0.2, 1.0, 0.2)
const DELTA_RED := Color(1.0, 0.25, 0.2)
const DIM := Color(0.62, 0.6, 0.58)
## Artifact properties: awake (gold), asleep / missing ability (dim shades of it).
const ARTIFACT_GOLD := Color(1.0, 0.84, 0.4)
const ARTIFACT_ASLEEP := Color(0.62, 0.55, 0.36)
const FILL := Color(0.03, 0.03, 0.055, 0.95)
## Tier-set block: the set name, worn / missing piece names (active bonuses use ENCHANT_GREEN,
## inactive ones DIM).
const SET_NAME_COLOR := YELLOW
const SET_PIECE_WORN := Color(1.0, 1.0, 0.6)
const SET_PIECE_MISSING := Color(0.58, 0.58, 0.58)
## Left indent of the piece names under the set name.
const SET_PIECE_INDENT := 14
## Gap between the slot names of the compact set block (no bullets, no indent: the five fit
## one line of the tooltip).
const SET_SLOT_GAP := 12
## Gap between the differences of the compact Artifact comparison block.
const DELTA_FLOW_GAP := 16
## Gap between two lines of the tooltip (px); the compact Artifact block packs them closer.
const LINE_SEPARATION := 3
const COMPACT_ARTIFACT_SEPARATION := 1

## upgrade_direction / item_score weights: the viewer's primary stat counts most, the other
## primary stats barely (they do nothing for the class), defensive stats by their budget cost
## (GDD 5.4), weapon damage per second (with a nominal primary stat) on top.
const PRIMARY_WEIGHT := 3.0
const OFF_PRIMARY_WEIGHT := 0.15
const DPS_WEIGHT := 2.5
const NOMINAL_PRIMARY := 10.0
const UPGRADE_THRESHOLD := 0.25
## Tier sets (GDD 5.5 "Botok"): a piece that completes a 2- / 4-piece bonus is an upgrade unless
## its score is more than this share below the replaced item's; the other way round, an item
## that would break an active bonus is an upgrade only when the set piece's score is more than
## this share below it (so bots never flip-flop between the two).
const SET_UPGRADE_TOLERANCE := 0.3

const WEAPON_TYPE_NAMES := {
	&"sword": "Sword", &"axe": "Axe", &"mace": "Mace", &"dagger": "Dagger", &"bow": "Bow",
	&"gun": "Gun", &"wand": "Wand", &"staff": "Staff", &"shield": "Shield", &"tome": "Tome",
	&"two_hand_sword": "Sword", &"two_hand_mace": "Mace", &"orb": "Orb",
}

var item: ItemInstance
var viewer: ClassData
var compare: ItemInstance
var price := 0
## The "If you replace this item:" block (Y toggles it on the character panel).
var comparison_visible := true
## Shared screens (the shop): whose tooltip this is – a "P2" tag in the player's colour on top
## and the frame border in that colour. Empty = none.
var owner_tag := ""
var owner_color := Color.WHITE
## The viewer's equipment (M5): set bonuses use it to show the worn pieces "(n/5)" and which
## bonuses are active. Null = no counts (the loot roll). Set it before show_item.
var viewer_equipment: Equipment

var _box: VBoxContainer
static var _italic: FontVariation


## Main + off hand compared as one item (what a two-hander replaces): summed stats and weapon
## DPS, shown as "Equipped: Dagger + Dagger". Never equipped itself.
class EquippedPair extends ItemInstance:
	var parts: Array[ItemInstance] = []

	static func of(main: ItemInstance, off: ItemInstance) -> EquippedPair:
		var pair := EquippedPair.new()
		pair.parts = [main, off]
		pair.display_name = "%s + %s" % [main.display_name, off.display_name]
		pair.slot_type = Items.SlotType.WEAPON
		pair.rarity = maxi(main.rarity, off.rarity)
		pair.wave = maxi(main.wave, off.wave)
		pair.item_level = roundi((main.item_level + off.item_level) * 0.5)
		pair.buy_price = main.buy_price + off.buy_price
		return pair


static func create() -> ItemTooltip:
	var t := ItemTooltip.new()
	t.name = "ItemTooltip"
	t.theme = UiTheme.get_theme()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.custom_minimum_size = Vector2(WIDTH, 0)
	t._box = UiTheme.vbox(LINE_SEPARATION)
	t.add_child(t._box)
	t.add_theme_stylebox_override(&"panel", frame_style(0))
	t.minimum_size_changed.connect(t._shrink_to_fit, CONNECT_DEFERRED)
	t.visible = false
	return t


## [param viewer] decides red "cannot use" lines; [param compare] (may be null) is the
## currently equipped item for the comparison block; [param price] > 0 shows a buy price.
func show_item(p_item: ItemInstance, p_viewer: ClassData = null, p_compare: ItemInstance = null, p_price: int = 0) -> void:
	item = p_item
	viewer = p_viewer
	compare = p_compare
	price = p_price
	_rebuild()
	visible = item != null


## Lays the tooltip out now and shrinks it to its content, so a caller that places it in the
## frame its content changed (ShopPanel.layout_tooltips) gets its real size. Without this the
## wrapped lines still have the 40 px width they were created with until the containers sort at
## the end of the frame – the tooltip measures several times its height. Containers top-down,
## then each label's minimum size is refreshed (a label does not report a new width by itself).
func layout_now() -> void:
	reset_size()
	_layout_tree(self)
	reset_size()


static func _layout_tree(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c in node.get_children():
		if not c.is_queued_for_deletion():
			_layout_tree(c)
	if node is Label:
		(node as Label).update_minimum_size()


## Identifies the comparison item across calls: an EquippedPair is a new object every time
## (equipped_for_compare), so it is known by its two parts.
static func compare_key(p_compare: ItemInstance) -> String:
	if p_compare == null:
		return "0"
	if p_compare is EquippedPair:
		var parts := (p_compare as EquippedPair).parts
		return "%d+%d" % [parts[0].uid, parts[1].uid]
	return str(p_compare.uid)


func set_owner_tag(tag: String, color: Color) -> void:
	if tag == owner_tag and color == owner_color:
		return
	owner_tag = tag
	owner_color = color
	if item != null:
		_rebuild()


func set_comparison_visible(value: bool) -> void:
	if value == comparison_visible:
		return
	comparison_visible = value
	if item != null:
		_rebuild()


## Every text line currently shown (tests, debugging).
func line_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for l in _labels(self):
		out.append(l.text)
	return out


## The first label whose text contains [param fragment] (equals it with [param exact]);
## null if none.
func find_line(fragment: String, exact: bool = false) -> Label:
	for l in _labels(self):
		if (l.text == fragment) if exact else (fragment in l.text):
			return l
	return null


## Dark WoW tooltip frame with a border in the rarity colour.
static func frame_style(rarity: int) -> UiFrameStyle:
	var s := UiFrameStyle.new()
	s.fill = FILL
	var rc := ItemIcon.rarity_color_of(rarity)
	s.border = Color(0.55, 0.55, 0.58).lerp(rc, 0.0 if rarity <= 0 else 0.75)
	s.border_width = 2
	s.corner_radius = 6
	s.shadow_size = 12
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.inner_shadow = 10
	s.inner_shadow_color = Color(0, 0, 0, 0.55)
	s.sheen = 0.025
	s.studs = false
	if rarity >= Items.Rarity.EPIC:
		s.glow = Color(rc, 0.28)
		s.glow_size = 10
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	return s.rebuild()


# --- Static helpers ---------------------------------------------------------------------

## Everything [param p_item] adds to a player's stats while equipped: rolled stats, the
## weapon's own bonus stats and EQUIP enchant stats.
static func total_stats(p_item: ItemInstance) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	if p_item == null:
		return out
	if p_item is EquippedPair:
		for part in (p_item as EquippedPair).parts:
			var part_stats := total_stats(part)
			for stat in part_stats:
				out[stat] = out.get(stat, 0.0) + part_stats[stat]
		return out
	out = p_item.all_stats()
	for roll in p_item.enchants:
		var extra := roll.equip_stats()
		for stat in extra:
			out[stat] = out.get(stat, 0.0) + extra[stat]
	if p_item.companion != null:
		# A pair (Fangs of the Shadow) is worth both pieces: it equips as one.
		var more := total_stats(p_item.companion)
		for stat in more:
			out[stat] = out.get(stat, 0.0) + more[stat]
	return out


## Stat differences equipping [param item] instead of [param equipped] would make (by stat id).
static func stat_delta(p_item: ItemInstance, equipped: ItemInstance) -> Dictionary[StringName, float]:
	var a := total_stats(p_item)
	var b := total_stats(equipped)
	var out: Dictionary[StringName, float] = {}
	for stat in a:
		out[stat] = a[stat] - b.get(stat, 0.0)
	for stat in b:
		if not a.has(stat):
			out[stat] = -b[stat]
	for stat in out.keys():
		if absf(out[stat]) < 0.001:
			out.erase(stat)
	return out


## Damage per second of a weapon item (0 for armour and passive off-hands). With
## [param primary] the weapon's scaling on that stat counts [param primary_value] points.
static func weapon_dps(p_item: ItemInstance, primary: StringName = &"", primary_value: float = 0.0,
		with_companion: bool = true) -> float:
	if p_item is EquippedPair:
		var total := 0.0
		for part in (p_item as EquippedPair).parts:
			total += weapon_dps(part, primary, primary_value)
		return total
	if p_item == null or not p_item.is_weapon() or not p_item.weapon.attacks():
		return 0.0
	var w := p_item.weapon
	var dmg := w.base_damage
	if primary != &"":
		dmg += float(w.scaling.get(primary, 0.0)) * primary_value
	var dps := dmg / maxf(0.08, w.cooldown)
	if with_companion and p_item.companion != null:
		dps += weapon_dps(p_item.companion, primary, primary_value)
	return dps


## How much [param stat] is worth to [param p_viewer] in the upgrade heuristic.
static func stat_weight(stat: StringName, p_viewer: ClassData) -> float:
	if p_viewer != null and stat == p_viewer.primary_stat:
		return PRIMARY_WEIGHT
	match stat:
		Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT:
			return OFF_PRIMARY_WEIGHT if p_viewer != null else 1.0
		Stats.STAMINA:
			return 1.2
		Stats.ARMOR, Stats.LEECH:
			return 2.0
		Stats.VERSATILITY, Stats.DODGE, Stats.SPIRIT:
			return 1.5
		Stats.FORTUNE, Stats.GOLD_FIND, Stats.PICKUP_RANGE, Stats.XP_GAIN:
			return 0.5
	return 1.0


## Weighted value of [param p_item] for [param p_viewer] (stats + weapon DPS).
static func item_score(p_item: ItemInstance, p_viewer: ClassData) -> float:
	if p_item == null:
		return 0.0
	var score := 0.0
	var stats := total_stats(p_item)
	for stat in stats:
		score += stats[stat] * stat_weight(stat, p_viewer)
	var primary: StringName = p_viewer.primary_stat if p_viewer != null else &""
	score += weapon_dps(p_item, primary, NOMINAL_PRIMARY) * DPS_WEIGHT
	return score


## Simple "is it an upgrade" heuristic used by badges and bots: +1 better, -1 worse, 0 unclear.
## [param equipped] is what it would replace (equipped_for_compare). An item the viewer cannot
## use is never an upgrade, nor is anything that would leave the hero without an attacking
## weapon (a shield / tome replacing a two-hander; with [param equipment] every such case,
## Equipment.equip_disarms); anything else usable beats an empty slot. With [param equipment]
## tier sets count (SetBonuses.bonus_change): an item that would complete a set bonus is an
## upgrade unless its score is more than SET_UPGRADE_TOLERANCE below the replaced item's, one
## that would break an active bonus is worse unless the replaced piece's score is more than
## SET_UPGRADE_TOLERANCE below its own. Backpack pieces of the same sets count as worn, as
## many as the next threshold still needs ([method set_lookahead]), so a piece that makes the
## next threshold reachable counts too.
static func upgrade_direction(p_item: ItemInstance, equipped: ItemInstance, p_viewer: ClassData,
		equipment: Equipment = null) -> int:
	if p_item == null:
		return 0
	if p_viewer != null and not p_item.can_be_used_by(p_viewer):
		return -1
	if disarms(p_item, equipped, equipment):
		return -1
	# Artifacts (M6): a usable one always replaces what it would push out, and an equipped one is
	# never swapped for ordinary gear (it grows; bots must not flip-flop).
	if p_item.is_artifact():
		return 1
	if equipped != null and equipped.is_artifact():
		return -1
	if equipped == null:
		return 1
	var mine := item_score(p_item, p_viewer)
	var theirs := item_score(equipped, p_viewer)
	if equipment != null:
		var displaced: Array[ItemInstance] = [equipped]
		if equipped is EquippedPair:
			displaced.assign((equipped as EquippedPair).parts)
		var lookahead := set_lookahead(p_item, displaced, equipment, p_viewer)
		var change := SetBonuses.bonus_change(p_item, displaced, equipment, lookahead)
		if change > 0 and mine >= theirs * (1.0 - SET_UPGRADE_TOLERANCE):
			return 1
		if change < 0 and theirs >= mine * (1.0 - SET_UPGRADE_TOLERANCE):
			return -1
	var diff := mine - theirs
	if diff > UPGRADE_THRESHOLD:
		return 1
	if diff < -UPGRADE_THRESHOLD:
		return -1
	return 0


## The backpack set pieces [method upgrade_direction] may count as worn when it weighs
## [param p_item] against [param displaced] (SetBonuses.bonus_change's lookahead, which takes
## from them, best first, only what the next threshold of each set still needs): pieces of
## [param p_item]'s set or of a displaced piece's set that [param equipment] can equip into
## other slots, each going where no set piece is worn and scoring at most
## SET_UPGRADE_TOLERANCE below what it would replace (equipped_for_compare; an empty slot
## always qualifies). Best item_score first (backpack order on ties), one piece per slot – the
## best one. Empty when no set is involved.
static func set_lookahead(p_item: ItemInstance, displaced: Array[ItemInstance], equipment: Equipment,
		p_viewer: ClassData) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	if p_item == null or equipment == null:
		return out
	var sets: Array[StringName] = []
	if p_item.set_id != &"":
		sets.append(p_item.set_id)
	for d in displaced:
		if d != null and d.set_id != &"" and d.set_id not in sets:
			sets.append(d.set_id)
	if sets.is_empty():
		return out
	var pieces: Array[ItemInstance] = []
	var scores: Dictionary[ItemInstance, float] = {}
	for piece in equipment.backpack:
		if piece != null and piece != p_item and piece.set_id in sets and piece not in scores:
			pieces.append(piece)
			scores[piece] = item_score(piece, p_viewer)
	var order: Array[int] = []
	order.assign(range(pieces.size()))
	order.sort_custom(func(a: int, b: int) -> bool:
		return scores[pieces[a]] > scores[pieces[b]] or (scores[pieces[a]] == scores[pieces[b]] and a < b))
	var taken: Array[Items.EquipSlot] = []
	taken.append_array(equipment.target_slots(p_item))
	for i in order:
		var piece := pieces[i]
		if not equipment.can_equip(piece):
			continue
		var targets := equipment.target_slots(piece)
		var clash := false
		for t in targets:
			if t in taken:
				clash = true
		if clash:
			continue
		var there := equipped_for_compare(piece, equipment)
		if there != null and (there.set_id != &"" \
				or scores[piece] < item_score(there, p_viewer) * (1.0 - SET_UPGRADE_TOLERANCE)):
			continue
		taken.append_array(targets)
		out.append(piece)
	return out


## Whether equipping [param p_item] in place of [param equipped] would leave the hero without
## an attacking weapon: a non-attacking off-hand item (shield, tome) replacing a two-hander,
## or – when [param equipment] is given – anything Equipment.equip_disarms refuses.
static func disarms(p_item: ItemInstance, equipped: ItemInstance, equipment: Equipment = null) -> bool:
	if p_item == null or Equipment.is_attacking_weapon(p_item):
		return false
	if equipment != null and p_item.is_weapon() and equipment.equip_disarms(p_item):
		return true
	return equipped != null and equipped.is_two_handed() and Equipment.is_attacking_weapon(equipped)


## The equipped item [param p_item] would be compared with / replace: for rings, trinkets and
## dual-wield one-handers the weaker of the two (null when one of them is empty). Weapons
## compare with everything they push out: a two-hander with main + off hand together (an
## EquippedPair; the one that is there when only one hand is filled), an off-hand item or a
## one-hander next to an equipped two-hander with that two-hander (the off hand is not
## "empty" then).
static func equipped_for_compare(p_item: ItemInstance, equipment: Equipment) -> ItemInstance:
	if p_item == null or equipment == null:
		return null
	var targets := equipment.target_slots(p_item)
	if targets.is_empty():
		return null
	if p_item.is_weapon():
		var main := equipment.get_item(Items.EquipSlot.MAIN_HAND)
		var off := equipment.get_item(Items.EquipSlot.OFF_HAND)
		if p_item.is_two_handed() or p_item.companion != null:
			if main != null and off != null:
				return EquippedPair.of(main, off)
			return main if main != null else off
		if main != null and main.is_two_handed():
			return main
	if targets.size() == 1:
		return equipment.get_item(targets[0])
	var worst: ItemInstance = null
	var worst_score := INF
	for s in targets:
		var current := equipment.get_item(s)
		if current == null:
			return null
		var sc := item_score(current, equipment.class_data)
		if sc < worst_score:
			worst = current
			worst_score = sc
	return worst


## Whether [param p_item] carries the green "Looted" tag (tooltip, loot-roll info row): looted
## items do, an Artifact does not – it has no "Looted" Item Level bonus (10 + 3 x wave + 25).
static func shows_looted_tag(p_item: ItemInstance) -> bool:
	return p_item != null and p_item.looted and not p_item.is_artifact()


## "Head", "Finger", "One-Hand", "Two-Hand", "Off Hand" ...
static func slot_text(p_item: ItemInstance) -> String:
	if p_item.is_weapon():
		match p_item.weapon.hand:
			WeaponData.Hand.TWO_HAND:
				return "Two-Hand"
			WeaponData.Hand.OFF_HAND:
				return "Off Hand"
		return "One-Hand"
	return Items.SLOT_NAMES.get(p_item.slot_type, "")


## "Plate", "Cloth", "Sword", "Shield" ... ("" for jewellery and trinkets).
static func type_text(p_item: ItemInstance) -> String:
	if p_item.is_weapon():
		return WEAPON_TYPE_NAMES.get(p_item.weapon.weapon_type, String(p_item.weapon.weapon_type).capitalize())
	if p_item.armor_type != Items.NO_ARMOR:
		return Items.ARMOR_TYPE_NAMES.get(p_item.armor_type, "")
	return ""


## Whether [param p_viewer] is proficient with the item's armor / weapon type (class
## restrictions are shown on the "Classes:" line instead).
static func type_usable(p_item: ItemInstance, p_viewer: ClassData) -> bool:
	if p_viewer == null:
		return true
	if p_item.is_weapon():
		return p_viewer.can_use(p_item.weapon)
	return p_item.armor_type == Items.NO_ARMOR or p_item.armor_type <= p_viewer.armor_type


static func class_display_name(id: StringName) -> String:
	var data := Db.get_class_data(id) if Db != null else null
	return data.display_name if data != null else String(id).capitalize()


## Tooltip line of an enchant: its description, or "Equip: +N Stat" when it has none.
static func enchant_text(roll: EnchantRoll) -> String:
	if roll == null or roll.enchant == null:
		return ""
	var text := roll.description().strip_edges()
	if text != "":
		return text
	var parts := PackedStringArray()
	var extra := roll.equip_stats()
	for stat in _ordered(extra.keys()):
		parts.append("%s %s" % [Stats.format_value(stat, extra[stat]), Stats.display_name(stat)])
	return ("Equip: " + ", ".join(parts)) if not parts.is_empty() else ""


static func fmt_number(v: float, decimals: int = 1) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(int(roundf(v)))
	return ("%." + str(decimals) + "f") % v


## WoW line order: primary stats, then Stamina, then the rest in Stats.ALL order (unknown ids
## last, alphabetically).
static func _ordered(keys: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	var order: Array[StringName] = [Stats.STRENGTH, Stats.AGILITY, Stats.INTELLECT]
	order.append_array(Stats.ALL)
	for stat in order:
		if stat in out:
			continue
		if stat in keys:
			out.append(stat)
	var rest: Array[StringName] = []
	for k in keys:
		if StringName(k) not in out:
			rest.append(StringName(k))
	rest.sort()
	out.append_array(rest)
	return out


static func _italic_font() -> Font:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = ThemeDB.fallback_font
		_italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.22, 1.0), Vector2.ZERO)
	return _italic


# --- Building -------------------------------------------------------------------------------

func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if item == null:
		return
	_box.add_theme_constant_override(&"separation", COMPACT_ARTIFACT_SEPARATION if compact_artifact() else LINE_SEPARATION)
	var style := frame_style(item.rarity)
	if owner_tag != "":
		style.border = owner_color
		style.border_width = 3
		_line(owner_tag, owner_color, SMALL_SIZE, UiTheme.bold_font())
	add_theme_stylebox_override(&"panel", style)
	var rarity := clampi(item.rarity, 0, UiTheme.RARITY_COLORS.size() - 1)

	var title := _line(item.display_name, UiTheme.RARITY_COLORS[rarity], NAME_SIZE, UiTheme.bold_font())
	title.add_theme_constant_override(&"outline_size", 6)
	if shows_looted_tag(item):
		_line("Looted", ENCHANT_GREEN, SMALL_SIZE)
	_line("Item Level %d" % item.item_level, YELLOW, SMALL_SIZE)

	var usable := type_usable(item, viewer)
	_pair(slot_text(item), type_text(item), WHITE, WHITE if usable else UNUSABLE_RED)
	if item.is_weapon():
		_weapon_lines(item.weapon)

	var stats := item.all_stats()
	for stat in _ordered(stats.keys()):
		var v: float = stats[stat]
		if absf(v) < 0.001:
			continue
		_line("%s %s" % [Stats.format_value(stat, v), Stats.display_name(stat)], WHITE)

	if item.class_restriction != &"":
		var own := viewer == null or viewer.id == item.class_restriction
		# (The compact Artifact block leaves out the class line of the hero's own class: an
		# Artifact is always its class's.)
		if not (own and compact_artifact()):
			_line("Classes: %s" % class_display_name(item.class_restriction), WHITE if own else UNUSABLE_RED)
	for roll in item.enchants:
		var text := enchant_text(roll)
		if text != "":
			_line(text, ENCHANT_GREEN)
	if item.unique_text != "":
		_line(item.unique_text, ENCHANT_GREEN)
	if item.is_artifact():
		_artifact_block()
	if item.set_id != &"":
		_set_block()
	if item.flavor != "" and not compact_set() and not compact_artifact():
		var flavor := _line("\"%s\"" % item.flavor, YELLOW, SMALL_SIZE + 1, _italic_font())
		flavor.add_theme_constant_override(&"outline_size", 3)

	_gap(4)
	if price > 0:
		var affordable := RunState.can_afford(price)
		_price_row("Price:", price, YELLOW if affordable else UNUSABLE_RED, BODY_SIZE)
	if item.can_sell():
		_price_row("Sell Price:", item.sell_value(), WHITE, SMALL_SIZE)

	if comparison_visible and compare != null and compare != item:
		_comparison_block()
	_shrink_to_fit()


## The Artifact lines (see the class doc): pair note, then the two properties.
func _artifact_block() -> void:
	if item.pair_off:
		_line("Off-hand piece of a pair: it equips and unequips with its main hand", DIM, SMALL_SIZE)
		return
	if item.companion != null:
		_line("A pair: it equips together with %s" % item.companion.display_name, DIM, SMALL_SIZE)
	var rows := Artifacts.property_rows(item, _viewer_hero())
	if rows.is_empty():
		return
	_gap(3)
	for row in rows:
		var state: StringName = row["state"]
		var awake := state == Artifacts.STATE_AWAKE
		var color := ARTIFACT_GOLD if awake else (ARTIFACT_ASLEEP if state == Artifacts.STATE_ASLEEP else DIM)
		var status := ""
		match state:
			Artifacts.STATE_ASLEEP:
				status = Artifacts.awakens_text(int(row["waves_left"]))
			Artifacts.STATE_NEEDS_ABILITY:
				status = "(needs %s)" % row["needs"]
		_pair(str(row["name"]), status, color, DIM if not awake else color)
		_line(str(row["short"] if compact_artifact() else row["text"]), color, SMALL_SIZE)


## The hero looking at this tooltip (their equipment is [member viewer_equipment]; else the
## first joined hero of [member viewer]'s class): decides "(needs Whirlwind)". Null = unknown.
func _viewer_hero() -> Player:
	var fallback: Player = null
	for slot in PlayerManager.get_slots():
		var hero := slot.player as Player
		if hero == null or not is_instance_valid(hero):
			continue
		if viewer_equipment != null and hero.equipment == viewer_equipment:
			return hero
		if fallback == null and viewer != null and slot.class_data == viewer:
			fallback = hero
	return fallback if viewer_equipment == null else null


func _weapon_lines(w: WeaponData) -> void:
	if w.attacks():
		_pair("%s Damage" % fmt_number(w.base_damage), "Speed %.2f" % w.cooldown, WHITE, WHITE)
		# (This weapon alone: the pair's other dagger has its own tooltip, the comparison counts both.)
		_line("(%s damage per second)" % fmt_number(weapon_dps(item, &"", 0.0, false), 1), WHITE)
		var parts := PackedStringArray()
		for stat: StringName in _ordered(w.scaling.keys()):
			parts.append("%s %d%%" % [Stats.display_name(stat), roundi(float(w.scaling[stat]) * 100.0)])
		if not parts.is_empty() and not compact_artifact():
			_line("Scales with " + ", ".join(parts), DIM, SMALL_SIZE)
	if w.block_chance > 0.0:
		_line("%s%% Block Chance" % fmt_number(w.block_chance), WHITE)


## Whether the shown item gets the compact set block (a set piece with a viewer; see the
## class doc).
func compact_set() -> bool:
	return item != null and item.set_id != &"" and viewer_equipment != null


## Whether the shown item gets the compact Artifact block (an Artifact with a viewer: the player
## panels, the shop): each property's short text, no flavor text, no "Scales with" line and no
## class line for the hero's own class, the lines closer together, and the comparison block's
## differences flow in a few lines – an Artifact's two property blocks make
## the tallest tooltip of the game and a corner panel has no room for it in full.
## Without a viewer (the loot roll) everything keeps its full text.
func compact_artifact() -> bool:
	return item != null and item.is_artifact() and viewer_equipment != null


## The tier-set block (SetBonuses.describe for [member viewer_equipment]); a set_id without
## SetData keeps the plain "Part of the … set" line.
func _set_block() -> void:
	var rows := SetBonuses.describe(item, viewer_equipment)
	if rows.is_empty():
		_line("Part of the %s set" % String(item.set_id).capitalize(), DIM, SMALL_SIZE)
		return
	_gap(4)
	# The pieces flow in a few lines ("• Helm  • Pauldrons …") instead of five rows – in the
	# compact block one line of slot names: tooltips inside a player panel shrink to the
	# panel's height, so every line counts.
	var compact := compact_set()
	var pieces: HFlowContainer = null
	var first_bonus := true
	for row in rows:
		var text := str(row.get("text", ""))
		var active: bool = row.get("active", false)
		match row.get("kind"):
			SetBonuses.ROW_HEADER:
				_line(text, SET_NAME_COLOR, BODY_SIZE)
			SetBonuses.ROW_PIECE:
				if pieces == null:
					pieces = _piece_flow(compact)
				var color := SET_PIECE_WORN if active else SET_PIECE_MISSING
				if compact:
					pieces.add_child(_slot_entry(str(row.get("slot", text)), color))
				else:
					pieces.add_child(_piece_entry(text, color))
			SetBonuses.ROW_BONUS:
				if first_bonus:
					_gap(4)
					first_bonus = false
				_line(text, ENCHANT_GREEN if active else DIM, SMALL_SIZE)


## An indented flow row for the set's piece names (under the set name); [param compact]: the
## slot names' row (no indent, SET_SLOT_GAP apart).
func _piece_flow(compact: bool = false) -> HFlowContainer:
	var indent := MarginContainer.new()
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indent.add_theme_constant_override(&"margin_left", 0 if compact else SET_PIECE_INDENT)
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override(&"h_separation", SET_SLOT_GAP if compact else 14)
	flow.add_theme_constant_override(&"v_separation", 0)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	indent.add_child(flow)
	_box.add_child(indent)
	return flow


## "• <piece name>" as one unit of the flow (bullet and name never split across lines).
func _piece_entry(text: String, color: Color) -> HBoxContainer:
	var entry := UiTheme.hbox(5)
	for t in ["•", text]:
		var l := UiTheme.label(t, &"", SMALL_SIZE, color)
		l.add_theme_constant_override(&"outline_size", 4)
		l.add_theme_constant_override(&"shadow_offset_y", 1)
		entry.add_child(l)
	return entry


## One slot name of the compact set block ("Shoulders"), bright when worn.
func _slot_entry(text: String, color: Color) -> Label:
	var l := UiTheme.label(text, &"", SMALL_SIZE, color)
	l.add_theme_constant_override(&"outline_size", 4)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	return l


func _comparison_block() -> void:
	_gap(2)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_constant_override(&"separation", 6)
	_box.add_child(rule)
	_line("If you replace this item:", YELLOW, SMALL_SIZE)
	var rc := UiTheme.RARITY_COLORS[clampi(compare.rarity, 0, UiTheme.RARITY_COLORS.size() - 1)]
	_line("Equipped: %s (ilvl %d)" % [compare.display_name, compare.item_level], rc.lerp(DIM, 0.35), SMALL_SIZE)
	var any := false
	# The compact Artifact block: the differences flow in a few lines instead of one row each.
	var flow: HFlowContainer = _delta_flow() if compact_artifact() else null
	if item.is_weapon() or compare.is_weapon():
		var dps := weapon_dps(item) - weapon_dps(compare)
		if absf(dps) >= 0.05:
			_delta_line("%s%s Damage per second" % ["+" if dps > 0.0 else "", fmt_number(dps, 1)], DELTA_GREEN if dps > 0.0 else DELTA_RED, flow)
			any = true
	var delta := stat_delta(item, compare)
	for stat in _ordered(delta.keys()):
		var v: float = delta[stat]
		_delta_line("%s %s" % [Stats.format_value(stat, v), Stats.display_name(stat)], DELTA_GREEN if v > 0.0 else DELTA_RED, flow)
		any = true
	if not any:
		_line("No stat changes", DIM, SMALL_SIZE)


## One difference of the comparison block: its own row, or – in the compact Artifact block – one
## unit of [param flow].
func _delta_line(text: String, color: Color, flow: HFlowContainer) -> void:
	if flow == null:
		_line(text, color)
		return
	var l := UiTheme.label(text, &"", BODY_SIZE, color)
	l.add_theme_constant_override(&"outline_size", 4)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	flow.add_child(l)


## The wrapping row the compact Artifact comparison block puts its differences in.
func _delta_flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override(&"h_separation", DELTA_FLOW_GAP)
	flow.add_theme_constant_override(&"v_separation", 0)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(flow)
	return flow


func _line(text: String, color: Color, font_size: int = BODY_SIZE, font: Font = null) -> Label:
	var l := UiTheme.wrapped_label(text, &"", font_size, color)
	l.add_theme_constant_override(&"outline_size", 4)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	if font != null:
		l.add_theme_font_override(&"font", font)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(l)
	return l


func _pair(left: String, right: String, left_color: Color, right_color: Color) -> HBoxContainer:
	var row := UiTheme.hbox(8)
	var l := UiTheme.label(left, &"", BODY_SIZE, left_color)
	l.add_theme_constant_override(&"outline_size", 4)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if right != "":
		var r := UiTheme.label(right, &"", BODY_SIZE, right_color)
		r.add_theme_constant_override(&"outline_size", 4)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(r)
	_box.add_child(row)
	return row


func _price_row(caption: String, amount: int, color: Color, font_size: int) -> void:
	var row := UiTheme.hbox(6)
	var l := UiTheme.label(caption, &"", font_size, WHITE)
	l.add_theme_constant_override(&"outline_size", 4)
	row.add_child(l)
	var v := UiTheme.label(UiTheme.format_int(amount), &"", font_size, color)
	v.add_theme_constant_override(&"outline_size", 4)
	v.add_theme_font_override(&"font", UiTheme.bold_font())
	row.add_child(v)
	var coin := UiIcon.create(UiIcon.Kind.COIN, Vector2(font_size, font_size) * 0.9)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	_box.add_child(row)


func _gap(h: float) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(0, h)
	_box.add_child(c)


## Free-floating tooltips shrink back to their content (a Control only grows by itself).
func _shrink_to_fit() -> void:
	if get_parent() is Container:
		return
	if size != get_combined_minimum_size():
		reset_size()


static func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in node.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out
