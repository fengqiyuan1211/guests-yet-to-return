extends Control
## Post-tutorial story owns presentation; existing services own stock, money and menus.
const UI=preload("res://scripts/opening_ui.gd")
const Prep=preload("res://scripts/opening_preparation.gd")
const Conversation=preload("res://scripts/merchant_conversation.gd")
const PAPER=preload("res://assets/pixel_b/paper.svg")
var arrival_timer: Timer
var stage: Control
var background: TextureRect
var props: Control
var heading: Label
var speaker: Label
var dialogue: Label
var status: Label
var next_button: Button
var preparation: Control
var external_page: Control
var conversation: Control
var history_panel: Control
var narrative_panel: Control
var story_audio: Node
var nodes: Array=[]
var row: Dictionary={}
var clock:=0.0
var pulse:=0.0
var busy:=false
var tip: Label
var sign_press:=Vector2.ZERO
var hint_target: Control
var autoplay = preload("res://scripts/story_autoplay.gd").new()
var auto_button: Button
var fast_forward = preload("res://scripts/story_fast_forward.gd").new()
var speed_hint: Panel
var scene_cover: ColorRect
var prop_tween: Tween
var room_transition: Tween
var prop_key := ""
var water_cup: Control
var sign_face: Button
var character_art: Control
var name_edit: LineEdit
var name_hint: Label
var signature_button: Button

func _ready() -> void:
	OpeningFlow.front_end=true
	TimeManager.set_running(false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.backdrop(self)
	stage=Control.new()
	stage.size=Vector2(1600,900)
	stage.add_theme_font_override("font",UI.FONT)
	add_child(stage)
	background=preload("res://scripts/opening_background.gd").new()
	background.size=stage.size
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	character_art=preload("res://scripts/opening_portrait.gd").new()
	stage.add_child(character_art)
	props=Control.new()
	props.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage.add_child(props)
	scene_cover=ColorRect.new()
	scene_cover.size=Vector2(1600,900)
	scene_cover.color=Color("10181f")
	scene_cover.modulate.a=0
	scene_cover.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage.add_child(scene_cover)
	var chapter:=UI.panel(stage,Rect2(45,30,875,70))
	heading=UI.label(chapter,Rect2(25,12,825,46),"先把今晚的灯点起来",28)
	UI.button(stage,Rect2(1035,35,200,48),"历史对话 H",_history,true)
	UI.button(stage,Rect2(1260,35,290,48),"保存并返回开始",func():
		if not busy: OpeningFlow.return_to_title()
	,true)
	speed_hint=UI.panel(stage,Rect2(1220,95,320,44))
	speed_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	UI.label(speed_hint,Rect2(12,5,296,34),"快进中 ×10 · 松开恢复",21,Color("ffe7a7"))
	speed_hint.hide()
	var panel:=UI.panel(stage,Rect2(55,650,1490,208))
	narrative_panel=panel
	speaker=UI.label(panel,Rect2(35,17,1290,39),"",24,Color("eac88d"))
	dialogue=UI.label(panel,Rect2(35,64,1400,86),"",27)
	dialogue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed: _advance()
	)
	status=UI.label(panel,Rect2(35,165,770,30),"",17,Color("dbccb2"))
	auto_button=UI.button(panel,Rect2(815,152,230,46),"自动播放：关 A",_toggle_auto,true)
	auto_button.tooltip_text="对话自动继续；签收、备料、购物与开门仍由你操作。"
	next_button=UI.button(panel,Rect2(1060,152,380,46),"继续 · 空格",_advance,true)
	next_button.tooltip_text="短按空格或点击继续；长按空格 10 倍速，签收、购物、开门等操作仍需手动确认。"
	tip=UI.label(stage,Rect2(220,590,1160,44),"",23,Color("ffe7a7"))
	tip.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	story_audio=preload("res://scripts/opening_audio.gd").new()
	add_child(story_audio)
	resized.connect(_fit)
	_fit()
	nodes=OpeningFlow.departure_nodes()
	if not OpeningFlow.begin_departure():
		status.text=OpeningFlow.last_error
		next_button.disabled=true
		return
	_render()

func _fit() -> void:
	var factor:=minf(size.x/1600.0,size.y/900.0)
	stage.scale=Vector2.ONE*factor
	stage.position=(size-stage.size*factor)*.5

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func current_index() -> int:
	for i in range(nodes.size()):
		if nodes[i].id==OpeningFlow.state.departure.node: return i
	return 0

func _reflection() -> String:
	if OpeningFlow.state.tutorial_status=="skipped": return "步骤先留着。哪天想练，我们再开一杯。"
	var result: Dictionary=OpeningFlow.state.tutorial.get("session",{}).get("result",{})
	var evaluation: Dictionary=result.get("evaluation",{})
	if float(evaluation.get("score",0))>=85: return "香气回来了。您尝尝，是不是记得的那个味道？"
	# The evaluator's descriptor already comes from the actual cup.
	var description:=str(evaluation)
	if "齁甜" in description: return "甜味停得久了些。两种利口酒，下次可以再量稳一点。"
	if "酸涩" in description: return "青柠先出来了。把这次的量记下，下一杯就知道往哪儿调。"
	return "和纸上那杯不一样。差在哪里，咱们已经记下来了。"

func _render() -> void:
	autoplay.reset()
	busy=false
	narrative_panel.show()
	row=nodes[current_index()].duplicate(true)
	if row.get("dynamic")=="cup": row.text=_reflection()
	elif OpeningFlow.state.tutorial_status=="skipped" and row.has("skip_text"): row.text=row.skip_text
	if not OpeningFlow.observe_departure(row):
		status.text=OpeningFlow.last_error
		next_button.disabled=true
		return
	heading.text="开业前 · "+str(row.chapter)
	speaker.text=OpeningFlow.protagonist_speaker(str(row.speaker))
	character_art.present(row,true,fast_forward.active)
	dialogue.text=row.text
	dialogue.visible_characters=dialogue.text.length() if fast_forward.active else 0
	clock=dialogue.visible_characters
	status.text="回看 · 长按空格 10 倍速 · 不改变经营进度" if OpeningFlow.replaying else "点击/短按继续 · 长按空格 10 倍速 · H 历史"
	next_button.text=str(row.get("button","继续 · 空格"))
	next_button.disabled=false
	if OpeningFlow.replaying and row.get("action")=="finish": next_button.text="开业，迎接米洛 →"
	background.texture=preload("res://scripts/pixel_art.gd").texture("res://assets/art/saloon-day-unlit-v2.png" if row.background=="saloon" else "res://assets/art/opening/porch.png")
	background.material.set_shader_parameter("ocean",false)
	story_audio.present(row,self)
	if is_instance_valid(prop_tween): prop_tween.kill()
	props.position=Vector2.ZERO
	props.modulate=Color.WHITE
	_clear(props)
	water_cup=null
	sign_face=null
	hint_target=null
	name_edit=null
	name_hint=null
	signature_button=null
	tip.text=""
	_render_prop()
	var next_prop:=str(row.get("prop",""))
	if next_prop!=prop_key and next_prop in ["parcel","receipt","ledger","sign"]:
		props.modulate.a=0
		props.position.y=0 if OpeningFlow.reduced_motion else 18
		prop_tween=create_tween().set_parallel()
		prop_tween.tween_property(props,"modulate:a",1.0,.35)
		prop_tween.tween_property(props,"position:y",0.0,.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	prop_key=next_prop
	if row.get("action")=="prepare": _show_preparation()
	if row.get("action")=="finish" and OpeningFlow.can_write_playthrough():
		status.text="营业牌已翻开 · 稍后直接迎接第一位客人"
		if not is_instance_valid(arrival_timer):
			arrival_timer=Timer.new()
			arrival_timer.one_shot=true
			add_child(arrival_timer)
			arrival_timer.timeout.connect(_enter_first_arrival)
		arrival_timer.start(4.5)

func _enter_first_arrival() -> void:
	if row.get("action")!="finish" or not OpeningFlow.can_write_playthrough(): return
	if busy or OpeningTransition.busy or is_instance_valid(history_panel):
		arrival_timer.start(.5)
		return
	busy=true
	if not OpeningFlow.finish_opening():
		busy=false
		status.text=OpeningFlow.last_error


func _paper(rect: Rect2) -> TextureRect:
	var paper:=TextureRect.new()
	paper.texture=PAPER
	paper.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper.position=rect.position
	paper.size=rect.size
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	props.add_child(paper)
	return paper

func _render_prop() -> void:
	var prop:=str(row.get("prop",""))
	if prop=="drink" and OpeningFlow.state.tutorial_status!="skipped":
		var preview:=preload("res://scripts/workbench_drink_preview.gd").new()
		preview.result=OpeningFlow.state.tutorial.get("session",{}).get("result",{}).duplicate(true)
		preview.reference_only=true
		# Preview reserves 48 px below the glass: its foot lands at canvas y=590.
		preview.position=Vector2(1000,368)
		preview.size=Vector2(240,270)
		preview.tabletop_shadow=true
		preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
		props.add_child(preview)
	elif prop in ["parcel","receipt","ledger"]:
		var paper:=_paper(Rect2(540,200,520,350))
		paper.rotation=-.025
		UI.label(props,Rect2(593,235,420,42),"交 接 账 册" if prop!="receipt" else "收 货 签 认",32,Color("51371f"))
		var text:="旧酒单 · 空白收货单\n\n收件人：酒馆的新主人\n\n纸上的东西，慢慢理清。"
		if prop=="receipt":
			UI.label(props,Rect2(590,302,420,35),"已收到：账册、旧酒单",24,Color("63482c"))
			UI.label(props,Rect2(590,348,420,32),"收件人签字：",23,Color("63482c"))
		else:
			UI.label(props,Rect2(590,302,420,195),text,24,Color("63482c"))
		if row.get("action")=="sign":
			_render_signature()
	elif prop=="water":
		var image:=preload("res://scripts/workbench_drink_preview.gd").new()
		image.reference_only=true
		image.result={"cup":"highball","capacity_ml":300,"contents":{"contents":{"drinking_water":170},"ice":"none","garnish":false},"liquid_profiles":{"drinking_water":{"version":"story-water-1","rgb":[237,247,255],"strength":0.0,"turbidity":0.0}}}
		image.position=Vector2(970,330) if row.get("action")=="water" else Vector2(860,358)
		image.size=Vector2(180,235)
		image.tabletop_shadow=true
		image.visible=OpeningFlow.state.departure.water or row.get("action")=="water"
		image.mouse_filter=Control.MOUSE_FILTER_IGNORE
		props.add_child(image)
		water_cup=image
		var caption:=UI.panel(props,Rect2(565,235,430,160))
		UI.label(caption,Rect2(25,25,380,100),"门口的椅子还在。\n给赶路的人，留一杯水。",28)
	elif prop=="sign":
		var opened: bool=OpeningFlow.state.departure.opened
		var paper:=_paper(Rect2(595,235,410,265))
		paper.rotation=.025
		var button:=UI.button(props,Rect2(635,285,330,135),"营 业 中" if opened else "准 备 中",_advance)
		sign_face=button
		button.add_theme_font_size_override("font_size",42)
		button.add_theme_color_override("font_color",Color("563a23"))
		for color_key in ["font_disabled_color","font_hover_color","font_focus_color","font_pressed_color"]:
			button.add_theme_color_override(color_key,Color("563a23"))
		button.add_theme_stylebox_override("disabled",StyleBoxEmpty.new())
		button.disabled=row.get("action")!="open"
		if not button.disabled:
			hint_target=button
			button.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
					if event.pressed: sign_press=event.position
					elif event.position.distance_to(sign_press)>35 and not OpeningFlow.state.departure.opened: _advance()
			)
			tip.text="↓  点击或拖动营业牌 · 也可以按空格"
		UI.label(props,Rect2(635,437,340,40),"今晚，先开这一会儿。",23,Color("63482c"))

func _render_signature() -> void:
	_cancel_fast_forward()
	name_edit=LineEdit.new()
	name_edit.name="ProtagonistName"
	name_edit.position=Vector2(590,385)
	name_edit.size=Vector2(420,48)
	name_edit.max_length=OpeningFlow.PLAYER_NAME_LIMIT
	name_edit.placeholder_text="在这里写下你的名字"
	name_edit.text=str(OpeningFlow.state.get("player_name",""))
	name_edit.add_theme_font_override("font",UI.FONT)
	name_edit.add_theme_font_size_override("font_size",25)
	name_edit.add_theme_color_override("font_color",Color("51371f"))
	name_edit.add_theme_color_override("font_placeholder_color",Color("887354"))
	name_edit.add_theme_color_override("caret_color",Color("51371f"))
	name_edit.add_theme_color_override("selection_color",Color("b5a57a"))
	for style in ["normal","focus"]:
		var box:=StyleBoxFlat.new()
		box.bg_color=Color("f6e7bd")
		box.border_color=Color("9e713c" if style=="focus" else "baa173")
		box.set_border_width_all(2)
		box.content_margin_left=12
		box.content_margin_right=12
		name_edit.add_theme_stylebox_override(style,box)
	props.add_child(name_edit)
	name_hint=UI.label(props,Rect2(590,438,430,28),"1—16 个字 · 将作为你的主角名字",18,Color("745033"))
	signature_button=UI.button(props,Rect2(650,478,310,46),"确认名字并签收",_advance,true)
	hint_target=signature_button
	next_button.text="确认名字并签收"
	status.text="输入时空格与字母只用于填写 · 点击按钮确认"
	if OpeningFlow.replaying: status.text="回看试填 · 不会更改正式存档中的主角名字"
	tip.text="↓  点击签字栏填写名字，再点击确认"
	name_edit.text_changed.connect(func(_value):
		name_hint.text="1—16 个字 · 将作为你的主角名字"
		name_hint.add_theme_color_override("font_color",Color("745033"))
	)
	name_edit.focus_entered.connect(_cancel_fast_forward)
	name_edit.grab_focus()

func _process(delta: float) -> void:
	if not is_instance_valid(dialogue): return
	if not get_window().has_focus():
		autoplay.reset()
		_cancel_fast_forward()
		return
	pulse+=delta
	if is_instance_valid(hint_target): hint_target.modulate=Color(1,1,1,.8+.2*sin(pulse*3))
	if is_instance_valid(history_panel) or is_instance_valid(external_page) or is_instance_valid(conversation) or is_instance_valid(preparation):
		autoplay.reset()
		_cancel_fast_forward()
		return
	var playback:=fast_forward.step(delta,_can_auto_advance() or (busy and str(row.get("action","")).is_empty()))
	if is_instance_valid(room_transition): room_transition.set_speed_scale(playback)
	speed_hint.visible=fast_forward.active
	background.playback_speed=playback
	if fast_forward.active: clock=dialogue.text.length()
	else: clock+=delta*34
	dialogue.visible_characters=mini(int(clock),dialogue.text.length())
	if autoplay.tick(delta,dialogue.text.length(),dialogue.visible_characters>=dialogue.text.length(),_can_auto_advance(),fast_forward.active): _advance()

func _cancel_fast_forward() -> void:
	fast_forward.cancel()
	if is_instance_valid(speed_hint): speed_hint.hide()
	if is_instance_valid(background): background.playback_speed=1.0
	if is_instance_valid(room_transition): room_transition.set_speed_scale(1.0)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT: _cancel_fast_forward()

func _can_auto_advance() -> bool:
	return not row.is_empty() and not busy and not next_button.disabled and str(row.get("action","")).is_empty() and not is_instance_valid(history_panel) and not is_instance_valid(external_page) and not is_instance_valid(conversation) and not is_instance_valid(preparation)

func _toggle_auto() -> void:
	auto_button.text="自动播放：开 A" if autoplay.toggle() else "自动播放：关 A"
	next_button.grab_focus()

func _advance() -> void:
	autoplay.reset()
	if busy or OpeningTransition.busy or next_button.disabled or row.is_empty() or is_instance_valid(history_panel) or is_instance_valid(conversation) or is_instance_valid(external_page) or is_instance_valid(preparation): return
	if row.get("action")!="sign" and dialogue.visible_characters>=0 and dialogue.visible_characters<dialogue.text.length():
		clock=dialogue.text.length()
		dialogue.visible_characters=-1
		return
	var patch: Dictionary={}
	match str(row.get("action","")):
		"sign":
			if not is_instance_valid(name_edit): return
			var error:=OpeningFlow.player_name_error(name_edit.text)
			if not error.is_empty():
				name_hint.text=error
				name_hint.add_theme_color_override("font_color",Color("963f30"))
				name_edit.grab_focus()
				return
		"water": patch.water=true
		"open":
			if not Prep.ready_menu():
				status.text="库存发生变化，先返回备料，确保有一款酒能够制作。"
				_show_preparation()
				return
			patch.opened=true
		"finish":
			busy=true
			if not OpeningFlow.finish_opening():
				busy=false
				status.text=OpeningFlow.last_error
			return
	var i:=current_index()
	if i+1>=nodes.size(): return
	patch.node=nodes[i+1].id
	var saved: bool=OpeningFlow.sign_receipt(name_edit.text) if row.get("action")=="sign" else OpeningFlow.update_departure(patch)
	if not saved:
		status.text=OpeningFlow.last_error
		return
	if is_instance_valid(name_edit):
		name_edit.text=OpeningFlow.protagonist_name()
		name_edit.editable=false
		name_edit.release_focus()
		name_hint.hide()
	busy=true
	next_button.disabled=true
	if not str(row.get("action","")).is_empty(): _cancel_fast_forward()
	await _perform_action(str(row.get("action","")))
	var changed_room: bool=nodes[i+1].background!=row.background and not fast_forward.active
	if changed_room:
		room_transition=create_tween()
		room_transition.tween_property(scene_cover,"modulate:a",1.0,.3)
		await room_transition.finished
	_render()
	if changed_room:
		busy=true
		room_transition=create_tween()
		room_transition.tween_property(scene_cover,"modulate:a",0.0,.5)
		await room_transition.finished
		busy=false

func _perform_action(action: String) -> void:
	if action.is_empty(): return
	if is_instance_valid(prop_tween): prop_tween.kill()
	props.position=Vector2.ZERO
	props.modulate=Color.WHITE
	if is_instance_valid(hint_target): hint_target.hide()
	tip.text=""
	match action:
		"sign":
			story_audio.play_cue("paper")
			var stamp:=UI.label(props,Rect2(790,438,230,40),"已 签 收",30,Color("8b4435"))
			stamp.pivot_offset=stamp.size*.5
			stamp.rotation=-.1
			stamp.scale=Vector2.ONE*(1.0 if OpeningFlow.reduced_motion else 1.25)
			stamp.modulate.a=0
			var imprint:=create_tween().set_parallel()
			imprint.tween_property(stamp,"modulate:a",1.0,.25)
			imprint.tween_property(stamp,"scale",Vector2.ONE,.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			await imprint.finished
			status.text="已签收 · 从今天起，这里有了新的收件人。"
			await get_tree().create_timer(.6).timeout
		"water":
			if is_instance_valid(water_cup):
				var pass_cup:=create_tween().set_parallel()
				pass_cup.tween_property(water_cup,"position",Vector2(860,358),.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
				pass_cup.tween_property(water_cup,"scale",Vector2.ONE,.65)
				await pass_cup.finished
			story_audio.play_cue("clink")
			status.text="水递过去了。门外的人坐了下来。"
			await get_tree().create_timer(.45).timeout
		"open":
			# Paper and lettering share one hinge so the sign turns as one object.
			if is_instance_valid(sign_face): sign_face.show()
			props.pivot_offset=Vector2(800,365)
			var turn:=create_tween()
			turn.tween_property(props,"scale:x",.03,.23)
			await turn.finished
			if is_instance_valid(sign_face):
				sign_face.text="营 业 中"
				sign_face.disabled=true
			story_audio.play_cue("door")
			var settle_sign:=create_tween()
			settle_sign.tween_property(props,"scale:x",1.0,.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			await settle_sign.finished
			status.text="营业中 · 今晚，先等一位客人。"
			await get_tree().create_timer(.55).timeout

func _show_preparation() -> void:
	if not OpeningFlow.ensure_replay_world():
		status.text=OpeningFlow.last_error
		return
	if is_instance_valid(preparation): return
	narrative_panel.hide()
	preparation=preload("res://scripts/opening_supply_lesson.gd").new()
	preparation.size=Vector2(1600,900)
	stage.add_child(preparation)
	preparation.completed.connect(func():
		preparation.queue_free()
		preparation=null
		narrative_panel.show()
		_render())

func _show_legacy_preparation() -> void:
	narrative_panel.hide()
	tip.text=""
	if is_instance_valid(preparation): preparation.queue_free()
	preparation=Control.new()
	preparation.size=stage.size
	stage.add_child(preparation)
	var panel:=UI.panel(preparation,Rect2(105,130,1390,705))
	UI.label(panel,Rect2(35,20,1050,48),"今晚先备一款",34)
	UI.label(panel,Rect2(35,80,1290,36),"选配方 → 看真实余量 → 去货栈补货 → 确认加入酒单",22,Color("dfc89c"))
	var recipes:=MenuCatalog.all_recipes()
	var list:=ScrollContainer.new()
	list.position=Vector2(35,145)
	list.size=Vector2(335,420)
	panel.add_child(list)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	list.add_child(column)
	for recipe: Dictionary in recipes:
		var b:=Button.new()
		b.text=str(recipe.name)+( "  ✓" if OpeningFlow.state.departure.recipe==recipe.id else "")
		b.custom_minimum_size=Vector2(310,60)
		b.add_theme_font_size_override("font_size",24)
		b.pressed.connect(_select_recipe.bind(str(recipe.id)))
		column.add_child(b)
	var report:=Prep.report(str(OpeningFlow.state.departure.recipe))
	var recipe: Dictionary=report.recipe
	var heading_text:=str(recipe.get("name","未选择"))+"  /  "+str(recipe.get("english_name",""))
	UI.label(panel,Rect2(410,143,900,45),heading_text,28)
	var scroll:=ScrollContainer.new()
	scroll.position=Vector2(410,207)
	scroll.size=Vector2(925,295)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",14)
	scroll.add_child(details)
	for item: Dictionary in report.rows:
		var line:=Label.new()
		line.text="%s\n需 %s %s · 现有 %s %s%s" % [item.name,_amount(item.required),item.unit,_amount(item.remaining),item.unit,"  ✓" if item.missing<=0 else " · 还缺 %s %s" % [_amount(item.missing),item.unit]]
		line.add_theme_font_size_override("font_size",21)
		line.add_theme_color_override("font_color",Color("d7e4be") if item.missing<=0 else Color("f3d9a6"))
		details.add_child(line)
	var equipment:=Label.new()
	equipment.text="杯型：%s · 器具与冰由吧台常备\n材料备齐后，经典酒谱会点亮；上架仍由你确认。" % str(recipe.get("glass","按配方"))
	equipment.add_theme_font_size_override("font_size",18)
	details.add_child(equipment)
	var message:="材料已备齐。" if report.ready else "补齐至少需 %d 金币 · 当前 %d 金币" % [report.cost,SlotWallet.balance]
	if report.cost>SlotWallet.balance: message+=" · 可先选择花费更少的酒"
	if not report.message.is_empty(): message=report.message
	if OpeningFlow.replaying: message="回看只展示备料说明，不购买、不修改正式酒单。"
	UI.label(panel,Rect2(410,523,915,60),message,21,Color("ffe1a7"))
	var meet:=UI.button(panel,Rect2(35,610,390,57),"去货栈 · 认识老板娘",_visit_shop)
	meet.name="VisitShop"
	var publish:=UI.button(panel,Rect2(875,610,460,57),"看过说明，继续" if OpeningFlow.replaying else "确认上架，回去准备开门",_publish)
	publish.name="PublishOpeningMenu"
	publish.disabled=not OpeningFlow.replaying and (not report.ready or not OpeningFlow.state.departure.seed_heard)
	UI.label(panel,Rect2(35,568,1290,34),"不必重复买已有材料。先去认认门，听她说完，再回来确认今晚的酒单。",19)
	UI.button(panel,Rect2(470,610,350,57),"保存并返回开始",OpeningFlow.return_to_title)

func _amount(value: float) -> String:
	return WorkbenchSession.format_amount(value)

func _select_recipe(id: String) -> void:
	if OpeningFlow.update_departure({"recipe":id}): _show_preparation()
	else: status.text=OpeningFlow.last_error

func _visit_shop() -> void:
	if is_instance_valid(preparation):
		preparation.queue_free()
		preparation=null
	if not OpeningFlow.state.departure.merchant_met:
		_start_conversation("merchant_intro",_after_introduction)
	else: _browse_shop()

func _start_conversation(topic: String, done: Callable) -> void:
	if not OpeningFlow.replaying and Relationships.state.flags.get("done:"+topic,false): done.call(); return
	var view:=Control.new()
	view.size=stage.size
	stage.add_child(view)
	var harbor:=preload("res://scripts/harbor_day_night.gd").new()
	harbor.size=stage.size
	view.add_child(harbor)
	var portrait_layer:=Control.new()
	portrait_layer.size=Vector2(1600,535)
	portrait_layer.clip_contents=true
	portrait_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	view.add_child(portrait_layer)
	var art:=TextureRect.new()
	art.name="MerchantPortrait"
	# Ignore the source minimum BEFORE assigning texture/size, or the 1447px
	# source silently expands this control into an unintended face close-up.
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture=preload("res://scripts/pixel_art.gd").sprite("harbor_merchant")
	art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art.position=Vector2(90,125)
	art.size=Vector2(560,725)
	portrait_layer.add_child(art)
	conversation=Conversation.new()
	conversation.topic=topic
	conversation.preview_only=OpeningFlow.replaying
	conversation.closed.connect(func():
		var complete: bool=conversation.index>=Relationships.config.topics[topic].size()
		conversation=null
		view.queue_free()
		SaloonAudio.set_scene_context(self,"opening_home")
		if complete: done.call()
		else: _show_preparation()
	)
	view.add_child(conversation)
	SaloonAudio.set_scene_context(self,"shop")

func _after_introduction() -> void:
	if OpeningFlow.update_departure({"merchant_met":true}): _browse_shop()
	else: status.text=OpeningFlow.last_error

func _browse_shop() -> void:
	if OpeningFlow.replaying:
		_start_conversation("merchant_seed",_after_seed)
		return
	external_page=preload("res://scenes/harbor_shop.tscn").instantiate()
	external_page.set("opening_visit",true)
	external_page.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	external_page.size=stage.size
	external_page.close_requested.connect(_close_shop)
	stage.add_child(external_page)
	var report:=Prep.report(str(OpeningFlow.state.departure.recipe))
	for item: Dictionary in report.rows:
		if item.missing>0:
			external_page.focus_item(item.sku)
			break
	external_page.show_opening_help()

func _close_shop() -> void:
	if is_instance_valid(external_page):
		external_page.queue_free()
		external_page=null
	if not OpeningFlow.state.departure.seed_heard: _start_conversation("merchant_seed",_after_seed)
	else: _show_preparation()

func _after_seed() -> void:
	if OpeningFlow.update_departure({"seed_heard":true}): _show_preparation()
	else: status.text=OpeningFlow.last_error

func _publish() -> void:
	if not OpeningFlow.replaying and not OpeningFlow.state.departure.seed_heard: return
	if not OpeningFlow.replaying and not Prep.publish(str(OpeningFlow.state.departure.recipe)):
		status.text=MenuCatalog.last_error
		_show_preparation()
		return
	if not OpeningFlow.update_departure({"node":"ready"}):
		status.text=OpeningFlow.last_error
		return
	preparation.queue_free()
	preparation=null
	_render()

func _history() -> void:
	if busy or OpeningTransition.busy: return
	if is_instance_valid(history_panel) or is_instance_valid(conversation) or is_instance_valid(external_page) or is_instance_valid(preparation): return
	_cancel_fast_forward()
	history_panel=preload("res://scripts/opening_history.gd").new()
	history_panel.entries=OpeningFlow.history_entries()
	for seen: Dictionary in OpeningFlow.state.departure.seen: history_panel.entries.append(seen.duplicate(true))
	history_panel.closed.connect(_close_history)
	stage.add_child(history_panel)

func _close_history() -> void:
	autoplay.reset()
	if is_instance_valid(history_panel): history_panel.queue_free()
	history_panel=null
	next_button.grab_focus()

func _input(event: InputEvent) -> void:
	if OpeningTransition.busy:
		_cancel_fast_forward()
		get_viewport().set_input_as_handled()
		return
	if busy:
		if event is InputEventKey and not event.echo and (event.keycode==KEY_SPACE or event.physical_keycode==KEY_SPACE):
			if event.pressed: fast_forward.press()
			else: _cancel_fast_forward()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or is_instance_valid(conversation) or is_instance_valid(external_page): return
	# Text entry owns Space, A/H shortcuts and IME keys; never interpret them as story input.
	if is_instance_valid(name_edit) and name_edit.has_focus() and not is_instance_valid(history_panel):
		_cancel_fast_forward()
		return
	var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if key not in [KEY_SPACE,KEY_ESCAPE,KEY_H,KEY_A]: return
	get_viewport().set_input_as_handled()
	if event.echo: return
	if key==KEY_SPACE:
		if is_instance_valid(history_panel) or is_instance_valid(preparation):
			_cancel_fast_forward()
		elif event.pressed: fast_forward.press()
		else:
			var tap: bool=fast_forward.release()
			_cancel_fast_forward()
			if tap: _advance()
		return
	if not event.pressed: return
	if is_instance_valid(history_panel):
		if key in [KEY_ESCAPE,KEY_H]: _close_history()
	elif key==KEY_ESCAPE: OpeningFlow.return_to_title()
	elif key==KEY_H: _history()
	elif key==KEY_A and not is_instance_valid(preparation): _toggle_auto()
	elif not is_instance_valid(preparation): _advance()
