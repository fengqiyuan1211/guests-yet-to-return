extends RefCounted

const DESCRIPTIONS := {
	"jigger": "量酒器｜精确量取\n把酒或液体配料拖到量酒器，观察刻度，按空格停止。量好后拖到容器倒入；转移不会再次扣库存。",
	"shaker": "摇壶｜摇和与出酒\n先加入材料和冰，再盖好壶盖；按住拿起，快速来回移动鼠标摇和。拖到成品杯出酒：盖好时通过内置滤网只出液体，打开时全部倒入。",
	"mixing": "搅拌杯｜搅拌与直倒\n拖入吧勺，按住杯口或勺柄移动鼠标，自动转圈，移动越快搅拌越快。拖杯身下半部到成品杯会连冰和配料一起倒入；拖滤冰器到杯上则只倒酒液。",
	"spoon": "吧勺｜自动搅拌\n拖到杯口插入，按住杯口或勺柄移动鼠标控制转速，无需画圆。松手暂停；单击露出的勺柄收回。",
	"strainer": "滤冰器｜只倒酒液\n拖到搅拌杯或打开的摇壶，酒液自动过滤到成品杯，冰和固体配料留在原容器。杯满即停，余量留在原容器。",
	"muddler": "捣棒｜轻压配料\n拖到装有配料的制作容器，按住上下移动鼠标轻压。薄荷不宜过度捣碎，可参考上方力度和时长提示。",
	"lid": "摇壶盖｜封好再摇\n拖到壶口或点击开合，也可选中摇壶后按空格。盖好才能摇和；盖内滤网让出酒时留下冰和配料。",
	"cap": "顶盖｜封住摇壶\n与壶盖一起开合，拖到壶口或点击操作。出酒时会自动打开顶盖，通过内置滤网倒入成品杯。",
	"glass": "成品杯｜盛酒与出杯\n酒和材料可以直接拖入。更换杯型：点击右侧杯子菜单里的杯型。制作完成后选中杯子按空格，或拖到出杯区。",
}

static func description(id: String) -> String:
	if DESCRIPTIONS.has(id): return DESCRIPTIONS[id]
	if WorkbenchSession.CUPS.has(id):
		return "%s｜成品杯\n点击即可替换桌上的杯子，保留杯内材料。试玩容量：%s ml；装不下时保留原杯。" % [{"rocks":"平底杯","coupe":"碟形杯","highball":"高球杯","glass_cocktail_glass":"鸡尾酒杯","glass_balloon_glass":"球形杯"}.get(id,id),WorkbenchSession.format_amount(WorkbenchSession.CUP_CAPACITIES[id])]
	return ""

static func popup(text: String) -> Control:
	if text.strip_edges().is_empty(): return null
	var panel:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("f3e1be")
	style.border_color=Color("967344")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel",style)
	var label:=Label.new()
	label.custom_minimum_size.x=330
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.text=text
	label.add_theme_font_override("font",preload("res://assets/fonts/NotoSerifSC.ttf"))
	label.add_theme_font_size_override("font_size",19)
	label.add_theme_color_override("font_color",Color("49321f"))
	panel.add_child(label)
	return panel
