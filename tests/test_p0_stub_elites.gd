extends TestCase
## P0 stub values owned by ELITES: EliteAffixes spawns nothing and draws nothing. ELITES: delete
## or replace this file when you implement EliteAffixes (architecture §3.1). The contracts
## that stay (constants, rate_mult reset by RunState.start_run / set by Main, no elites below
## FIRST_WAVE) are in test_m5_foundation.gd (frozen, integrator only).


func after_each() -> void:
	EliteAffixes.rate_mult = 1.0


func test_elite_affixes_stub_spawns_nothing() -> void:
	EliteAffixes.rate_mult = 5.0
	var state := RunState.rng.state
	check(EliteAffixes.schedule(10, 60.0, 4, RunState.rng).is_empty(), "stub: no elites")
	check_eq(EliteAffixes.roll_count(10, 4, RunState.rng), 0, "stub: count 0")
	check_eq(EliteAffixes.expected_count(10, 4), 0.0, "stub: expected 0")
	check_eq(EliteAffixes.roll_affix(RunState.rng), &"", "stub: no affix")
	check_eq(RunState.rng.state, state, "stub: no draws")
