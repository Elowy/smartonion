extends TestCase
## P0 stub values owned by GOBLIN: the GoblinSpawner never spawns. GOBLIN: delete or replace
## this file when you implement GoblinSpawner (architecture §3.1). The contracts that stay
## (Main creates it under the WaveDirector, announced → HUD banner, chance_override reset /
## applied) are in test_m5_foundation.gd (frozen, integrator only).


func after_each() -> void:
	GoblinSpawner.chance_override = -1.0


func test_goblin_spawner_stub_spawns_nothing() -> void:
	GoblinSpawner.chance_override = 1.0
	var spawner := GoblinSpawner.create(null)
	check(spawner.director == null and spawner.goblin == null, "no director, no goblin")
	check_eq(spawner.pending_time(), -1.0, "stub: no goblin this wave")
	check_eq(GoblinSpawner.chance_for(5, 100.0), 0.0, "stub: no chance")
	check_eq(GoblinSpawner.team_fortune(), 0.0, "stub: no Fortune read")
	spawner.free()
