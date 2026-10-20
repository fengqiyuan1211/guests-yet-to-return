extends Control
## Guidance only: the existing shop owns selection, prices, purchases and stock.
signal ready_to_mix
const UI=preload("res://scripts/opening_ui.gd")
const Prep=preload("res://scripts/opening_preparation.gd")
var shop: Control
var panel: Panel
var title: Label
var description: Label
var proceed: Button
var marker: Control
var target: Control
var current_sku := ""
var clock := 0.0
var refresh_clock := 0.0

func _ready() -> void:
	name="OpeningShopGuide"
	size=Vector2(1600,900)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=80
	panel=UI.panel(self,Rect2(45,450,610,232))
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	title=UI.label(panel,Rect2(22,12,565,35),"",24,Color("ffe0a2"))
	description=UI.label(panel,Rect2(22,57,565,110),"",22)
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	proceed=UI.button(panel,Rect2(22,174,565,44),"回吧台，照配方做金汤力 →",_proceed,true)
	marker=Control.new()
	marker.mouse_filter=Control.MOUSE_FILTER_IGNORE
	marker.size=size
	add_child(marker)
	marker.draw.connect(_draw_marker)
	shop.opening_purchase_guard=_purchase_reason
	refresh()

func _process(delta: float) -> void:
	clock+=delta
	refresh_clock+=delta
	visible=not is_instance_valid(shop.merchant_dialogue)
	if refresh_clock>.12:
		refresh_clock=0
		refresh()
	marker.queue_redraw()

func refresh() -> void:
	proceed.hide()
	var back: Button=shop.find_child("BackButton",true,false)
	if is_instance_valid(back):
		back.text="← 回工作台" if WorkbenchSession.state.session.get("opening_practice",false) or (supply_report().ready and Relationships.state.flags.get("done:merchant_seed",false)) else "保存并返回开始"
	if not Relationships.state.flags.get("done:merchant_intro",false):
		title.text="01 · 先认识老板娘"
		description.text="这就是港口货栈。\n点击发光的「先认识一下」，听她介绍。\n稍后我们买金酒、汤力水和青柠角。"
		target=shop.topic_button
		return
	var report: Dictionary=supply_report()
	for i in range(report.rows.size()):
		var item: Dictionary=report.rows[i]
		if item.missing<=0: continue
		if current_sku!=item.sku:
			current_sku=item.sku
			shop.focus_item(current_sku)
		title.text="%02d · 买%s" % [i+2,item.name]
		description.text="备料合计 %s %s；库存已有 %s %s。\n买 %d 包就够；下方显示整包价格。\n先备练习＋营业各一杯，购买会进入仓库。" % [WorkbenchSession.format_amount(item.required),item.unit,WorkbenchSession.format_amount(item.remaining),item.unit,item.packages]
		if shop.selected_id!=current_sku:
			target=shop.find_child("Product_"+current_sku,true,false)
			if not is_instance_valid(target):
				proceed.text="定位需要购买的材料"
				proceed.show()
				target=proceed
		elif int(shop.packages)!=int(item.packages):
			target=shop.find_child("QuantityMinus" if shop.packages>item.packages else "QuantityPlus",true,false)
		else: target=shop.buy_button
		return
	if not Relationships.state.flags.get("done:merchant_seed",false):
		title.text="05 · 她还有一句话"
		description.text="材料齐了，不必重复购买。\n点击老板娘的对话按钮，再聊一句。\n多来往、多倾听，也许会听到特别的故事。"
		target=shop.topic_button
		return
	title.text="06 · 带上材料，回吧台"
	description.text="接下来做一杯金汤力。\n这次用高球杯直接调和，不用摇壶。\n真实扣料；做完再确认加入营业酒单。"
	proceed.text="回吧台，照配方做金汤力 →"
	proceed.show()
	target=proceed

func _purchase_reason(sku: String, packages: int) -> String:
	for row: Dictionary in supply_report().rows:
		if row.sku==sku and row.missing>0 and packages<=int(row.packages): return ""
	return "这次先按提示买够练习和营业材料，留好开店预算；开业后可自由采购。"

func supply_report() -> Dictionary:
	var continuing: bool=WorkbenchSession.state.session.get("opening_practice",false)
	return Prep.report("gin_and_tonic",1 if continuing else 2)

func _proceed() -> void:
	if not supply_report().ready:
		shop.focus_item(current_sku)
		refresh()
		return
	if Relationships.state.flags.get("done:merchant_intro",false) and Relationships.state.flags.get("done:merchant_seed",false): ready_to_mix.emit()

func _draw_marker() -> void:
	if not visible or not is_instance_valid(target) or not target.is_visible_in_tree(): return
	var rect: Rect2=get_global_transform_with_canvas().affine_inverse()*target.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,target.size)
	var pulse:=0.7 if OpeningFlow.reduced_motion else .65+.25*sin(clock*3.5)
	var color:=Color(1,.82,.4,pulse)
	marker.draw_rect(rect.grow(5),Color(1,.78,.3,.14),false,10)
	marker.draw_rect(rect.grow(3),color,false,3)
	if target==proceed:
		var tip:=Vector2(rect.position.x-7,rect.get_center().y)
		marker.draw_line(tip-Vector2(38,0),tip-Vector2(14,0),Color("fff0c0"),5)
		marker.draw_colored_polygon(PackedVector2Array([tip,tip+Vector2(-18,-10),tip+Vector2(-18,10)]),Color("ffe1a0"))
		return
	var tip:=Vector2(rect.get_center().x,rect.position.y-8)
	var offset:=0.0 if OpeningFlow.reduced_motion else sin(clock*3.5)*5
	tip.y+=offset
	marker.draw_line(tip-Vector2(0,42),tip-Vector2(0,14),Color("fff0c0"),5)
	marker.draw_colored_polygon(PackedVector2Array([tip,tip+Vector2(-12,-18),tip+Vector2(12,-18)]),Color("ffe1a0"))
