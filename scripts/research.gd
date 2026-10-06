extends Control
signal close_requested
const PAPER=preload("res://assets/codex/journal-paper-v1.png")
const Preview=preload("res://scripts/workbench_drink_preview.gd")
const Research=preload("res://scripts/research_data.gd")
const DESK=preload("res://assets/research/research-desk-v1.png")
const Hotspot=preload("res://scripts/research_desk_hotspot.gd")
const INK=Color("513921")
const MUTED=Color("806243")
var surface: Control
var body: Control
var balance: Label
var feedback: Label
var view:="entry"
var selected_id:=""
var base_id:=""
var desk: Control
var sheet: Control
var desk_hint: Label
var page_title: Label
var back_button: Button

func _ready() -> void:
	SaloonAudio.acquire_scene(self,"research")
	surface=Control.new()
	surface.size=Vector2(1600,900)
	add_child(surface)
	var background:=TextureRect.new()
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.texture=DESK
	background.size=surface.size
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(background)
	desk=Control.new()
	desk.size=surface.size
	desk.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(desk)
	sheet=Control.new()
	sheet.size=surface.size
	sheet.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(sheet)
	_paper(sheet,Rect2(75,130,1450,680))
	page_title=_label(sheet,Rect2(128,166,940,48),"",32)
	body=Control.new()
	body.position=Vector2(128,240)
	body.size=Vector2(1300,470)
	sheet.add_child(body)
	back_button=_button(surface,Rect2(42,30,220,48),"‹ 返回酒馆  Esc",_back)
	var badge:=Panel.new()
	badge.position=Vector2(1340,28)
	badge.size=Vector2(216,55)
	var badge_style:=StyleBoxFlat.new()
	badge_style.bg_color=Color("f1dfba")
	badge_style.border_color=Color("956d3b")
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(5)
	surface.add_child(badge)
	badge.add_theme_stylebox_override("panel",badge_style)
	balance=_label(badge,Rect2(16,8,185,38),"",24)
	var message_panel:=Panel.new()
	message_panel.position=Vector2(350,832)
	message_panel.size=Vector2(900,48)
	var message_style:=StyleBoxFlat.new()
	message_style.bg_color=Color(.12,.075,.035,.9)
	message_style.border_color=Color("9e7944")
	message_style.set_border_width_all(1)
	message_style.set_corner_radius_all(6)
	message_panel.add_theme_stylebox_override("panel",message_style)
	message_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(message_panel)
	feedback=_label(message_panel,Rect2(15,6,870,37),"",18,Color("f2e0bc"))
	feedback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	view=Navigation.research_view
	base_id=Navigation.research_base_id
	Navigation.research_base_id=""
	Navigation.research_view="entry"
	WorkbenchSession.changed.connect(_refresh)
	resized.connect(_fit)
	_fit()
	_refresh()

func _fit() -> void:
	var factor:=minf(size.x/1600,size.y/900)
	surface.scale=Vector2.ONE*factor
	surface.position=(size-surface.size*factor)*.5

func _paper(parent: Node, rect: Rect2) -> void:
	var paper:=TextureRect.new()
	paper.texture=PAPER
	paper.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper.position=rect.position
	paper.size=rect.size
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(paper)

func _label(parent: Node, rect: Rect2, text: String, px:=22, color:=INK) -> Label:
	var label:=Label.new()
	label.position=rect.position
	label.size=rect.size
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",px)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, rect: Rect2, text: String, callback: Callable) -> Button:
	var button:=Button.new()
	button.position=rect.position
	button.size=rect.size
	button.text=text
	button.focus_mode=Control.FOCUS_NONE
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size",22)
	button.add_theme_color_override("font_color",Color("f3e4c5"))
	for state_name in ["normal","hover","pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("735133") if state_name=="normal" else Color("936a42")
		style.border_color=Color("ba945c")
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state_name,style)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _back() -> void:
	if view!="entry": _show("entry")
	else: close_requested.emit()

func _show(next: String) -> void:
	view=next
	selected_id=""
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(body): return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for child in desk.get_children():
		desk.remove_child(child)
		child.queue_free()
	desk.visible=view=="entry"
	sheet.visible=view!="entry"
	back_button.text="‹ 返回酒馆  Esc" if view=="entry" else "‹ 返回研发书桌"
	page_title.text="我的配方" if view=="library" else "传说配方研习"
	balance.text="灵感  %d" % WorkbenchSession.research_state().inspiration
	feedback.text="研发使用仓库原料；没有销售收入。返回页面会保留桌上的半成品。"
	match view:
		"library": _library()
		"legendary": _legendary()
		_: _entry()

func _object(points: Array, callback: Callable, hint: String) -> void:
	var button:=Hotspot.new()
	button.size=surface.size
	button.outline=PackedVector2Array(points)
	button.pressed.connect(callback)
	button.mouse_entered.connect(func(): feedback.text=hint)
	button.focus_entered.connect(func(): feedback.text=hint)
	desk.add_child(button)

func _entry() -> void:
	feedback.text="点击笔记本开始试调，或翻阅传说手稿与配方盒。"
	_object([Vector2(139,395),Vector2(855,305),Vector2(985,723),Vector2(149,801)],func(): _begin("research_diy"),"自由 DIY · 先写目标用量，再调出你的味道。")
	_object([Vector2(980,210),Vector2(1410,235),Vector2(1410,460),Vector2(921,432)],func(): _show("legendary"),"传说研习 · 获得配方，再以完美出品掌握它。")
	_object([Vector2(1080,452),Vector2(1418,489),Vector2(1370,795),Vector2(1016,743)],func(): _show("library"),"我的配方 · 翻阅已保存的成品、用量与试调笔记。")
	var title:=_label(desk,Rect2(310,35,600,50),"研 发 书 桌",32,Color("ffedca"))
	title.add_theme_color_override("font_shadow_color",Color("201309"))
	title.add_theme_constant_override("shadow_offset_x",2)
	title.add_theme_constant_override("shadow_offset_y",2)
	var page:=Control.new()
	page.position=Vector2(590,396)
	page.rotation=-.09
	page.mouse_filter=Control.MOUSE_FILTER_IGNORE
	desk.add_child(page)
	_label(page,Rect2(5,0,270,45),"自由 DIY",34).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var source:=MenuCatalog.get_recipe(base_id)
	if source.is_empty(): source=WorkbenchSession.research_state().recipes.get(base_id,{})
	_label(page,Rect2(15,64,250,84),"从空白的一页开始\n调出属于你的味道。" if source.is_empty() else "以「%s」为起点\n调整配比，开始新的试调。" % str(source.name),21).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_label(page,Rect2(15,163,250,68),"目标用量随时可改\n首次取料消耗 1 点灵感",17,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_button(page,Rect2(5,243,270,51),"开始试调  ›",func(): _begin("research_diy"))
	if not base_id.is_empty():
		_button(desk,Rect2(600,758,285,38),"清空参考，从空白开始",func():
			base_id=""
			_refresh()
		)
	var legend:=Control.new()
	legend.position=Vector2(1061,264)
	legend.rotation=.065
	legend.mouse_filter=Control.MOUSE_FILTER_IGNORE
	desk.add_child(legend)
	_label(legend,Rect2(0,4,280,41),"传说研习",30).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_label(legend,Rect2(0,48,280,30),"翻阅特别的配方",18,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var library:=Control.new()
	library.position=Vector2(1082,602)
	library.rotation=.08
	library.mouse_filter=Control.MOUSE_FILTER_IGNORE
	desk.add_child(library)
	_label(library,Rect2(0,0,220,40),"我的配方",30).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_label(library,Rect2(0,42,220,28),"已收藏 %d 份试调" % WorkbenchSession.research_recipes().size(),18,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var session: Dictionary=WorkbenchSession.state.session
	if not session.is_empty() and session.status in ["mixing","finished"]:
		var resume:=_button(desk,Rect2(955,95,590,45),"继续桌上这一杯 · "+str(session.recipe.name),func(): Navigation.go_to(&"mixing"))
		resume.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS

func _resume_button() -> void:
	var s: Dictionary=WorkbenchSession.state.session
	if not s.is_empty() and s.status in ["mixing","finished"]:
		_button(body,Rect2(710,355,565,58),"继续桌上这一杯 · "+str(s.recipe.name),func(): Navigation.go_to(&"mixing"))
		_label(body,Rect2(710,418,570,40),"开始另一杯前，请先完成或明确丢弃半成品。",18,MUTED)

func _begin(mode: String, recipe_id: String="") -> void:
	var id:="research-begin-%d" % Time.get_ticks_usec()
	if WorkbenchSession.command(id,str(WorkbenchSession.state.session.get("id","")),"begin_research",{"mode":mode,"recipe_id":recipe_id,"base_recipe_id":base_id}):
		Navigation.go_to(&"mixing")
	else: feedback.text=WorkbenchSession.last_error

func _scroll(rect: Rect2) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.position=rect.position
	scroll.size=rect.size
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",12)
	scroll.add_child(rows)
	return rows

func _library() -> void:
	var records:=WorkbenchSession.research_recipes()
	if records.is_empty():
		_label(body,Rect2(25,40,1200,100),"这里还没有你的配方。\n先完成一次 DIY 试调，在结果页命名并保存。",27)
		_button(body,Rect2(25,190,430,60),"去试调第一杯",func(): _show("entry"))
		return
	if selected_id.is_empty(): selected_id=str(records.back().id)
	var rows:=_scroll(Rect2(5,0,350,465))
	for r in records:
		var button:=_button(rows,Rect2(0,0,330,70),str(r.name),func():
			selected_id=str(r.id)
			_refresh()
		)
		button.custom_minimum_size=Vector2(320,70)
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var record: Dictionary=WorkbenchSession.research_state().recipes.get(selected_id,{})
	if record.is_empty(): return
	var preview:=Preview.new()
	preview.position=Vector2(390,80)
	preview.size=Vector2(300,325)
	preview.result=record.result
	body.add_child(preview)
	_button(body,Rect2(390,412,300,46),"以此研发新的一杯",func():
		base_id=selected_id
		_show("entry")
	)
	var title:=_label(body,Rect2(390,5,890,46),str(record.name),28)
	title.autowrap_mode=TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var english:=_label(body,Rect2(390,48,890,30),str(record.english_name),18,MUTED)
	english.autowrap_mode=TextServer.AUTOWRAP_OFF
	english.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var details:=_scroll(Rect2(725,87,550,370))
	var text:="成品配方 · v%d\n" % int(record.version)
	for row in record.ingredients: text+="%s  %s %s\n" % [row.name,WorkbenchSession.format_amount(float(row.amount)),row.unit]
	text+="\n酒感 %d · 甜 %d · 酸 %d · 苦 %d\n" % [record.attributes.alcohol_intensity,record.attributes.sweetness,record.attributes.sourness,record.attributes.bitterness]
	for line in record.instructions: text+="\n"+str(line)
	if not record.notes.is_empty(): text+="\n\n复做笔记\n"+str(record.notes)
	var label:=Label.new()
	label.text=text
	label.custom_minimum_size=Vector2(515,0)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",21)
	label.add_theme_color_override("font_color",INK)
	details.add_child(label)
	feedback.text="已保存成品用量和试调笔记。当前可查阅配方，营业上架将在后续版本开放。"

func _legendary() -> void:
	var records: Array=Research.config().legendary_recipes
	var state:=WorkbenchSession.research_state()
	if records.is_empty():
		_label(body,Rect2(20,30,1100,100),"还没有收到特别的配方。",30)
		return
	var r: Dictionary=records[0]
	var acquired: bool=state.acquired.has(r.id)
	var mastered: bool=state.mastered.has(r.id)
	if not acquired:
		_label(body,Rect2(30,35,1050,55),"等一位客人留下他的酒单",32)
		_label(body,Rect2(30,125,1000,100),"有些配方藏在客人的故事里。\n收到那张旧纸后，再来这里试着调一杯。",24)
		_resume_button()
		return
	var preview:=Preview.new()
	preview.position=Vector2(0,5)
	preview.size=Vector2(325,420)
	var liquids: Dictionary={}
	for row: Dictionary in r.ingredients:
		if row.inventory_unit=="ml": liquids[row.sku_id]=row.inventory_amount
	preview.result={"cup":"highball","capacity_ml":350,"contents":{"contents":liquids,"ice":"cube","ice_batches":[{"kind":"cube","volume":100,"mass_g":100,"pieces":8}],"garnishes":["sku_cocktail_cherry"]}}
	body.add_child(preview)
	_label(body,Rect2(360,0,690,45),str(r.name),32)
	_label(body,Rect2(360,48,700,35),"已掌握 · 可加入营业酒单" if mastered else "小线赠予 · 等你调出旧日的味道",20,MUTED)
	var text:=""
	for row: Dictionary in r.ingredients:
		text+="%s  %s %s\n" % [row.name,WorkbenchSession.format_amount(float(row.amount)),"颗" if row.unit=="piece" else row.unit]
	text+="高球杯 · 方冰 100 g\n轻轻搅拌 3—6 秒，最后放上樱桃。"
	_label(body,Rect2(360,98,800,222),text,19)
	var badge:=Panel.new()
	badge.position=Vector2(360,322)
	badge.size=Vector2(795,52)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("4d3824")
	style.border_color=Color("dcba64")
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	badge.add_theme_stylebox_override("panel",style)
	body.add_child(badge)
	_label(badge,Rect2(18,8,760,37),"传说 · 未完待续     完美出品时呈现",22,Color("f0d387"))
	_button(body,Rect2(360,395,250,54),"再调一杯" if mastered else "按酒单开始研习",func(): _begin("research_legendary",str(r.id)))
	_button(body,Rect2(630,395,250,54),"查看旧酒单",func():
		var paper:=preload("res://scripts/memory_recipe_paper.gd").new()
		paper.allow_research_link=false
		add_child(paper))
	if mastered: _button(body,Rect2(900,395,255,54),"加入营业酒单",func(): Navigation.go_to(&"menu"))
	feedback.text="按原配方完美出品后掌握。研习照常消耗原料。" if not mastered else "配方已经记住，去酒单里选择上架即可。"

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		_back()
		get_viewport().set_input_as_handled()
