extends "res://tests/verify_workbench_drag.gd"
const Appearance=preload("res://scripts/workbench_liquid_appearance.gd")
const LiquidVisual=preload("res://scripts/workbench_liquid.gd")
const ShapeVisual=preload("res://scripts/workbench_vessel_shape.gd")
const Preview=preload("res://scripts/workbench_drink_preview.gd")

func new_cup() -> void:
	if WorkbenchSession.state.session.get("status")=="mixing": bench._issue("discard")
	check(bench._issue("start"),"new cup")
	bench._issue("cup",{"cup":"highball"})
	bench.table.animation_progress=1
	bench.table.animated_source=""
	bench.table.lift_blend=0
	bench.table.stop_gesture()
	bench._set_technique("shake")

func pour(source: String, target: String) -> void:
	var rect: Rect2=bench.table._rect(source)
	drag_between(local_point(rect.position+rect.size*Vector2(.5,.8)),local_point(bench.table.POS[target]))

func run() -> void:
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	for source in ["glass","jigger","shaker","mixing"]:
		for target in ["glass","jigger","shaker","mixing"]:
			if source==target: continue
			new_cup()
			check(bench._issue("withdraw",{"material":"gin","ml":10,"vessel":source}),"fill "+source)
			var stock: float=WorkbenchSession.remaining("gin")
			pour(source,target)
			var s: Dictionary=WorkbenchSession.state.session
			check(s.vessels[target].contents.get("gin")==10 and s.vessels[source].contents.is_empty(),"native drag "+source+" -> "+target)
			check(WorkbenchSession.remaining("gin")==stock,"transfer never consumes warehouse stock twice")
			check(s.actions.back().kind=="transfer" and s.actions.back().payload.vessel==target,"actual target is logged")
			check(WorkbenchSession._valid(WorkbenchSession.state),"new direction preserves valid save")
			if source=="glass" and target=="mixing":
				bench.table.set_process(false)
				bench.table.animation_progress=.45
				bench.table.queue_redraw()
				await capture("vessels-01-glass-back-to-mixing")
				bench.table.set_process(true)
	for target in ["glass","mixing","jigger"]:
		new_cup()
		bench._issue("withdraw",{"material":"gin","ml":20,"vessel":"shaker"})
		bench._issue("ice",{"ice":"cube","vessel":"shaker"})
		bench._issue("lid")
		pour("shaker",target)
		var s: Dictionary=WorkbenchSession.state.session
		check(s.vessels[target].contents.get("gin")==20 and WorkbenchSession.ice_mass(s.vessels.shaker)==50 and WorkbenchSession.ice_mass(s.vessels[target])==0,"closed shaker filters into "+target)
		check(s.actions.back().kind=="filter" and s.actions.back().payload.integrated_strainer,"integrated strainer logged for "+target)
		bench.table.animation_progress=.4
		check(not bench.table.shaker_pour_pose().is_equal_approx(Transform2D.IDENTITY),"shaker pour pose supports "+target)
		if target=="mixing":
			bench.table.set_process(false)
			bench.table.queue_redraw()
			await capture("vessels-02-shaker-to-mixing")
			bench.table.set_process(true)
	new_cup()
	bench._issue("withdraw",{"material":"gin","ml":80,"vessel":"glass"})
	bench._issue("withdraw",{"material":"gin","ml":60,"vessel":"jigger"})
	var stock_before: float=WorkbenchSession.remaining("gin")
	pour("glass","jigger")
	var session: Dictionary=WorkbenchSession.state.session
	check(session.vessels.jigger.contents.gin==90 and session.vessels.glass.contents.gin==50,"small receiving vessel fills and remainder stays in source")
	check(WorkbenchSession.remaining("gin")==stock_before,"partial pour never debits stock")
	var action: Dictionary=session.actions.back().duplicate(true)
	var before:=WorkbenchSession.snapshot()
	check(WorkbenchSession.command(action.command_id,session.id,action.kind,action.payload) and WorkbenchSession.snapshot()==before,"repeat transfer receipt is idempotent")
	pour("glass","jigger")
	check(WorkbenchSession.snapshot()==before,"full receiver does not lose source liquid")
	new_cup()
	bench._issue("withdraw",{"material":"lime","ml":30,"vessel":"mixing"})
	bench._issue("ice",{"ice":"cube","vessel":"mixing"})
	pour("mixing","jigger")
	check(WorkbenchSession.state.session.vessels.jigger.contents.get("lime")==30 and WorkbenchSession.ice_mass(WorkbenchSession.state.session.vessels.jigger)==50,"unfiltered transfer to jigger retains liquid and ice")
	check(WorkbenchSession._valid(WorkbenchSession.state),"ice in small vessel remains capacity-valid")
	new_cup()
	bench._issue("withdraw",{"material":"lime","ml":20,"vessel":"glass"})
	bench._issue("lid")
	before=WorkbenchSession.snapshot()
	pour("glass","shaker")
	check(WorkbenchSession.snapshot()==before,"closed receiving shaker must be opened")
	bench._issue("lid")
	before=WorkbenchSession.snapshot()
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/blocked.json"
	pour("glass","shaker")
	check(WorkbenchSession.snapshot()==before,"write failure rolls back both vessels")
	Supplies.save_path=path
	var profiles:=Appearance.profiles()
	check(profiles.size()==16 and Appearance.valid_snapshot(profiles),"all 16 catalog liquids configured")
	for id in profiles:
		var color: Color=Appearance.sample({id:100},profiles).color
		check(color.a>=.15 and color.a<=.82,"transparent bounded opacity for "+id)
		check(profiles[id].has("reference_note") and profiles[id].has("color_basis"),"color provenance for "+id)
	var orange: Color=Appearance.sample({"sku_cointreau":30},profiles).color
	var pink: Color=Appearance.sample({"sku_maraschino":30},profiles).color
	check(orange.r>.9 and orange.g>.5 and orange.b<.3,"Cointreau uses bright orange art direction")
	check(pink.r>.9 and pink.b>pink.g and pink.g>.45,"Maraschino uses translucent pink art direction")
	check(Appearance.sample({"gin":90,"sku_cointreau":30},profiles).color.a<orange.a,"clear spirit dilutes tint without becoming opaque white")
	check(float(Appearance.rendering().bottom_darken)<.18,"bottom shading is brighter than previous renderer")
	var legacy:=WorkbenchSession.snapshot()
	legacy.session.liquid_profiles.sku_cointreau={"version":"appearance-playtest-1","rgb":[230,242,247],"strength":0,"turbidity":0}
	check(WorkbenchSession._commit(legacy),"legacy active palette fixture")
	before=WorkbenchSession.snapshot()
	check(bench._issue("refresh_appearance"),"active palette refresh")
	check(WorkbenchSession.state.session.vessels==before.session.vessels and WorkbenchSession.state.session.actions==before.session.actions and WorkbenchSession.state.session.consumed==before.session.consumed,"palette refresh does not change facts, actions or consumption")
	check(WorkbenchSession.state.session.liquid_profiles==profiles,"active palette receives current configuration")
	check(Supplies.load_state() and WorkbenchSession.load_state(),"transferred contents and refreshed colors restore")
	for id in profiles:
		check((Appearance.carbonation({id:100},profiles)>0)==(id in ["sku_soda_water","sku_tonic_water","sku_cola"]),"only carbonated drinks fizz: "+id)
	check(is_equal_approx(Appearance.carbonation({"soda":50,"gin":50},profiles),.5),"dilution reduces carbonation by liquid volume")
	check(Appearance.carbonation({"sku_tonic_water":100},{"sku_tonic_water":{"rgb":[255,255,255]}})>.8,"legacy snapshots retain tonic bubbles")
	var invalid:=profiles.duplicate(true)
	invalid.sku_soda_water.carbonation=2
	check(not Appearance.valid_snapshot(invalid),"invalid carbonation snapshot rejected")
	for shape in ["highball","mixing","coupe","glass_cocktail_glass","glass_balloon_glass"]:
		var rect:=Rect2(0,0,180,280)
		var body:=ShapeVisual.body(rect,shape,ShapeVisual.surface(shape,.65))
		var a:=LiquidVisual.bubble_samples(body,rect,1.0,1)
		var b:=LiquidVisual.bubble_samples(body,rect,1.5,1)
		check(a.size()>5 and a!=b,"visible moving bubbles in "+shape)
		var inside:=true
		for bubble in a:
			for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
				inside=inside and Geometry2D.is_point_in_polygon(bubble.point+direction*(bubble.radius+1),body)
		check(inside,"bubble bounds contained by "+shape)
		check(LiquidVisual.bubble_samples(body,rect,1,0).is_empty(),"still liquids have no particles")
	new_cup()
	check(bench._issue("withdraw",{"material":"soda","ml":220,"vessel":"glass"}),"carbonated tabletop glass")
	check(bench._issue("withdraw",{"material":"soda","ml":180,"vessel":"mixing"}),"carbonated tabletop mixing vessel")
	await get_tree().create_timer(1.1).timeout
	before=WorkbenchSession.snapshot()
	await capture("vessels-03-carbonated-workbench")
	check(WorkbenchSession.snapshot()==before,"animated bubbles never change saved cup state")
	await palette_gallery(profiles)
	print("VESSEL TRANSFERS AND COLORS: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)

func palette_gallery(profiles: Dictionary) -> void:
	var ids: Array=profiles.keys()
	for page in range(2):
		var gallery:=Control.new()
		gallery.size=Vector2(1600,900)
		bench.surface.add_child(gallery)
		var bg:=ColorRect.new()
		bg.size=gallery.size
		bg.color=Color("241b17")
		gallery.add_child(bg)
		bench._text(gallery,Rect2(45,22,1490,48),"液体颜色检查 · %d / 2 · 原生 Godot 成品渲染" % (page+1),30)
		for i in range(8):
			var id: String=ids[page*8+i]
			var origin:=Vector2(24+(i%4)*393,85+(i/4)*397)
			var preview:=Preview.new()
			preview.position=origin
			preview.size=Vector2(380,350)
			preview.result={"contents":{"contents":{id:240.0}},"cup":"highball","capacity_ml":350,"liquid_profiles":profiles}
			gallery.add_child(preview)
			var label: Label=bench._text(gallery,Rect2(origin+Vector2(10,350),Vector2(363,35)),str(Supplies.get_item(id).name),21)
			label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		await settle()
		await capture("vessels-colors-%02d" % (page+1))
		gallery.queue_free()
		await settle()
