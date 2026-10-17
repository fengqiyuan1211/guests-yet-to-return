extends Control
const UI=preload("res://scripts/opening_ui.gd")
const STORY_PATH="res://data/opening/story.json"
var nodes: Array=[]
var stage: Control
var background: TextureRect
var heading: Label
var speaker: Label
var dialogue: Label
var progress: Label
var next_button: Button
var choices: Control
var error_label: Label
var fade: ColorRect
var transition: Tween
var current_background:=""
var type_clock:=0.0
var ending:=false
var busy:=false
var mail_card: Panel
var mail_button: Button
var mail_reader: Control
var active_mail_id:=""
var history_panel: Control
var history_button: Button
var chapter_panel: Panel
var story_audio: Node

func _ready() -> void:
	OpeningFlow.front_end=true
	TimeManager.set_running(false)
	nodes=JSON.parse_string(FileAccess.get_file_as_string(STORY_PATH)).nodes
	story_audio=preload("res://scripts/opening_audio.gd").new()
	add_child(story_audio)
	stage=Control.new()
	stage.size=Vector2(1600,900)
	add_child(stage)
	background=preload("res://scripts/opening_background.gd").new()
	background.size=stage.size
	stage.add_child(background)
	fade=ColorRect.new()
	fade.color=Color("142128")
	fade.size=stage.size
	fade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage.add_child(fade)
	chapter_panel=UI.panel(stage,Rect2(55,30,950,70))
	chapter_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	heading=UI.label(chapter_panel,Rect2(22,12,906,46),"",28)
	history_button=UI.button(stage,Rect2(1035,35,155,48),"历史对话 H",_open_history,true)
	UI.button(stage,Rect2(1210,35,155,48),"跳过剧情",_skip,true)
	UI.button(stage,Rect2(1380,35,155,48),"返回开始",OpeningFlow.return_to_title,true)
	var panel:=UI.panel(stage,Rect2(55,650,1490,208))
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed: _advance()
	)
	speaker=UI.label(panel,Rect2(35,17,1290,39),"",24,Color("eac88d"))
	dialogue=UI.label(panel,Rect2(35,66,1400,83),"",28)
	dialogue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	progress=UI.label(panel,Rect2(35,165,1050,29),"",16,Color("bfb5a2"))
	next_button=UI.button(panel,Rect2(1110,150,330,48),"空格 · 继续",_advance,true)
	choices=Control.new()
	choices.position=Vector2(600,475)
	stage.add_child(choices)
	error_label=UI.label(stage,Rect2(70,865,1460,30),"",18,Color("ffd597"))
	resized.connect(_fit)
	_fit()
	_render()

func _fit() -> void:
	var factor:=minf(size.x/1600.0,size.y/900.0)
	stage.scale=Vector2.ONE*factor
	stage.position=(size-stage.size*factor)*.5

func _render() -> void:
	ending=OpeningFlow.state.phase=="ending"
	var index:=int(OpeningFlow.state.node)
	var node: Dictionary=nodes[index]
	story_audio.present({"id":"ending","music":"opening_home","background":"porch"} if ending else node,self)
	var bg: String="porch" if ending else str(node.background)
	if bg!=current_background:
		current_background=bg
		background.texture=load("res://assets/art/saloon-day-unlit-v2.png" if bg=="saloon" else "res://assets/art/opening/"+bg+".png")
		background.material.set_shader_parameter("ocean",bg=="harbor-sunset")
		if is_instance_valid(transition): transition.kill()
		fade.modulate.a=1
		transition=create_tween()
		transition.tween_property(fade,"modulate:a",0.0,.65)
	heading.text="序章 · 今晚，先把灯点亮" if ending else node.chapter+" · "+node.title
	chapter_panel.size.x=minf(950.0,heading.get_theme_font("font").get_string_size(heading.text,HORIZONTAL_ALIGNMENT_LEFT,-1,28).x+44.0)
	heading.size.x=chapter_panel.size.x-44.0
	speaker.text="老管家" if ending else node.speaker
	dialogue.text="开门了，才知道谁会来。\n回响的配方会留在图鉴，之后由您决定是否放进营业酒单。" if ending else node.text
	progress.text="回看结束后返回开始界面；不改变原旅程。" if OpeningFlow.replaying else ("教学杯不计收入；正式原料需要从商店备齐。" if ending else "%d / %d · 空格/点击继续 · Esc 保存并返回" % [index+1,nodes.size()])
	for child in choices.get_children():
		child.hide()
		child.queue_free()
	var answered:=str(OpeningFlow.state.choices.get(str(node.id),""))
	var options: Array=[] if ending else node.get("choices",[])
	if not answered.is_empty():
		for option: Dictionary in options:
			if option.text==answered: dialogue.text=option.reply
	elif not options.is_empty():
		for i in range(options.size()):
			var option: Dictionary=options[i]
			var b:=UI.button(choices,Rect2(0,i*70,880,58),str(option.text),_choose.bind(str(option.text)))
			if i==0: b.grab_focus()
	next_button.disabled=not options.is_empty() and answered.is_empty()
	next_button.text=("结束回看" if OpeningFlow.replaying else "翻转营业牌 · 开门") if ending else ("空格 · 开始调酒" if index==nodes.size()-1 else "空格 · 继续")
	_render_mail(node if not ending else {})
	dialogue.visible_characters=0
	type_clock=0

func _render_mail(node: Dictionary) -> void:
	if is_instance_valid(mail_card):
		mail_card.hide()
		mail_card.queue_free()
	mail_card=null
	active_mail_id=str(node.get("mail_id",""))
	if active_mail_id.is_empty(): return
	var mail: Dictionary=OpeningFlow.story.mail[active_mail_id]
	var read: bool=OpeningFlow.state.mail_read.get(active_mail_id,false)
	mail_card=UI.panel(stage,Rect2(690,160,820,255))
	UI.label(mail_card,Rect2(28,15,740,32),"邮件  ·  已阅读" if read else "●  收到一封新邮件",20,Color("eac88d"))
	UI.label(mail_card,Rect2(28,55,740,48),str(mail.subject),30)
	UI.label(mail_card,Rect2(28,109,740,31),str(mail.sender),20,Color("caba9e"))
	UI.label(mail_card,Rect2(28,148,740,31),str(mail.preview),21)
	mail_button=UI.button(mail_card,Rect2(444,193,344,46),"打开邮箱 · 查看邮件",_open_mail,true)
	if not read: next_button.text="查看邮箱 · 读这封信"

func _open_mail() -> void:
	if active_mail_id.is_empty() or is_instance_valid(mail_reader) or is_instance_valid(history_panel): return
	mail_reader=preload("res://scripts/opening_mail.gd").new()
	mail_reader.mail=OpeningFlow.story.mail[active_mail_id]
	mail_reader.closed.connect(_close_mail)
	mail_reader.read_requested.connect(_read_mail)
	stage.add_child(mail_reader)

func _close_mail() -> void:
	if is_instance_valid(mail_reader):
		mail_reader.hide()
		mail_reader.queue_free()
	mail_reader=null
	_focus_story_action()

func _read_mail() -> void:
	if not OpeningFlow.mark_mail_read(active_mail_id):
		mail_reader.show_error(OpeningFlow.last_error)
		return
	_close_mail()
	# Explicitly reading the mail is the action that advances this story beat.
	dialogue.visible_characters=dialogue.text.length()
	_advance()

func _process(delta: float) -> void:
	if is_instance_valid(history_panel) or is_instance_valid(mail_reader): return
	if dialogue.visible_characters<dialogue.text.length():
		type_clock+=delta*32
		dialogue.visible_characters=mini(int(type_clock),dialogue.text.length())

func _choose(text: String) -> void:
	if not OpeningFlow.advance(int(OpeningFlow.state.node),text):
		error_label.text=OpeningFlow.last_error
		return
	_render()

func _advance() -> void:
	if busy or is_instance_valid(mail_reader) or is_instance_valid(history_panel): return
	if not active_mail_id.is_empty() and not OpeningFlow.state.mail_read.get(active_mail_id,false):
		_open_mail()
		return
	if dialogue.visible_characters<dialogue.text.length():
		type_clock=dialogue.text.length()
		dialogue.visible_characters=dialogue.text.length()
		return
	if next_button.disabled: return
	if ending:
		busy=true
		if not OpeningFlow.finish_opening():
			busy=false
			error_label.text=OpeningFlow.last_error
		return
	var index:=int(OpeningFlow.state.node)
	if index==nodes.size()-1: _skip()
	elif OpeningFlow.advance(index+1): _render()
	else: error_label.text=OpeningFlow.last_error

func _skip() -> void:
	if ending or is_instance_valid(history_panel) or is_instance_valid(mail_reader): return
	if OpeningFlow.begin_tutorial(): get_tree().change_scene_to_file("res://scenes/workbench.tscn")
	else: error_label.text=OpeningFlow.last_error

func _open_history() -> void:
	if is_instance_valid(history_panel) or is_instance_valid(mail_reader): return
	history_panel=preload("res://scripts/opening_history.gd").new()
	history_panel.entries=OpeningFlow.history_entries()
	history_panel.closed.connect(_close_history)
	stage.add_child(history_panel)

func _close_history() -> void:
	if is_instance_valid(history_panel):
		history_panel.hide()
		history_panel.queue_free()
	history_panel=null
	_focus_story_action()

func _focus_story_action() -> void:
	if not next_button.disabled:
		next_button.grab_focus()
	else:
		for child in choices.get_children():
			if child is Button and child.is_visible_in_tree():
				child.grab_focus()
				break

func _input(event: InputEvent) -> void:
	# Reserved story keys run before Control's ui_accept (Space). Consuming both
	# edges prevents focused History/Skip buttons from firing on key release.
	if not is_visible_in_tree() or not event is InputEventKey: return
	if event.keycode not in [KEY_SPACE,KEY_H,KEY_ESCAPE] and event.physical_keycode not in [KEY_SPACE,KEY_H,KEY_ESCAPE]: return
	get_viewport().set_input_as_handled()
	_unhandled_key_input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if is_instance_valid(history_panel): _close_history()
		elif is_instance_valid(mail_reader): _close_mail()
		else: OpeningFlow.return_to_title()
	elif event.physical_keycode==KEY_H or event.keycode==KEY_H:
		get_viewport().set_input_as_handled()
		if is_instance_valid(history_panel): _close_history()
		else: _open_history()
	elif event.physical_keycode==KEY_SPACE or event.keycode==KEY_SPACE:
		get_viewport().set_input_as_handled()
		_advance()
	else: return
