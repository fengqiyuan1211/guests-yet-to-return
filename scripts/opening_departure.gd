extends Control
## Post-tutorial story owns presentation; existing services own stock, money and menus.
const UI=preload("res://scripts/opening_ui.gd")
const Prep=preload("res://scripts/opening_preparation.gd")
const Conversation=preload("res://scripts/merchant_conversation.gd")
const PAPER=preload("res://assets/pixel_b/paper.svg")
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
	props=Control.new()
	props.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage.add_child(props)
	var chapter:=UI.panel(stage,Rect2(45,30,875,70))
	heading=UI.label(chapter,Rect2(25,12,825,46),"先把今晚的灯点起来",28)
	UI.button(stage,Rect2(1035,35,200,48),"历史对话 H",_history,true)
	UI.button(stage,Rect2(1260,35,290,48),"保存并返回开始",OpeningFlow.return_to_title,true)
	speed_hint=UI.panel(stage,Rect2(1220,95,320,44))
	speed_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	UI.label(speed_hint,Rect2(12,5,296,34),"快进中 ×3 · 松开恢复",21,Color("ffe7a7"))
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
	next_button.tooltip_text="短按空格或点击继续；长按空格 3 倍速，签收、购物、开门等操作仍需手动确认。"
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
	speaker.text=row.speaker
	dialogue.text=row.text
	dialogue.visible_characters=0
	clock=0
	status.text="回看 · 长按空格 3 倍速 · 不改变经营进度" if OpeningFlow.replaying else "点击/短按继续 · 长按空格 3 倍速 · H 历史"
	next_button.text=str(row.get("button","继续 · 空格"))
	next_button.disabled=false
	background.texture=preload("res://scripts/pixel_art.gd").texture("res://assets/art/saloon-day-unlit-v2.png" if row.background=="saloon" else "res://assets/art/opening/porch.png")
	background.material.set_shader_parameter("ocean",false)
	story_audio.present(row,self)
	_clear(props)
	hint_target=null
	tip.text=""
	_render_prop()
	if row.get("action")=="prepare": _show_preparation()

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
		if prop=="receipt": text="已收到：账册、旧酒单\n\n收件人签字："+("已签收" if OpeningFlow.state.departure.signed else "________________")
		UI.label(props,Rect2(590,302,420,195),text,24,Color("63482c"))
		if row.get("action")=="sign":
			hint_target=UI.button(props,Rect2(650,465,310,58),"点击签收",_advance)
			tip.text="↓  点击签收单，或按空格"
	elif prop=="water":
		var image:=preload("res://scripts/workbench_drink_preview.gd").new()
		image.reference_only=true
		image.result={"cup":"highball","capacity_ml":300,"contents":{"contents":{"drinking_water":170},"ice":"none","garnish":false},"liquid_profiles":{"drinking_water":{"version":"story-water-1","rgb":[237,247,255],"strength":0.0,"turbidity":0.0}}}
		image.position=Vector2(1010,205)
		image.size=Vector2(210,350)
		image.mouse_filter=Control.MOUSE_FILTER_IGNORE
		props.add_child(image)
		var caption:=UI.panel(props,Rect2(555,280,430,160))
		UI.label(caption,Rect2(25,25,380,100),"门口的椅子还在。\n给赶路的人，留一杯水。",28)
	elif prop=="sign":
		var opened: bool=OpeningFlow.state.departure.opened
		var paper:=_paper(Rect2(595,235,410,265))
		paper.rotation=.025
		var button:=UI.button(props,Rect2(635,285,330,135),"营 业 中" if opened else "准 备 中",_advance)
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
	var playback:=fast_forward.step(delta,_can_auto_advance())
	speed_hint.visible=fast_forward.active
	background.playback_speed=playback
	clock+=delta*34*playback
	dialogue.visible_characters=mini(int(clock),dialogue.text.length())
	if autoplay.tick(delta*playback,dialogue.text.length(),dialogue.visible_characters>=dialogue.text.length(),_can_auto_advance(),fast_forward.active): _advance()

func _cancel_fast_forward() -> void:
	fast_forward.cancel()
	if is_instance_valid(speed_hint): speed_hint.hide()
	if is_instance_valid(background): background.playback_speed=1.0

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT: _cancel_fast_forward()

func _can_auto_advance() -> bool:
	return not row.is_empty() and not busy and not next_button.disabled and str(row.get("action","")).is_empty() and not is_instance_valid(history_panel) and not is_instance_valid(external_page) and not is_instance_valid(conversation) and not is_instance_valid(preparation)

func _toggle_auto() -> void:
	auto_button.text="自动播放：开 A" if autoplay.toggle() else "自动播放：关 A"
	next_button.grab_focus()

func _advance() -> void:
	autoplay.reset()
	if busy or next_button.disabled or row.is_empty() or is_instance_valid(history_panel) or is_instance_valid(conversation) or is_instance_valid(external_page) or is_instance_valid(preparation): return
	if dialogue.visible_characters>=0 and dialogue.visible_characters<dialogue.text.length():
		clock=dialogue.text.length()
		dialogue.visible_characters=-1
		return
	var patch: Dictionary={}
	match str(row.get("action","")):
		"sign": patch.signed=true
		"water": patch.water=true
		"open":
			if not OpeningFlow.replaying and not Prep.ready_menu():
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
	if OpeningFlow.update_departure(patch): _render()
	else: status.text=OpeningFlow.last_error

func _show_preparation() -> void:
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
	var art:=TextureRect.new()
	art.texture=preload("res://scripts/pixel_art.gd").sprite("harbor_merchant")
	art.position=Vector2(50,95)
	art.size=Vector2(640,790)
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.add_child(art)
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
	if not event is InputEventKey or is_instance_valid(conversation) or is_instance_valid(external_page): return
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
