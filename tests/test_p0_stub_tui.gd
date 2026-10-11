extends TestCase
## P0 stub values owned by T-UI: the TalentTab stub (a centred "Talents" label, no input, no
## prompts). T-UI: delete or replace this file when you implement the tab (architecture §3.1).
## The panel wiring that stays (the Talents tab opens, --panel-tab) is tested in
## test_m5_foundation.gd (frozen, integrator only).

const DT := 1.0 / 60.0


func test_talent_tab_stub() -> void:
	var tab := TalentTab.create(null)
	check(tab.player() == null, "no slot, no hero")
	check(not tab.handle_input(null, DT), "stub: no input used")
	check(not tab.is_modal(), "stub: never modal")
	check(tab.prompt_spec().is_empty() and tab.context_text() == "", "stub: no prompts")
	var title := tab.get_node_or_null(^"Title") as Label
	check(title != null and title.text == "Talents", "stub: a centred Talents label")
	tab.refresh()
	tab.set_focused(true)
	tab.free()
