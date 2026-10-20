extends Control
## Presentation only: deriving the portrait from the current row also supports
## resume/replay/fast-forward without adding flags to the story save.
const ROOT := "res://assets/pixel_b/opening_characters/"
const ACTORS := {
	"那位客人": "old_friend", "老管家": "caretaker",
	"投递员": "courier", "调酒师": "city_bartender",
	"同事甲": "colleague_a", "同事乙": "colleague_b",
	"年轻同事": "junior_colleague"
}
# Crown-to-chin heights measured in the cropped source textures. Full image
# height is unsuitable: the seated guest is cropped much closer than the others.
const HEAD_HEIGHTS := {
	"old_friend": 380.0, "caretaker": 375.0, "courier": 400.0,
	"city_bartender": 380.0, "colleague_a": 385.0,
	"colleague_b": 385.0, "junior_colleague": 410.0
}
const DISPLAY_HEAD_HEIGHT := 190.0
const HEAD_TOP := 185.0
var actor_id := ""
var portrait: TextureRect
var entrance: Tween
var cache: Dictionary = {}

func _ready() -> void:
	name = "OpeningPortrait"
	size = Vector2(1600,650)
	clip_contents = true # Bodies continue behind the dialogue instead of floating.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait = TextureRect.new()
	portrait.name = "SpeakerArt"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var cutout := ShaderMaterial.new()
	cutout.shader = preload("res://shaders/opening_portrait.gdshader")
	portrait.material = cutout
	add_child(portrait)
	hide()

static func actor_for(row: Dictionary) -> String:
	var voice := str(row.get("speaker",""))
	# An off-screen knock and a dead friend's message are not present-day bodies.
	if voice.contains("旧消息") or not str(row.get("mail_id","")).is_empty(): return ""
	return str(ACTORS.get(voice.split(" · ")[0],""))

func present(row: Dictionary, departure := false, instant := false) -> void:
	var next := actor_for(row)
	var changed_actor := next != actor_id
	actor_id = next
	if is_instance_valid(entrance): entrance.kill()
	if actor_id.is_empty():
		hide()
		portrait.texture = null
		return
	var path := ROOT + actor_id + ".tres"
	if not cache.has(path): cache[path] = load(path)
	portrait.texture = cache[path]
	if portrait.texture == null:
		hide()
		return
	var center_x := 810.0
	if departure: center_x = 270.0
	# Off-screen/quiet delivery changes placement, not the camera distance.
	if str(row.get("speaker","")).contains("远处"): center_x = 1180.0
	var extent := portrait.texture.get_size()
	extent *= DISPLAY_HEAD_HEIGHT / float(HEAD_HEIGHTS[actor_id])
	portrait.size = extent.round()
	var target := Vector2(center_x-extent.x*.5,HEAD_TOP).round()
	portrait.position = target
	portrait.modulate = Color.WHITE
	show()
	if changed_actor and not instant and not OpeningFlow.reduced_motion:
		portrait.modulate.a = 0.0
		portrait.position.x -= 10
		entrance = create_tween().set_parallel()
		entrance.tween_property(portrait,"modulate:a",1.0,.18)
		entrance.tween_property(portrait,"position",target,.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
