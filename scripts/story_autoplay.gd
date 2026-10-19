extends RefCounted
## Presentation-only timer. Choices, mail and tutorial actions always wait for the player.
var enabled := false
var elapsed := 0.0

func toggle() -> bool:
	enabled = not enabled
	reset()
	return enabled

func reset() -> void:
	elapsed = 0.0

func tick(delta: float, text_length: int, text_complete: bool, can_advance: bool, held_fast_forward := false) -> bool:
	if (not enabled and not held_fast_forward) or not text_complete or not can_advance:
		reset()
		return false
	elapsed += maxf(0.0, delta)
	# Typewriting already gives reading time; leave an additional pause after it finishes.
	if elapsed < clampf(1.4 + text_length * 0.035, 2.5, 6.0): return false
	reset()
	return true
