extends Control
signal close_requested
const Table = preload("res://scripts/workbench_table.gd")
const Art = preload("res://scripts/workbench_art.gd")
const Measure = preload("res://scripts/workbench_measure.gd")
const PAPER = preload("res://assets/codex/journal-paper-v1.png")
const INK := Color("573c28")
const CREAM := Color("efdab3")
var surface: Control
var table: Control
var note: Label
var status_label: Label
var duration_label: Label
var footer: Label
var context: Control
var pantry: Control
var pantry_items: Control
var category_buttons: Array[Button] = []
var item_buttons: Dictionary = {}
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
var next_hint: Label

func _ready() -> void:
	surface=Control.new()
	surface.size=Vector2(1600,900)
	add_child(surface)
	table=Table.new()
	table.size=surface.size
	surface.add_child(table)
	table.vessel_selected.connect(_select)
	table.prop_selected.connect(_prop)
	table.transfer_requested.connect(func(source, destination): _act("transfer",{"source":source,"vessel":destination}))
	table.motion_completed.connect(_motion)
	table.item_dropped.connect(_dropped)
	table.serve_requested.connect(_finish)
	_build()
	resized.connect(_fit)
	_fit()
	WorkbenchSession.changed.connect(_refresh)
	if WorkbenchSession.state.session.is_empty() or WorkbenchSession.state.session.get("status")=="discarded": _issue("start")
	_refresh()
	if data.get("status")=="finished": _result()

func _fit() -> void:
	var factor := minf(size.x/1600.0,size.y/900.0)
	surface.scale = Vector2.ONE*factor
	surface.position = (size-Vector2(1600,900)*factor)*.5

func _style(fill: Color, border := Color("916c43")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(7)
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
	_paper(surface,Rect2(22,22,300,298))
	_text(surface,Rect2(46,39,254,36),"试调订单",29,INK)
	_text(surface,Rect2(46,79,254,28),"码头试作 · 配方参考",17,INK)
	note=_text(surface,Rect2(46,114,258,125),"",21,INK)
	_text(surface,Rect2(46,246,254,53),"量取 → 加冰 → 摇和 → 过滤\n允许改变用量与步骤",16,INK)
	pantry=_panel(surface,Rect2(1260,18,322,864),Color("382619"))
	_paper(pantry,Rect2(10,10,302,844))
	_text(pantry,Rect2(32,30,260,52),"备 料 柜",34,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for i in range(6):
		var name: String=["基酒","配料","装饰","杯子","冰块","器具"][i]
		var b:=_button(pantry,Rect2(21+(i%3)*94,106+(i/3)*47,92,44),name,_show_category.bind(name))
		b.add_theme_color_override("font_color",INK)
		category_buttons.append(b)
	pantry_items=Control.new()
	pantry_items.position=Vector2(20,217)
	pantry_items.size=Vector2(282,510)
	pantry.add_child(pantry_items)
	_text(pantry,Rect2(27,758,273,47),"拖到杯子或制作容器\n空格停下 · 拖回收起",17,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	context=_panel(surface,Rect2(340,785,895,70),Color(.12,.085,.055,.85))
	context.mouse_filter=Control.MOUSE_FILTER_IGNORE
	status_label=_text(surface,Rect2(350,866,875,30),"",18)
	duration_label=_text(surface,Rect2(880,835,350,26),"",16)
	footer=_text(surface,Rect2(25,825,292,30),"Esc 返回 · 半成品自动保留",16)
	_button(surface,Rect2(342,22,145,38),"返回 Esc",_leave)
	_button(surface,Rect2(497,22,130,38),"记录 R",_log)
	_button(surface,Rect2(637,22,130,38),"重做 N",_restart)
	next_hint=_text(context,Rect2(12,4,871,62),"",20)
	next_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
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
	var items: Array=[]
	match value:
		"基酒": items=[["gin","金酒"],["rum","朗姆酒"],["vodka","伏特加"]]
		"配料": items=[["lime","青柠汁"],["syrup","糖浆"],["soda","苏打水"]]
		"装饰": items=[["garnish","青柠角"]]
		"杯子": items=[["coupe","碟形杯"],["highball","高球杯"]]
		"冰块": items=[["cube","标准方冰"],["crushed","碎冰"]]
		"器具": items=[["shaker","摇壶"],["jigger","量酒器"],["spoon","吧勺"],["strainer","滤冰器"],["muddler","轻压棒"],["mixing","搅拌杯"]]
	for i in range(items.size()):
		var id: String=items[i][0]
		var label: String=items[i][1]
		var b:=_button(pantry_items,Rect2((i%2)*142,(i/2)*167,140,165),"",func(): pass)
		b.gui_input.connect(_pantry_input.bind(value,id))
		b.add_theme_stylebox_override("normal",_style(Color(0,0,0,0),Color(.45,.32,.17,.25)))
		b.add_theme_stylebox_override("hover",_style(Color(.89,.74,.44,.3),Color("b38d45")))
		var art:=TextureRect.new()
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture=Art.texture(id)
		art.position=Vector2(26,8)
		art.size=Vector2(88,111)
		art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
		_text(b,Rect2(4,117,132,28),label,20,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		if WorkbenchSession.MATERIALS.has(id):
			_text(b,Rect2(4,142,132,20),"%d ml" % int(WorkbenchSession.state.stock.get(id,0)),14,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		item_buttons[id]=b

func _process(_delta: float) -> void:
	if is_instance_valid(measure):
		if measure_waiting and table.pour_blend>.95:
			measure_waiting=false
			measure.set_process(true)
		table.preview_amount=measure.progress*measure.target*1.5

func _pantry_input(event: InputEvent, tab: String, id: String) -> void:
	if is_instance_valid(modal): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		table.begin_item_drag(tab,id,table.get_global_transform_with_canvas().affine_inverse()*item_buttons[id].get_global_transform_with_canvas()*event.position)

func _place_material(id: String) -> bool:
	var items: Array = WorkbenchSession.state.get("table_materials",[]).duplicate()
	if not items.has(id): items.append(id)
	if not WorkbenchSession.set_table_materials(items):
		status_label.text=WorkbenchSession.last_error
		return false
	table.bottle=id
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
			_begin_measure(id,int(dose_overrides.get(id,data.recipe.ingredients.get(id,30))),target)
		elif target.is_empty() or target.begins_with("bottle:"):
			_choose_item("基酒",id)
		else:
			status_label.text="请拖到成品杯、量酒器或打开的制作容器。"
		return
	if tab=="冰块" and target in ["shaker","mixing","glass"]:
		_act("ice",{"vessel":target,"ice":id})
	elif tab=="装饰" and target=="glass": _act("garnish")
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
	if tab in ["基酒","配料"]:
		if not _place_material(id): return
		selected="bottle"
		table.selected="bottle"
		_rebuild_context()
		status_label.text=WorkbenchSession.MATERIALS[id].name+"已放到桌上，拖到杯子或制作容器开始倒入。"
	elif tab in ["冰块","装饰"]:
		pending_item=id
		status_label.text="已取用%s，点击桌上%s。" % ["青柠角" if id=="garnish" else "冰块","成品杯放置" if id=="garnish" else "容器加入"]
	elif tab=="杯子":
		_act("cup",{"cup":"coupe" if id=="coupe" else "highball"})
		_select("glass")
	else:
		if Table.POS.has(id): _select(id)
		else: _prop(id)
	table.queue_redraw()

func _issue(kind: String, payload: Dictionary={}) -> bool:
	counter+=1
	var id:="%d-%d-%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec(),counter]
	return WorkbenchSession.command(id,str(WorkbenchSession.state.session.get("id","")),kind,payload)

func _act(kind: String,payload: Dictionary={}) -> void:
	table.stop_gesture()
	if not _issue(kind,payload):
		status_label.text=WorkbenchSession.last_error
	else:
		if kind in ["transfer","filter"]:
			table.animated_source=payload.get("source","")
			table.animation_progress=0
			table.animated_destination=payload.get("vessel","")
		status_label.text={"transfer":"已倒入。","filter":"已过滤入杯，冰留在源容器。","ice":"冰已加入。","lid":"摇壶已盖好。" if data.get("lid",false) else "摇壶已打开。","garnish":"装饰已放好。"}.get(kind,"已保存。")
		_rebuild_context()

func _refresh() -> void:
	data=WorkbenchSession.snapshot().session
	table.materials=WorkbenchSession.state.get("table_materials",[]).duplicate()
	table.apply_snapshot(data)
	table.queue_redraw()
	var lines: Array[String]=[]
	for material in data.get("recipe",WorkbenchSession.RECIPE).ingredients:
		lines.append("%s %d ml  ·  已取 %d" % [WorkbenchSession.MATERIALS[material].name,int(data.get("recipe",WorkbenchSession.RECIPE).ingredients[material]),int(data.get("withdrawn",{}).get(material,0))])
	note.text="\n".join(lines)
	var duration:=0.0
	for action in data.get("actions",[]):
		if action.kind==technique: duration+=float(action.payload.get("seconds",0))
	duration_label.text=("%s %.1f 秒" % [{"shake":"摇和","stir":"搅拌","muddle":"轻压"}[technique],duration]) if duration>0 else ""
	if not WorkbenchSession.last_error.is_empty(): status_label.text=WorkbenchSession.last_error
	elif data.get("status")=="finished": status_label.text="试作完成。可查看结果，或另起一杯。"
	elif status_label.text.is_empty(): status_label.text="拖动材料到杯子或制作容器，按空格停止倒入。"
	_rebuild_context()

func _rebuild_context() -> void:
	if not is_instance_valid(next_hint): return
	if data.is_empty(): return
	if data.get("status")=="finished":
		next_hint.text="这杯已完成 · 空格查看结果 · N 另起一杯"
		return
	var vessels: Dictionary=data.vessels
	var glass_amount:=WorkbenchSession.amount(vessels.glass)
	var jigger_amount:=WorkbenchSession.amount(vessels.jigger)
	var shaker_amount:=WorkbenchSession.amount(vessels.shaker)
	var mixing_amount:=WorkbenchSession.amount(vessels.mixing)
	if selected=="bottle" and not table.bottle.is_empty():
		var ml: int=int(dose_overrides.get(table.bottle,data.recipe.ingredients.get(table.bottle,30)))
		next_hint.text="%s · 目标 %d ml · 滚轮调剂量
拖到成品杯、量酒器或打开的制作容器，空格停止倒入" % [WorkbenchSession.MATERIALS[table.bottle].name,ml]
	elif selected=="glass" and glass_amount>0:
		var waste:=jigger_amount+shaker_amount+mixing_amount
		next_hint.text="成品杯 %d ml · 拖冰块／装饰到杯中 · 点杯后空格出杯，或拖杯脚到出杯区" % glass_amount
		if waste>0: next_hint.text+="
出杯时，其他容器剩余 %d ml 将记为弃置。" % waste
	elif selected=="jigger" and jigger_amount>0:
		next_hint.text="量酒器已有 %d ml · 拖到摇壶、搅拌杯或成品杯，松手倒入" % jigger_amount
	elif selected=="shaker":
		next_hint.text="壶盖已合上 · 按住壶身拿起，上下推拉前后摇和 · 空格打开盖子" if data.lid else "将材料和冰拖入摇壶 · 空格或拖盖子合盖 · 拖滤冰器到壶上过滤入杯"
	elif selected=="mixing":
		next_hint.text="将材料拖入搅拌杯 · 拖旁边的吧勺到杯口，再按住杯口画圈 · 拖滤冰器到杯上出酒"
	elif jigger_amount>0:
		next_hint.text="下一步：量酒器已有 %d ml，拖到要接酒的容器。" % jigger_amount
	elif glass_amount>0:
		next_hint.text="杯中已有 %d ml · 可以继续直倒、加冰或装饰 · 点成品杯后空格出杯" % glass_amount
	elif shaker_amount>0:
		next_hint.text="下一步：摇壶加冰、合盖，再拿起前后摇和。"
	elif mixing_amount>0:
		next_hint.text="下一步：把吧勺拖到搅拌杯，沿杯口画圈搅拌。"
	else:
		next_hint.text="从右侧拖材料到杯子或制作容器 · 空格停止倒入
右上角是成品杯，点击菜单杯型即可替换；已有酒液会保留。"

func _select(id: String) -> void:
	serve_armed=id=="glass"
	selected=id
	table.selected=id
	if id=="shaker" and data.get("lid",false):
		technique="shake"
		table.technique="shake"
	if not pending_item.is_empty():
		var item:=pending_item
		pending_item=""
		if item=="garnish":
			if id!="glass": status_label.text="请把装饰放到成品杯。"
			else: _act("garnish")
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
	technique=value
	table.technique=value
	if value=="shake": _select("shaker")
	elif selected not in ["mixing","glass","shaker"]: _select("mixing")
	_refresh()
	status_label.text="盖好壶盖，按住壶身拿起；鼠标上下推拉来前后摇和，松手放回。" if value=="shake" else ("按住杯口沿圆周拖动搅拌。" if value=="stir" else "按住杯子上下拖动轻压。")

func _motion(kind: String, seconds: float) -> void:
	if data.get("status")!="mixing": return
	if not _issue(kind,{"vessel":selected,"seconds":seconds}): status_label.text=WorkbenchSession.last_error

func _dialog(title: String, height := 520.0) -> Panel:
	table.stop_gesture()
	_clear_modal()
	table.input_enabled = false
	modal = Control.new()
	modal.size = Vector2(1600,900)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.06,.04,.025,.78)
	dim.size = modal.size
	modal.add_child(dim)
	var p := _panel(modal,Rect2(400,(900-height)/2,800,height),Color("352a23"))
	_text(p,Rect2(30,20,670,49),title,30)
	_button(p,Rect2(706,20,65,46),"×",_clear_modal)
	return p

func _clear_modal() -> void:
	pending_confirm=Callable()
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
	var p:=_panel(modal,Rect2(348,663,876,197),Color(.14,.095,.045,.95))
	_text(p,Rect2(20,8,680,33),title,23)
	_button(p,Rect2(807,8,51,36),"×",_clear_modal)
	return p

func _begin_measure(material: String, target: int, vessel := "jigger") -> void:
	if data.get("status")!="mixing" or not WorkbenchSession.writable: return
	if not Table.POS.has(vessel) or (vessel=="shaker" and data.lid):
		status_label.text="请先打开摇壶盖，或选择其他接酒容器。"
		return
	if not _place_material(material): return
	var p:=_dosing_panel("倒入%s · %s" % [Table.NAMES[vessel],WorkbenchSession.MATERIALS[material].name])
	table.pour_vessel=vessel
	table.bottle=material
	table.pouring=true
	table.queue_redraw()
	measure=Measure.new()
	measure.target=target
	measure_waiting=true
	measure.set_process(false)
	measure.position=Vector2(45,43)
	measure.size=Vector2(760,113)
	p.add_child(measure)
	measure.decided.connect(func(ml,golden):
		var success:=_issue("withdraw",{"material":material,"ml":ml,"target_ml":target,"golden":golden,"vessel":vessel})
		_clear_modal()
		status_label.text=(("黄金用量！" if golden else "已倒入。")+"%s %d ml → %s" % [WorkbenchSession.MATERIALS[material].name,ml,Table.NAMES[vessel]]) if success else WorkbenchSession.last_error
		if success:
			_select(vessel)
			serve_armed=false
		_show_category(category)
	)
	_text(p,Rect2(200,150,600,35),"空格 停止倒入     ·     Esc 取消",22)

func _finish() -> void:
	table.stop_gesture()
	if _issue("finish"):
		_result()
	else:
		status_label.text=WorkbenchSession.last_error

func _result() -> void:
	var p := _dialog("试作完成 · " + str(data.recipe.name),580)
	var result: Dictionary = data.result
	var rows := [str(data.recipe.english_name),"", "成品杯实际用量"]
	for id in result.get("contents",{}).get("contents",{}):
		rows.append("%s   %d ml" % [WorkbenchSession.MATERIALS[id].name,int(result.contents.contents[id])])
	var waste := 0
	for qty in result.get("waste",{}).values():
		waste += int(qty)
	rows.append("\n其他容器弃置：%d ml\n步骤、用量与动作时长已保存。\n味觉评分、成本和配方保存尚未接入。" % waste)
	_text(p,Rect2(30,92,740,370),"\n".join(rows),22)
	_text(p,Rect2(30,481,740,64),"空格 另起一杯     ·     Esc 返回桌面",23)
	pending_confirm=func():
		if _issue("start"): _clear_modal()

func _restart() -> void:
	var p := _dialog("丢弃这一杯，重新试作？",320)
	_text(p,Rect2(30,94,740,90),"已用材料不会退回；上一杯的动作记录会保留。\n新的试作仍使用剩余练习库存。",22)
	_text(p,Rect2(30,222,740,61),"空格 确认重做     ·     Esc 继续当前制作",22)
	pending_confirm=func():
		if data.get("status")=="mixing" and not _issue("discard"):
			_clear_modal()
			return
		if _issue("start"): _clear_modal()

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
	var names := {"withdraw":"量取","transfer":"倒入","filter":"过滤","ice":"加冰","lid":"开合盖","cup":"选杯","garnish":"装饰","shake":"摇和","stir":"搅拌","muddle":"轻压","finish":"出杯","discard":"丢弃"}
	var index := 0
	for action in data.get("actions",[]):
		index += 1
		var detail := ""
		if action.kind == "withdraw":
			detail = "%s %d ml → %s" % [WorkbenchSession.MATERIALS[action.payload.material].name,int(action.payload.ml),Table.NAMES.get(action.payload.get("vessel","jigger"),"容器")]
		elif action.payload.has("seconds"):
			detail = "%.2f 秒" % action.payload.seconds
		elif action.payload.has("source"):
			detail = "%s → %s" % [Table.NAMES[action.payload.source],Table.NAMES[action.payload.vessel]]
		lines.append("%02d  %s   %s" % [index,names.get(action.kind,action.kind),detail])
	label.text = "\n".join(lines) if not lines.is_empty() else "还没有操作，先从材料柜取料。"
	scroll.add_child(label)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and not is_instance_valid(modal) and not table.bottle.is_empty():
		var material: String=table.bottle
		var previous: int=int(dose_overrides.get(material,data.recipe.ingredients.get(material,30)))
		dose_overrides[material]=clampi(previous+(5 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -5),5,60)
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
			elif is_instance_valid(modal): _clear_modal()
			else: _leave()
			get_viewport().set_input_as_handled()
		elif not is_instance_valid(modal) and event.keycode in [KEY_R,KEY_N]:
			if event.keycode==KEY_R: _log()
			else: _restart()
			get_viewport().set_input_as_handled()

func _leave() -> void:
	table.stop_gesture()
	if close_requested.get_connections().is_empty():
		get_tree().change_scene_to_file("res://scenes/home.tscn")
	else:
		close_requested.emit()

func _exit_tree() -> void:
	if is_instance_valid(measure):
		measure.active = false
		measure.set_process(false)
	if is_instance_valid(table):
		table.stop_gesture()
