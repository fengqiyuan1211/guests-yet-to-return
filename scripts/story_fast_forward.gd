extends RefCounted
## Hold belongs to this story view; never changes Engine.time_scale or saved progress.
const HOLD_DELAY := 0.35
var held := false
var held_seconds := 0.0
var active := false

func press() -> void:
	if held: return
	held=true
	held_seconds=0.0
	active=false

func release() -> bool:
	# A tap advances once on release. A completed hold must not also act as a tap.
	var tap:=held and held_seconds<HOLD_DELAY
	cancel()
	return tap

func cancel() -> void:
	held=false
	held_seconds=0.0
	active=false

func step(delta: float, allowed: bool) -> float:
	if held: held_seconds+=maxf(delta,0.0)
	active=held and held_seconds>=HOLD_DELAY and allowed
	return 3.0 if active else 1.0
