extends TextureRect
## An actual foreground layer: lower bodies pass behind this opaque counter.
const Composition = preload("res://scripts/saloon_composition.gd")

func _ready() -> void:
	var background: TextureRect = get_node("../../Background")
	var crop := AtlasTexture.new()
	# Use only the approved tabletop region; keep the original room above it.
	crop.atlas = load(Composition.COUNTER_TEXTURE_PATH)
	crop.region = Rect2(0, Composition.COUNTER_SOURCE_Y, Composition.SOURCE_SIZE.x,
		Composition.SOURCE_SIZE.y - Composition.COUNTER_SOURCE_Y)
	crop.filter_clip = true
	texture = crop
	material = background.material
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	position = Vector2(0, Composition.COUNTER_Y)
	size = Vector2(Composition.DESIGN_SIZE.x, Composition.DESIGN_SIZE.y - position.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
