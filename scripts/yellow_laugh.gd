extends Node2D
## Live mesh animation: preserves alpha and the counter's clipping, with shared SFX volume.
signal finished
const DURATION := 8.0
const TEXTURE := preload("res://assets/guests/reactions/yellow_laugh.png")
const SOUND := preload("res://assets/audio/sfx/yellow_laugh.wav")
const SHADER := preload("res://scripts/yellow_laugh.gdshader")
var elapsed := 0.0
var active := true
var material_instance: ShaderMaterial
var player: AudioStreamPlayer
var levels: Array = []

func _ready() -> void:
	levels = JSON.parse_string(FileAccess.get_file_as_string("res://assets/guests/reactions/yellow_laugh_levels.json"))
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for y in range(49):
		for x in range(33):
			vertices.append(Vector3(x / 32.0 * 580.0, y / 48.0 * 870.0, 0))
			uvs.append(Vector2(x / 32.0, y / 48.0))
	for y in range(48):
		for x in range(32):
			var a := y * 33 + x
			indices.append_array([a, a + 1, a + 33, a + 1, a + 34, a + 33])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var art := MeshInstance2D.new()
	art.mesh = mesh
	art.texture = TEXTURE
	art.scale = Vector2.ONE * (400.0 / 580.0)
	material_instance = ShaderMaterial.new()
	material_instance.shader = SHADER
	art.material = material_instance
	add_child(art)
	player = AudioStreamPlayer.new()
	player.stream = SOUND
	player.bus = "SFX"
	player.volume_db = -4.0
	add_child(player)
	player.play()

func _process(delta: float) -> void:
	if not active: return
	elapsed += delta
	if elapsed >= DURATION:
		stop()
		return
	material_instance.set_shader_parameter("clock", elapsed)
	var index := clampi(int(elapsed * 30.0), 0, levels.size() - 1)
	material_instance.set_shader_parameter("energy", float(levels[index]))

func stop() -> void:
	if not active: return
	active = false
	if is_instance_valid(player): player.stop()
	finished.emit()
	queue_free()
