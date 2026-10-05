extends Control
const Preview=preload("res://scripts/workbench_drink_preview.gd")
const PAPER=preload("res://assets/codex/journal-paper-v1.png")
const FONT=preload("res://assets/fonts/NotoSerifSC.ttf")
const KEYS=["alcohol_intensity","sweetness","sourness","bitterness"]
const LABELS=["酒感","甜度","酸度","苦度"]
var result: Dictionary={}
var preview: Control

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var evaluation: Dictionary=result.get("evaluation",{})
	var accent:=Color(str(evaluation.get("color","8c9aa2")))
	_label(Rect2(28,2,360,58),str(evaluation.get("title","旧记录 · 未评级")),38,accent.darkened(.28))
	_label(Rect2(385,17,490,42),str(result.get("recipe",{}).get("name","这一杯")),28,Color("493523"))
	_label(Rect2(387,60,520,28),str(result.get("recipe",{}).get("english_name","")),18,Color("816b4d"))
	preview=Preview.new()
	preview.position=Vector2(10,70)
	preview.size=Vector2(338,376)
	preview.result=result
	preview.accent=accent
	preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(preview)
	var amount:=WorkbenchSession.amount(result.get("contents",{"contents":{}}))
	_label(Rect2(22,450,310,32),"实际出品 %s ml" % WorkbenchSession.format_amount(amount),21,Color("493523"),true)
	_label(Rect2(380,107,540,28),"试调揭晓 / 实际成品属性" if not evaluation.get("has_target",true) else "实际属性  /  短线为配方目标",18,Color("816b4d"))
	if evaluation.is_empty():
		_label(Rect2(382,158,530,210),"这杯完成于评价系统接入之前。\n保留原成品与制作记录，不按新规则追溯打分。",22,Color("574332"))
	else:
		for i in range(4):
			var y:=147+i*53
			_label(Rect2(382,y,75,34),LABELS[i],22,Color("493523"))
			_label(Rect2(826,y,58,34),str(roundi(float(evaluation.attributes[KEYS[i]]))),24,Color("493523"))
			if evaluation.get("has_target",true): _label(Rect2(884,y+4,92,30),"目标 %s" % str(roundi(float(evaluation.targets[KEYS[i]]))),16,Color("816b4d"))
		for i in range(mini(2,evaluation.tags.size())):
			var tag: Dictionary=evaluation.tags[i]
			_label(Rect2(393+i*178,370,160,36),tag.text,21,Color(str(tag.color)).darkened(.35),true)
		var score: Variant=evaluation.get("score")
		_label(Rect2(382,420,580,32),("品质 %d / 100" % int(score)) if score!=null else "自由试调 · 记录这一杯的味道",24,accent.darkened(.25))
		var subs: Dictionary=evaluation.subscores
		_label(Rect2(382,458,580,28),"风味印象 · 试调记录" if not evaluation.get("has_target",true) else "配方 %d   ·   制作 %d   ·   出品 %d" % [subs.recipe,subs.process,subs.finish],18,Color("816b4d"))
		for i in range(mini(3,evaluation.reasons.size())):
			_label(Rect2(28,503+i*29,920,28),"· "+str(evaluation.reasons[i]),18,Color("574332"))
	_label(Rect2(28,599,922,26),"试玩参数 · 四项属性 0—100 · 酒感不等于 ABV · R 查看全部依据",16,Color("816b4d"))

func _label(rect: Rect2, text: String, size_px: int, color: Color, centered:=false) -> Label:
	var label:=Label.new()
	label.position=rect.position
	label.size=rect.size
	label.text=text
	label.tooltip_text=text
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",size_px)
	label.add_theme_color_override("font_color",color)
	label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter=Control.MOUSE_FILTER_PASS
	add_child(label)
	return label

func _draw() -> void:
	var evaluation: Dictionary=result.get("evaluation",{})
	if evaluation.is_empty(): return
	var colors: Array[Color]=[Color("b38061"),Color("c49a4f"),Color("90a25d"),Color("8a7162")]
	for i in range(4):
		var y:=165+i*53
		draw_style_box(_bar(Color("d7c4a1")),Rect2(466,y,340,11))
		var value:=float(evaluation.attributes[KEYS[i]])
		if value>0: draw_style_box(_bar(colors[i]),Rect2(466,y,340*value/100,11))
		var reference:=clampf(float(evaluation.targets[KEYS[i]]),0,100)
		var x:=466+340*reference/100
		if evaluation.get("has_target",true): draw_line(Vector2(x,y-5),Vector2(x,y+16),Color("554330"),2,true)
	for i in range(mini(2,evaluation.tags.size())):
		var color:=Color(str(evaluation.tags[i].color))
		draw_style_box(_bar(Color(color,.18)),Rect2(385+i*178,369,168,36))

func _bar(color: Color) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=color
	style.set_corner_radius_all(5)
	return style
