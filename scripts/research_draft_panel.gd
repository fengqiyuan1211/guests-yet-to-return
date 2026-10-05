extends Panel
signal edit_requested(material: String, amount: float, remove: bool)
signal add_requested
const Art=preload("res://scripts/workbench_art.gd")
const INK=Color("49301f")
var rows: VBoxContainer
var scroll: ScrollContainer
var fields: Dictionary={}
var actual_labels: Dictionary={}
var hints: Dictionary={}
var row_panels: Dictionary={}
var snapshot: Dictionary={}
var signature:=""
var add_button: Button
var subtitle: Label
var error_label: Label

func _ready() -> void:
	size=Vector2(400,428)
	add_theme_stylebox_override("panel",style(Color("f3e2c2"),Color("91673f")))
	var paper:=TextureRect.new()
	paper.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper.texture=preload("res://assets/codex/journal-paper-v1.png")
	paper.size=size
	paper.self_modulate=Color(1,1,1,.28)
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(paper)
	var clip:=Panel.new()
	clip.position=Vector2(163,-8)
	clip.size=Vector2(74,15)
	clip.add_theme_stylebox_override("panel",style(Color("8c683b"),Color("d5b273")))
	clip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	label(self,Rect2(22,18,355,33),"配方草稿  /  DIY",25)
	subtitle=label(self,Rect2(22,55,355,29),"点击目标数字修改 · 属性完成后揭晓",15)
	label(self,Rect2(24,92,122,27),"原料",17)
	label(self,Rect2(173,92,69,27),"目标",17)
	label(self,Rect2(280,92,68,27),"已加",17)
	scroll=ScrollContainer.new()
	scroll.position=Vector2(20,123)
	scroll.size=Vector2(364,210)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",7)
	scroll.add_child(rows)
	add_button=Button.new()
	add_button.text="＋ 添加原料或冰"
	add_button.position=Vector2(24,342)
	add_button.size=Vector2(352,35)
	add_button.add_theme_font_size_override("font_size",18)
	add_button.add_theme_color_override("font_color",INK)
	add_button.add_theme_stylebox_override("normal",style(Color("eddbb9")))
	add_button.add_theme_stylebox_override("hover",style(Color("ffecc6")))
	add_button.pressed.connect(func(): add_requested.emit())
	add_child(add_button)
	error_label=label(self,Rect2(24,383,352,38),"已加含桌上各容器；转移不重复，弃液不计。",14)
	error_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func style(fill: Color, border:=Color("b49a71")) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=fill
	box.border_color=border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	return box

func label(parent: Node, rect: Rect2, text: String, px: int) -> Label:
	var node:=Label.new()
	node.position=rect.position
	node.size=rect.size
	node.text=text
	node.add_theme_font_size_override("font_size",px)
	node.add_theme_color_override("font_color",INK)
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func apply_snapshot(value: Dictionary) -> void:
	snapshot=value
	var targets: Dictionary=value.get("draft",{}).get("targets",{})
	var actual: Dictionary=WorkbenchSession.draft_amounts(value)
	var keys: Array=targets.keys()
	for material in actual:
		if not keys.has(material) and float(actual[material])>0: keys.append(material)
	var next_signature:=JSON.stringify([keys,targets.keys(),value.get("status")])
	if signature!=next_signature:
		signature=next_signature
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		fields.clear()
		actual_labels.clear()
		hints.clear()
		row_panels.clear()
		if keys.is_empty():
			var empty:=label(rows,Rect2(0,0,340,150),"先写下想调的配比。\n也可以先取料，再补目标用量。",19)
			empty.custom_minimum_size=Vector2(340,140)
			empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		for material in keys: _row(str(material),targets.has(material))
	for material in keys:
		var amount:=float(actual.get(material,0))
		var target:=float(targets.get(material,0))
		var field: LineEdit=fields[material]
		if not field.has_focus(): field.text=WorkbenchSession.format_amount(target) if targets.has(material) else ""
		actual_labels[material].text=WorkbenchSession.format_amount(amount)
		var unit:=str(WorkbenchSession.draft_definitions()[material].get("unit","ml"))
		var text:="额外加入 · 可补写目标"
		if targets.has(material):
			var diff:=target-amount
			text=("还需 %s %s" % [WorkbenchSession.format_amount(diff),unit]) if diff>.05 else ("已达目标" if absf(diff)<.05 else "超出 %s %s" % [WorkbenchSession.format_amount(-diff),unit])
			if diff>60 and WorkbenchSession.MATERIALS.has(material): text+=" · 分次量取"
		if str(material).begins_with("ice:"): text+=" · 每份 %s g" % WorkbenchSession.format_amount(WorkbenchSession.ICE_PORTION_G)
		hints[material].text=text
		row_panels[material].add_theme_stylebox_override("panel",style(Color("fff0c8") if targets.has(material) and target>amount else Color("ead7b4")))
	add_button.disabled=value.get("status")!="mixing"

func _row(material: String, planned: bool) -> void:
	var def: Dictionary=WorkbenchSession.draft_definitions()[material]
	var row:=Panel.new()
	row.custom_minimum_size=Vector2(346,76)
	rows.add_child(row)
	row_panels[material]=row
	var icon:=TextureRect.new()
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.texture=Art.texture(material.trim_prefix("ice:"))
	icon.position=Vector2(7,10)
	icon.size=Vector2(25,34)
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var name_label:=label(row,Rect2(37,8,106,34),str(def.name),17)
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var field:=LineEdit.new()
	field.name="Target_"+material.replace(":","_")
	field.position=Vector2(145,9)
	field.size=Vector2(69,34)
	field.placeholder_text="—"
	field.alignment=HORIZONTAL_ALIGNMENT_CENTER
	field.max_length=7
	field.editable=snapshot.get("status")=="mixing"
	field.add_theme_font_size_override("font_size",18)
	field.add_theme_color_override("font_color",INK)
	field.add_theme_color_override("font_placeholder_color",Color("896e50"))
	field.add_theme_color_override("caret_color",INK)
	field.add_theme_stylebox_override("normal",style(Color("fff3d6")))
	field.add_theme_stylebox_override("focus",style(Color("fff8e5"),Color("ad792c")))
	row.add_child(field)
	fields[material]=field
	field.text_submitted.connect(func(_text): field.release_focus())
	field.focus_exited.connect(func(): _commit_field(material,field))
	label(row,Rect2(217,12,36,26),str(def.get("unit","ml")),14)
	actual_labels[material]=label(row,Rect2(256,10,59,30),"",18)
	hints[material]=label(row,Rect2(37,45,278,25),"",14)
	if planned and snapshot.get("status")=="mixing":
		var remove:=Button.new()
		remove.position=Vector2(315,9)
		remove.size=Vector2(26,29)
		remove.text="×"
		remove.focus_mode=Control.FOCUS_NONE
		remove.add_theme_font_size_override("font_size",18)
		remove.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
		remove.add_theme_color_override("font_color",INK)
		remove.pressed.connect(func(): edit_requested.emit(material,0,true))
		row.add_child(remove)

func _commit_field(material: String, field: LineEdit) -> void:
	if not is_inside_tree() or not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion() or snapshot.get("status")!="mixing": return
	var raw:=field.text.strip_edges()
	var targets: Dictionary=snapshot.get("draft",{}).get("targets",{})
	if raw.is_empty() and not targets.has(material): return
	if not raw.is_valid_float() or not is_finite(raw.to_float()) or raw.to_float()<=0:
		error_label.text="请输入大于 0 的用量；移除目标请点 ×。"
		field.text=WorkbenchSession.format_amount(float(targets[material])) if targets.has(material) else ""
		return
	if targets.has(material) and is_equal_approx(raw.to_float(),float(targets[material])): return
	edit_requested.emit(material,raw.to_float(),false)
