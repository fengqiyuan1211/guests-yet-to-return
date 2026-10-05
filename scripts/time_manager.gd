extends Node
## One real second = one game minute. At 04:00 finish serving the last guest before closing.
signal time_changed(day: int, minutes_since_midnight: int)
signal business_opened(day: int)
signal business_closed(completed_day: int)
signal fast_forward_changed(active: bool)
signal closing_wait_changed(active: bool)

const OPEN_MINUTE := 20 * 60
const CLOSE_MINUTE := 4 * 60
const FAST_FORWARD_SECONDS := 4.0
var day := 1
var minutes_since_midnight := 18 * 60
var running := true
var is_open := false
var closing_pending := false
var fast_forwarding := false
var _elapsed := 0.0
var _fast_elapsed := 0.0
var _fast_total := 0
var _fast_applied := 0

func snapshot() -> Dictionary:
	return {"day": day, "minutes": minutes_since_midnight, "elapsed": _elapsed,
		"fast_forwarding": fast_forwarding, "fast_elapsed": _fast_elapsed,
		"fast_total": _fast_total, "fast_applied": _fast_applied, "closing_pending": closing_pending}

func restore(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	minutes_since_midnight = int(data.get("minutes", 18 * 60))
	_elapsed = float(data.get("elapsed", 0.0))
	fast_forwarding = data.get("fast_forwarding", false)
	_fast_elapsed = float(data.get("fast_elapsed", 0.0))
	_fast_total = int(data.get("fast_total", 0))
	_fast_applied = int(data.get("fast_applied", 0))
	closing_pending = data.get("closing_pending", false) and minutes_since_midnight == CLOSE_MINUTE and not fast_forwarding
	if closing_pending: _elapsed = 0.0
	is_open = closing_pending or minutes_since_midnight >= OPEN_MINUTE or minutes_since_midnight < CLOSE_MINUTE
	running = true

func _process(delta: float) -> void:
	if not running or closing_pending:
		return
	if fast_forwarding:
		_fast_elapsed = minf(_fast_elapsed + delta, FAST_FORWARD_SECONDS)
		var target := int(floor(_fast_total * _fast_progress()))
		var step := target - _fast_applied
		_fast_applied = target
		advance_minutes(step)
		if _fast_elapsed >= FAST_FORWARD_SECONDS:
			fast_forwarding = false
			_elapsed = 0.0
			fast_forward_changed.emit(false)
		return
	_elapsed += delta
	var steps := int(floor(_elapsed))
	_elapsed -= steps
	advance_minutes(steps)

func _fast_progress() -> float:
	return smoothstep(0.0, FAST_FORWARD_SECONDS, _fast_elapsed)

func visual_minutes() -> float:
	if closing_pending: return float(CLOSE_MINUTE)
	# Fractional minutes keep both hands and lighting continuous between ticks.
	if fast_forwarding:
		return minutes_since_midnight + (_fast_total * _fast_progress() - _fast_applied)
	return minutes_since_midnight + _elapsed

func advance_minutes(amount: int) -> void:
	# Visit every crossed boundary even on a large frame or accelerated day.
	if closing_pending: return
	for _i in range(maxi(amount, 0)):
		minutes_since_midnight = (minutes_since_midnight + 1) % (24 * 60)
		if minutes_since_midnight == OPEN_MINUTE:
			is_open = true
			closing_pending = false
			business_opened.emit(day)
		elif minutes_since_midnight == CLOSE_MINUTE:
			if _has_active_guest():
				closing_pending = true
				_elapsed = 0.0
				closing_wait_changed.emit(true)
			else:
				_close_business()
		time_changed.emit(day, minutes_since_midnight)
		if closing_pending: break # Discard extra steps; no accumulated time after departure.

func _has_active_guest() -> bool:
	var story := get_node_or_null("/root/StoryDialogue")
	return story != null and not str(story.guest_id).is_empty()

func finish_closing() -> bool:
	if not closing_pending or _has_active_guest(): return false
	_close_business()
	time_changed.emit(day, minutes_since_midnight)
	return true

func _close_business() -> void:
	if not is_open: return
	is_open = false
	closing_pending = false
	_elapsed = 0.0
	var completed := day
	day += 1
	business_closed.emit(completed)
	closing_wait_changed.emit(false)

func start_early() -> bool:
	if is_open or fast_forwarding:
		return false
	_fast_total = posmod(OPEN_MINUTE - minutes_since_midnight, 24 * 60)
	if _fast_total == 0:
		return false
	_fast_elapsed = 0.0
	_fast_applied = 0
	_elapsed = 0.0
	fast_forwarding = true
	fast_forward_changed.emit(true)
	return true

func set_running(value: bool) -> void:
	running = value

func formatted_time() -> String:
	return "%02d:%02d" % [minutes_since_midnight / 60, minutes_since_midnight % 60]

func formatted_day() -> String:
	return "第 %d 天" % day

func period_name() -> String:
	var minute := minutes_since_midnight
	if minute < CLOSE_MINUTE:
		return "深夜"
	if minute < 8 * 60:
		return "黎明"
	if minute < 11 * 60:
		return "清晨"
	if minute < 16 * 60:
		return "白昼"
	if minute < 18 * 60:
		return "傍晚"
	if minute < OPEN_MINUTE:
		return "黄昏"
	return "夜晚"
