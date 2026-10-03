extends "res://tests/verify_workbench_scene.gd"
const Shape=preload("res://scripts/workbench_vessel_shape.gd")
const Liquid=preload("res://scripts/workbench_liquid.gd")
const Ice=preload("res://scripts/workbench_ice.gd")
const CUPS=["coupe","glass_cocktail_glass","glass_balloon_glass","highball","mixing"]

class Gallery extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("493c31"))
		for row in range(2):
			for column in range(5):
				var id: String=CUPS[column]
				var texture:=Art.texture(id)
				var extent:=texture.get_size()*minf(260.0/texture.get_width(),320.0/texture.get_height())
				var rect:=Rect2(Vector2(column*320+160-extent.x*.5,row*440+60),extent)
				var contents: Dictionary={"lime":12 if row==0 else 84}
				if id!="mixing": Liquid.draw(self,rect,contents,120,false,0,false,0,false,1,id)
				draw_texture_rect(texture,rect,false)
				if id=="mixing": Liquid.draw(self,rect,contents,120,false,0,false,0,true,1,id)
				draw_string(ThemeDB.fallback_font,Vector2(column*320+15,row*440+30),id+ (" 10%" if row==0 else " 70%"),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("edd9b6"))

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func run() -> void:
	for id in CUPS:
		var p:=Shape.profile(id)
		var last:=1.0
		for fraction in [.001,.01,.1,.3,.5,.7,.9,1.0]:
			var y:=Shape.surface(id,fraction)
			check(y<last and y>=p.walls.front().x and y<=p.walls.back().x,"volume raises surface within bowl: %s %s" % [id,fraction])
			last=y
			var body:=Shape.body(Rect2(0,0,200,240),id,y)
			check(not Geometry2D.triangulate_polygon(body).is_empty(),"valid liquid mesh at tiny and full doses: %s %s" % [id,fraction])
			var outside:=0.0
			for polygon in Geometry2D.clip_polygons(body,Shape.cavity(Rect2(0,0,200,240),id)):
				var area:=0.0
				for i in range(polygon.size()): area+=polygon[i].cross(polygon[(i+1)%polygon.size()])
				outside+=absf(area)*.5
			# Polygon clipping uses quantized coordinates; allow subpixel slivers only.
			check(outside<.02,"liquid stays inside art cavity: %s %s" % [id,fraction])
		check(Liquid.surface_fraction(30,120,false,true,false,1,id)<Liquid.surface_fraction(30,120,false,false,false,1,id),"ice displacement raises shared surface: "+id)
	check(Shape.radius("glass_balloon_glass",.23)>Shape.radius("glass_balloon_glass",.065),"balloon widens below its rim")
	check(Shape.radius("glass_balloon_glass",.46)<Shape.radius("glass_balloon_glass",.23),"balloon rounds in toward stem")
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	bench._issue("withdraw",{"material":"lime","ml":60,"vessel":"glass"})
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	for cup in WorkbenchSession.CUPS:
		bench._act("cup",{"cup":cup})
		bench._issue("spoon",{"target":"glass"})
		await settle()
		check(WorkbenchSession.amount(bench.data.vessels.glass)==60 and WorkbenchSession.state.stock==stock,"cup profile changes appearance only: "+cup)
		var spoon: Dictionary=bench.table.spoon_geometry()
		check(not spoon.is_empty() and bench.table._hit(spoon.handle)=="spoon","spoon remains reachable: "+cup)
		await capture("61-shaped-"+cup)
	bench._act("ice",{"vessel":"glass","ice":"cube"})
	await get_tree().create_timer(1.8).timeout
	await capture("62-shaped-balloon-ice")
	bench._issue("finish")
	bench._result()
	await capture("64-shaped-result-card")
	home.hide()
	var gallery:=Gallery.new()
	gallery.size=Vector2(1600,900)
	add_child(gallery)
	await capture("63-cup-shapes-low-high")
	gallery.queue_free()
	home.queue_free()
	await settle()
	print("VESSEL SHAPE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
