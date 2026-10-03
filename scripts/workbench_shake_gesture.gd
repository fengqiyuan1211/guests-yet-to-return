extends RefCounted
## Screen-independent stroke recognition in logical workbench pixels.
const MIN_SPEED:=180.0
const MIN_STROKE:=18.0
const MAX_STROKE_SECONDS:=.38
var leg:=Vector2.ZERO
var leg_seconds:=0.0
var reversal_pending:=false
var last_reversal:=-10.0
var last_fast:=-10.0

func reset() -> void:
	leg=Vector2.ZERO
	leg_seconds=0
	reversal_pending=false
	last_reversal=-10
	last_fast=-10

func sample(delta: Vector2, seconds: float, time: float) -> bool:
	if seconds<=0: return false
	if seconds>.18 or delta.length()>220: reset(); return false
	var speed:=delta.length()/seconds
	if speed<MIN_SPEED or delta.length()<.8:
		if time-last_fast>.16: reset()
		return false
	if time-last_fast>.18: reset()
	last_fast=time
	if leg.length()>1 and delta.normalized().dot(leg.normalized())<-.75:
		reversal_pending=leg.length()>=MIN_STROKE and leg_seconds<=MAX_STROKE_SECONDS
		leg=Vector2.ZERO
		leg_seconds=0
	leg+=delta
	leg_seconds+=seconds
	if reversal_pending and leg.length()>=MIN_STROKE:
		last_reversal=time
		reversal_pending=false
	return time-last_reversal<.30 and leg_seconds<=MAX_STROKE_SECONDS and leg.length()<180
