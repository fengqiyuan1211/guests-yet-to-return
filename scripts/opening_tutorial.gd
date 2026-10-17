extends Control
## Observes the real cup; does not fabricate actions, quantities, scores or inventory.
const UI=preload("res://scripts/opening_ui.gd")
const TABLE=preload("res://scripts/workbench_table.gd")
var bench: Control
var step_title: Label
var detail: Label
var targets: Array[Rect2]=[]
var current_key:=""
var pulse:=0.0
var config: Dictionary={}
var gesture := ""
var cue := ""
var cue_detail := ""
var anchors: Array[Vector2]=[]
var gesture_clock := 0.0
var visual_key := ""
var guide_visible := true
var completed_flash := 0.0

func _ready() -> void:
	name="OpeningTutorialGuide"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=80
	size=Vector2(1600,900)
	config=OpeningFlow.tutorial_config()
	var backing:=UI.panel(self,Rect2(22,419,300,105))
	backing.mouse_filter=Control.MOUSE_FILTER_IGNORE
	step_title=UI.label(self,Rect2(30,422,305,36),"",20,Color("ffe0a2"))
	step_title.clip_text=true
	step_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	detail=UI.label(self,Rect2(30,462,294,66),"",17)
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	bench.footer.text="Esc 保存并返回开始界面"
	bench.gold_label.text="独立教学包 · 不扣仓库"

func _process(delta: float) -> void:
	if not WorkbenchSession.tutorial_active or bench.data.is_empty(): return
	if get_window().has_focus():
		pulse+=delta
		gesture_clock+=delta
		completed_flash=maxf(0.0,completed_flash-delta)
	guide_visible=not is_instance_valid(bench.external_page) and (not is_instance_valid(bench.modal) or is_instance_valid(bench.measure))
	visible=guide_visible
	if not guide_visible: return
	# The tutorial banner includes technique timing; keep the ordinary panel from overlapping it.
	bench.technique_panel.hide()
	if bench.data.status=="finished":
		hide()
		targets.clear()
		step_title.text="第一杯已经完成"
		detail.text="这次出品会按实际操作评价。"
		queue_redraw()
		return
	var s: Dictionary=bench.data
	var step:=next_step(s)
	step_title.text=str(step.title)
	detail.text="跟随金色光标操作\n练习材料不足可按 N 重做。"
	if step.key!=current_key and not is_instance_valid(bench.measure) and bench.table.carry_id.is_empty():
		if not current_key.is_empty(): completed_flash=1.3
		current_key=step.key
		if step.has("category"): bench._show_category(step.category)
		_reveal_target.call_deferred(step.get("targets",[]))
	if not is_instance_valid(bench.modal): bench.next_hint.text=step.hint
	targets.clear()
	anchors.clear()
	for id in step.get("targets",[]):
		var rect:=_target_rect(str(id))
		if rect.has_area():
			targets.append(rect.grow(6))
			anchors.append(rect.get_center())
	_update_gesture(step)
	var key:=str(step.key)+":"+gesture
	if key!=visual_key:
		visual_key=key
		gesture_clock=0.0
	queue_redraw()

func _reveal_target(ids: Array) -> void:
	if ids.is_empty() or not bench.item_buttons.has(ids[0]): return
	var button: Control=bench.item_buttons[ids[0]]
	if is_instance_valid(button): bench.pantry_scroll.ensure_control_visible(button)

func _local_rect(control: Control) -> Rect2:
	return get_global_transform_with_canvas().affine_inverse()*control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,control.size)

func _target_rect(id: String) -> Rect2:
	if TABLE.RECTS.has(id): return bench.table._rect(id)
	if bench.item_buttons.has(id):
		var button: Control=bench.item_buttons[id]
		return _local_rect(button).intersection(_local_rect(bench.pantry_scroll))
	return Rect2()

func _update_gesture(step: Dictionary) -> void:
	gesture="drag" if anchors.size()>1 else "click"
	cue="按住鼠标左键，沿光标拖到目标"
	cue_detail="在发光的目标上松开鼠标"
	if step.key=="cup":
		gesture="click"
		if targets.size()>1: targets.resize(1)
		cue="点击右侧发光的碟形杯"
		cue_detail="只需点击选杯，不用拖动"
	elif step.key=="ice":
		cue="把方冰拖进摇壶，共加入 3 份"
		cue_detail="每份 4 块 / 50 g · 已加入 %s / 150 g" % WorkbenchSession.format_amount(WorkbenchSession.ice_mass(bench.data.vessels.shaker))
	elif step.key=="lid":
		cue="把桌上的滤盖拖到摇壶上"
		cue_detail="盖好之后，才能拿起摇和"
	elif step.key=="shake":
		gesture="shake"
		cue="按住摇壶拿起，快速来回摇动"
		var elapsed:=float(bench.table.accumulated)
		for action: Dictionary in bench.data.actions:
			if action.kind=="shake" and action.payload.get("vessel")=="shaker": elapsed+=float(action.payload.seconds)
		cue_detail="有效摇和 %.1f 秒 · 建议 6–10 秒" % elapsed
		if elapsed>=float(config.shake_seconds):
			cue="已摇和到位，松开鼠标"
			cue_detail="下一步：把摇壶拖到成品杯，倒出酒液"
	elif step.key=="muddle":
		cue="轻压棒拖入摇壶，再按住上下拉动"
	elif step.key=="pour":
		cue="把摇壶拖到右上角杯子，再松手"
		cue_detail="滤盖会留下冰块，只倒入酒液"
	elif step.key=="finish":
		gesture="space" if bench.selected=="glass" else "click"
		cue="按空格，完成这杯回响" if gesture=="space" else "点击右上角的成品杯"
		cue_detail="完成后查看这杯酒的真实品质与数值"
	elif str(step.key).begins_with("transfer_"):
		cue="把量酒器拖到摇壶上，再松手"
		cue_detail="把刚量好的酒液倒进去"
	elif str(step.key).begins_with("measure_"):
		cue="把发光的原料拖到量酒器"
		cue_detail="放到量酒器上，会出现用量刻度"
	if is_instance_valid(bench.measure):
		gesture="space"
		var measure: Control=bench.measure
		var close_to_goal: bool=absf(measure.current_ml()-measure.target)<=measure.target*measure.recommended_ratio
		cue="现在按空格！" if close_to_goal else "看刻度，接近红线时按空格"
		cue_detail="目标 %s ml · 当前 %s ml · 停下才会记入用量" % [WorkbenchSession.format_amount(measure.target),WorkbenchSession.format_amount(measure.current_ml())]
		targets.clear()
		anchors.clear()
		var rect:=_local_rect(measure)
		targets.append(rect.grow(5))
		var ratio: float=clampf(measure.target/measure.volume_limit(),0.0,1.0)
		anchors.append(rect.position+Vector2(25+(rect.size.x-50)*ratio,46))
	elif not bench.table.carry_id.is_empty() or (bench.table.dragging and gesture=="drag"):
		gesture="drop"
		cue="拖到发光目标，松开鼠标"
		cue_detail="目标就在金色光圈处"

func next_step(s: Dictionary) -> Dictionary:
	var v: Dictionary=s.vessels
	if s.cup!="coupe": return _step("cup","01 · 选一只杯子","从右侧「杯子」选择碟形鸡尾酒杯，杯子会放到右上角。","杯子",["coupe","glass"])
	# Once a real filtered pour exists, do not ask the player to refill the now empty shaker.
	var poured:=false
	for a in s.actions:
		if a.kind in ["filter","transfer"] and a.payload.get("source")=="shaker" and a.payload.get("vessel")=="glass" and float(a.get("pour",{}).get("ml",0))>0: poured=true
	if poured and WorkbenchSession.amount(v.glass)>0:
		return _step("finish","09 · 留下今天这一杯","点击右上角成品杯，再按空格完成。品质会根据这一杯的实际操作计算。","",["glass"])
	var shake:=0.0
	for action in s.actions:
		if action.kind=="shake" and action.payload.get("vessel")=="shaker": shake+=float(action.payload.seconds)
	# Follow the frozen recipe, including older unfinished tutorial cups.
	var rule: Dictionary=s.recipe.get("quality_rule",{})
	if rule.has("muddle"):
		if float(v.shaker.contents.get("syrup",0))<3.5: return _liquid(s,"syrup",5,"02 · 第一次量取","配料")
		if float(v.shaker.get("solids",{}).get("sku_mint_leaf",0))<4:
			return _step("mint","旧版练习 · 薄荷","这杯保留旧版目标。加入 4 片薄荷；按 N 可重做为新版午夜蓝配方。","配料",["sku_mint_leaf","shaker"])
		var muddle:=0.0
		for action in s.actions:
			if action.kind=="muddle" and action.payload.get("vessel")=="shaker": muddle+=float(action.payload.seconds)
		if muddle<2.0: return _step("muddle","旧版练习 · 轻压","将轻压棒拖到摇壶，按住上下轻拉至有效 2 秒。按 N 可重新准备新版练习。","器具",["muddler","shaker"])
	var index:=2
	for row: Dictionary in s.recipe.get("ingredient_rows",[]):
		if row.get("inventory_unit")!="ml": continue
		var material: String=WorkbenchSession.ITEM_ALIASES.get(row.sku_id,row.sku_id)
		var wanted:=float(row.inventory_amount)
		if float(v.shaker.contents.get(material,0))<wanted*float(config.minimum_fraction):
			return _liquid(s,material,wanted,"%02d · 量取%s" % [index,str(row.name)],"配料" if material in ["lime","syrup"] else "基酒")
		index+=1
	if WorkbenchSession.ice_mass(v.shaker)<float(config.ice_g):
		return _step("ice","06 · 加入制作冰","方冰每份 50 g / 4 块。拖入摇壶共 3 份；现在已有 %s g。" % WorkbenchSession.format_amount(WorkbenchSession.ice_mass(v.shaker)),"冰块",["cube","shaker"])
	if not s.lid:
		return _step("lid","07 · 合上摇壶","点击摇壶后按空格盖好；也可以把桌上的滤盖拖到摇壶上。","",["lid","shaker"])
	if shake<float(config.shake_seconds):
		return _step("shake","08 · 拿起，来回摇","拖起摇壶，快速来回移动。有效摇和 %.1f / %.1f 秒；达到提示后即可停下。" % [shake,float(config.shake_seconds)],"",["shaker"])
	return _step("pour","09 · 看看回响的颜色","把盖好的摇壶拖到右上角杯子，内置滤盖会留下冰块，只倒入酒液。","",["shaker","glass"])

func _liquid(s: Dictionary, material: String, amount: float, title: String, category: String) -> Dictionary:
	var held: float=float(s.vessels.jigger.contents.get(material,0))
	if held>0:
		return _step("transfer_"+material,title,"量酒器中有 %s ml。把量酒器拖到摇壶，将里面的液体倒进去，不会重复扣料。" % WorkbenchSession.format_amount(held),"",["jigger","shaker"])
	var info: Dictionary=WorkbenchSession.MATERIALS[material]
	return _step("measure_"+material,title,"把%s拖到量酒器，接近 %s ml 红线时按空格停止；实际用量按你停下的位置记录。" % [info.name,WorkbenchSession.format_amount(amount)],category,[material,"jigger"])

func _step(key: String,title: String,hint: String,category: String,ids: Array) -> Dictionary:
	var value:={"key":key,"title":title,"hint":hint,"targets":ids}
	if not category.is_empty(): value.category=category
	return value

func _draw() -> void:
	if not guide_visible or anchors.is_empty(): return
	var alpha:=.85 if OpeningFlow.reduced_motion else .78+.2*sin(pulse*4)
	var gold:=Color(1,.81,.36,alpha)
	for rect in targets:
		draw_style_box(_border(Color(1,.76,.25,.13),9),rect.grow(7))
		draw_style_box(_border(gold,3),rect)
	var banner:=Rect2(365,302 if is_instance_valid(bench.measure) else 84,650,108)
	var paper:=StyleBoxFlat.new()
	paper.bg_color=Color("f6e7c8")
	paper.border_color=Color("b98b3e")
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(12)
	paper.shadow_color=Color(0,0,0,.4)
	paper.shadow_size=8
	draw_style_box(paper,banner)
	draw_string(UI.FONT,banner.position+Vector2(20,28),"下一步" if completed_flash<=0 else "✓ 指引已更新",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("826332"))
	draw_string(UI.FONT,banner.position+Vector2(20,60),cue,HORIZONTAL_ALIGNMENT_LEFT,610,27,Color("352416"))
	draw_string(UI.FONT,banner.position+Vector2(20,91),cue_detail,HORIZONTAL_ALIGNMENT_LEFT,610,19,Color("665039"))
	var start:=anchors[0]
	var finish:=anchors[-1]
	var t:=.5 if OpeningFlow.reduced_motion else fmod(gesture_clock,2.6)/2.6
	match gesture:
		"drag":
			_path(start,finish,gold)
			_marker(start,"从这里拿起",gold)
			_marker(finish,"拖到这里松手",gold)
			var travel:=smoothstep(.15,.82,t)
			var cursor:=start.lerp(finish,travel)+Vector2(0,-sin(travel*PI)*55)
			_cursor(cursor,travel>0 and travel<1)
		"drop":
			_marker(finish,"在这里松手",gold)
			var ring:=30.0 if OpeningFlow.reduced_motion else 23.0+12.0*sin(pulse*4)
			draw_arc(finish,ring,0,TAU,48,gold,4,true)
		"click":
			_marker(start,"点击这里",gold)
			draw_arc(start,24+12*t,0,TAU,48,Color(1,.85,.5,1-t*.65),3,true)
			_cursor(start+Vector2(8,9 if OpeningFlow.reduced_motion else 9+sin(pulse*4)*6),false)
		"shake":
			var a:=start+Vector2(-38,30)
			var b:=start+Vector2(38,-85)
			_path(a,b,gold)
			_marker(start+Vector2(0,-110),"按住 · 来回摇",gold)
			var rhythm:=.5 if OpeningFlow.reduced_motion else .5+.5*sin(pulse*8)
			_cursor(a.lerp(b,rhythm),true)
		"space":
			if not is_instance_valid(bench.measure): _marker(start,"已选中成品杯",gold)
			var key_box:=Rect2(690,banner.end.y+14,220,54)
			draw_style_box(paper,key_box)
			draw_string(UI.FONT,key_box.position+Vector2(25,36),"SPACE  空格",HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("352416"))
			if not OpeningFlow.reduced_motion:
				draw_style_box(_border(gold,3),key_box.grow(3+2*sin(pulse*5)))

func _path(start: Vector2, finish: Vector2, color: Color) -> void:
	for i in range(22):
		var a:=float(i)/22
		var b:=a+.025
		var p:=start.lerp(finish,a)+Vector2(0,-sin(a*PI)*55)
		var q:=start.lerp(finish,b)+Vector2(0,-sin(b*PI)*55)
		draw_line(p+Vector2(1,2),q+Vector2(1,2),Color(0,0,0,.6),5,true)
		draw_line(p,q,color,3,true)
	var direction:=(finish-start+Vector2(0,55*PI)).normalized()
	draw_colored_polygon(PackedVector2Array([finish,finish-direction.rotated(.5)*22,finish-direction.rotated(-.5)*22]),color)

func _marker(point: Vector2, text: String, color: Color) -> void:
	var text_size:=UI.FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,19)
	var pos:=Vector2(clampf(point.x-text_size.x*.5,12,1580-text_size.x),maxf(90,point.y-54))
	var box:=_border(color,1)
	box.bg_color=Color("30291f")
	draw_style_box(box,Rect2(pos-Vector2(10,25),text_size+Vector2(20,10)))
	draw_string(UI.FONT,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("ffe6ad"))

func _cursor(point: Vector2, held: bool) -> void:
	var outline:=PackedVector2Array([Vector2.ZERO,Vector2(0,39),Vector2(10,30),Vector2(20,48),Vector2(28,44),Vector2(18,27),Vector2(33,25)])
	var shadow:=PackedVector2Array()
	var points:=PackedVector2Array()
	for p in outline:
		points.append(point+p)
		shadow.append(point+p+Vector2(3,4))
	draw_colored_polygon(shadow,Color(0,0,0,.65))
	draw_colored_polygon(points,Color("ffda79") if held else Color("fff8e5"))
	points.append(points[0])
	draw_polyline(points,Color("6c4721"),2,true)
	if held: draw_arc(point,16,0,TAU,32,Color("ffda79"),3,true)

func _border(color: Color, width:=2) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=Color.TRANSPARENT
	box.border_color=color
	box.set_border_width_all(width)
	box.set_corner_radius_all(12)
	return box
