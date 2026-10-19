extends Control
signal close_requested
const ToolHelp=preload("res://scripts/workbench_tool_help.gd")
const ToolButton=preload("res://scripts/workbench_tool_button.gd")
const Evaluation=preload("res://scripts/workbench_evaluation.gd")
const ResultCard = preload("res://scripts/workbench_result_card.gd")
const WorkbenchAudio = preload("res://scripts/workbench_audio.gd")
const Table = preload("res://scripts/workbench_table.gd")
const Art = preload("res://scripts/workbench_art.gd")
const GarnishPreview = preload("res://scripts/workbench_garnish_preview.gd")
const IcePreview = preload("res://scripts/workbench_ice_preview.gd")
const Measure = preload("res://scripts/workbench_measure.gd")
const DraftPanel=preload("res://scripts/research_draft_panel.gd")
const PAPER = preload("res://assets/pixel_b/paper.svg")
const INK := Color("573c28")
const CREAM := Color("efdab3")
var surface: Control
var table: Control
var note: RichTextLabel
var recipe_panel: Control
var draft_panel: Control
var recipe_title: Label
var recipe_subtitle: Label
var status_label: Label
var duration_label: Label
var technique_panel: Panel
var technique_title: Label
var technique_detail: Label
var technique_progress: ProgressBar
var guidance_rule: Dictionary={}
var guidance_trace: Dictionary={}
var evaluation_model:=Evaluation.config()
var footer: Label
var context: Control
var pantry: Control
var pantry_items: Control
var pantry_scroll: ScrollContainer
var pantry_empty: Label
var category_buttons: Array[Button] = []
var item_buttons: Dictionary = {}
var stock_labels: Dictionary = {}
var gold_label: Label
var external_page: Control
var modal: Control
var measure: Control
var selected := ""
var serve_armed := false
var technique := "shake"
var category := "基酒"
var pending_item := ""
var data: Dictionary = {}
var counter := 0
var dose_overrides: Dictionary = {}
var measure_waiting := false
var pending_confirm := Callable()
var modal_close := Callable()
var feedback_panel: Panel
var feedback_text: Label
var restock_button: Button
var restock_material:=""
var next_hint: Label
var sfx: Node

func _ready() -> void:
	SaloonAudio.acquire_workbench(self)
	sfx=WorkbenchAudio.new()
	add_child(sfx)
	surface=Control.new()
	surface.size=Vector2(1600,900)
	add_child(surface)
	table=Table.new()
	table.size=surface.size
	surface.add_child(table)
	table.item_grabbed.connect(func(id: String): SaloonAudio.ui.item(str(data.get("cup","highball")) if id=="glass" else id))
	table.vessel_selected.connect(_select)
	table.prop_selected.connect(_prop)
	table.transfer_requested.connect(_transfer_vessel)
	table.motion_completed.connect(_motion)
	table.muddle_contact.connect(func(pressure: float): sfx.muddle(pressure))
	table.spoon_remove_requested.connect(func(): _act("spoon",{"target":""}))
	table.item_dropped.connect(_dropped)
	table.serve_requested.connect(_finish)
	table.empty_requested.connect(_empty_vessel)
	_build()
	resized.connect(_fit)
	_fit()
	WorkbenchSession.changed.connect(_refresh)
	SlotWallet.balance_changed.connect(func(_value): _update_stock_ui())
	if WorkbenchSession.state.session.is_empty() or WorkbenchSession.state.session.get("status")=="discarded": _issue("start")
	var active: Dictionary=WorkbenchSession.state.session
	if active.get("status")=="mixing" and active.get("liquid_profiles",{})!=preload("res://scripts/workbench_liquid_appearance.gd").profiles(): _issue("refresh_appearance")
	_refresh()
	if data.get("status")=="finished": _result()
	if WorkbenchSession.tutorial_active:
		var guide=preload("res://scripts/opening_tutorial.gd").new()
		guide.bench=self
		surface.add_child(guide)

func _fit() -> void:
	var factor := minf(size.x/1600.0,size.y/900.0)
	surface.scale = Vector2.ONE*factor
	surface.position = (size-Vector2(1600,900)*factor)*.5

func _style(fill: Color, border := Color("916c43")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	box.set_content_margin_all(10)
	return box

func _panel(parent: Node, rect: Rect2, color: Color) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel",_style(color))
	parent.add_child(p)
	return p

func _text(parent: Node, rect: Rect2, value: String, px := 22, color := CREAM) -> Label:
	var l := Label.new()
	l.position = rect.position
	l.size = rect.size
	l.text = value
	l.add_theme_font_size_override("font_size",px)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _button(parent: Node, rect: Rect2, value: String, callback: Callable, primary := false) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.text = value
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size",21)
	b.add_theme_stylebox_override("normal",_style(Color("876037") if primary else Color("403128")))
	b.add_theme_stylebox_override("hover",_style(Color("9b7446") if primary else Color("65503a"),Color("dfb777")))
	b.add_theme_stylebox_override("pressed",_style(Color("34291f")))
	b.add_theme_color_override("font_color",CREAM)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _paper(parent: Node, rect: Rect2) -> TextureRect:
	var paper := TextureRect.new()
	paper.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper.texture=PAPER
	paper.position=rect.position
	paper.size=rect.size
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(paper)
	return paper

func _build() -> void:
	recipe_panel=Control.new()
	recipe_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(recipe_panel)
	_paper(recipe_panel,Rect2(22,22,300,388))
	recipe_title=_text(recipe_panel,Rect2(46,39,254,36),"试调配方",27,INK)
	recipe_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	recipe_subtitle=_text(recipe_panel,Rect2(46,79,254,28),"",15,INK)
	recipe_subtitle.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var recipe_scroll:=ScrollContainer.new()
	recipe_scroll.position=Vector2(46,114)
	recipe_scroll.size=Vector2(258,248)
	recipe_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	recipe_panel.add_child(recipe_scroll)
	note=RichTextLabel.new()
	note.bbcode_enabled=true
	note.fit_content=true
	note.scroll_active=false
	note.add_theme_font_override("normal_font",preload("res://assets/fonts/NotoSerifSC.ttf"))
	var adjustment_font:=SystemFont.new()
	adjustment_font.font_names=PackedStringArray(["PingFang SC","Microsoft YaHei","Noto Sans CJK SC"])
	adjustment_font.font_weight=600
	note.add_theme_font_override("bold_font",adjustment_font)
	note.add_theme_font_size_override("normal_font_size",17)
	note.add_theme_color_override("default_color",INK)
	recipe_scroll.add_child(note)
	note.custom_minimum_size.x=236
	note.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_text(recipe_panel,Rect2(46,370,254,25),"滚动查看用料差异与步骤",14,INK)
	draft_panel=DraftPanel.new()
	draft_panel.position=Vector2(22,80)
	surface.add_child(draft_panel)
	draft_panel.edit_requested.connect(_edit_draft)
	draft_panel.add_requested.connect(_draft_picker)
	draft_panel.hide()
	pantry=_panel(surface,Rect2(1260,18,322,864),Color("382619"))
	_paper(pantry,Rect2(10,10,302,844))
	_text(pantry,Rect2(32,30,260,52),"备 料 柜",34,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for i in range(6):
		var name: String=["基酒","配料","装饰","杯子","冰块","器具"][i]
		var b:=_button(pantry,Rect2(21+(i%3)*94,106+(i/3)*47,92,44),name,_show_category.bind(name))
		b.add_theme_color_override("font_color",INK)
		category_buttons.append(b)
	pantry_scroll=ScrollContainer.new()
	pantry_scroll.position=Vector2(20,217)
	pantry_scroll.size=Vector2(282,510)
	pantry_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	pantry.add_child(pantry_scroll)
	pantry_items=Control.new()
	pantry_items.custom_minimum_size=Vector2(268,510)
	pantry_scroll.add_child(pantry_items)
	pantry_empty=_text(pantry,Rect2(30,270,260,110),"这一类还没有库存\n按 S 去商店补货",21,INK)
	pantry_empty.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_text(pantry,Rect2(27,758,273,47),"拖到杯子或制作容器\n空格停下 · 拖回收起",17,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	context=_panel(surface,Rect2(340,780,895,108),Color("f3e2c2"))
	context.mouse_filter=Control.MOUSE_FILTER_IGNORE
	status_label=_text(context,Rect2(16,76,863,27),"",19,INK)
	technique_panel=_panel(surface,Rect2(350,78,690,127),Color("f3e2c2"))
	technique_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	technique_title=_text(technique_panel,Rect2(15,8,660,32),"",23,INK)
	technique_detail=_text(technique_panel,Rect2(15,42,660,50),"",18,INK)
	technique_progress=ProgressBar.new()
	technique_progress.position=Vector2(15,105)
	technique_progress.size=Vector2(660,24)
	technique_progress.scale.y=.35
	technique_progress.show_percentage=false
	technique_progress.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for key in ["background","fill"]:
		var bar:=StyleBoxFlat.new()
		bar.bg_color=Color("d8c8a9") if key=="background" else Color("b4924f")
		bar.set_content_margin_all(0)
		bar.set_corner_radius_all(0)
		technique_progress.add_theme_stylebox_override(key,bar)
	technique_panel.add_child(technique_progress)
	var footer_panel:=_panel(surface,Rect2(22,817,300,71),Color("f3e2c2"))
	footer_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	footer=_text(footer_panel,Rect2(14,7,274,27),"Esc 返回 · 半成品自动保留",16,INK)
	duration_label=_text(footer_panel,Rect2(14,37,274,26),"",18,INK)
	_button(surface,Rect2(342,22,145,38),"返回 Esc",_leave)
	_button(surface,Rect2(497,22,130,38),"记录 R",_log)
	_button(surface,Rect2(637,22,130,38),"重做 N",_restart)
	_button(surface,Rect2(777,22,120,38),"跳过教学" if WorkbenchSession.tutorial_active else "仓库 B",_skip_tutorial if WorkbenchSession.tutorial_active else _open_storage.bind("backpack"))
	_button(surface,Rect2(907,22,140,38),"教学说明" if WorkbenchSession.tutorial_active else "商店 S",_tutorial_help if WorkbenchSession.tutorial_active else _open_storage.bind("shop"))
	gold_label=_text(surface,Rect2(1060,26,190,30),"",20)
	next_hint=_text(context,Rect2(16,6,863,65),"",23,Color("352416"))
	next_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback_panel=_panel(surface,Rect2(350,200,690,80),Color("f3e2c2"))
	feedback_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	feedback_text=_text(feedback_panel,Rect2(15,8,660,64),"",21,INK)
	feedback_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	restock_button=_button(feedback_panel,Rect2(510,18,165,44),"去商店补货",_open_restock)
	restock_button.hide()
	feedback_panel.hide()
	_show_category("基酒")

func _show_category(value: String) -> void:
	category=value
	for i in range(category_buttons.size()):
		var b: Button=category_buttons[i]
		var chosen: bool=b.text==value
		b.add_theme_stylebox_override("normal",_style(Color(.77,.58,.29,.35) if chosen else Color(0,0,0,0),Color("ab844d")))
	for child in pantry_items.get_children():
		child.hide()
		child.queue_free()
	item_buttons.clear()
	stock_labels.clear()
	var items: Array=WorkbenchSession.pantry_items(value)
	pantry_empty.visible=items.is_empty()
	pantry_items.custom_minimum_size=Vector2(268,maxi(510,ceili(items.size()/2.0)*185))
	pantry_scroll.scroll_vertical=0
	for i in range(items.size()):
		var id: String=items[i][0]
		var label: String=items[i][1]
		var b:=_button(pantry_items,Rect2((i%2)*136,(i/2)*185,132,181),"",func(): pass)
		b.set_meta("custom_audio",true)
		b.gui_input.connect(_pantry_input.bind(value,id))
		b.add_theme_stylebox_override("normal",_style(Color(0,0,0,0),Color(.45,.32,.17,.25)))
		b.add_theme_stylebox_override("hover",_style(Color(.89,.74,.44,.3),Color("b38d45")))
		var art: Control
		if id in ["cube","crushed"]:
			art=IcePreview.new()
			art.kind=id
		elif WorkbenchSession.GARNISHES.has(id) or id in ["sku_mint_leaf","sku_white_cane_sugar"]:
			art=GarnishPreview.new()
			art.kind=id
		else:
			var texture:=TextureRect.new()
			texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture.texture=Art.texture(id)
			art=texture
		art.position=Vector2(22,8)
		art.size=Vector2(88,98)
		art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
		var title:=_text(b,Rect2(6,108,120,47),label,16,INK)
		title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		title.max_lines_visible=2
		title.clip_text=true
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		if value=="器具":
			b.set_script(ToolButton)
			b.tooltip_text=ToolHelp.description(id)
		title.add_theme_font_size_override("font_size",14 if label.length()>8 else 17)
		if WorkbenchSession.MATERIALS.has(id) or WorkbenchSession.GARNISHES.has(id) or WorkbenchSession.SOLIDS.has(id):
			var quantity_label:=_text(b,Rect2(6,157,120,22),"",14,INK)
			quantity_label.clip_text=true
			quantity_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			stock_labels[id]=quantity_label
		if value=="冰块":
			title.text="方冰 · 4 块\n每份 50 g" if id=="cube" else "碎冰 · 1 铲\n每份 50 g"
			title.add_theme_font_size_override("font_size",16)
			title.size.y=48
		item_buttons[id]=b
	_update_stock_ui()

func _update_stock_ui() -> void:
	if not is_instance_valid(pantry_items): return
	var available: Array=[]
	for entry in WorkbenchSession.pantry_items(category): available.append(entry[0])
	if available!=item_buttons.keys():
		var previous_scroll:=pantry_scroll.scroll_vertical
		_show_category(category)
		pantry_scroll.set_deferred("scroll_vertical",previous_scroll)
		return
	if not restock_material.is_empty() and WorkbenchSession.remaining(restock_material)>=1 and is_instance_valid(restock_button):
		restock_button.hide()
		feedback_text.size.x=660
		feedback_text.text="%s已补货，可以继续制作。" % _material_info(restock_material).name
		restock_material=""
	if is_instance_valid(gold_label): gold_label.text="教学包 · 不扣仓库" if WorkbenchSession.tutorial_active else "金币 %d" % SlotWallet.balance
	for id in stock_labels:
		var left: float=WorkbenchSession.remaining(id)
		var unit: String=WorkbenchSession.GARNISHES[id].unit if WorkbenchSession.GARNISHES.has(id) else (WorkbenchSession.SOLIDS[id].unit if WorkbenchSession.SOLIDS.has(id) else "ml")
		stock_labels[id].text=("%s %s" % [str(int(left)) if is_equal_approx(left,round(left)) else "%.1f" % left,unit]) if left>0 else "缺货 · S 补货"
		item_buttons[id].modulate=Color.WHITE if left>0 else Color(.7,.7,.7)

func _open_storage(route: String) -> void:
	if WorkbenchSession.tutorial_active:
		_tutorial_help()
		return
	if is_instance_valid(external_page): return
	_clear_modal()
	table.stop_gesture()
	table.cancel_carry()
	table.input_enabled=false
	var paths: Dictionary={"shop":"res://scenes/harbor_shop.tscn","backpack":"res://scenes/backpack.tscn"}
	external_page=load(paths[route]).instantiate()
	external_page.set_anchors_preset(Control.PRESET_TOP_LEFT)
	external_page.size=Vector2(1600,900)
	external_page.close_requested.connect(func():
		external_page.hide()
		external_page.queue_free()
		external_page=null
		table.input_enabled=true
		_refresh()
	)
	surface.add_child(external_page)

func _process(delta: float) -> void:
	_update_technique_hint()
	if is_instance_valid(feedback_panel): feedback_panel.position.y=214 if technique_panel.visible else 78
	if is_instance_valid(measure):
		if measure_waiting and table.pour_blend>.95:
			measure_waiting=false
			measure.set_process(true)
		table.preview_amount=measure.progress*measure.volume_limit()

	if is_instance_valid(external_page) or (is_instance_valid(modal) and not is_instance_valid(measure)):
		sfx.silence()
		return
	var direct_pour: bool=table.pouring and table.pour_blend>.94 and is_instance_valid(measure) and measure.active and measure.is_processing()
	var transfer_pour: bool=not table.animated_source.is_empty() and table.animation_progress>.24 and table.animation_progress<.72
	if not table.dragging or table.technique!="muddle": sfx.stop_muddle()
	var motion: String=table.technique if table.motion_is_active() else ""
	sfx.drive(delta,direct_pour or transfer_pour,motion,table.motion_energy)

func _pantry_input(event: InputEvent, tab: String, id: String) -> void:
	if is_instance_valid(modal): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		table.begin_item_drag(tab,id,table.get_global_transform_with_canvas().affine_inverse()*item_buttons[id].get_global_transform_with_canvas()*event.position)

func _place_material(id: String) -> bool:
	if WorkbenchSession.remaining(id)<.1:
		_notify_empty(id)
		return false
	var items: Array = WorkbenchSession.state.get("table_materials",[]).duplicate()
	var replaced: String=str(items[0]) if items.size()==5 and not items.has(id) else ""
	if not WorkbenchSession.place_table_material(id):
		status_label.text=WorkbenchSession.last_error
		return false
	table.bottle=id
	if not replaced.is_empty():
		feedback_panel.show()
		restock_button.hide()
		feedback_text.size.x=660
		feedback_text.text="已收起%s，拿出%s。" % [WorkbenchSession.MATERIALS[replaced].name,WorkbenchSession.MATERIALS[id].name]
	return true

func _dropped(tab: String, id: String, target: String, dragged: bool) -> void:
	if data.get("status")!="mixing" or is_instance_valid(modal): return
	if not dragged:
		if tab=="器具" and id in ["lid","cap"]: _prop(id)
		else: _choose_item("基酒" if tab=="材料" else tab,id)
		return
	if WorkbenchSession.MATERIALS.has(id):
		if target=="pantry":
			var items: Array = WorkbenchSession.state.get("table_materials",[]).duplicate()
			items.erase(id)
			if WorkbenchSession.set_table_materials(items):
				if table.bottle==id: table.bottle=""
				selected=""
				_rebuild_context()
				status_label.text="材料已收起，杯中已取用的酒液保留。"
			else: status_label.text=WorkbenchSession.last_error
		elif target in Table.POS:
			_begin_measure(id,_measure_target(id),target)
		elif target.is_empty() or target.begins_with("bottle:"):
			_choose_item("基酒",id)
		else:
			status_label.text="请拖到成品杯、量酒器或打开的制作容器。"
		return
	if WorkbenchSession.SOLIDS.has(id) and target in ["shaker","mixing","glass"]:
		_act("add_solid",{"material":id,"vessel":target})
	elif tab=="冰块" and target in ["shaker","mixing","glass"]:
		_act("ice",{"vessel":target,"ice":id})
	elif tab=="装饰" and target=="glass": _act("garnish",{"material":id})
	elif tab=="杯子" and target=="glass": _choose_item(tab,id)
	elif tab=="器具":
		if id in ["lid","cap"] and target in ["shaker","lid","cap"]:
			if not data.lid: _act("lid")
		elif id in ["spoon","muddler"] and target in ["shaker","mixing","glass"]:
			_select(target)
			_set_technique("stir" if id=="spoon" else "muddle")
		elif id=="strainer" and target in ["shaker","mixing"]:
			_act("filter",{"source":target,"vessel":"glass"})
		else: status_label.text="将器具拖到对应容器上。"
	else: status_label.text="这个位置无法放置，物品已归位。"

func _choose_item(tab: String, id: String) -> void:
	if data.get("status")!="mixing" or not WorkbenchSession.writable:
		status_label.text="这杯已结束，请另起一杯。"
		return
	table.stop_gesture()
	pending_item=""
	if WorkbenchSession.SOLIDS.has(id):
		pending_item=id
		status_label.text="%s：拖入容器加入 1 %s。" % [WorkbenchSession.SOLIDS[id].name,WorkbenchSession.SOLIDS[id].unit]
	elif tab in ["基酒","配料"]:
		if not _place_material(id): return
		selected="bottle"
		table.selected="bottle"
		_rebuild_context()
		status_label.text=WorkbenchSession.MATERIALS[id].name+"已放到桌上，拖到杯子或制作容器开始倒入。"
	elif tab in ["冰块","装饰"]:
		pending_item=id
		status_label.text="已取用%s，点击桌上%s。" % [WorkbenchSession.GARNISHES[id].name if WorkbenchSession.GARNISHES.has(id) else "冰块","成品杯放置" if WorkbenchSession.GARNISHES.has(id) else "容器加入"]
	elif tab=="杯子":
		_act("cup",{"cup":id})
		_select("glass")
	else:
		if Table.POS.has(id): _select(id)
		else: _prop(id)
	table.queue_redraw()

func _issue(kind: String, payload: Dictionary={}) -> bool:
	counter+=1
	var id:="%d-%d-%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec(),counter]
	var before:=data.duplicate(true)
	var success:=WorkbenchSession.command(id,str(WorkbenchSession.state.session.get("id","")),kind,payload)
	if success: _addition_feedback(kind,payload,before)
	elif kind in ["withdraw","garnish","add_solid"] and payload.has("material") and WorkbenchSession.remaining(payload.material)<(.1 if WorkbenchSession.MATERIALS.has(payload.material) else 1): _notify_empty(payload.material)
	return success

func _transfer_vessel(source: String, destination: String) -> void:
	var payload: Dictionary={"source":source,"vessel":destination}
	if source=="shaker" and destination in ["glass","mixing","jigger"] and data.get("lid",false):
		# The three-piece shaker pours through its built-in strainer after uncapping.
		payload.integrated_strainer=true
		_act("filter",payload)
	else:
		_act("transfer",payload)

func _act(kind: String,payload: Dictionary={}) -> void:
	table.stop_gesture()
	if kind=="filter": table.mixing_pour_offset=Vector2.ZERO
	if not _issue(kind,payload):
		status_label.text=WorkbenchSession.last_error
	else:
		if kind=="ice": SaloonAudio.ui.item(str(payload.get("ice","cube")))
		elif kind=="cup": SaloonAudio.ui.item(str(payload.get("cup","highball")))
		elif kind in ["spoon","lid"]: SaloonAudio.ui.item(kind)
		elif kind in ["add_solid","garnish"]: SaloonAudio.ui.item(str(payload.get("material","")))
		if kind=="spoon" and data.get("spoon_vessel","").is_empty():
			technique="shake"
			table.technique=technique
		if kind in ["transfer","filter"]:
			table.animated_source=payload.get("source","")
			table.animation_progress=0
			table.animated_destination=payload.get("vessel","")
			if table.animated_source=="shaker": table.begin_shaker_pour()
		status_label.text={"spoon":"吧勺已收回。" if data.get("spoon_vessel","").is_empty() else "吧勺已插入。","transfer":"已倒入能容纳的部分，余量保留在原容器。","filter":"已过滤入杯，剩余酒液、冰和固体留在源容器。","ice":"已加冰 %s g；容器累计 %s g。" % [WorkbenchSession.format_amount(WorkbenchSession.ICE_PORTION_G),WorkbenchSession.format_amount(WorkbenchSession.ice_mass(data.vessels[payload.get("vessel","glass")]))],"lid":"摇壶已盖好。" if data.get("lid",false) else "摇壶已打开。","garnish":"第 %d 份装饰已放好。" % WorkbenchSession.garnishes(data.vessels.glass).size(),"cup":"杯型已更换 · 容量 %s ml。" % WorkbenchSession.format_amount(WorkbenchSession.capacity(data,"glass")),"add_solid":"已加入 1 份配料，并扣除对应库存。"}.get(kind,"已保存。")
		_rebuild_context()

func _refresh() -> void:
	data=WorkbenchSession.snapshot().session
	table.set_materials(WorkbenchSession.state.get("table_materials",[]))
	table.apply_snapshot(data)
	table.queue_redraw()
	var recipe: Dictionary=data.get("recipe",WorkbenchSession.RECIPE)
	recipe_title.text=str(recipe.name)
	recipe_title.tooltip_text=str(recipe.name)
	recipe_subtitle.text=str(recipe.english_name)+" · 配方参考"
	note.text=preload("res://scripts/workbench_notes.gd").text_for(data,WorkbenchSession)
	if data.get("mode")=="research_diy":
		recipe_title.text="自由 DIY · 制作笔记"
		recipe_subtitle.text="灵感 %d · %s" % [WorkbenchSession.research_state().inspiration,"本杯已扣 1 点" if data.get("inspiration_charged",false) else "首次取料扣 1 点"]
		note.text=WorkbenchSession.research_note(data)
	elif data.get("mode")=="research_legendary": recipe_subtitle.text="传说研习 · 完美制作后掌握"
	var diy: bool=data.get("mode")=="research_diy"
	recipe_panel.visible=not diy
	draft_panel.visible=diy
	if diy: draft_panel.apply_snapshot(data)
	technique_panel.position.x=450 if diy else 350
	feedback_panel.position.x=450 if diy else 350
	guidance_rule=evaluation_model.rules.get(str(recipe.get("id","")),{}).duplicate(true)
	if guidance_rule.get("mix")!=technique:
		guidance_rule.mix=technique
		guidance_rule.time_window=[6,10] if technique=="shake" else [4,8]
	guidance_trace=Evaluation.replay(data.get("actions",[]),guidance_rule,WorkbenchSession.MATERIALS,selected if selected in Table.POS else "glass")
	var duration:=0.0
	for action in data.get("actions",[]):
		if action.kind==technique: duration+=float(action.payload.get("seconds",0))
	duration_label.text=("%s %.1f 秒" % [{"shake":"摇和","stir":"搅拌","muddle":"轻压"}[technique],duration]) if duration>0 else ""
	if not WorkbenchSession.last_error.is_empty(): status_label.text=WorkbenchSession.last_error
	elif data.get("status")=="finished": status_label.text="试作完成。可查看结果，或另起一杯。"
	elif status_label.text.is_empty(): status_label.text="拖动材料到杯子或制作容器，按空格停止倒入。"
	_rebuild_context()
	_update_stock_ui()

func _rebuild_context() -> void:
	if not is_instance_valid(next_hint): return
	if data.is_empty(): return
	if data.get("status")=="finished":
		next_hint.text="这杯已完成 · 空格查看结果 · N 另起一杯"
		return
	if selected==data.get("spoon_vessel","") and not selected.is_empty():
		next_hint.text="吧勺已插在%s里 · 按住杯口或勺柄移动鼠标控制转速\n松手暂停，勺子留在杯中；单击露出的勺柄收回。" % Table.NAMES[selected]
		return
	var vessels: Dictionary=data.vessels
	var glass_amount:=WorkbenchSession.amount(vessels.glass)
	var jigger_amount:=WorkbenchSession.amount(vessels.jigger)
	var shaker_amount:=WorkbenchSession.amount(vessels.shaker)
	var mixing_amount:=WorkbenchSession.amount(vessels.mixing)
	if selected=="bottle" and not table.bottle.is_empty():
		var ml: float=_measure_target(table.bottle)
		next_hint.text="%s · 量酒器目标 %s ml · 滚轮调剂量
拖到量酒器按刻度取量；直接拖入杯中则凭感觉倒入" % [WorkbenchSession.MATERIALS[table.bottle].name,WorkbenchSession.format_amount(ml)]
		if data.get("mode")=="research_diy":
			next_hint.text=("目标已达 · 可在左上角增加目标，或直接倒入杯中自由加料" if ml<=0 else "%s · 本次量取目标 %s ml\n在左上角编辑总用量；量酒器红线随剩余用量更新。" % [WorkbenchSession.MATERIALS[table.bottle].name,WorkbenchSession.format_amount(ml)])
		if float(data.recipe.ingredients.get(table.bottle,0))>60: next_hint.text+=" · 按配方分次加入"
	elif selected=="glass" and glass_amount>0:
		var waste:=jigger_amount+shaker_amount+mixing_amount
		next_hint.text="成品杯 %s ml · 冰 %s g · 装饰 %d 份 · 容量 %s ml\n继续加冰／装饰 · 空格或拖杯脚出杯" % [WorkbenchSession.format_amount(glass_amount),WorkbenchSession.format_amount(WorkbenchSession.ice_mass(vessels.glass)),WorkbenchSession.garnishes(vessels.glass).size(),WorkbenchSession.format_amount(WorkbenchSession.capacity(data,"glass"))]
		if waste>0: next_hint.text+=" · 另有 %s ml 将弃置。" % WorkbenchSession.format_amount(waste)
	elif selected=="jigger" and jigger_amount>0:
		next_hint.text="量酒器已有 %s ml · 拖到摇壶、搅拌杯或成品杯，松手倒入" % WorkbenchSession.format_amount(jigger_amount)
	elif selected=="shaker":
		next_hint.text="壶盖已合上 · 任意方向快速来回摇 · 拖到成品杯松手倒酒\n倒酒时自动取下小顶盖，冰留在摇壶内；空格可打开壶盖" if data.lid else "将材料和冰拖入摇壶 · 空格或拖盖子合盖\n拖摇壶到成品杯倒入；也可从器具菜单拖滤冰器到壶上过滤"
	elif selected=="mixing":
		next_hint.text="将材料拖入搅拌杯 · 从器具菜单拖吧勺到杯口，按住移动控制转速 · 拖杯身下部直倒，或拖滤冰器到杯上过滤"
	elif jigger_amount>0:
		next_hint.text="下一步：量酒器已有 %s ml，拖到要接酒的容器。" % WorkbenchSession.format_amount(jigger_amount)
	elif glass_amount>0:
		next_hint.text="杯中已有 %s ml · 可以继续直倒、加冰或装饰 · 点成品杯后空格出杯" % WorkbenchSession.format_amount(glass_amount)
	elif shaker_amount>0:
		next_hint.text="下一步：摇壶加冰、合盖，再拿起前后摇和。"
	elif mixing_amount>0:
		next_hint.text="下一步：把吧勺拖到搅拌杯，按住杯口移动鼠标控制自动搅拌。"
	else:
		next_hint.text="从右侧拖材料到杯子或制作容器 · 空格停止倒入
右上角是成品杯，点击菜单杯型即可替换；已有酒液会保留。"

func _select(id: String) -> void:
	serve_armed=id=="glass"
	selected=id
	table.selected=id
	if data.get("spoon_vessel","")==id:
		technique="stir"
		table.technique="stir"
	elif technique=="stir":
		technique="shake"
		table.technique="shake"
	if id=="shaker" and data.get("lid",false):
		technique="shake"
		table.technique="shake"
	if not pending_item.is_empty():
		var item:=pending_item
		pending_item=""
		if WorkbenchSession.SOLIDS.has(item):
			_act("add_solid",{"material":item,"vessel":id})
		elif WorkbenchSession.GARNISHES.has(item):
			if id!="glass": status_label.text="请把装饰放到成品杯。"
			else: _act("garnish",{"material":item})
		else: _act("ice",{"vessel":id,"ice":item})
	_refresh()

func _prop(id: String) -> void:
	if data.get("status")!="mixing": return
	match id:
		"lid","cap": _act("lid")
		"spoon":
			_select("mixing")
			_set_technique("stir")
		"muddler":
			_select("glass")
			_set_technique("muddle")
		"strainer":
			if selected not in ["shaker","mixing"]: _select("shaker")
			_act("filter",{"source":selected,"vessel":"glass"})

func _set_technique(value: String) -> void:
	table.stop_gesture()
	if value=="stir":
		if selected not in ["mixing","glass","shaker"]: _select("mixing")
		if data.get("spoon_vessel","")!=selected:
			if not _issue("spoon",{"target":selected}):
				status_label.text=WorkbenchSession.last_error
				return
			SaloonAudio.ui.item("spoon")
	if value=="muddle" and not data.get("spoon_vessel","").is_empty():
		if not _issue("spoon",{"target":""}): return
	if value=="muddle": table.muddler_vessel=selected
	else: table.muddler_vessel=""
	technique=value
	table.technique=value
	if value=="shake": _select("shaker")
	elif selected not in ["mixing","glass","shaker"]: _select("mixing")
	_refresh()
	status_label.text="盖好壶盖，按住壶身拿起；拖到任意位置快速来回摇动；拖到成品杯松手倒酒。" if value=="shake" else ("吧勺已插入 · 按住杯口或勺柄移动鼠标控制转速；单击勺柄收回。" if value=="stir" else "握住露出的棒柄上下拉动：上提、下压；松手暂停，棒子留在杯中。握住杯身下部可倒酒。")

func _update_technique_hint() -> void:
	if not is_instance_valid(technique_panel): return
	if technique=="muddle":
		_update_muddle_hint()
		return
	technique_panel.visible=data.get("status")=="mixing" and selected in ["shaker","mixing","glass"] and technique in ["shake","stir"] and float(guidance_trace.get("traced",0))>0 and not is_instance_valid(modal) and not is_instance_valid(external_page)
	if not technique_panel.visible: return
	var window: Array=guidance_rule.get("time_window",[6,10])
	var elapsed: float=float(guidance_trace.get("min_seconds",0))+table.accumulated
	var stage: String="继续混合" if elapsed<float(window[0]) else ("已到位，可停手" if elapsed<=float(window[1]) else "偏久，建议停手")
	var longest: float=float(guidance_trace.get("max_seconds",0))+table.accumulated
	if longest>float(window[1]): stage="已有材料偏久，建议停手"
	var name: String="摇和" if technique=="shake" else "搅拌"
	var required: String=evaluation_model.rules.get(str(data.recipe.get("id","")),{}).get("mix",technique)
	if required!=technique: stage="本配方需"+("摇和" if required=="shake" else "搅拌")
	technique_title.text="%s %.1f 秒 / 建议 %s–%s 秒  ·  %s" % [name,elapsed,WorkbenchSession.format_amount(float(window[0])),WorkbenchSession.format_amount(float(window[1])),stage]
	technique_title.add_theme_color_override("font_color",Color("3e6344") if required==technique and elapsed>=float(window[0]) and longest<=float(window[1]) else INK)
	technique_detail.text="节奏力度：%s · %s\n%s" % [table.pace_text(),WorkbenchSession.LiquidState.description(data.vessels[selected]),"盖好壶盖，按住快速来回摇" if technique=="shake" else "按住移动调速，无需画圆；松手暂停"]
	technique_progress.max_value=float(window[1])*1.5
	technique_progress.value=elapsed
	technique_panel.tooltip_text="试玩推荐时长；只计有效动作，以最后加入材料的混合时间为准。力度按鼠标节奏估算。"

func _update_muddle_hint() -> void:
	technique_panel.visible=data.get("status")=="mixing" and selected in ["shaker","mixing","glass"] and not is_instance_valid(modal) and not is_instance_valid(external_page)
	if not technique_panel.visible: return
	var info:=WorkbenchSession.Muddle.summary(data.vessels[selected])
	var work: float=info.min_work
	var stage:="尚未加入薄荷"
	if info.count>0:
		stage="轻压中 · 叶面逐渐压软" if work<2 else ("已到位，可停手" if info.max_work<=4 else ("叶片正在破碎 · 建议停手" if info.max_work<9 else "已明显捣碎 · 请停手"))
	if work<2 and info.max_work>4: stage="已有叶片偏碎 · 新叶仍需轻压"
	technique_title.text="轻压 %.1f 秒 · %s" % [float(info.seconds)+table.accumulated,stage]
	technique_title.add_theme_color_override("font_color",Color("3e6344") if work>=2 and info.max_work<=4 else (Color("934826") if info.max_work>4 else INK))
	technique_detail.text="力度：%s · 下压深度 %d%%\n握住棒柄上下拉动；建议 2–4 秒，松手暂停。" % [table.pace_text(),roundi(table.muddle_depth*100)]
	if info.count==0: technique_detail.text="将薄荷拖入此容器，再握住棒柄上下拉动。"
	technique_progress.max_value=9
	technique_progress.value=work
	technique_panel.tooltip_text="试玩参数：进度按下压时长与鼠标速度估算；新加入的叶片单独记录。达到提示即可停手，不需要把薄荷完全捣碎。"

func _motion(kind: String, seconds: float) -> void:
	if data.get("status")!="mixing": return
	var payload: Dictionary={"vessel":selected,"seconds":seconds,"control":clampf(table.control_integral/maxf(.001,table.accumulated),0,1)}
	if kind=="muddle": payload.pressure=clampf(table.pressure_integral/maxf(.001,table.accumulated),0,1)
	if not _issue(kind,payload): status_label.text=WorkbenchSession.last_error

func _dialog(title: String, height := 520.0, width := 800.0, on_close := Callable()) -> Panel:
	table.stop_gesture()
	_clear_modal()
	modal_close = on_close
	table.input_enabled = false
	modal = Control.new()
	modal.size = Vector2(1600,900)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.06,.04,.025,.78)
	dim.size = modal.size
	modal.add_child(dim)
	var p := _panel(modal,Rect2((1600-width)/2,(900-height)/2,width,height),Color("352a23"))
	_text(p,Rect2(30,20,width-130,49),title,30)
	var close_button := _button(p,Rect2(width-94,20,65,46),"×",_close_modal)
	close_button.name = "CloseDialog"
	return p

func _close_modal() -> void:
	if modal_close.is_valid(): modal_close.call()
	else: _clear_modal()

func _clear_modal() -> void:
	sfx.silence()
	pending_confirm=Callable()
	modal_close=Callable()
	if is_instance_valid(table):
		table.pouring = false
		table.preview_amount = 0.0
		measure_waiting = false
		table.input_enabled = true
		table.queue_redraw()
	if is_instance_valid(context): context.show()
	if is_instance_valid(measure):
		measure.active = false
		measure.set_process(false)
	measure = null
	if is_instance_valid(modal):
		modal.hide()
		modal.queue_free()
	modal = null

func _measure_target(material: String) -> float:
	if data.get("mode")=="research_diy": return WorkbenchSession.dose_target(material,data)
	return float(dose_overrides.get(material,WorkbenchSession.dose_target(material,data)))

func _edit_draft(material: String, amount: float, remove: bool) -> void:
	var revision: int=int(data.get("draft",{}).get("revision",0))
	if _issue("edit_draft",{"material":material,"amount":amount,"remove":remove,"revision":revision}):
		dose_overrides.erase(material)
		status_label.text="草稿已保存；实际用料保留，下一次量取按新目标计算。"
		draft_panel.error_label.text="已加含桌上各容器；转移不重复，弃液不计。"
	else:
		status_label.text=WorkbenchSession.last_error
		draft_panel.error_label.text=WorkbenchSession.last_error
		draft_panel.apply_snapshot(data)

func _draft_picker() -> void:
	if data.get("mode")!="research_diy" or data.get("status")!="mixing": return
	var p:=_dialog("写入配方草稿",650,740)
	_text(p,Rect2(30,72,665,32),"选择后可直接修改目标用量；写草稿不会消耗库存。",18)
	var scroll:=ScrollContainer.new()
	scroll.position=Vector2(30,122)
	scroll.size=Vector2(680,493)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",8)
	scroll.add_child(rows)
	var definitions:=WorkbenchSession.draft_definitions()
	var planned: Dictionary=data.get("draft",{}).get("targets",{})
	for material in definitions:
		if planned.has(material): continue
		var definition: Dictionary=definitions[material]
		var unit:=str(definition.get("unit","ml"))
		var initial:=30.0 if WorkbenchSession.MATERIALS.has(material) else (50.0 if str(material).begins_with("ice:") else 1.0)
		var stock:="冰站供应" if str(material).begins_with("ice:") else "库存 %s %s" % [WorkbenchSession.format_amount(WorkbenchSession.remaining(material)),unit]
		var button:=_button(rows,Rect2(0,0,650,49),"%s  ·  %s" % [definition.name,stock],func():
			_edit_draft(material,initial,false)
			_clear_modal()
		)
		button.custom_minimum_size=Vector2(640,49)
	if rows.get_child_count()==0: _text(rows,Rect2(0,0,640,60),"所有可用原料都已写入草稿。",21)

func _ingredients() -> void:
	_show_category("基酒")

func _dosing_panel(title: String) -> Panel:
	table.stop_gesture()
	_clear_modal()
	modal=Control.new()
	modal.size=Vector2(1600,900)
	modal.mouse_filter=Control.MOUSE_FILTER_STOP
	surface.add_child(modal)
	table.input_enabled=false
	context.hide()
	var diy: bool=data.get("mode")=="research_diy"
	var p:=_panel(modal,Rect2(448 if diy else 348,92,776 if diy else 876,197),Color("f3e2c2"))
	_text(p,Rect2(20,8,p.size.x-130,33),title,23,INK)
	_button(p,Rect2(p.size.x-69,8,51,36),"×",_clear_modal)
	return p

func _begin_measure(material: String, target: float, vessel := "jigger") -> void:
	if is_instance_valid(measure): return
	if data.get("status")!="mixing" or not WorkbenchSession.writable: return
	var focused:=get_viewport().gui_get_focus_owner()
	if focused is LineEdit and draft_panel.is_ancestor_of(focused): focused.release_focus()
	if not Table.POS.has(vessel) or (vessel=="shaker" and data.lid):
		status_label.text="请先打开摇壶盖，或选择其他接酒容器。"
		return
	if data.get("mode")=="research_diy":
		target=WorkbenchSession.dose_target(material,data)
		if target<=0 and vessel=="jigger":
			status_label.text="这款原料已达草稿目标。修改左上角目标后再量取，或直接倒入容器自由加料。"
			return
	if not _place_material(material): return
	var available:=minf(WorkbenchSession.remaining(material),WorkbenchSession.capacity(data,vessel)-WorkbenchSession.amount(data.vessels[vessel])-WorkbenchSession.ice_volume(data.vessels[vessel]))
	if available<.1:
		status_label.text="容器已满或原料不足，请换容器或补货。"
		return
	if data.get("mode")=="research_diy" and vessel=="jigger": target=minf(target,available)
	target=clampf(target,.1 if data.get("mode")=="research_diy" else .5,60.0)
	var p:=_dosing_panel("倒入%s · %s" % [Table.NAMES[vessel],WorkbenchSession.MATERIALS[material].name])
	table.pour_vessel=vessel
	table.bottle=material
	table.pouring=true
	table.queue_redraw()
	measure=Measure.new()
	measure.target=target
	measure.precise=vessel=="jigger"
	measure.max_ml=minf(available,target*1.5) if measure.precise else available
	# Free pouring has no target marker and its flow rate varies slightly per bottle lift.
	if not measure.precise: measure.seconds=measure.max_ml/randf_range(22.0,29.0)
	measure.reference=data.get("draft",{}).get("targets",{}).has(material) if data.get("mode")=="research_diy" else data.recipe.ingredients.has(material)
	measure_waiting=true
	measure.set_process(false)
	measure.position=Vector2(45,43)
	measure.size=Vector2(p.size.x-116,113)
	p.add_child(measure)
	measure.decided.connect(func(ml,golden):
		var success:=_issue("withdraw",{"material":material,"ml":ml,"target_ml":target,"golden":golden,"method":"jigger" if vessel=="jigger" else "free_pour","vessel":vessel})
		_clear_modal()
		status_label.text=(("推荐范围内 · " if golden else "已倒入。")+"%s %s ml → %s" % [WorkbenchSession.MATERIALS[material].name,WorkbenchSession.format_amount(ml),Table.NAMES[vessel]]) if success else WorkbenchSession.last_error
		if success:
			_select(vessel)
			serve_armed=false
		_show_category(category)
	)
	_button(p,Rect2(45,148,310,40),"停止倒入 · 空格",func():
		if is_instance_valid(measure): measure.confirm()
	,true)
	_button(p,Rect2(375,148,p.size.x-420,40),"取消 · Esc",_close_modal)

func _finish() -> void:
	table.stop_gesture()
	if data.get("status") == "finished":
		if _service_cup(): _send_finished_drink()
		else: _result()
		return
	if _issue("finish"):
		if _service_cup(): _send_finished_drink()
		else: _result()
	else:
		status_label.text=WorkbenchSession.last_error

func _service_cup() -> bool:
	return not data.has("order") and not WorkbenchSession.is_research(data) and not str(data.get("guest", {}).get("visit_id", "")).is_empty()

func _send_finished_drink() -> void:
	if data.get("status") != "finished" or not _service_cup(): return
	CustomerService.deliver(data.result)
	_result()

func _return_after_serving() -> void:
	# Delivery receipts make closing/reopening this card safe to repeat.
	if CustomerService.deliver(data.result): Navigation.go_to(&"home")
	else: _result()

func _served_record() -> Dictionary:
	var record: Dictionary = CustomerService.current_record()
	if record.get("status") == "settled" and record.get("drink_id") == data.get("result", {}).get("drink_id") and record.get("visit_id") == data.get("guest", {}).get("visit_id"):
		return record
	return {}

func _result() -> void:
	var p:=_dialog("",760,1020,_return_after_serving if _service_cup() else Callable())
	var evaluation: Dictionary=data.result.get("evaluation",{})
	var accent:=Color(str(evaluation.get("color","8c9aa2")))
	var style:=_style(Color("f1e2c3"),accent)
	style.set_border_width_all(3)
	style.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel",style)
	var paper:=TextureRect.new()
	paper.texture=PAPER
	paper.position=Vector2(6,6)
	paper.size=Vector2(1008,748)
	paper.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper.modulate=Color(1,1,1,.16)
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.add_child(paper)
	p.move_child(paper,0)
	var card:=ResultCard.new()
	card.name="FinishedDrinkCard"
	card.position=Vector2(20,65)
	card.size=Vector2(980,630)
	card.result=data.result.duplicate(true)
	card.service_record = _served_record() if _service_cup() else {}
	card.result["cup"]=data.result.get("cup",data.cup)
	card.result["capacity_ml"]=data.result.get("capacity_ml",WorkbenchSession.capacity(data,"glass"))
	p.add_child(card)
	_text(p,Rect2(34,20,800,30),"这一杯的出品",23,INK)
	if WorkbenchSession.tutorial_active:
		_button(p,Rect2(40,705,360,44),"重做练习 · 不扣仓库",_restart)
		_button(p,Rect2(525,705,435,44),"记下这一杯，准备开门 · 空格",_finish_tutorial,true)
		pending_confirm=_finish_tutorial
		return
	if WorkbenchSession.is_research(data):
		var saved: bool=WorkbenchSession.research_state().saved_drinks.has(data.result.drink_id)
		if data.mode=="research_diy":
			_button(p,Rect2(40,697,240,44),"查看我的配方" if saved else "命名并保存配方",_research_library if saved else _save_research_dialog,true)
		else:
			if data.result.get("research_success",false):
				_button(p,Rect2(35,697,410,44),"已掌握 · 生成手绘酒图",_save_research_dialog,true)
			else: _text(p,Rect2(35,697,410,46),"尚未完美 · 可查看依据后重试",20,INK)
		_button(p,Rect2(475,697,235,44),"另起一杯",func():
			if _issue("start"): _clear_modal()
		)
		_button(p,Rect2(730,697,245,44),"返回研发室",func():
			Navigation.research_view="legendary" if data.mode=="research_legendary" else "entry"
			Navigation.go_to(&"research"))
		pending_confirm=_research_library if saved else (_save_research_dialog if data.mode=="research_diy" else _result_details)
		return
	if data.has("order"):
		var receipt: Dictionary=data.result.get("customer_receipt",{})
		if not receipt.is_empty():
			_button(p,Rect2(40,697,340,44),"查看客人评价与收款",_delivery_result,true)
			pending_confirm=_delivery_result
		else:
			_button(p,Rect2(40,697,340,44),"交给客人 · 空格",_deliver,true)
			pending_confirm=_deliver
		_button(p,Rect2(410,697,240,44),"查看制作依据",_result_details)
		_button(p,Rect2(680,697,290,44),"返回桌面",_clear_modal)
		return
	elif _service_cup():
		var served := _served_record()
		var note := "客人已收到这杯酒 · 获得 %d 金币" % int(served.amount) if not served.is_empty() else (CustomerService.last_error if not CustomerService.last_error.is_empty() else "这一杯已经做好，送给正在等你的客人。")
		_text(p,Rect2(45,667,930,26),note,18,INK)
		_button(p,Rect2(355,705,310,44),"回酒馆，听听客人怎么说" if not served.is_empty() else "送给客人，返回酒馆",_return_after_serving,true)
		pending_confirm = _return_after_serving
		return
	pending_confirm=func():
		if _issue("start"): _clear_modal()
	_button(p,Rect2(45,704,300,44),"另起一杯 · 空格",pending_confirm,true)
	_button(p,Rect2(365,704,290,44),"返回桌面 · Esc",_close_modal)
	_button(p,Rect2(675,704,290,44),"查看依据 · R",_result_details)

func _deliver() -> void:
	if GuestService.deliver(str(data.result.drink_id)):
		data=WorkbenchSession.snapshot().session
		_delivery_result()
	else:
		var p:=_dialog("这杯暂时未完成交付",380,860)
		_text(p,Rect2(40,100,780,140),GuestService.last_error+"\n当前成品已保留，重试不会重复收款。",25)
		_button(p,Rect2(40,290,370,52),"重试交付 · 空格",_deliver,true)
		_button(p,Rect2(445,290,370,52),"返回成品",_result)
		pending_confirm=_deliver

func _delivery_result() -> void:
	var receipt: Dictionary=data.result.get("customer_receipt",{})
	if receipt.is_empty(): return
	var p:=_dialog("客人的评价",620,960)
	p.add_theme_stylebox_override("panel",_style(Color("f1e2c3"),Color("b08a54")))
	for child in p.get_children():
		if child is Label: child.add_theme_color_override("font_color",INK)
	var preview:=preload("res://scripts/workbench_drink_preview.gd").new()
	preview.position=Vector2(30,100)
	preview.size=Vector2(290,365)
	preview.result=data.result
	p.add_child(preview)
	_text(p,Rect2(350,100,560,70),str(receipt.satisfaction)+(" · %.1f 分" % float(receipt.score) if receipt.score!=null else " · 本杯未饮用"),30,INK)
	_text(p,Rect2(350,185,560,165),str(receipt.get("reaction","")),25,INK).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_text(p,Rect2(350,365,560,80),"实收 %d 金币\n酒款 %d + 小费 %d" % [receipt.total_paid,receipt.base_paid,receipt.tip],26,INK)
	_text(p,Rect2(40,475,875,40),"已记入手帐；口味满意度与制作品质分别记录。",20,INK)
	_button(p,Rect2(40,545,420,50),"返回酒馆 · 空格",func(): Navigation.go_to(&"home"),true)
	_button(p,Rect2(490,545,420,50),"查看手帐",func():
		Navigation.journal_focus_guest=str(data.guest.id)
		Navigation.go_to(&"journal")
	)
	pending_confirm=func(): Navigation.go_to(&"home")

func _research_library() -> void:
	Navigation.research_view="library"
	Navigation.go_to(&"research")

var image_dialog: Control

func _save_research_dialog() -> void:
	if is_instance_valid(image_dialog): return
	var editor:=preload("res://scripts/research_image_dialog.gd").new()
	image_dialog=editor
	editor.session=data.duplicate(true)
	add_child(editor)
	editor.saved.connect(func(): _result())


func _result_details() -> void:
	var p:=_dialog("这一杯的评价依据",700,1020)
	var scroll:=ScrollContainer.new()
	scroll.position=Vector2(30,85)
	scroll.size=Vector2(960,525)
	p.add_child(scroll)
	var rows: Array[String]=[]
	var evaluation: Dictionary=data.result.get("evaluation",{})
	for reason in evaluation.get("reasons",[]): rows.append("· "+str(reason))
	var flavours: Array[String]=[]
	for tag in evaluation.get("tags",[]): flavours.append(str(tag.text))
	if not flavours.is_empty(): rows.append("\n风味："+"、".join(flavours))
	rows.append("\n成品实际用料")
	for id in data.result.contents.contents:
		rows.append("%s  %s ml" % [WorkbenchSession.MATERIALS[id].name,WorkbenchSession.format_amount(float(data.result.contents.contents[id]))])
	for id in data.result.contents.get("solids",{}):
		rows.append("%s  %s %s" % [WorkbenchSession.SOLIDS[id].name,WorkbenchSession.format_amount(float(data.result.contents.solids[id])),WorkbenchSession.SOLIDS[id].unit])
	var decorations: Dictionary={}
	for id in WorkbenchSession.garnishes(data.result.contents): decorations[id]=int(decorations.get(id,0))+1
	for id in decorations: rows.append("%s  %d %s" % [WorkbenchSession.GARNISHES[id].name,decorations[id],WorkbenchSession.GARNISHES[id].unit])
	rows.append("杯内冰：%s g" % WorkbenchSession.format_amount(WorkbenchSession.ice_mass(data.result.contents)))
	var waste:=0.0
	for amount in data.result.get("waste",{}).values(): waste+=float(amount)
	rows.append("其他容器弃置：%s ml" % WorkbenchSession.format_amount(waste))
	rows.append("\n评价说明")
	for note_text in evaluation.get("notes",["旧记录没有评级，未追溯重算。"]): rows.append(str(note_text))
	rows.append("客人评价及收款已记录在手帐。" if data.result.has("customer_receipt") else "本页为出品评价，尚未交付顾客或结算销售。")
	var label:=Label.new()
	label.custom_minimum_size=Vector2(930,0)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.text="\n".join(rows)
	label.add_theme_font_size_override("font_size",22)
	label.add_theme_color_override("font_color",CREAM)
	scroll.add_child(label)
	pending_confirm=_result
	_button(p,Rect2(30,626,445,44),"返回成品卡 · 空格",_result,true)
	_button(p,Rect2(495,626,475,44),"返回桌面 · Esc",_close_modal)

func _restart() -> void:
	if WorkbenchSession.tutorial_active:
		if OpeningFlow.begin_tutorial(true):
			_clear_modal()
			selected=""
			_refresh()
		else: status_label.text=OpeningFlow.last_error
		return
	var p := _dialog("丢弃这一杯，重新试作？",320)
	_text(p,Rect2(30,94,740,90),"已用材料不会退回；上一杯的动作记录会保留。\n继续使用仓库剩余原料，缺料需到商店补货。",22)
	pending_confirm=func():
		if data.get("status")=="mixing" and not _issue("discard"):
			_clear_modal()
			return
		if _issue("start"): _clear_modal()
	_button(p,Rect2(30,222,350,52),"确认重做 · 空格",pending_confirm,true)
	_button(p,Rect2(400,222,370,52),"继续当前制作 · Esc",_close_modal)

func _log() -> void:
	var p := _dialog("这一杯的动作记录",620)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30,88)
	scroll.size = Vector2(740,490)
	p.add_child(scroll)
	var label := Label.new()
	label.add_theme_font_size_override("font_size",21)
	label.add_theme_color_override("font_color",CREAM)
	var lines: Array[String] = []
	var names := {"spoon":"取放吧勺","withdraw":"量取","transfer":"倒入","filter":"过滤","ice":"加冰","lid":"开合盖","cup":"选杯","garnish":"装饰","shake":"摇和","stir":"搅拌","muddle":"轻压","finish":"出杯","discard":"丢弃","empty":"倒空容器"}
	var index := 0
	for action in data.get("actions",[]):
		index += 1
		var detail := ""
		if action.kind == "withdraw":
			detail = "%s %s ml → %s" % [WorkbenchSession.MATERIALS[action.payload.material].name,WorkbenchSession.format_amount(float(action.get("actual_ml",action.payload.ml))),Table.NAMES.get(action.payload.get("vessel","jigger"),"容器")]
		elif action.kind=="add_solid":
			var solid: Dictionary=WorkbenchSession.SOLIDS[action.payload.material]
			detail="%s 1 %s" % [solid.name,solid.unit]
		elif action.kind=="garnish":
			var decoration: Dictionary=WorkbenchSession.GARNISHES.get(action.payload.get("material","garnish"),{})
			detail="%s 1 %s" % [decoration.get("name","装饰"),decoration.get("unit","件")]
		elif action.kind=="empty":
			detail="%s · 损耗 %s ml · 冰 %s g" % [Table.NAMES[action.payload.vessel],WorkbenchSession.format_amount(WorkbenchSession.amount(action.removed)),WorkbenchSession.format_amount(WorkbenchSession.ice_mass(action.removed))]
		elif action.has("pour"):
			detail="%s → %s · %s ml · 冰 %s g" % [Table.NAMES[action.payload.source],Table.NAMES[action.payload.vessel],WorkbenchSession.format_amount(action.pour.ml),WorkbenchSession.format_amount(action.pour.ice_g)]
		elif action.kind=="spoon":
			detail="收回" if action.payload.get("target","").is_empty() else "插入"+Table.NAMES.get(action.payload.target,"容器")
		elif action.payload.has("seconds"):
			detail = "%.2f 秒" % action.payload.seconds
		elif action.payload.has("source"):
			detail = "%s → %s" % [Table.NAMES[action.payload.source],Table.NAMES[action.payload.vessel]]
		lines.append("%02d  %s   %s" % [index,names.get(action.kind,action.kind),detail])
	label.text = "\n".join(lines) if not lines.is_empty() else "还没有操作，先从材料柜取料。"
	scroll.add_child(label)

func _input(event: InputEvent) -> void:
	if is_instance_valid(image_dialog): return
	if is_instance_valid(external_page): return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and draft_panel.is_ancestor_of(focus) and not focus.get_global_rect().has_point(event.position):
			focus.release_focus()
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			if is_instance_valid(modal):
				if data.get("status")=="finished": _result()
				else: _clear_modal()
			else: focus.release_focus()
			get_viewport().set_input_as_handled()
		return
	if data.get("mode")!="research_diy" and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and not is_instance_valid(modal) and not table.bottle.is_empty() and not Rect2(1260,18,322,864).has_point(table.get_global_transform_with_canvas().affine_inverse()*event.position) and not Rect2(22,22,300,298).has_point(table.get_global_transform_with_canvas().affine_inverse()*event.position):
		var material: String=table.bottle
		var previous: float=float(dose_overrides.get(material,WorkbenchSession.dose_target(material,data)))
		dose_overrides[material]=clampf(previous+(5 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -5),5,60)
		selected="bottle"
		_rebuild_context()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_SPACE or event.keycode==KEY_SPACE:
			if is_instance_valid(measure): measure.confirm()
			elif is_instance_valid(modal):
				if pending_confirm.is_valid(): pending_confirm.call()
			elif data.get("status")=="finished": _result()
			elif selected=="glass" and serve_armed: _finish()
			elif selected=="shaker": _act("lid")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if not table.carry_id.is_empty(): table.cancel_carry()
			elif is_instance_valid(modal): _close_modal()
			else: _leave()
			get_viewport().set_input_as_handled()
		elif event.keycode==KEY_R and is_instance_valid(modal) and data.get("status")=="finished":
			if not _service_cup(): _result_details()
			get_viewport().set_input_as_handled()
		elif not is_instance_valid(modal) and event.keycode in [KEY_R,KEY_N,KEY_B,KEY_S]:
			match event.keycode:
				KEY_R: _log()
				KEY_N: _restart()
				KEY_B: _open_storage("backpack")
				KEY_S: _open_storage("shop")
			get_viewport().set_input_as_handled()

func _leave() -> void:
	sfx.silence()
	table.stop_gesture()
	if WorkbenchSession.tutorial_active:
		OpeningFlow.return_to_title()
		return
	if WorkbenchSession.is_research(data):
		Navigation.research_view="entry"
		Navigation.go_to(&"research")
		return
	if close_requested.get_connections().is_empty():
		get_tree().change_scene_to_file("res://scenes/home.tscn")
	else:
		close_requested.emit()

func _exit_tree() -> void:
	SaloonAudio.release_workbench(self)
	if is_instance_valid(sfx): sfx.silence()
	if is_instance_valid(measure):
		measure.active = false
		measure.set_process(false)
	if is_instance_valid(table):
		table.stop_gesture()

func _tutorial_help() -> void:
	var p:=_dialog("先熟悉这张工作台",370)
	_text(p,Rect2(30,90,740,180),"拖动材料到量酒器，空格停止量取。\n把量酒器拖到摇壶；轻压棒拖入后上下拉动。\n盖好摇壶，拖起快速来回摇，最后拖到成品杯。\n教学包独立消耗；N 重做，Esc 保留进度返回。",23)
	pending_confirm=_clear_modal

func _skip_tutorial() -> void:
	var p:=_dialog("跳过这次教学？",320)
	_text(p,Rect2(30,92,740,100),"不会生成虚假的成品、品质评分或销售收入。\n以后可从开始界面回看序章、练习调酒。",23)
	_button(p,Rect2(30,228,300,50),"继续练习",_clear_modal)
	_button(p,Rect2(420,228,340,50),"跳过，准备开门",_finish_tutorial.bind(true),true)
	pending_confirm=_finish_tutorial.bind(true)

func _finish_tutorial(skipped := false) -> void:
	if OpeningFlow.finish_tutorial(skipped):
		get_tree().change_scene_to_file("res://scenes/opening_departure.tscn")
	else: status_label.text=OpeningFlow.last_error

func _material_info(id: String) -> Dictionary:
	return WorkbenchSession.MATERIALS.get(id,WorkbenchSession.SOLIDS.get(id,WorkbenchSession.GARNISHES.get(id,{})))

func _notify_empty(id: String) -> void:
	var info:=_material_info(id)
	if info.is_empty(): return
	restock_material=id
	feedback_panel.show()
	restock_button.show()
	feedback_text.size.x=480
	feedback_text.text="%s%s · 可去商店补货" % [info.name,"已用完" if WorkbenchSession.remaining(id)<=.001 else "不足一次用量"]
	status_label.text=feedback_text.text

func _addition_feedback(kind: String, payload: Dictionary, before: Dictionary) -> void:
	if not is_instance_valid(feedback_panel): return
	if kind in ["start","select_recipe"]:
		feedback_panel.hide()
		restock_material=""
		return
	var message:=""
	var material:=str(payload.get("material","garnish" if kind=="garnish" else ""))
	var vessel:=str(payload.get("vessel","glass"))
	var info:=_material_info(material)
	if kind=="withdraw": message="加入 %s %s ml → %s" % [info.name,WorkbenchSession.format_amount(WorkbenchSession.amount(data.vessels[vessel])-WorkbenchSession.amount(before.vessels[vessel])),Table.NAMES[vessel]]
	elif kind in ["add_solid","garnish"]: message="加入 %s 1 %s → %s" % [info.name,info.get("unit","份"),Table.NAMES[vessel]]
	elif kind=="ice": message="加入%s %s g → %s\n此容器累计冰量 %s g" % ["方冰" if payload.ice=="cube" else "碎冰",WorkbenchSession.format_amount(WorkbenchSession.ICE_PORTION_G),Table.NAMES[vessel],WorkbenchSession.format_amount(WorkbenchSession.ice_mass(data.vessels[vessel]))]
	elif kind in ["transfer","filter"]:
		var source: Dictionary=before.vessels[payload.source]
		var left: Dictionary=data.vessels[payload.source]
		var ml:=WorkbenchSession.amount(source)-WorkbenchSession.amount(left)
		var ice:=WorkbenchSession.ice_mass(source)-WorkbenchSession.ice_mass(left)
		message="倒入 %s ml%s → %s" % [WorkbenchSession.format_amount(ml)," · 冰 %s g" % WorkbenchSession.format_amount(ice) if ice>0 else "",Table.NAMES[vessel]]
		message+="\n%s剩余 %s ml · 冰 %s g%s" % [Table.NAMES[payload.source],WorkbenchSession.format_amount(WorkbenchSession.amount(left)),WorkbenchSession.format_amount(WorkbenchSession.ice_mass(left)),"（过滤保留固体）" if kind=="filter" else ""]
	elif kind=="empty":
		message="已倒掉 %s ml · 冰 %s g 及容器内配料\n%s已清空，原料不退回库存" % [WorkbenchSession.format_amount(WorkbenchSession.amount(before.vessels[vessel])),WorkbenchSession.format_amount(WorkbenchSession.ice_mass(before.vessels[vessel])),Table.NAMES[vessel]]

	if message.is_empty(): return
	feedback_panel.show()
	feedback_text.size.x=660
	feedback_text.text=message
	# Keep an unfilled restock shortcut available across subsequent additions.
	if not material.is_empty() and not info.is_empty() and WorkbenchSession.remaining(material)<(.1 if WorkbenchSession.MATERIALS.has(material) else 1):
		_notify_empty(material)
		feedback_text.text=message+"\n"+feedback_text.text
	elif not restock_material.is_empty() and WorkbenchSession.remaining(restock_material)<1:
		feedback_text.size.x=480
		restock_button.show()
	else:
		restock_material=""
		restock_button.hide()

func _open_restock() -> void:
	var sku:=str(_material_info(restock_material).get("sku_id",""))
	_open_storage("shop")
	if is_instance_valid(external_page) and external_page.has_method("focus_item") and not sku.is_empty(): external_page.focus_item(sku)

func _empty_vessel(vessel: String) -> void:
	if data.get("status")!="mixing" or is_instance_valid(modal): return
	table.stop_gesture()
	if _issue("empty",{"vessel":vessel}):
		table.animated_source=""
		table.transition_progress=1.0
		table.drain_flash=1.0
		sfx.tap()
		status_label.text="%s已倒空，材料记为损耗；其他容器保留。" % Table.NAMES[vessel]
		_rebuild_context()
	else: status_label.text=WorkbenchSession.last_error
