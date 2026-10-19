extends RefCounted
## Normalize only the displayed art; catalogue paths and original PNGs stay intact.
static var _visible_textures: Dictionary = {}
static var _body_layout: Dictionary = {}

static func visible_texture(source: Texture2D) -> Texture2D:
	if source!=null and source.resource_path.begins_with("res://assets/pixel_b/"): return source
	if source == null:
		return null
	var key := source.get_instance_id()
	if _visible_textures.has(key):
		return _visible_textures[key]
	var image := source.get_image()
	if image == null or image.is_empty():
		return source
	if image.is_compressed() and image.decompress() != OK:
		return source
	var bounds := _ink_bounds(image)
	if not bounds.has_area():
		return source
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = bounds
	cropped.filter_clip = true
	_visible_textures[key] = cropped
	return cropped

static func _ink_bounds(image: Image) -> Rect2:
	# Tiny sampling avoids scanning a full resolution image on the UI thread.
	# Ignore almost invisible alpha speckles, retaining a generous edge allowance.
	var probe := image.duplicate() as Image
	probe.resize(192, 192, Image.INTERPOLATE_NEAREST)
	var first := Vector2i(192, 192)
	var last := Vector2i(-1, -1)
	for y in range(192):
		for x in range(192):
			if probe.get_pixel(x, y).a <= 0.125:
				continue
			first.x = mini(first.x, x)
			first.y = mini(first.y, y)
			last.x = maxi(last.x, x)
			last.y = maxi(last.y, y)
	if last.x < first.x:
		return Rect2(Vector2.ZERO, Vector2(image.get_width(), image.get_height()))
	var scale := Vector2(image.get_width(), image.get_height()) / 192.0
	return Rect2(Vector2(first) * scale, Vector2(last - first + Vector2i.ONE) * scale).grow(scale.x * 2.0).intersection(Rect2(Vector2.ZERO, Vector2(image.get_width(), image.get_height())))

static func fit(picture: TextureRect, source: Texture2D, area: Rect2, cocktail_id := "", centered := false) -> void:
	picture.position = area.position
	picture.size = area.size
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = visible_texture(source)
	if picture.texture == null:
		return
	picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if source.resource_path.begins_with("res://assets/pixel_b/"): return
	if _body_layout.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/cocktails/layout.json"))
		if data is Dictionary and data.get("cocktails") is Dictionary:
			_body_layout = data.cocktails
	var settings: Dictionary = _body_layout.get(cocktail_id, {})
	var top := float(settings.get("body_top", 0.0))
	var bottom := float(settings.get("body_bottom", 1.0))
	if top < 0.0 or bottom > 1.0 or bottom <= top:
		return
	var dimensions := Vector2(picture.texture.get_width(), picture.texture.get_height())
	var fit_scale := minf(area.size.x / dimensions.x, area.size.y / dimensions.y)
	if not settings.is_empty():
		# Cup bodies share a target height; mint and citrus keep their headroom.
		fit_scale = minf(fit_scale, area.size.y * 0.77 / (float(source.get_height()) * (bottom - top)))
	picture.size = dimensions * fit_scale
	var left := area.position.x + (area.size.x - picture.size.x) * 0.5
	var offset_y := (area.size.y - picture.size.y) * 0.5 if centered else area.size.y - picture.size.y
	if centered and settings.has("body_center_x") and picture.texture is AtlasTexture:
		var body_x := float(settings.body_center_x)
		if is_finite(body_x) and body_x >= 0.0 and body_x <= 1.0:
			var atlas := picture.texture as AtlasTexture
			var pivot := float(source.get_width()) * body_x - atlas.region.position.x
			left = clampf(area.get_center().x - pivot * fit_scale, area.position.x, area.end.x - picture.size.x)
	picture.position = Vector2(left, area.position.y + offset_y)
