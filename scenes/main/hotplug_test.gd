class_name HotplugTest
extends RefCounted
## --hotplug-test (smoke): a scripted hotplug scenario that exercises the whole flow end to end. During the second
## wave P2's bot is swapped onto a fake pad (PadSource fake mode) and that pad is "unplugged"; the run must pause
## with the take-over prompt, a different fake pad takes the slot over with A, START on it resumes, and the bot gets
## P2 back so the run plays on. Its own timers, never RunState.rng. SMOKE_RESULT gets a "hotplug" block (only then).
##
## The steps wait for the real flow (PlayerManager.track_connections -> Main._on_device_disconnected -> PauseMenu ->
## PlayerManager.take_over -> PauseMenu resume); a step that does not complete within [constant STEP_TIMEOUT] fails
## the smoke ("hotplug_failed"). With --view=lobby / --view=pause the flag only shows the state (make_ghost).

enum Step { WAITING, DISCONNECTING, TAKING_OVER, RESUMING, DONE, FAILED }

## Fake joypad ids, well away from real ones.
const PAD_OLD := 6
const PAD_NEW := 7
## Game seconds into the target wave before P2's pad is pulled.
const WAIT_SECONDS := 4.0
## Real seconds a step may take.
const STEP_TIMEOUT := 20.0
## The slot (P2) that is unplugged.
const SLOT_INDEX := 1

var step := Step.WAITING
var target_wave := 2
var disconnected := false
var paused_with_prompt := false
var took_over := false
var resumed := false
var notice := ""
var failure := ""

var _bot: PlayerInput
var _wave_time := 0.0
var _step_msec := 0
var _sub := 0


func _init(p_target_wave: int = 2) -> void:
	target_wave = p_target_wave
	PadSource.enable_fake(true)


## Leaves fake mode (Main calls it when it goes).
func finish() -> void:
	PadSource.enable_fake(false)


func is_done() -> bool:
	return step == Step.DONE


## The "hotplug" block of the SMOKE_RESULT.
func summary() -> Dictionary:
	return {"disconnected": disconnected, "paused_with_prompt": paused_with_prompt, "took_over": took_over,
			"resumed": resumed, "done": step == Step.DONE, "notice": notice, "failure": failure}


## One rendered frame. Returns "" while all is well, else why the smoke must fail.
func tick(main: Main, delta: float) -> String:
	if step == Step.DONE or step == Step.FAILED:
		return failure
	var slot := PlayerManager.get_slot(SLOT_INDEX)
	if slot == null:
		return _fail("P%d is gone" % (SLOT_INDEX + 1))
	match step:
		Step.WAITING:
			if main.state == Main.State.WAVE and main.wave == target_wave and not main.is_paused():
				_wave_time += delta
				if _wave_time >= WAIT_SECONDS:
					_unplug(slot)
		Step.DISCONNECTING:
			# The slot must be reported missing: Main pauses with the notice and the menu offers the take-over.
			if main.is_paused() and PlayerManager.is_missing(slot) and main.hud != null and main.hud.is_notice_visible():
				disconnected = true
				paused_with_prompt = main.pause_menu.visible and not main.pause_menu.entries.is_empty() \
						and main.pause_menu.entries.has(PauseMenu.DROP_BASE + SLOT_INDEX)
				notice = main.hud.notice_label.text
				PadSource.fake_connect(PAD_NEW)
				_sub = 0
				_enter(Step.TAKING_OVER)
		Step.TAKING_OVER:
			if _sub == 0:
				_sub = 1  # (the new pad has been connected for one frame: now it presses A)
				PadSource.fake_press(PAD_NEW, JOY_BUTTON_A, true)
			else:
				var pad := slot.input as JoypadInput
				if pad != null and pad.device == PAD_NEW and pad.is_connected_device():
					PadSource.fake_press(PAD_NEW, JOY_BUTTON_A, false)
					took_over = true
					_sub = 0
					_enter(Step.RESUMING)
		Step.RESUMING:
			if not main.is_paused():
				PadSource.fake_press(PAD_NEW, JOY_BUTTON_START, false)
				resumed = true
				# P2 is the bot again; the fake pads leave.
				PlayerManager.rebind(SLOT_INDEX, _bot)
				PadSource.fake_disconnect(PAD_NEW)
				_enter(Step.DONE)
			else:
				# START on P2's new pad resumes: pressed on every fourth frame (an edge each time, a skipped frame retries).
				_sub += 1
				PadSource.fake_press(PAD_NEW, JOY_BUTTON_START, _sub % 4 == 2)
	if step != Step.DONE and step != Step.WAITING and Time.get_ticks_msec() - _step_msec > int(STEP_TIMEOUT * 1000.0):
		return _fail("step %s timed out" % Step.keys()[step])
	return failure


## P2 plays on a fake pad, then the pad is pulled.
func _unplug(slot: PlayerSlot) -> void:
	_bot = make_ghost(slot)
	_enter(Step.DISCONNECTING)


## Moves [param slot] onto a fake pad (fake mode on) and unplugs it: the slot is a ghost from the next frame on.
## Returns the input it had. The screenshot views (--view=lobby / pause with --hotplug-test) use it too.
static func make_ghost(slot: PlayerSlot) -> PlayerInput:
	if slot == null:
		return null
	if not PadSource.fake:
		PadSource.enable_fake(true)
	var old := slot.input
	var fake := RemotePlay.backend as FakeRemotePlayBackend
	if fake != null and slot.is_remote():
		fake.assign_device(PAD_OLD, slot.session_id)  # (--fake-rpt: the pad belongs to the same guest)
	PadSource.fake_connect(PAD_OLD)
	PlayerManager.rebind(slot.index, JoypadInput.new(PAD_OLD))
	PadSource.fake_disconnect(PAD_OLD)
	return old


func _enter(next: Step) -> void:
	step = next
	_step_msec = Time.get_ticks_msec()


func _fail(why: String) -> String:
	step = Step.FAILED
	failure = why
	return failure
