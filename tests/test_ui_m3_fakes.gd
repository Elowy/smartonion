extends TestCase
## Shared builders for the M3 HUD tests (test_ui_m3_*.gd): fake ResourceData / AbilityData and a
## hero whose AbilityRunner uses them, so the tests do not depend on the class .tres files.
## Preload it:  const Fakes := preload("res://tests/test_ui_m3_fakes.gd")
## (It is a test file itself only so the runner loads it; it has no test methods.)

const UiFakes := preload("res://tests/ui_fakes.gd")


## An effect that only counts casts.
class CastEffect extends AbilityEffect:
	var casts := 0

	func cast(_ctx: AbilityContext) -> bool:
		casts += 1
		return true


## An effect that publishes charges like BlinkEffect does (the bar reads them by duck typing).
class ChargeEffect extends AbilityEffect:
	var available := 1
	var maximum := 2

	func charges_available() -> int:
		return available

	func charges_max() -> int:
		return maximum


static func resource(id: StringName, display: ResourceData.Display, max_value: float, color: Color, start: float = 0.0) -> ResourceData:
	var r := ResourceData.new()
	r.id = id
	r.display_name = String(id).capitalize()
	r.display = display
	r.max_value = max_value
	r.start_value = start
	r.color = color
	return r


static func rage() -> ResourceData:
	return resource(&"rage", ResourceData.Display.BAR, 100.0, Color(0.85, 0.15, 0.1))


static func energy() -> ResourceData:
	return resource(&"energy", ResourceData.Display.BAR, 100.0, Color(1.0, 0.9, 0.2), 100.0)


static func combo() -> ResourceData:
	return resource(&"combo_points", ResourceData.Display.PIPS, 5.0, Color(1.0, 0.45, 0.2))


static func holy_power() -> ResourceData:
	return resource(&"holy_power", ResourceData.Display.PIPS, 3.0, Color(1.0, 0.85, 0.3))


static func ability(id: StringName, resource_id: StringName = &"", cost: float = 0.0, cooldown: float = 0.0, icon: StringName = &"") -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = String(id).capitalize().replace("_", " ")
	a.icon = icon if icon != &"" else id
	a.resource = resource_id
	a.cost = cost
	a.cooldown = cooldown
	a.targeting = AbilityData.Targeting.SELF
	a.effect = CastEffect
	a.color = Color(0.9, 0.3, 0.2)
	return a


## A hero under [param parent] on [param input]'s device whose runner uses exactly
## [param resources] (primary first) and [param abilities] (slot 0, 1, ...).
static func hero(parent: Node, input: PlayerInput, resources: Array[ResourceData], abilities: Array[AbilityData], class_id: StringName = &"warrior", index: int = 0) -> Player:
	var slot := PlayerSlot.new(index, input, PlayerManager.PLAYER_COLORS[index])
	slot.class_data = Db.get_class_data(class_id)
	var p := Player.create(slot)
	parent.add_child(p)
	var runner := p.abilities
	runner.resources.clear()
	runner.resource_order.clear()
	for d in resources:
		runner.resources[d.id] = ClassResource.new(d)
		runner.resource_order.append(d.id)
	for i in AbilityRunner.MAX_SLOTS:
		runner.set_slot(i, abilities[i] if i < abilities.size() else null)
	return p


static func step_physics(p: Player, seconds: float) -> void:
	var ticks := int(roundf(seconds * 60.0))
	for i in ticks:
		p.abilities._physics_process(1.0 / 60.0)
