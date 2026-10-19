extends RefCounted
## Shared canvas coordinates keep people, counter and room aligned at every aspect ratio.
const DESIGN_SIZE := Vector2(1600, 900)
const BACKGROUND_PATH := "res://assets/pixel_b/saloon_depth/saloon-teal-runner.png"
const COUNTER_TEXTURE_PATH := BACKGROUND_PATH
const SOURCE_SIZE := Vector2(1672, 941)
# First opaque pixel row of the far counter lip in the approved painting.
const COUNTER_SOURCE_Y := 544.0
const COUNTER_Y := COUNTER_SOURCE_Y / SOURCE_SIZE.y * DESIGN_SIZE.y

static func guest_rect(id: String) -> Rect2:
	# Upper hips continue behind the counter instead of terminating at its edge.
	match id:
		"hank": return Rect2(510, 110, 470, 490)
		"ada": return Rect2(495, 110, 500, 510)
		"milo": return Rect2(495, 110, 500, 520)
		_: return Rect2(545, 135, 400, 600)
