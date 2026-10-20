extends Control
## Choosing a drink reads the published menu; only starting creates a cup snapshot.
signal close_requested
const PAPER = preload("res://assets/pixel_b/paper.svg")
const INK := Color("57391f")
const CREAM := Color("eed9b3")
var surface: Control
var list: VBoxContainer
var detail: VBoxContainer
var drink_image: TextureRect
var diy_preview: Control
var demand_hint: Label
var title: Label
var subtitle: Label
var status: Label
var start_button: Button
var resume_button: Button
var back_button: Button
var replacing_id := ""
var selected_id := ""
var buttons: Dictionary = {}
var guest: Dictionary = {}
var starting := false

func _ready() -> void:
	if is_instance_valid(GameSession.home) and not GameSession.home.guest_profile.is_empty():
		var profile: Dictionary=GameSession.home.guest_profile
		guest={"id":str(profile.id),"name":str(profile.name) if StoryDialogue.is_known(str(profile.id)) else "来客", "day":TimeManager.day,"visit":GameSession.home.guest_count}
	_build()
	resized.connect(_fit)
	_fit()
	MenuCatalog.changed.connect(_reload)
	_reload()

func _fit() -> void:
	var factor:=minf(size.x/1600.0,size.y/900.0)
	surface.scale=Vector2.ONE*factor
	surface.position=(size-Vector2(1600,900)*factor)*.5

func _style(color: Color) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=color
	style.border_color=Color("b38c56")
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(14)
	return style

func _label(parent: Node, value: String, px:=22, color:=INK) -> Label:
	var label:=Label.new()
	label.text=value
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_size_override("font_size",px)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, callback: Callable) -> Button:
	var button:=Button.new()
	button.text=value
	button.custom_minimum_size.y=52
	button.add_theme_font_size_override("font_size",22)
	button.add_theme_color_override("font_color",CREAM)
	button.add_theme_color_override("font_hover_color",Color("fff2d4"))
	button.add_theme_stylebox_override("normal",_style(Color("62462e")))
	button.add_theme_stylebox_override("hover",_style(Color("916b3e")))
	button.add_theme_stylebox_override("pressed",_style(Color("493321")))
	button.focus_mode=Control.FOCUS_NONE
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _place(control: Control, rect: Rect2) -> void:
	control.position=rect.position
	control.size=rect.size

func _paper(rect: Rect2) -> void:
	var paper:=TextureRect.new()
	paper.texture=PAPER
	paper.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(paper)
	_place(paper,rect)

func _scroll(rect: Rect2) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	surface.add_child(scroll)
	_place(scroll,rect)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	scroll.add_child(column)
	return column

func _build() -> void:
	surface=Control.new()
	surface.size=Vector2(1600,900)
	add_child(surface)
	var backdrop:=ColorRect.new()
	backdrop.color=Color("291c15")
	surface.add_child(backdrop)
	_place(backdrop,Rect2(0,0,1600,900))
	_paper(Rect2(50,100,510,680))
	_paper(Rect2(578,100,970,680))
	_place(_label(surface,"为%s选一杯" % guest.get("name","客人"),34,CREAM),Rect2(68,30,900,52))
	_place(_button(surface,"× 退出选酒",func(): close_requested.emit()),Rect2(1300,28,232,52))
	_place(_label(surface,"今 晚 的 酒 单",30),Rect2(85,132,420,50))
	_place(_label(surface,"从已上架酒款中选择",18),Rect2(85,189,420,28))
	demand_hint=_label(surface,"",18)
	_place(demand_hint,Rect2(85,222,430,100))
	list=_scroll(Rect2(82,330,436,333))
	_place(_button(surface,"管理营业酒单",_manage_menu),Rect2(86,699,430,52))
	title=_label(surface,"",36)
	_place(title,Rect2(628,131,660,60))
	subtitle=_label(surface,"",19)
	_place(subtitle,Rect2(630,197,638,36))
	drink_image=TextureRect.new()
	drink_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	drink_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drink_image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(drink_image)
	_place(drink_image,Rect2(1300,120,185,220))
	diy_preview=preload("res://scripts/workbench_drink_preview.gd").new()
	diy_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(diy_preview)
	_place(diy_preview,Rect2(1284,120,230,250))
	detail=_scroll(Rect2(630,264,632,450))
	status=_label(surface,"",19,CREAM)
	_place(status,Rect2(70,785,1470,36))
	back_button=_button(surface,"← 返回聊天  Esc",func(): close_requested.emit())
	_place(back_button,Rect2(70,832,250,54))
	resume_button=_button(surface,"继续桌上这一杯",_resume)
	_place(resume_button,Rect2(982,832,252,54))
	start_button=_button(surface,"开始制作  空格 →",_start)
	_place(start_button,Rect2(1252,832,295,54))

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _reload() -> void:
	var target: Dictionary=CustomerService.state.active.get("demand",{})
	demand_hint.text=""
	if PlayModes.mode=="mixing":
		demand_hint.text=str(CustomerService.state.active.get("free_order",{}).get("speech","")).replace("[b]","").replace("[/b]","")
	elif target.get("target") is Dictionary:
		var a: Dictionary=target.target
		var limits: Array=[]
		for rule: Dictionary in target.get("constraints",[]): limits.append(str(rule.get("label","")))
		demand_hint.text="本次口味：酒感 %s · 甜 %s · 酸 %s · 苦 %s\n要求：%s" % [str(a.alcohol_intensity),str(a.sweetness),str(a.sourness),str(a.bitterness),"、".join(limits) if not limits.is_empty() else "没有额外禁忌"]
	_clear(list)
	buttons.clear()
	var offered: Array=CustomerService.state.active.get("free_order",{}).get("menu",MenuCatalog.entries) if PlayModes.mode=="mixing" else MenuCatalog.entries
	for entry in offered:
		var recipe: Dictionary=MenuCatalog.get_recipe(str(entry.id))
		if recipe.is_empty(): continue
		var button:=_button(list,"%s    ·    %s 金币\n%s" % [recipe.name,str(entry.price),recipe.get("english_name","")],_select.bind(str(entry.id)))
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y=92
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		buttons[entry.id]=button
	if selected_id.is_empty() and OpeningFlow.first_service_pending() and guest.get("id")=="milo" and buttons.has("gin_and_tonic"): selected_id="gin_and_tonic"
	if not buttons.has(selected_id): selected_id=str(buttons.keys()[0]) if not buttons.is_empty() else ""
	_select(selected_id)

func _select(id: String) -> void:
	selected_id=id
	_clear(detail)
	for key in buttons: buttons[key].add_theme_stylebox_override("normal",_style(Color("996e3c") if key==id else Color("62462e")))
	var recipe: Dictionary=MenuCatalog.get_recipe(id)
	diy_preview.visible=recipe.get("source_kind","")=="diy"
	diy_preview.result=recipe.get("result",{}).duplicate(true)
	drink_image.visible=not diy_preview.visible
	if recipe.is_empty():
		title.text="酒单还空着"
		subtitle.text="先把想招待客人的酒加入营业酒单。"
		drink_image.texture=null
		_label(detail,"点击左下方「管理营业酒单」，选择已解锁酒款并保存；回来后就能选酒制作。",24)
	else:
		title.text=str(recipe.name)
		subtitle.text=str(recipe.get("english_name",""))+"  /  "+str(recipe.get("category",""))
		drink_image.texture=CocktailDatabase.get_image(id)
		var attributes:=GridContainer.new()
		attributes.columns=2
		attributes.add_theme_constant_override("h_separation",26)
		attributes.add_theme_constant_override("v_separation",10)
		detail.add_child(attributes)
		for field in [["酒感","alcohol_intensity"],["甜度","sweetness"],["酸度","sourness"],["苦度","bitterness"]]:
			_label(attributes,"%s   %s / 100" % [field[0],WorkbenchSession.format_amount(float(recipe[field[1]])) if recipe.has(field[1]) else "—"],23).custom_minimum_size.x=276
		_label(detail,"酒感是感受强度，不等于酒精度。",15)
		_label(detail,"口感："+" · ".join(recipe.get("mouthfeel_tags",[]))+"\n风味："+" · ".join(recipe.get("flavor_tags",[])),21)
		_label(detail,str(recipe.get("story","")),20)
		_label(detail,"制作："+str(recipe.get("preparation","自由调配")),21)
		_label(detail,"配方参考 · "+str(recipe.get("recipe_status","")),18)
		for row in recipe.get("ingredients",[]):
			var available: bool=MenuCatalog.ingredient_available(row)
			_label(detail,"%s   %s %s%s" % [row.name,WorkbenchSession.format_amount(float(row.amount)),str(row.unit),"" if available else "  · 库存不足"],19)
		_label(detail,"缺料可在工作台按 S 补货；仍可自由调整做法。",17)
	var session: Dictionary=WorkbenchSession.snapshot().session
	var pending: bool=not session.is_empty() and session.get("status")=="mixing" and not session.get("actions",[]).is_empty()
	resume_button.visible=pending
	replacing_id=str(session.id) if pending else ""
	start_button.text="收拾并制作新酒  空格" if pending else "开始制作  空格 →"
	start_button.disabled=recipe.is_empty() or not WorkbenchSession.writable
	status.text="选定后按空格开始制作，左上角会显示这款酒的配方。"
	if OpeningFlow.first_service_pending() and guest.get("id")=="milo": status.text="为米洛制作第一杯 · 建议选择刚练过的金汤力；完成后点击「交给客人」。"
	if PlayModes.mode=="mixing": status.text=str(CustomerService.state.active.get("free_order",{}).get("speech","请先准备营业酒单。" )).replace("[b]","").replace("[/b]","")
	if recipe.is_empty(): status.text="暂无上架酒款，请先保存一份营业酒单。"
	if pending: status.text="开工将收拾桌上的「%s」，制作新选的酒；已用原料不退回。也可继续原来这一杯。" % session.recipe.name
	if not WorkbenchSession.writable: status.text=WorkbenchSession.last_error

func _manage_menu() -> void:
	if has_meta("editor"): return
	# Reuse the existing editor as an overlay; saving and closing returns here.
	var editor: Control=preload("res://scenes/drink_menu.tscn").instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	editor.position=Vector2.ZERO
	editor.size=Vector2(1600,900)
	surface.add_child(editor)
	editor.mouse_filter=Control.MOUSE_FILTER_STOP
	set_meta("editor",editor)
	editor.close_requested.connect(func():
		editor.queue_free()
		remove_meta("editor")
		_reload()
	)

func _resume() -> void:
	Navigation.go_to(&"mixing")

func _start() -> void:
	if starting or start_button.disabled: return
	if not TimeManager.is_open or StoryDialogue.guest_id!=str(guest.get("id","")) or TimeManager.day!=int(guest.get("day",-1)) or not is_instance_valid(GameSession.home) or GameSession.home.guest_count!=int(guest.get("visit",-1)):
		status.text="当前接待已结束，请返回主页重新选择客人。"
		return
	starting=true
	var command_id:="select-recipe-%d" % Time.get_ticks_usec()
	var quote := CustomerService.prepare_order(selected_id)
	if quote.is_empty():
		starting = false
		status.text = CustomerService.last_error if not CustomerService.last_error.is_empty() else "客人已离店，或这桌已经结账。"
		return
	guest["visit_id"] = quote.visit_id
	var payload: Dictionary={"recipe_id":selected_id,"guest":guest}
	if not replacing_id.is_empty(): payload.replace_session_id=replacing_id
	if WorkbenchSession.command(command_id,"","select_recipe",payload):
		Navigation.go_to(&"mixing")
	else:
		status.text=WorkbenchSession.last_error
		starting=false

func _input(event: InputEvent) -> void:
	if has_meta("editor"):
		if event is InputEventKey and event.is_action_pressed("ui_cancel"):
			get_meta("editor")._unhandled_key_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE,KEY_ENTER] or event.physical_keycode==KEY_SPACE:
			get_viewport().set_input_as_handled()
			_start()
		elif event.keycode==KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_requested.emit()
