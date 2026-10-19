extends Control
## One-time, resumable presentation; customer/economy services remain authoritative.
signal completed
const UI=preload("res://scripts/opening_ui.gd")
var home: Control
var saved_modulates: Dictionary={}
var audio: Node
var phase := "waiting"
var shot_tween: Tween
var hint: Label
var fast_forward=preload("res://scripts/story_fast_forward.gd").new()

func _process(delta: float) -> void:
	var speed: float=fast_forward.step(delta,phase not in ["waiting","complete"])
	if is_instance_valid(shot_tween): shot_tween.set_speed_scale(speed)
	if is_instance_valid(hint): hint.text="快进中 ×3 · 松开恢复" if fast_forward.active else "长按空格 · 3 倍速"

func _pause(seconds: float) -> void:
	shot_tween=create_tween()
	shot_tween.tween_interval(seconds)
	await shot_tween.finished

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT: fast_forward.cancel()

func _ready() -> void:
	size=Vector2(1600,900)
	mouse_filter=Control.MOUSE_FILTER_STOP
	for child in home.get_node("%HomeContent").get_children():
		if child is CanvasItem:
			saved_modulates[child]=child.modulate
			child.modulate.a=0.0
	home.get_node("%HomeContent").process_mode=Node.PROCESS_MODE_DISABLED
	home.relationship_hint.hide()
	home.get_node("%GuestLayer").modulate.a=0.0
	audio=preload("res://scripts/opening_audio.gd").new()
	add_child(audio)
	TimeManager.set_running(false)
	run.call_deferred()

func run() -> void:
	if OpeningTransition.busy: await OpeningTransition.finished
	phase="empty_room"
	var caption:=UI.panel(self,Rect2(55,650,1490,208))
	UI.label(caption,Rect2(35,22,1400,40),"我 · 心声",24,Color("eac88d"))
	var line:=UI.label(caption,Rect2(35,80,1400,65),"门开了。接下来，得由我自己招呼了。",28)
	hint=UI.label(caption,Rect2(1090,165,340,30),"长按空格 · 3 倍速",18,Color("d8c7ac"))
	caption.modulate.a=0
	shot_tween=create_tween()
	shot_tween.tween_property(caption,"modulate:a",1.0,.45)
	await shot_tween.finished
	await _pause(2.3)
	phase="arrival"
	audio.play_cue("door")
	await _pause(.35)
	# Change to the opening hour without running a customer wait timer during the shot.
	home._restoring_reception=not StoryDialogue.guest_id.is_empty()
	if not TimeManager.is_open:
		var start:=TimeManager.minutes_since_midnight
		var distance:=posmod(TimeManager.OPEN_MINUTE-start,1440)
		shot_tween=create_tween()
		shot_tween.tween_method(func(progress: float):
			var target:=start+int(round(distance*progress))
			TimeManager.advance_minutes(maxi(0,target-TimeManager.minutes_since_midnight))
		,0.0,1.0,.65)
		await shot_tween.finished
	else: home._on_business_opened(TimeManager.day)
	home._restoring_reception=false
	shot_tween=create_tween()
	shot_tween.tween_property(home.get_node("%GuestLayer"),"modulate:a",1.0,.6)
	await shot_tween.finished
	line.text="门口的牌子亮着，我想……进来歇一会儿。"
	caption.get_child(0).text="门口的客人"
	await _pause(2.8)
	phase="handover"
	shot_tween=create_tween()
	shot_tween.tween_property(caption,"modulate:a",0.0,.4)
	for child in saved_modulates:
		if not is_instance_valid(child): continue
		var duration:=.4 if child.name in ["GuestDialogue","GuestNote"] else .65
		shot_tween.parallel().tween_property(child,"modulate",saved_modulates[child],duration)
	await shot_tween.finished
	# An input held through the cinematic cannot immediately order/skip a conversation.
	while Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		await get_tree().process_frame
	home.get_node("%HomeContent").process_mode=Node.PROCESS_MODE_INHERIT
	home.arrival_presenting=false
	if GameSession.save_game(): OpeningFlow.acknowledge_arrival()
	home._refresh_relationship_hint()
	TimeManager.set_running(true)
	SaloonAudio.release_scene(OpeningTransition)
	phase="complete"
	completed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and not OpeningTransition.busy:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_SPACE:
			if event.pressed: fast_forward.press()
			else: fast_forward.release()
	if event is InputEventKey or event is InputEventMouse or event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
