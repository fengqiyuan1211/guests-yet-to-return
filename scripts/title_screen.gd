extends Control
const UI=preload("res://scripts/opening_ui.gd")
var stage: Control
var modal: Panel
var hint: Label
var menu: Control
var hover_chime: AudioStreamPlayer
var last_hover_ms := -1000

func _ready() -> void:
	OpeningFlow.front_end=true
	TimeManager.set_running(false)
	GameSession.home=null
	SaloonAudio.acquire_scene(self,"title")
	stage=Control.new()
	stage.size=Vector2(1600,900)
	add_child(stage)
	var bg=preload("res://scripts/opening_background.gd").new()
	var backgrounds: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/opening/backgrounds.json"))
	for entry: Dictionary in backgrounds.stages:
		if entry.id==backgrounds.active and entry.status=="active":
			bg.texture=preload("res://scripts/pixel_art.gd").texture(entry.background)
			bg.waves=bool(entry.get("ocean",false))
	if bg.texture==null: bg.texture=preload("res://assets/pixel_b/harbor.png")
	bg.size=stage.size
	stage.add_child(bg)
	# Quiet left-side tint makes the real text readable without an opaque menu card.
	var shade:=ColorRect.new()
	shade.color=Color(.04,.07,.1,.14)
	shade.size=stage.size
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage.add_child(shade)
	UI.label(stage,Rect2(94,134,700,105),"致未归的客人",70)
	UI.label(stage,Rect2(102,247,720,38),"G U E S T S   Y E T   T O   R E T U R N",20)
	menu=Control.new()
	stage.add_child(menu)
	var started: bool=OpeningFlow.state.phase!="new"
	var y:=352.0
	var first:=UI.button(menu,Rect2(92,y,310,62),"继续旅程" if started else "开始游戏",_continue)
	first.disabled=not OpeningFlow.writable
	y+=77
	if started:
		UI.button(menu,Rect2(92,y,310,62),"新的开始",_ask_new)
		y+=77
	UI.button(menu,Rect2(92,y,310,62),"设置",_settings)
	y+=77
	UI.button(menu,Rect2(92,y,310,62),"制作名单",_credits)
	y+=77
	UI.button(menu,Rect2(92,y,310,62),"退出游戏",func(): get_tree().quit())
	if started:
		UI.button(stage,Rect2(1120,824,360,48),"回看序章 · 练习教学",_replay,true)
	else: UI.label(stage,Rect2(1140,824,360,48),"海风与潮声",20)
	hint=UI.label(stage,Rect2(90,837,940,45),OpeningFlow.last_error,19)
	resized.connect(_fit)
	_fit()
	first.grab_focus()
	var surf:=AudioStreamPlayer.new()
	var track: AudioStreamWAV=preload("res://assets/audio/opening/shore.wav").duplicate()
	track.loop_mode=AudioStreamWAV.LOOP_FORWARD
	track.loop_end=track.data.size()/2
	surf.stream=track
	surf.bus=&"SFX"
	surf.volume_db=-26
	add_child(surf)
	surf.play()
	hover_chime=AudioStreamPlayer.new()
	hover_chime.stream=preload("res://assets/audio/opening/button-shimmer.wav")
	hover_chime.bus=&"SFX"
	hover_chime.volume_db=-16.0
	hover_chime.max_polyphony=2
	add_child(hover_chime)
	_wire_hover(stage)

func _wire_hover(node: Node) -> void:
	if node is Button:
		var callback:=_hover_button.bind(node)
		if not node.mouse_entered.is_connected(callback):
			node.mouse_entered.connect(callback)
	for child in node.get_children(): _wire_hover(child)

func _hover_button(button: Button) -> void:
	if button.disabled or not button.is_visible_in_tree() or not get_window().has_focus(): return
	if is_instance_valid(modal) and not modal.is_ancestor_of(button): return
	var now:=Time.get_ticks_msec()
	if now-last_hover_ms<260: return
	last_hover_ms=now
	hover_chime.play()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(hover_chime):
		hover_chime.stop()

func _fit() -> void:
	var scale_factor:=minf(size.x/1600.0,size.y/900.0)
	stage.scale=Vector2.ONE*scale_factor
	stage.position=(size-stage.size*scale_factor)*.5

func _continue() -> void:
	if OpeningTransition.busy: return
	var phase:=str(OpeningFlow.state.phase)
	if phase=="new" and not OpeningFlow.begin_story():
		hint.text=OpeningFlow.last_error
		return
	if phase=="ready":
		if not OpeningFlow.enter_game(): hint.text=OpeningFlow.last_error
	elif phase=="tutorial":
		if OpeningFlow.begin_tutorial(): OpeningTransition.go("res://scenes/workbench.tscn","workbench")
		else: hint.text=OpeningFlow.last_error
	elif phase=="ending": OpeningTransition.go("res://scenes/opening_departure.tscn")
	else: OpeningTransition.go("res://scenes/opening_story.tscn","opening_solitude")

func _close() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
		modal=null
	menu.mouse_filter=Control.MOUSE_FILTER_PASS
	for child in menu.get_children():
		if child is Button: child.disabled=not OpeningFlow.writable and child==menu.get_child(0)
	menu.get_child(0).grab_focus()

func _panel(title: String) -> Panel:
	_close()
	for child in menu.get_children():
		if child is Button: child.disabled=true
	modal=UI.panel(stage,Rect2(430,182,970,580))
	UI.label(modal,Rect2(38,30,840,65),title,34)
	UI.button(modal,Rect2(795,28,135,48),"返回",_close,true)
	_wire_hover(modal)
	return modal

func _ask_new() -> void:
	var p:=_panel("开始一段新的旅程？")
	var text:=UI.label(p,Rect2(42,132,870,200),"将备份现有进度，再从开篇剧情重新开始。\n金币、仓库、手帐、人物与小游戏进度会重新初始化。\n\n只想体验新增剧情？请返回并选择右下角的“回看序章”。",25)
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	UI.button(p,Rect2(44,442,350,70),"保留当前旅程",_close).grab_focus()
	UI.button(p,Rect2(510,442,400,70),"备份后开始新旅程",func():
		if OpeningTransition.busy: return
		if GameSession.restart_game():
			OpeningTransition.go("res://scenes/opening_story.tscn","opening_solitude")
		else: text.text=GameSession.last_error
	)
	_wire_hover(p)

func _replay() -> void:
	if OpeningTransition.busy: return
	if OpeningFlow.begin_replay(): OpeningTransition.go("res://scenes/opening_story.tscn","opening_solitude")
	else: hint.text=OpeningFlow.last_error

func _settings() -> void:
	var p:=_panel("风与酒馆的声音")
	for i in range(3):
		var entry: Array=[["Master","总音量"],["Music","背景音乐"],["SFX","音效与海浪"]][i]
		UI.label(p,Rect2(46,128+i*86,250,54),str(entry[1]),25)
		var slider:=HSlider.new()
		slider.position=Vector2(300,140+i*86)
		slider.size=Vector2(590,42)
		slider.max_value=100
		slider.value=SaloonAudio.get_volume(str(entry[0]))
		slider.value_changed.connect(func(value: float): SaloonAudio.set_volume(str(entry[0]),value))
		p.add_child(slider)
	var motion:=CheckButton.new()
	motion.text="减少动态（关闭海浪位移和灯光变化）"
	motion.add_theme_font_override("font",UI.FONT)
	motion.add_theme_font_size_override("font_size",23)
	motion.position=Vector2(45,421)
	motion.size=Vector2(850,60)
	motion.button_pressed=OpeningFlow.reduced_motion
	motion.toggled.connect(OpeningFlow.set_reduced_motion)
	p.add_child(motion)

func _credits() -> void:
	var p:=_panel("致未归的客人")
	UI.label(p,Rect2(45,132,875,310),"开篇 · 回响 / Echo World\n\n开始界面配乐\nLaura – Soft Acoustic Guitar Folk Instrumental\nkaazoom / Pixabay\n\n海港与剧情美术：项目手绘方向，AI 辅助制作\n海浪：局部水域着色与合成环境声",25)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(modal):
		_close()
		get_viewport().set_input_as_handled()
