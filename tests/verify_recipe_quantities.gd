extends "res://tests/verify_research.gd"
const Q=preload("res://scripts/recipe_quantities.gd")
const Detail=preload("res://scripts/cocktail_detail.gd")

func run() -> void:
	var records:=CocktailDatabase.list_cocktails()
	records.append_array(Research.config().legendary_recipes)
	for recipe in records:
		for row in recipe.ingredients:
			check(row.unit==row.inventory_unit and row.amount==row.inventory_amount,"canonical quantity matches inventory "+recipe.id+":"+row.sku_id)
			check(row.unit in ["ml","g","piece","sprig"],"supported quantity "+recipe.id)
		for row in recipe.ice:
			check(row.kind in ["cube","crushed"] and row.unit=="g" and row.use in ["制作冰","出品冰"],"explicit ice contract "+recipe.id)
			check(row.inventory_policy=="excluded_from_ingredient_inventory","ice remains outside stock "+recipe.id)
		var session:={"recipe":{"ingredients":{},"ingredient_rows":recipe.ingredients,"ice":recipe.ice},"vessels":{}}
		var note:=WorkbenchSession.recipe_note(session)
		check(not "dash" in note and not "piece" in note and not "sprig" in note,"workbench uses readable units "+recipe.id)
	check(Q.amount_text({"amount":1,"unit":"dash","inventory_amount":1,"inventory_unit":"ml"})=="1 ml","legacy dash display uses established conversion")
	check(Q.amount_text({"amount":2,"unit":"piece","name":"薄荷叶"})=="2 片","mint leaves")
	check(Q.amount_text({"amount":1,"unit":"sprig","name":"薄荷枝"})=="1 枝","mint sprig")
	check(Q.amount_text({"amount":1,"unit":"piece","name":"鸡尾酒樱桃"})=="1 颗","cherry")
	check(Q.amount_text({"amount":1,"unit":"piece","name":"青柠角"})=="1 块","lime wedge")
	var mojito:=MenuCatalog.get_recipe("mojito")
	var picture:=Research.preview_result(mojito)
	check(picture.contents.ice=="crushed","Mojito preview preserves crushed ice")
	check(Research.preview_result(MenuCatalog.get_recipe("echo_world")).contents.ice=="none","tutorial production ice does not appear in serving glass")
	op("begin_research",{"mode":"research_diy"});op("cup",{"cup":"highball"})
	op("withdraw",{"material":"gin","ml":30,"vessel":"glass"})
	op("garnish",{"material":"garnish","vessel":"glass"})
	op("ice",{"ice":"crushed","vessel":"glass"});op("ice",{"ice":"crushed","vessel":"glass"});op("finish")
	op("save_research",{"name":"单位核对","english_name":"Units","notes":""})
	var record: Dictionary=WorkbenchSession.research_recipes()[0]
	check(Research.valid(WorkbenchSession.research_state()),"new DIY passes save validation")
	check(record.ice.size()==1 and record.ice[0].amount==100 and record.ice[0].kind=="crushed" and record.ice[0].use=="出品冰","DIY ice batches aggregate with correct type and stage")
	for row in record.ingredients: check(row.unit==row.inventory_unit,"DIY uses stock units even for garnishes")
	var legacy:=record.duplicate(true)
	legacy.ice=[{"name":"碎冰","amount":50,"unit":"g"},{"name":"碎冰","amount":50,"unit":"g"}]
	var normalized:=Q.recipe(legacy)
	check(normalized.ice.size()==1 and normalized.ice[0].kind=="crushed" and legacy.ice.size()==2,"legacy DIY adapts without rewriting historical record")
	var note:=WorkbenchSession.recipe_note({"recipe":{"ingredients":{},"ingredient_rows":record.ingredients,"ice":legacy.ice},"vessels":{}})
	check("出品冰 · 碎冰 100 g（2 份）" in note,"legacy crushed recipe never shows cube count")
	print("RECIPE QUANTITIES: %d checks, %d failures" % [count,failures.size()]);get_tree().quit(0 if failures.is_empty() else 1)
