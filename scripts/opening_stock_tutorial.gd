extends "res://scripts/opening_tutorial.gd"
## Real-stock lesson: observes the same live vessels and uses ordinary workbench inputs.
const Evaluation=preload("res://scripts/workbench_evaluation.gd")

func _rule(s: Dictionary) -> Dictionary:
	var model: Dictionary=s.get("quality_model",bench.evaluation_model)
	return s.recipe.get("quality_rule",model.rules.get("gin_and_tonic",{}))

func _stirred(s: Dictionary) -> float:
	return float(Evaluation.replay(s.actions,_rule(s),WorkbenchSession.MATERIALS,"glass").get("min_seconds",0))

func _ready() -> void:
	stock_lesson=true
	super._ready()
	bench.footer.text="Esc 回酒馆 · 做完后交给米洛" if OpeningFlow.first_service_pending() else "Esc 回货栈 · 半成品自动保留"
	bench._update_stock_ui()

func next_step(s: Dictionary) -> Dictionary:
	var glass: Dictionary=s.vessels.glass
	if s.cup!="highball": return _step("cup","01 · 高球杯","点击右侧高球杯。金汤力在成品杯里直接调制。","杯子",["highball","glass"])
	if WorkbenchSession.ice_mass(glass)<150:
		return _step("ice","02 · 加入 3 份方冰","把方冰拖入高球杯，共 3 份。每份 4 块 / 50 g，总计 150 g。","冰块",["cube","glass"])
	for row: Dictionary in s.recipe.ingredient_rows:
		if row.get("inventory_unit")!="ml": continue
		var material: String=WorkbenchSession.ITEM_ALIASES.get(row.sku_id,row.sku_id)
		var goal:=float(row.inventory_amount)
		if float(glass.contents.get(material,0))>=goal*.8: continue
		for vessel in ["jigger","mixing","shaker"]:
			if float(s.vessels[vessel].contents.get(material,0))>0:
				if vessel=="shaker" and s.lid: return _step("stock_open","打开摇壶","点击摇壶，再按空格打开盖子。","",["shaker"])
				return _step("transfer_stock","倒入高球杯","把装有材料的容器拖到右上角高球杯，松手倒入。","",[vessel,"glass"])
		# Tonic exceeds a jigger's capacity. Direct pouring is intentionally judged by eye.
		var destination: String="jigger" if material=="gin" else "glass"
		return _step("measure_stock" if material=="gin" else "tonic","03 · 加入"+str(row.name),"把金酒拖到量酒器，接近 50 ml 红线时按空格。" if material=="gin" else "汤力水直接拖到高球杯。凭液面判断，按空格停下；目标约 150 ml，倒完查看实际量。","基酒" if material=="gin" else "配料",[material,destination])
	var window: Array=_rule(s).get("time_window",[3,6])
	var stirred:=_stirred(s)
	if stirred<float(window[0]):
		if s.get("spoon_vessel","")!="glass": return _step("spoon","04 · 轻轻调和","从器具把吧勺拖入高球杯。轻搅即可，不要摇和气泡饮料。","器具",["spoon","glass"])
		return _step("stir","04 · 轻搅 %s–%s 秒" % [window[0],window[1]],"按住杯中的吧勺，轻轻画圈。有效轻搅 %.1f / %s 秒，够了就松手。" % [stirred,window[0]],"",["glass"])
	if s.get("spoon_vessel","")=="glass": return _step("remove_spoon","收回吧勺","点击杯中露出的吧勺，让它自动收回。","",["glass"])
	if not WorkbenchSession.garnishes(glass).has("garnish"):
		return _step("garnish","05 · 一角青柠","把装饰菜单里的青柠角拖到高球杯，一块即可。","装饰",["garnish","glass"])
	return _step("finish","06 · 看看这杯金汤力","点击成品杯，再按空格完成。查看品质后点击「交给米洛」或按空格交付。" if OpeningFlow.first_service_pending() else "点击成品杯，再按空格完成。查看品质后确认加入今晚酒单。","",["glass"])

func _update_gesture(step: Dictionary) -> void:
	super._update_gesture(step)
	if is_instance_valid(bench.measure):
		if not bench.measure.precise:
			cue="观察杯中液面，点击停止或按空格"
			cue_detail="直倒没有实时刻度；停止后会告诉你实际倒入多少"
		return
	if gesture=="drop": return
	match str(step.key):
		"cup": cue="点击右侧发光的高球杯"
		"ice":
			cue="把方冰拖进高球杯，共 3 份"
			cue_detail="每份 4 块 / 50 g · 已加入 %s / 150 g" % WorkbenchSession.format_amount(WorkbenchSession.ice_mass(bench.data.vessels.glass))
		"transfer_stock": cue="把装有酒液的容器拖到高球杯"
		"tonic":
			cue="把汤力水直接拖到高球杯"
			cue_detail="目标约 150 ml，凭液面判断，按空格停止"
		"spoon":
			cue="把吧勺拖进高球杯"
			cue_detail="只需轻搅，让酒液混合，保留气泡"
		"stir":
			gesture="stir"
			cue="按住杯中吧勺，轻轻画圈"
			var elapsed:=_stirred(bench.data)+float(bench.table.accumulated)
			var window: Array=_rule(bench.data).get("time_window",[3,6])
			cue_detail="有效轻搅 %.1f 秒 · 建议 %s–%s 秒" % [elapsed,window[0],window[1]]
			if elapsed>=float(window[0]): cue="已经轻搅到位，松开鼠标"
		"remove_spoon":
			cue="点击杯中露出的吧勺，自动收回"
			cue_detail="下一步：在杯沿放一角青柠"
		"garnish":
			cue="把青柠角拖到高球杯"
			cue_detail="一块即可；这次会消耗仓库中的材料"
