extends CanvasLayer
## Persistent cover and input barrier across scene destruction/creation.
signal finished
var busy := false
var cover: ColorRect
var target_path := ""

func _ready() -> void:
	layer=120
	process_mode=Node.PROCESS_MODE_ALWAYS
	cover=ColorRect.new()
	cover.color=Color("10181f")
	cover.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.hide()

func go(path: String, music := "opening_home") -> bool:
	if busy or not ResourceLoader.exists(path): return false
	busy=true
	target_path=path
	SaloonAudio.set_scene_context(self,music)
	cover.modulate.a=0.0
	cover.show()
	_switch.call_deferred(path)
	return true

func _switch(path: String) -> void:
	var old:=get_tree().current_scene
	var previous_mode: int=old.process_mode if is_instance_valid(old) else Node.PROCESS_MODE_INHERIT
	if is_instance_valid(old): old.process_mode=Node.PROCESS_MODE_DISABLED
	var out:=create_tween()
	out.tween_property(cover,"modulate:a",1.0,.25 if OpeningFlow.reduced_motion else .4)
	await out.finished
	var error:=get_tree().change_scene_to_file(path)
	if error!=OK:
		if is_instance_valid(old): old.process_mode=previous_mode
		cover.hide(); busy=false
		SaloonAudio.release_scene(self)
		finished.emit()
		push_error("Opening transition could not load: "+path)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var destination:=get_tree().current_scene
	var mode: int=destination.process_mode
	destination.process_mode=Node.PROCESS_MODE_DISABLED
	var reveal:=create_tween()
	reveal.tween_property(cover,"modulate:a",0.0,.3 if OpeningFlow.reduced_motion else .65)
	await reveal.finished
	# Never give the next scene the release/repeat of the key that left the last one.
	while Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		await get_tree().process_frame
	if is_instance_valid(destination): destination.process_mode=mode
	cover.hide()
	busy=false
	# First arrival keeps the bridge track until the player actually takes control.
	if not (path.ends_with("home.tscn") and OpeningFlow.arrival_pending()): SaloonAudio.release_scene(self)
	finished.emit()

func _input(event: InputEvent) -> void:
	if busy and (event is InputEventKey or event is InputEventMouse or event is InputEventScreenTouch):
		get_viewport().set_input_as_handled()
