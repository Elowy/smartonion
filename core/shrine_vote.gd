class_name ShrineVote
extends RefCounted
## The party's vote on a shrine (GDD 16.1, M6b): every voter says Accept or Decline, ALL must accept. A
## single Decline declines the shrine at once; so does the clock running out ([constant VOTE_TIME], whoever has
## not voted by then counts as a decline); a voter who leaves is not counted. Once the outcome is decided it
## never changes. A pure data model (no nodes, no RNG): the ShrineScreen shows it, the tests drive it.

enum Choice { UNDECIDED, ACCEPT, DECLINE }
enum Outcome { PENDING, ACCEPTED, DECLINED }

## Seconds the party has to decide (then: declined).
const VOTE_TIME := 15.0

## Slot indices of the voters, in slot order.
var voters: Array[int] = []
## Slot index -> Choice.
var choices: Dictionary[int, int] = {}
## Seconds left; a vote with [member time_limit] <= 0 has no clock.
var time_limit := VOTE_TIME
var time_left := VOTE_TIME
## Why the vote ended: &"" while pending, then &"accepted", &"declined" (a voter said no), &"timeout" or
## &"nobody" (no voter left).
var reason: StringName = &""

var _outcome := Outcome.PENDING


static func create(p_voters: Array[int], p_time: float = VOTE_TIME) -> ShrineVote:
	var v := ShrineVote.new()
	v.voters = p_voters.duplicate()
	v.voters.sort()
	for i in v.voters:
		v.choices[i] = Choice.UNDECIDED
	v.time_limit = p_time
	v.time_left = p_time
	v._settle()
	return v


func is_voter(slot_index: int) -> bool:
	return choices.has(slot_index)


func choice_of(slot_index: int) -> int:
	return choices.get(slot_index, Choice.UNDECIDED)


func outcome() -> Outcome:
	return _outcome


func is_decided() -> bool:
	return _outcome != Outcome.PENDING


func is_accepted() -> bool:
	return _outcome == Outcome.ACCEPTED


## Voters who have not said anything yet.
func undecided() -> Array[int]:
	var out: Array[int] = []
	for i in voters:
		if choice_of(i) == Choice.UNDECIDED:
			out.append(i)
	return out


## [param slot_index] votes [param accept] (Accept / Decline). A voter may change an Accept into a Decline
## while the vote is open, nothing else. Returns false for a non-voter or a vote that is over.
func cast(slot_index: int, accept: bool) -> bool:
	if _outcome != Outcome.PENDING or not choices.has(slot_index):
		return false
	var now := Choice.ACCEPT if accept else Choice.DECLINE
	if choices[slot_index] == Choice.DECLINE:
		return false
	choices[slot_index] = now
	_settle()
	return true


## [param slot_index] leaves the vote (the player left the game). The others may now be unanimous.
func remove_voter(slot_index: int) -> void:
	if not choices.has(slot_index):
		return
	choices.erase(slot_index)
	voters.erase(slot_index)
	_settle()


## Runs the clock; the undecided voters decline when it reaches 0.
func tick(delta: float) -> void:
	if _outcome != Outcome.PENDING or time_limit <= 0.0:
		return
	time_left = maxf(0.0, time_left - delta)
	_settle()


func _settle() -> void:
	if _outcome != Outcome.PENDING:
		return
	for i in voters:
		if choices[i] == Choice.DECLINE:
			_end(Outcome.DECLINED, &"declined")
			return
	if voters.is_empty():
		_end(Outcome.DECLINED, &"nobody")
		return
	if undecided().is_empty():
		_end(Outcome.ACCEPTED, &"accepted")
		return
	if time_limit > 0.0 and time_left <= 0.0:
		_end(Outcome.DECLINED, &"timeout")


func _end(outcome_value: Outcome, why: StringName) -> void:
	_outcome = outcome_value
	reason = why
