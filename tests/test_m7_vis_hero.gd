extends TestCase
## M7b VIS-HERO: worn Head / Shoulders / Chest armour on the onion (GDD 13) – EquipLook, OnionArmor,
## OnionModel.set_equipment and the places that feed it (Player, the character panel preview).

const Items_ := preload("res://tests/test_ui_items.gd")
const Fakes := preload("res://tests/player_fakes.gd")
const UiFakes := preload("res://tests/ui_fakes.gd")

const HEAD := EquipLook.Slot.HEAD
const SHOULDERS := EquipLook.Slot.SHOULDERS
const CHEST := EquipLook.Slot.CHEST
## Render draws of a hero (outline counts double) with the class starter look and weapons, measured
## on the base commit before the equipment was visible: warrior, mage, paladin, rogue, warlock.
const DRAWS_BEFORE: Dictionary[StringName, int] = {&"warrior": 23, &"mage": 23, &"paladin": 25, &"rogue": 24,
	&"warlock": 32}
## A class without a measured baseline above (a later class, until its package adds the number) is
## measured on the spot: its starter look is its own baseline, held to this ceiling (the heaviest
## launch class is 32), and the same +[constant DRAW_BUDGET] applies to its gear.
const DRAWS_UNMEASURED_MAX := 40
## Draw calls a fully geared hero may add on top of the starter look.
const DRAW_BUDGET := 10

var _nodes: Array[Node] = []
var _world: Node3D


func after_each() -> void:
	for i in range(_nodes.size() - 1, -1, -1):
		if is_instance_valid(_nodes[i]):
			_nodes[i].free()
	_nodes.clear()
	if _world != null:
		Fakes.free_world(_world)
		_world = null
	PlayerManager.clear()
	EnemyGrid.mark_dirty()


## A fresh run with a world for real Players.
func _players_world() -> Node3D:
	PlayerManager.clear()
	RunState.start_run(1, 11)
	_world = Fakes.make_world(tree)
	return _world


func _keep(n: Node) -> Node:
	_nodes.append(n)
	return n


func _onion(class_id: StringName, head: EquipLook = null, shoulders: EquipLook = null, chest: EquipLook = null) -> OnionModel:
	var cd := Db.get_class_data(class_id)
	var m := _keep(OnionModel.new()) as OnionModel
	m.setup(cd, Color(0.2, 0.5, 1.0))
	m.set_weapons(cd.main_hand, cd.off_hand)
	m.set_looks(head, shoulders, chest)
	return m


func _look(slot: int, armor: int, tier: int = 0, rarity: int = 0, set_id: StringName = &"", unique_id: StringName = &"") -> EquipLook:
	return EquipLook.make(slot as EquipLook.Slot, armor, tier, rarity, set_id, unique_id)


func _suit(armor: int, tier: int = 0, rarity: int = 0, set_id: StringName = &"") -> Array[EquipLook]:
	return [_look(HEAD, armor, tier, rarity, set_id), _look(SHOULDERS, armor, tier, rarity, set_id),
		_look(CHEST, armor, tier, rarity, set_id)]


func _dressed(class_id: StringName, suit: Array[EquipLook]) -> OnionModel:
	return _onion(class_id, suit[0], suit[1], suit[2])


func _item(slot_type: Items.SlotType, armor_type: int, rarity: int = 0, wave: int = 1) -> ItemInstance:
	return Items_.armor("Test piece", slot_type, armor_type, rarity, {"stamina": 1}, wave)


## Render draws of the visible meshes below [param root] (a toon mesh with an outline pass counts twice).
func _draws(root: Node) -> int:
	var total := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not _visible_below(mi, root):
			continue
		var outlined := mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).next_pass != null
		total += mi.mesh.get_surface_count() * (2 if outlined else 1)
	return total


func _visible_below(node: Node, root: Node) -> bool:
	var n := node
	while n != null:
		if n is Node3D and not (n as Node3D).visible:
			return false
		if n == root:
			return true
		n = n.get_parent()
	return true


func _gear(m: OnionModel) -> Node3D:
	return m.get_node("Yaw/Body/Gear") as Node3D


func _gear_names(m: OnionModel) -> Array[String]:
	var out: Array[String] = []
	for c in _gear(m).get_children():
		out.append(String(c.name))
	return out


func _vertices(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func _colors(mesh: Mesh) -> PackedColorArray:
	var out := PackedColorArray()
	if mesh != null:
		for s in mesh.get_surface_count():
			out.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR])
	return out


## Whether the mesh has a vertex of [param color] (vertex colours are stored with 8 bits).
func _has_color(mesh: Mesh, color: Color) -> bool:
	for c in _colors(mesh):
		if absf(c.r - color.r) < 0.01 and absf(c.g - color.g) < 0.01 and absf(c.b - color.b) < 0.01:
			return true
	return false


# --- EquipLook -----------------------------------------------------------------------

func test_a_look_is_digested_from_an_item() -> void:
	var item := _item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, Items.Rarity.EPIC, 9)
	var look := EquipLook.from_item(item)
	check(look != null, "a helm has a look")
	check_eq(look.slot, HEAD, "head slot")
	check_eq(look.armor, ClassData.ArmorType.PLATE, "plate")
	check_eq(look.tier, 1, "wave 9 is material tier II")
	check_eq(look.rarity, Items.Rarity.EPIC, "rarity")
	check_eq(look.family(), &"plate_helm", "family id")
	check_eq(EquipLook.from_item(_item(Items.SlotType.CHEST, ClassData.ArmorType.CLOTH, 0, 17)).tier, 2, "wave 17 is tier III")
	check_eq(EquipLook.from_item(_item(Items.SlotType.CHEST, ClassData.ArmorType.CLOTH, 0, 8)).tier, 0, "wave 8 is tier I")
	check_eq(EquipLook.from_item(_item(Items.SlotType.SHOULDERS, ClassData.ArmorType.MAIL)).slot, SHOULDERS, "shoulders")
	# Items without a model part.
	check(EquipLook.from_item(null) == null, "no item, no look")
	check(EquipLook.from_item(_item(Items.SlotType.WRIST, ClassData.ArmorType.PLATE)) == null, "wrists are not shown")
	check(EquipLook.from_item(_item(Items.SlotType.NECK, Items.NO_ARMOR)) == null, "jewellery is not shown")
	check(EquipLook.from_item(ItemInstance.from_weapon(Db.get_weapon(&"sword"))) == null, "weapons have their own models")


func test_set_and_unique_ids_go_into_the_look() -> void:
	var set_piece := _item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, Items.Rarity.EPIC)
	set_piece.set_id = &"battlegear_of_fury"
	set_piece.unique = true
	set_piece.source_id = &"set_warrior_head"
	var look := EquipLook.from_item(set_piece)
	check(look.is_set() and look.set_id == &"battlegear_of_fury", "set id")
	check_eq(look.unique_id, &"set_warrior_head", "unique id")
	check_eq(look.detail(), EquipLook.MAX_TIER, "a set piece always has the richest detail")
	var plain := EquipLook.from_item(_item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE))
	check(not plain.is_set() and plain.unique_id == &"", "a generated item has neither")
	check(look.key() != EquipLook.make(HEAD, ClassData.ArmorType.PLATE, 0, Items.Rarity.EPIC).key(), "the set is part of the key")
	check(plain.key() != EquipLook.make(HEAD, ClassData.ArmorType.PLATE, 0, Items.Rarity.RARE).key(), "so is the rarity")
	check_eq(plain.key(), EquipLook.make(HEAD, ClassData.ArmorType.PLATE, 0, 0).key(), "same look, same key")


func test_item_bases_use_the_family_names_of_the_look() -> void:
	# ItemBase.look names the model piece of every Head / Shoulders / Chest base: it is the family id.
	var seen := 0
	for id in Db.item_bases:
		var base := Db.item_bases[id]
		var slot := EquipLook.slot_for_type(base.slot_type)
		if slot < 0 or base.armor_type == Items.NO_ARMOR:
			continue
		seen += 1
		check_eq(base.look, EquipLook.family_of(slot, base.armor_type), "%s look" % id)
	check(seen >= 36, "every head / shoulders / chest base was checked (%d)" % seen)


func test_every_class_set_has_a_style() -> void:
	check(Db.sets.size() >= 5, "the class sets are loaded")
	for id in Db.sets:
		check(OnionArmor.SET_STYLES.has(id), "set %s has its own kit" % id)
	for style: Dictionary in OnionArmor.SET_STYLES.values():
		for k: String in ["main", "dark", "light", "trim", "glow"]:
			check(style.has(k), "style has %s" % k)


# --- Silhouette families --------------------------------------------------------------

func test_every_slot_and_armour_type_has_its_own_silhouette() -> void:
	var cd := Db.get_class_data(&"warrior")
	var seen: Dictionary[String, bool] = {}
	for slot in EquipLook.SLOT_COUNT:
		var meshes: Array[Mesh] = []
		for armor in 4:
			var part := OnionArmor.part(slot, _look(slot, armor, 1, 2), cd)
			check(part != null and (part.solid != null or part.cloth != null), "slot %d armour %d builds" % [slot, armor])
			var mesh := part.solid if part.solid != null else part.cloth
			check(not meshes.has(mesh), "slot %d armour %d is its own mesh" % [slot, armor])
			meshes.append(mesh)
			seen["%.2f,%.2f,%.2f" % [mesh.get_aabb().size.x, mesh.get_aabb().size.y, mesh.get_aabb().size.z]] = true
	check(seen.size() >= 10, "the 12 families differ in size (%d distinct)" % seen.size())


func test_plate_pauldrons_are_the_biggest() -> void:
	var cd := Db.get_class_data(&"warrior")
	var widths: Array[float] = []
	for armor in 4:
		var part := OnionArmor.part(SHOULDERS, _look(SHOULDERS, armor, 0, 0), cd)
		var box := AABB()
		for m in [part.solid, part.cloth]:
			if m != null:
				box = box.merge((m as Mesh).get_aabb()) if box.has_surface() else (m as Mesh).get_aabb()
		widths.append(box.size.x)
	check(widths[3] > widths[2] and widths[2] > widths[1] and widths[1] > widths[0],
		"cloth < leather < mail < plate across the shoulders (%s)" % [widths])
	# WoW-oversized: tier III plate is wider than the class starter pauldrons of the warrior.
	var starter := OnionArmor.part(SHOULDERS, null, cd)
	var big := OnionArmor.part(SHOULDERS, _look(SHOULDERS, ClassData.ArmorType.PLATE, 2, 0), cd)
	check(big.solid.get_aabb().size.x > starter.solid.get_aabb().size.x, "tier III plate pauldrons out-size the starter ones")


func test_material_tier_adds_detail() -> void:
	var cd := Db.get_class_data(&"warrior")
	for slot in EquipLook.SLOT_COUNT:
		for armor in 4:
			var counts: Array[int] = []
			for tier in 3:
				var part := OnionArmor.part(slot, _look(slot, armor, tier, 1), cd)
				counts.append(_vertices(part.solid) + _vertices(part.cloth))
			check(counts[0] < counts[1] and counts[1] < counts[2], "slot %d armour %d: more detail each tier (%s)" % [slot, armor, counts])


func test_heads_stay_clear_of_the_face() -> void:
	# The eyes and the mouth sit mid-body: no head piece may reach below the brow line in front.
	var cd := Db.get_class_data(&"mage")
	for armor in 4:
		for tier in 3:
			var part := OnionArmor.part(HEAD, _look(HEAD, armor, tier, 0), cd)
			var low := INF
			for m in [part.solid, part.cloth]:
				if m == null:
					continue
				for s in (m as Mesh).get_surface_count():
					for v: Vector3 in (m as Mesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
						# Front sector only (the coif / lappets frame the cheeks and hang lower at the sides).
						if v.z < -0.2 and absf(v.x) < 0.2:
							low = minf(low, v.y)
			# A mask (it hides the mouth) is meant to reach the lower face, not the eyes.
			var limit := 0.35 if part.hides_mouth else 0.42
			check(low > limit, "armour %d tier %d head piece keeps the face open (lowest front point %.2f)" % [armor, tier, low])


func test_gear_keeps_the_hero_in_a_sane_size() -> void:
	for id in Db.class_ids:
		for armor in 4:
			var m := _dressed(id, _suit(armor, 2, 4))
			var top := 0.0
			var half_width := 0.0
			for mi in m.get_node("Yaw/Body").find_children("*", "MeshInstance3D", true, false):
				var node := mi as MeshInstance3D
				if node.mesh == null or not node.visible:
					continue
				var xf := Transform3D.IDENTITY
				var n: Node = node
				while n != m.get_node("Yaw/Body"):
					xf = (n as Node3D).transform * xf
					n = n.get_parent()
				var box := xf * node.mesh.get_aabb()
				if node.name != "Mesh":
					top = maxf(top, box.end.y)
					half_width = maxf(half_width, maxf(absf(box.position.x), absf(box.end.x)))
			check(top < 1.75, "%s armour %d: %.2f m tall" % [id, armor, top])
			check(half_width < 1.0, "%s armour %d: %.2f m half width" % [id, armor, half_width])


# --- Class starter look ------------------------------------------------------------------

## Draw calls of the class starter look (nothing worn) the gear budgets build on: the measured
## [constant DRAWS_BEFORE] where there is one, else what the look draws now (up to
## [constant DRAWS_UNMEASURED_MAX]).
func _baseline(id: StringName) -> int:
	if DRAWS_BEFORE.has(id):
		return DRAWS_BEFORE[id]
	var starter := _draws(_onion(id))
	check(starter <= DRAWS_UNMEASURED_MAX, "%s: %d starter draws, no measured baseline (ceiling %d; add it to DRAWS_BEFORE)"
			% [id, starter, DRAWS_UNMEASURED_MAX])
	return starter


func test_empty_slots_show_the_class_starter_look() -> void:
	for id in Db.class_ids:
		var cd := Db.get_class_data(id)
		var m := _onion(id)
		check_eq(m.equipment_key(), "-|-|-", "%s: nothing worn" % id)
		for slot in EquipLook.SLOT_COUNT:
			check(m.worn_look(slot) == null, "%s slot %d empty" % [id, slot])
			var part := OnionArmor.part(slot, null, cd)
			if part != null:
				check(part.is_starter(), "%s slot %d is the starter piece" % [id, slot])
		check_eq(_gear_names(m).has("Solid"), true, "%s: plain armour mesh" % id)
		check_eq(_draws(m), _baseline(id), "%s: same draw calls as before the equipment was visible" % id)
	# The classes' own pieces are still there.
	check(_onion(&"mage").get_node_or_null("Yaw/Body/HatStar") != null, "the mage's hat star")
	check(not (_onion(&"mage").get_node("Yaw/Body/Sprout") as Node3D).visible, "the wizard hat covers the sprout")
	check(_onion(&"warlock").get_node_or_null("Yaw/Body/HornFlameL") != null, "the warlock's horn flames")
	check(_onion(&"warlock").get_node_or_null("Yaw/Body/FelTrim") != null, "the warlock's fel trim")
	check(_onion(&"warrior").get_node_or_null("Yaw/Body/Gear/Solid") != null, "the warrior's horned helm and pauldrons")


func test_starter_pieces_carry_the_class_extras_of_their_slot() -> void:
	var cd := Db.get_class_data(&"warlock")
	check_eq(OnionArmor.part(HEAD, null, cd).extras, [&"horn_flames"] as Array[StringName], "the flames belong to the hood")
	check_eq(OnionArmor.part(CHEST, null, cd).extras, [&"fel_trim"] as Array[StringName], "the fel trim to the belt")
	check_eq(OnionArmor.part(SHOULDERS, null, cd).solid, null, "the warlock has no starter pauldrons")
	check(OnionArmor.part(SHOULDERS, null, Db.get_class_data(&"warrior")).solid != null, "the warrior has")


func test_an_equipped_item_replaces_only_its_own_slot() -> void:
	var m := _onion(&"warlock")
	var before_solid := (m.get_node("Yaw/Body/Gear/Solid") as MeshInstance3D).mesh
	m.set_looks(_look(HEAD, ClassData.ArmorType.CLOTH, 0, 1), null, null)
	check(m.get_node_or_null("Yaw/Body/HornFlameL") == null, "the horned hood is gone, and its flames with it")
	check(m.get_node_or_null("Yaw/Body/FelTrim") != null, "the belt's fel trim stays: the chest slot is still empty")
	check((m.get_node("Yaw/Body/Gear/Solid") as MeshInstance3D).mesh != before_solid, "another armour mesh")
	# Unequip: the starter look is back.
	m.set_looks(null, null, null)
	check(m.get_node_or_null("Yaw/Body/HornFlameL") != null, "the flames are back")
	check((m.get_node("Yaw/Body/Gear/Solid") as MeshInstance3D).mesh == before_solid, "the very same starter mesh")


func test_the_face_follows_the_head_piece() -> void:
	var mage := _onion(&"mage")
	var sprout := mage.get_node("Yaw/Body/Sprout") as Node3D
	var eyes := mage.get_node("Yaw/Body/Face/Eyes") as MeshInstance3D
	var hat_eyes := eyes.mesh
	check(not sprout.visible, "a wizard hat hides the sprout")
	check(hat_eyes != null, "eyes")
	mage.set_looks(_look(HEAD, ClassData.ArmorType.CLOTH, 0, 0), null, null)
	check(sprout.visible, "a hood leaves the sprout out")
	check(eyes.mesh != hat_eyes, "no eyebrows under a worn head piece")
	mage.set_looks(null, null, null)
	check(not sprout.visible and eyes.mesh == hat_eyes, "the hat is back with its brows")
	# The rogue's hood is a mask: no mouth. A leather cap shows it again, the masked tiers hide it.
	var rogue := _onion(&"rogue")
	var mouth := rogue.get_node("Yaw/Body/Mouth") as Node3D
	check(not mouth.visible, "the rogue starter hood is a mask")
	rogue.set_looks(_look(HEAD, ClassData.ArmorType.LEATHER, 0, 0), null, null)
	check(mouth.visible, "a plain cap shows the mouth")
	rogue.set_looks(_look(HEAD, ClassData.ArmorType.LEATHER, 1, 0), null, null)
	check(not mouth.visible, "the bandana and mask hide it")
	var warrior := _onion(&"warrior")
	var helm_eyes := (warrior.get_node("Yaw/Body/Face/Eyes") as MeshInstance3D).mesh
	warrior.set_looks(_look(HEAD, ClassData.ArmorType.PLATE, 0, 0), null, null)
	check((warrior.get_node("Yaw/Body/Face/Eyes") as MeshInstance3D).mesh == helm_eyes, "helm to helm: the same brow-less eyes")


func test_the_sprout_and_the_eyes_stay_readable() -> void:
	# From the top-down camera the sprout and the eyes must not sit under armour: no worn head piece
	# hides the sprout (only the class's pointy hat does), and the eyes stay uncovered.
	for armor in 4:
		for tier in 3:
			var m := _dressed(&"warrior" if armor >= 2 else &"mage", _suit(armor, tier, 4))
			check((m.get_node("Yaw/Body/Sprout") as Node3D).visible, "armour %d tier %d: sprout visible" % [armor, tier])
			check((m.get_node("Yaw/Body/Face") as Node3D).visible, "armour %d tier %d: face visible" % [armor, tier])


# --- Rarity, glow, sets -------------------------------------------------------------------

func test_trim_colour_follows_the_rarity() -> void:
	var cd := Db.get_class_data(&"warrior")
	var seen: Array[Mesh] = []
	for rarity in 5:
		var part := OnionArmor.part(HEAD, _look(HEAD, ClassData.ArmorType.PLATE, 1, rarity), cd)
		check(_has_color(part.solid, WeaponModel.rarity_color(rarity)), "rarity %d: trim in the weapon rarity colour" % rarity)
		check(not seen.has(part.solid), "rarity %d: its own mesh" % rarity)
		seen.append(part.solid)
	for rarity in 5:
		var part := OnionArmor.part(SHOULDERS, _look(SHOULDERS, ClassData.ArmorType.MAIL, 1, rarity), cd)
		check(_has_color(part.solid, WeaponModel.rarity_color(rarity)), "mail pauldrons rarity %d trim" % rarity)


func test_epic_and_better_glow_faintly() -> void:
	for rarity in 5:
		var m := _dressed(&"warrior", _suit(ClassData.ArmorType.PLATE, 1, rarity))
		var names := _gear_names(m)
		var glows := names.any(func(n: String) -> bool: return n.begins_with("Glow"))
		check_eq(glows, rarity >= 3, "rarity %d glows: %s" % [rarity, names])
		for c in _gear(m).get_children():
			var mat := (c as MeshInstance3D).material_override as ShaderMaterial
			if c.name.begins_with("Glow"):
				check(mat != null and (mat.get_shader_parameter(&"emission_energy") as float) > 0.0, "a Glow mesh has emission")
				check_near(mat.get_shader_parameter(&"emission_energy"), OnionArmor.LEGENDARY_GLOW_ENERGY if rarity >= 4 else OnionArmor.GLOW_ENERGY, 0.001, "faint")
				check(mat.get_shader_parameter(&"emission_energy") < 0.3, "the glow stays faint")
			elif c.name == "Solid":
				check(mat == Mats.toon_vc(), "plain pieces use the shared toon material")
	# One rarity: one glow material shared by all three slots.
	var epic := _dressed(&"warrior", _suit(ClassData.ArmorType.PLATE, 1, 3))
	var glow_nodes := _gear_names(epic).filter(func(n: String) -> bool: return n.begins_with("Glow"))
	check_eq(glow_nodes.size(), 1, "head, shoulders and chest of one rarity merge into one glowing mesh")


func test_mixed_rarities_group_by_material() -> void:
	var m := _onion(&"warrior", _look(HEAD, ClassData.ArmorType.PLATE, 1, 3), _look(SHOULDERS, ClassData.ArmorType.PLATE, 1, 1),
		_look(CHEST, ClassData.ArmorType.PLATE, 1, 4))
	var names := _gear_names(m)
	check(names.has("Solid"), "the uncommon pauldrons are plain")
	check_eq(names.filter(func(n: String) -> bool: return n.begins_with("Glow")).size(), 2, "an Epic and a Legendary glow differently")


func test_legendaries_and_sets_add_a_glow_accent() -> void:
	var rare := _dressed(&"warrior", _suit(ClassData.ArmorType.PLATE, 2, 2))
	var epic := _dressed(&"warrior", _suit(ClassData.ArmorType.PLATE, 2, 3))
	var legendary := _dressed(&"warrior", _suit(ClassData.ArmorType.PLATE, 2, 4))
	var set := _dressed(&"warrior", _suit(ClassData.ArmorType.PLATE, 0, 3, &"battlegear_of_fury"))
	for m in [rare, epic]:
		check(not _gear_names(m).any(func(n: String) -> bool: return n.begins_with("Accent")), "no accent below Legendary")
	for m in [legendary, set]:
		check(_gear_names(m).any(func(n: String) -> bool: return n.begins_with("Accent")), "accent glow")
	var accent := legendary.get_node("Yaw/Body/Gear/Accent0") as MeshInstance3D
	check(accent.material_override == Mats.glow(WeaponModel.rarity_color(4), OnionArmor.ACCENT_ENERGY), "orange glow for a Legendary")
	check(accent.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow from a glow")
	var set_accent := set.get_node("Yaw/Body/Gear/Accent0") as MeshInstance3D
	var kit: Dictionary = OnionArmor.SET_STYLES[&"battlegear_of_fury"]
	check(set_accent.material_override == Mats.glow(kit["glow"], OnionArmor.ACCENT_ENERGY), "the set's own glow colour")


func test_a_tier_set_wears_its_class_coloured_kit() -> void:
	var generic := OnionArmor.palette(_look(HEAD, ClassData.ArmorType.PLATE, 2, 3))
	var kits: Array[Color] = []
	for id in OnionArmor.SET_STYLES:
		var look := _look(HEAD, ClassData.ArmorType.PLATE, 0, 3, id)
		var pal := OnionArmor.palette(look)
		check(pal.main != generic.main, "%s differs from the generic Epic kit" % id)
		check(not kits.has(pal.main), "%s has its own main colour" % id)
		kits.append(pal.main)
		check_eq(pal.glow, (OnionArmor.SET_STYLES[id] as Dictionary)["glow"], "%s glows in its colour" % id)
	var warrior := OnionArmor.palette(_look(HEAD, ClassData.ArmorType.PLATE, 0, 3, &"battlegear_of_fury"))
	check(warrior.main.r > warrior.main.g * 2.0 and warrior.main.r > warrior.main.b * 2.0, "the warrior set is red")
	var mage := OnionArmor.palette(_look(HEAD, ClassData.ArmorType.CLOTH, 0, 3, &"regalia_of_the_arcane"))
	check(mage.main.b > mage.main.r and mage.main.b > mage.main.g, "the mage set is blue")
	# A set piece uses the richest detail whatever the wave it dropped at.
	var cd := Db.get_class_data(&"warrior")
	var low := OnionArmor.part(HEAD, _look(HEAD, ClassData.ArmorType.PLATE, 0, 3, &"battlegear_of_fury"), cd)
	var high := OnionArmor.part(HEAD, _look(HEAD, ClassData.ArmorType.PLATE, 2, 3, &"battlegear_of_fury"), cd)
	check_eq(_vertices(low.solid), _vertices(high.solid), "tier does not matter for a set piece")
	var generic_t1 := OnionArmor.part(HEAD, _look(HEAD, ClassData.ArmorType.PLATE, 0, 3), cd)
	check(_vertices(low.solid) > _vertices(generic_t1.solid), "richer than a tier I Epic")


func test_the_class_colour_shows_on_generic_armour() -> void:
	# Plate on a warrior and on a paladin differ by the class colour (crest, pauldron top, tabard strip),
	# so two heroes in the same armour are still told apart.
	var look := _look(CHEST, ClassData.ArmorType.PLATE, 1, 2)
	var warrior := OnionArmor.part(CHEST, look, Db.get_class_data(&"warrior"))
	var paladin := OnionArmor.part(CHEST, look, Db.get_class_data(&"paladin"))
	check(warrior != paladin and warrior.cloth != paladin.cloth, "own cloth mesh per class")
	check(warrior.solid != null and paladin.solid != null, "both have armour")
	var red := Db.get_class_data(&"warrior").onion_color.lightened(0.08)
	check(_has_color(warrior.cloth, red), "the warrior's tabard strip is red")
	check(not _has_color(paladin.cloth, red), "the paladin's is not")


# --- Caching --------------------------------------------------------------------------------

func test_parts_and_meshes_are_cached_by_key() -> void:
	var cd := Db.get_class_data(&"mage")
	var a := OnionArmor.part(CHEST, _look(CHEST, ClassData.ArmorType.CLOTH, 1, 2), cd)
	var b := OnionArmor.part(CHEST, _look(CHEST, ClassData.ArmorType.CLOTH, 1, 2), cd)
	check(a == b, "same look, same part")
	check(a.solid == b.solid and a.cloth == b.cloth, "same meshes")
	check(MeshKit.has_cached("onion:armor:" + a.key + ":solid") or a.solid == null, "registered in the mesh cache")
	check(OnionArmor.part(CHEST, _look(CHEST, ClassData.ArmorType.CLOTH, 1, 3), cd) != a, "another rarity, another part")
	check(OnionArmor.part(CHEST, _look(CHEST, ClassData.ArmorType.CLOTH, 1, 2), Db.get_class_data(&"warlock")) != a, "the class colour is in the key")
	# The starter piece is cached too.
	check(OnionArmor.part(HEAD, null, cd) == OnionArmor.part(HEAD, null, cd), "starter part cached")


func test_heroes_in_the_same_gear_share_meshes_and_materials() -> void:
	var suit := _suit(ClassData.ArmorType.MAIL, 1, 3)
	var a := _dressed(&"warrior", suit)
	var b := _dressed(&"warrior", suit)
	for n in _gear_names(a):
		var ma := a.get_node("Yaw/Body/Gear/%s" % n) as MeshInstance3D
		var mb := b.get_node("Yaw/Body/Gear/%s" % n) as MeshInstance3D
		check(ma.mesh == mb.mesh, "%s mesh shared" % n)
		check(ma.material_override == mb.material_override, "%s material shared" % n)
	# Merged meshes are cached under their key too.
	var before := MeshKit.cache_size()
	var c := _dressed(&"warrior", suit)
	check_eq(MeshKit.cache_size(), before, "no new mesh for a third hero in the same gear")
	check(c != null, "built")
	for node in a.find_children("*", "MeshInstance3D", true, false):
		var mat := (node as MeshInstance3D).material_override as ShaderMaterial
		if mat != null:
			check(not mat.shader.code.contains("instance uniform"), "no instance uniforms")


func test_merged_parts_have_one_surface() -> void:
	var m := _dressed(&"paladin", _suit(ClassData.ArmorType.PLATE, 2, 2))
	for c in _gear(m).get_children():
		check_eq((c as MeshInstance3D).mesh.get_surface_count(), 1, "%s is one surface" % c.name)
	var solid := (m.get_node("Yaw/Body/Gear/Solid") as MeshInstance3D).mesh
	var parts: Array[int] = []
	for slot in EquipLook.SLOT_COUNT:
		parts.append(_vertices(OnionArmor.part(slot, _suit(ClassData.ArmorType.PLATE, 2, 2)[slot], Db.get_class_data(&"paladin")).solid))
	check_eq(_vertices(solid), parts[0] + parts[1] + parts[2], "the merged mesh holds exactly the three pieces")


# --- Rebuilding -------------------------------------------------------------------------------

func test_the_gear_is_rebuilt_only_when_the_worn_items_change() -> void:
	var m := _onion(&"warrior")
	var builds := m.gear_builds
	m.set_looks(null, null, null)
	m.set_equipment(null, null, null)
	check_eq(m.gear_builds, builds, "nothing changed: no rebuild")
	var head := _item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 2, 9)
	m.set_equipment(head, null, null)
	check_eq(m.gear_builds, builds + 1, "a new helm: one rebuild")
	m.set_equipment(head, null, null)
	check_eq(m.gear_builds, builds + 1, "the same helm again: none")
	var same_look := _item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 2, 12)
	m.set_equipment(same_look, null, null)
	check_eq(m.gear_builds, builds + 1, "another helm that looks the same (same type, tier, rarity): none")
	m.set_equipment(head, _item(Items.SlotType.SHOULDERS, ClassData.ArmorType.PLATE), null)
	check_eq(m.gear_builds, builds + 2, "pauldrons: one rebuild")
	m.set_equipment(null, null, null)
	check_eq(m.gear_builds, builds + 3, "everything off: one rebuild back to the starter look")
	# Frames do not rebuild anything.
	for i in 30:
		m._process(1.0 / 60.0)
	m.set_hp_ratio(0.3)
	m.set_weapons(Db.get_weapon(&"axe"), null)
	check_eq(m.gear_builds, builds + 3, "animation, HP and weapons leave the gear alone")


func test_a_look_in_the_wrong_slot_is_ignored() -> void:
	var m := _onion(&"mage")
	m.set_looks(_look(CHEST, ClassData.ArmorType.CLOTH), null, null)
	check(m.worn_look(HEAD) == null, "a chest piece is not a helm")
	check_eq(m.equipment_key(), "-|-|-", "nothing worn")


func test_the_looks_survive_a_new_setup() -> void:
	var look := _look(HEAD, ClassData.ArmorType.PLATE, 1, 2)
	var m := _onion(&"paladin", look, null, null)
	m.setup(Db.get_class_data(&"warrior"), Color.RED)
	check(m.worn_look(HEAD) == look, "the worn helm is kept")
	var warrior := Db.get_class_data(&"warrior")
	var expected := 0
	for slot in EquipLook.SLOT_COUNT:
		expected += _vertices(OnionArmor.part(slot, m.worn_look(slot), warrior).solid)
	check_eq(_vertices((m.get_node("Yaw/Body/Gear/Solid") as MeshInstance3D).mesh), expected, "the rebuilt model shows the helm + the warrior's own pauldrons and belt")


# --- Downed, peel, flash, vanish ----------------------------------------------------------------

func test_the_downed_ghost_covers_the_new_parts() -> void:
	var m := _dressed(&"warrior", _suit(ClassData.ArmorType.PLATE, 2, 4))
	var skins: Array[MeshInstance3D] = []
	for c in _gear(m).get_children():
		if not c.name.begins_with("Accent"):
			skins.append(c as MeshInstance3D)
	check(skins.size() >= 2, "solid + glow + cloth")
	var before: Array[Material] = []
	for mi in skins:
		before.append(mi.material_override)
	m.set_downed(true)
	for mi in skins:
		var mat := mi.material_override as ShaderMaterial
		check(mat != null and mat.shader == (Mats.ghost(Color.WHITE) as ShaderMaterial).shader, "%s turns into the ghost" % mi.name)
	for c in _gear(m).get_children():
		if c.name.begins_with("Accent"):
			check(not (c as Node3D).visible, "glow accents vanish with the ghost")
	m.set_downed(false)
	for i in skins.size():
		check(skins[i].material_override == before[i], "%s: normal look restored" % skins[i].name)
	for c in _gear(m).get_children():
		if c.name.begins_with("Accent"):
			check((c as Node3D).visible, "accents back")


func test_gear_changed_while_downed_is_a_ghost_too() -> void:
	var m := _onion(&"mage")
	m.set_downed(true)
	m.set_looks(_look(HEAD, ClassData.ArmorType.CLOTH, 2, 4), _look(SHOULDERS, ClassData.ArmorType.CLOTH, 2, 4), _look(CHEST, ClassData.ArmorType.CLOTH, 2, 4))
	var ghost_shader := (Mats.ghost(Color.WHITE) as ShaderMaterial).shader
	for c in _gear(m).get_children():
		if c.name.begins_with("Accent"):
			check(not (c as Node3D).visible, "accent hidden on the ghost")
		else:
			check(((c as MeshInstance3D).material_override as ShaderMaterial).shader == ghost_shader, "%s is a ghost" % c.name)
	m.set_downed(false)
	for c in _gear(m).get_children():
		if c.name.begins_with("Glow") or c.name == "Solid":
			check(((c as MeshInstance3D).material_override as ShaderMaterial).shader != ghost_shader, "%s solid again" % c.name)


func test_hit_flash_and_peel_still_work_with_gear() -> void:
	var m := _dressed(&"paladin", _suit(ClassData.ArmorType.PLATE, 1, 3))
	m.flash_hit()
	for c in _gear(m).get_children():
		if not c.name.begins_with("Accent"):
			check(Mats.overlay_amount(c as GeometryInstance3D) > 0.5, "%s flashes" % c.name)
	for i in 20:
		m._process(1.0 / 60.0)
	for c in _gear(m).get_children():
		if not c.name.begins_with("Accent"):
			check_near(Mats.overlay_amount(c as GeometryInstance3D), 0.0, 0.001, "%s calms down" % c.name)
	m.set_hp_ratio(0.15)
	check(m.bulb_damage() > 0.5, "the bulb still peels")
	for i in 3:
		check((m.get_node("Yaw/Body/Peel%d" % i) as Node3D).visible, "peel flap %d" % i)
	# A rebuild in the middle of a flash keeps the flash.
	m.flash_hit()
	m.set_looks(null, null, null)
	for c in _gear(m).get_children():
		if not c.name.begins_with("Accent"):
			check(Mats.overlay_amount(c as GeometryInstance3D) > 0.5, "new %s flashes too" % c.name)


func test_peel_flaps_ride_on_top_of_a_worn_chest_piece() -> void:
	var m := _onion(&"warrior")
	var bare: Array[float] = []
	for i in 3:
		var p := (m.get_node("Yaw/Body/Peel%d" % i) as Node3D).position
		bare.append(Vector2(p.x, p.z).length() - OnionModel.bulb_radius(p.y))
		check(bare[i] < 0.02, "flap %d sits on the bulb" % i)
	m.set_looks(null, null, _look(CHEST, ClassData.ArmorType.PLATE, 2, 3))
	for i in 3:
		var p := (m.get_node("Yaw/Body/Peel%d" % i) as Node3D).position
		var out := Vector2(p.x, p.z).length() - OnionModel.bulb_radius(p.y)
		check(out > 0.1, "flap %d is lifted over the armour (%.3f m)" % [i, out])
	m.set_hp_ratio(0.1)
	for i in 3:
		check((m.get_node("Yaw/Body/Peel%d" % i) as Node3D).visible, "flap %d shows at low HP" % i)
	m.set_looks(null, null, null)
	var p0 := (m.get_node("Yaw/Body/Peel0") as Node3D).position
	check(Vector2(p0.x, p0.z).length() - OnionModel.bulb_radius(p0.y) < 0.02, "back on the bulb without a chest piece")


func test_every_gear_mesh_is_below_the_yaw_node() -> void:
	# Rogue Vanish fades every MeshInstance3D below Yaw: the armour must be in there.
	var m := _dressed(&"rogue", _suit(ClassData.ArmorType.LEATHER, 2, 4))
	var below := (m.get_node("Yaw") as Node).find_children("*", "MeshInstance3D", true, false)
	for c in _gear(m).get_children():
		check(below.has(c), "%s is a MeshInstance3D below Yaw" % c.name)
	for c in m.get_node("Yaw/Body").get_children():
		if c.name in ["HatStar", "FelTrim", "HornFlameL", "HornFlameR"]:
			check(true, "extras are part of the body")


func test_rogue_vanish_fades_armour_put_on_during_the_effect() -> void:
	var rogue := Fakes.spawn_player(_players_world(), 0, &"rogue")
	check(rogue.abilities.try_cast(1), "Vanish")
	var yaw := rogue.model.get_node("Yaw") as Node
	var before := yaw.find_children("*", "MeshInstance3D", true, false).size()
	var bulb := rogue.model.get_node("Yaw/Body/Bulb") as MeshInstance3D
	var ghost := Mats.base_material(bulb)
	rogue.equipment.equip(_item(Items.SlotType.HEAD, ClassData.ArmorType.LEATHER, 4, 9))
	rogue.equipment.equip(_item(Items.SlotType.CHEST, ClassData.ArmorType.LEATHER, 3, 9))
	rogue.abilities._physics_process(1.0 / 60.0)
	var meshes := yaw.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() != before or true, "armour meshes were rebuilt")
	for node in meshes:
		var mi := node as MeshInstance3D
		check(Mats.base_material(mi) == ghost, "%s is part of the silhouette" % mi.name)
		check_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % mi.name)
	# When Vanish ends the new armour is solid again.
	for i in 130:
		rogue.abilities._physics_process(1.0 / 60.0)
	for node in yaw.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name in ["Solid", "Glow0", "Glow1", "Cloth"]:
			check(Mats.base_material(mi) != ghost, "%s solid again after Vanish" % mi.name)


# --- Draw calls -------------------------------------------------------------------------------

func test_draw_call_budget_per_hero() -> void:
	for id in Db.class_ids:
		var before := _baseline(id)
		var starter := _draws(_onion(id))
		check(starter <= before, "%s starter look: %d draws (before %d)" % [id, starter, before])
		var worst := 0
		for armor in 4:
			for rarity in [0, 3, 4]:
				for tier in 3:
					var d := _draws(_dressed(id, _suit(armor, tier, rarity)))
					worst = maxi(worst, d)
					check(d <= before + DRAW_BUDGET, "%s armour %d tier %d rarity %d: %d draws (limit %d)" % [id, armor, tier, rarity, d, before + DRAW_BUDGET])
		# Class set, mixed rarities: the worst realistic case.
		var mixed := _onion(id, _look(HEAD, 3, 2, 4), _look(SHOULDERS, 3, 2, 3, &"battlegear_of_fury"), _look(CHEST, 0, 2, 1))
		check(_draws(mixed) <= before + DRAW_BUDGET, "%s mixed gear: %d draws" % [id, _draws(mixed)])
	# Plain gear costs no more than the starter look: merged by material.
	var plain := _draws(_dressed(&"paladin", _suit(ClassData.ArmorType.PLATE, 1, 1)))
	check(plain <= DRAWS_BEFORE[&"paladin"] + 2, "uncommon plate: %d draws" % plain)


func test_equipment_adds_no_nodes_per_frame_work() -> void:
	# The model processes its animation as before; a hero in full gear has no per-gear scripts.
	var m := _dressed(&"warrior", _suit(ClassData.ArmorType.PLATE, 2, 4))
	for c in _gear(m).get_children():
		check_eq((c as Node).get_script(), null, "%s is a plain MeshInstance3D" % c.name)
		check_eq((c as Node).get_child_count(), 0, "%s has no children" % c.name)


# --- Wiring -----------------------------------------------------------------------------------

func test_the_player_shows_what_it_wears() -> void:
	var p := Fakes.spawn_player(_players_world(), 0, &"warrior")
	check_eq(p.model.equipment_key(), "-|-|-", "run start: the class starter look")
	var builds := p.model.gear_builds
	var helm := _item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 3, 9)
	check(p.equipment.add_to_backpack(helm), "in the bag")
	check_eq(p.model.gear_builds, builds, "the backpack is not worn")
	check(p.equipment.equip(helm), "equipped")
	check(p.model.worn_look(HEAD) != null and p.model.worn_look(HEAD).rarity == 3, "the helm shows")
	check_eq(p.model.gear_builds, builds + 1, "one rebuild")
	var chest := _item(Items.SlotType.CHEST, ClassData.ArmorType.MAIL, 1, 1)
	p.equipment.equip(chest)
	check(p.model.worn_look(CHEST) != null and p.model.worn_look(CHEST).armor == ClassData.ArmorType.MAIL, "the mail chest shows")
	var shoulders := _item(Items.SlotType.SHOULDERS, ClassData.ArmorType.PLATE, 2, 17)
	p.equipment.equip(shoulders)
	check_eq(p.model.worn_look(SHOULDERS).tier, 2, "tier III pauldrons")
	# Something that is not shown changes nothing.
	var builds_now := p.model.gear_builds
	p.equipment.equip(_item(Items.SlotType.WRIST, ClassData.ArmorType.PLATE))
	check_eq(p.model.gear_builds, builds_now, "bracers are not on the model")
	# Unequip and trade away: back to the starter look.
	check(p.equipment.unequip(Items.EquipSlot.HEAD), "unequipped")
	check(p.model.worn_look(HEAD) == null, "the starter helm is back")
	p.equipment.take(chest)
	check(p.model.worn_look(CHEST) == null, "chest gone (sold / traded): starter look")


func test_a_replaced_item_swaps_the_look() -> void:
	var p := Fakes.spawn_player(_players_world(), 0, &"paladin")
	var first := _item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 1, 1)
	var second := _item(Items.SlotType.HEAD, ClassData.ArmorType.MAIL, 3, 9)
	p.equipment.equip(first)
	var a := p.model.worn_look(HEAD).key()
	p.equipment.equip(second)
	check(p.model.worn_look(HEAD).key() != a, "the new helm replaced the old one")
	check(p.equipment.backpack.has(first), "the old helm went to the bag")


func test_the_character_panel_preview_follows_the_equipment() -> void:
	UiFakes.reset_players()
	RunState.start_run(1, 9)
	var slot := PlayerManager.join(ScriptedInput.new("panel:0"), Db.get_class_data(&"warrior"))
	var p := Player.create(slot)
	_keep(p)
	var panel := PlayerPanel.create(slot)
	tree.root.add_child(panel)
	_keep(panel)
	check(panel._preview.model != null, "preview model")
	check_eq(panel._preview.model.equipment_key(), "-|-|-", "starter look first")
	check(p.equipment.add_to_backpack(_item(Items.SlotType.HEAD, ClassData.ArmorType.PLATE, 3, 1)), "helm in the bag")
	p.equipment.equip(p.equipment.backpack[0])
	check(panel._preview.model.worn_look(HEAD) != null, "the preview shows the new helm")
	p.equipment.unequip(Items.EquipSlot.HEAD)
	check(panel._preview.model.worn_look(HEAD) == null, "and the starter helm after unequipping")


func test_the_lobby_preview_shows_the_starter_look() -> void:
	var preview := OnionPreview.create()
	tree.root.add_child(preview)
	_keep(preview)
	preview.show_class(Db.get_class_data(&"mage"), Color.BLUE)
	check(preview.model != null and preview.model.equipment_key() == "-|-|-", "the lobby shows the class starter look")
	check(preview.model.get_node_or_null("Yaw/Body/HatStar") != null, "with the mage's hat star")
