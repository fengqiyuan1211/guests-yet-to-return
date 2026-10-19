extends Control
const ToolHelp=preload("res://scripts/workbench_tool_help.gd")
## First-person artwork; interaction hit areas are tied to movable independent sprites.
signal item_grabbed(id: String)
signal vessel_selected(id: String)
signal prop_selected(id: String)
signal transfer_requested(source: String, destination: String)
signal spoon_remove_requested
signal muddle_contact(pressure: float)
signal motion_completed(kind: String, seconds: float)
signal empty_requested(vessel: String)
signal serve_requested
signal item_dropped(tab: String, id: String, target: String, dragged: bool)
const ShakeGesture=preload("res://scripts/workbench_shake_gesture.gd")
const Liquid = preload("res://scripts/workbench_liquid.gd")
const Garnish = preload("res://scripts/workbench_garnish.gd")
const Mint = preload("res://scripts/workbench_mint.gd")
const Ice = preload("res://scripts/workbench_ice.gd")
const Art = preload("res://scripts/workbench_art.gd")
const POS := {"jigger": Vector2(738,665), "shaker": Vector2(465,615), "mixing": Vector2(220,585), "glass": Vector2(1122,405)}
const NAMES := {"jigger":"量酒器","shaker":"三件式摇壶","mixing":"搅拌杯","glass":"成品杯","lid":"摇壶滤盖","cap":"摇壶顶盖","spoon":"吧勺","strainer":"滤冰器","muddler":"轻压棒","bottle":"取用的材料"}
const RECTS := {
	"mixing":Rect2(145,525,150,230), "glass":Rect2(1030,330,185,240),
	"shaker":Rect2(375,535,180,260), "jigger":Rect2(695,625,85,150),
	"lid":Rect2(560,535,100,85), "cap":Rect2(563,630,48,38),
	"spoon":Rect2(292,535,35,205), "strainer":Rect2(1090,720,130,130),
	"muddler":Rect2(1160,535,66,180)
}
var materials: Array = []
var material_origins: Dictionary={}
var retired_materials: Array=[]
var material_transition:=1.0
var materials_initialized:=false
var carry_id := ""
var carry_tab := ""
var carry_start := Vector2.ZERO
var carry_point := Vector2.ZERO
var drop_target := ""
var preview_amount := 0.0
var pour_blend := 0.0
var transition_from: Dictionary = {}
var transition_layers: Dictionary={}
const LiquidState=preload("res://scripts/workbench_liquid_state.gd")
var transition_progress := 1.0
var animated_destination := ""
var effects: Dictionary = {}
var ice_effects: Dictionary = {}
var ice_batch_effects: Dictionary = {}
var garnish_effects: Dictionary = {}
var mint_effects: Dictionary = {}
var mint_display: Dictionary={}
var shake_trail: Array = []
var clock := 0.0
var selected := ""
var technique := "shake"
var spoon_pressed := false
var spoon_moved := false
var stir_origin := Vector2.ZERO
var stir_angle := 0.0
var stir_energy := 0.0
var stir_rate:=0.0
var stir_pointer_time:=-10.0
var motion_energy := 0.0
var pointer_speed:=0.0
var control_integral:=0.0
var pressure_integral:=0.0
var muddle_down_played:=false
var muddler_vessel:=""
var muddle_gripped:=false
var muddle_depth:=0.5
var last_motion_time := -10.0
var returning_spoon: Dictionary = {}
var spoon_change_time := -10.0
var data: Dictionary = {}
var bottle := ""
var pouring := false
var pour_vessel := "jigger"
var moving_glass := false
var moving_shaker := false
var moving_mixing:=false
var mixing_pour_offset:=Vector2.ZERO
var released_shaker_pose := Transform2D.IDENTITY
var shaker_pour_start := Transform2D.IDENTITY
const DRAIN_RECT := Rect2(26,758,288,54)
var drain_flash := 0.0
const SERVE_RECT := Rect2(1005,660,220,90)
var input_enabled := true
var hover := ""
var dragging := false
var last_point := Vector2.ZERO
var press_point := Vector2.ZERO
var last_tick := 0
var accumulated := 0.0
var shake_direction := 0
var shake_gesture=ShakeGesture.new()
var shaker_offset:=Vector2.ZERO
var travel := 0.0
var movement := Vector2.ZERO
var lift_blend := 0.0
var shake_depth := 0.0
var depth_target := 0.0
var animated_source := ""
var animation_progress := 0.0
var _font: Font = preload("res://assets/fonts/NotoSerifSC.ttf")
var background: Texture2D
var lighting: TextureRect

func _init() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _ready() -> void:
	if ResourceLoader.exists(Art.ROOT+"background.png"):
		background = load(Art.ROOT+"background.png")
	lighting=preload("res://scripts/workbench_day_night.gd").new()
	lighting.size=Vector2(1600,900)
	lighting.show_behind_parent=true
	add_child(lighting)
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	mouse_exited.connect(func():
		hover=""
		tooltip_text=""
	)

func _process(delta: float) -> void:
	clock += delta
	for id in data.get("vessels",{}):
		var rows:=WorkbenchSession.Muddle.leaves(data.vessels[id])
		if not mint_display.has(id) or mint_display[id].size()!=rows.size(): mint_display[id]=rows.duplicate(true)
		for i in range(rows.size()): mint_display[id][i].work=move_toward(float(mint_display[id][i].work),float(rows[i].work),delta*5)

	material_transition=minf(1,material_transition+delta/.38)
	if material_transition>=1: retired_materials.clear()
	drain_flash=maxf(0,drain_flash-delta)
	_advance_stir(delta)
	motion_energy=move_toward(motion_energy,0,delta*7)
	var held: bool = dragging and not moving_shaker and selected=="shaker" and technique=="shake" and data.get("lid",false)
	shaker_offset=shaker_offset.lerp(movement if held else Vector2.ZERO,1-exp(-delta*22))
	lift_blend = move_toward(lift_blend,1.0 if held else 0.0,delta*4.5)
	if not held and lift_blend==0: shaker_offset=Vector2.ZERO
	shake_depth = lerpf(shake_depth,depth_target if held else 0.0,1-exp(-delta*18))
	pour_blend = move_toward(pour_blend,1.0 if pouring else 0.0,delta*4)
	transition_progress = minf(1.0,transition_progress+delta/1.1)
	if not animated_source.is_empty():
		animation_progress += delta/1.1
		if animation_progress>=1:
			animated_source=""
	if held and motion_is_active():
		shake_trail.append({"pose":shaker_pose(),"time":clock})
	while not shake_trail.is_empty() and clock-float(shake_trail[0].time)>.13: shake_trail.pop_front()
	queue_redraw()

func apply_snapshot(snapshot: Dictionary) -> void:
	if data.get("id","")!=snapshot.get("id",""):
		ice_effects.clear()
		ice_batch_effects.clear()
		garnish_effects.clear()
		mint_effects.clear()
		mint_display.clear()
		muddler_vessel=""
		returning_spoon={}
		stir_energy=0
		stir_rate=0
		stir_angle=0
	if data.get("spoon_vessel","")!=snapshot.get("spoon_vessel",""):
		if data.get("id","")==snapshot.get("id","") and not str(data.get("spoon_vessel","")).is_empty(): returning_spoon=spoon_geometry()
		spoon_change_time=clock
	if data.get("vessels",{}) != snapshot.get("vessels",{}):
		var previous_contents := {}
		var previous_layers: Dictionary={}
		for id in snapshot.get("vessels",{}):
			previous_layers[id]=layers_for(id) if data.get("id")==snapshot.get("id") else LiquidState.layers(snapshot.vessels[id])
			previous_contents[id] = contents_for(id) if data.get("id")==snapshot.get("id") else snapshot.vessels[id].contents.duplicate(true)
			var old: Dictionary=data.get("vessels",{}).get(id,{})
			var new: Dictionary=snapshot.vessels[id]
			if old.get("ice","none")!=new.ice or old.get("garnish",false)!=new.garnish: effects[id]=clock
			var same_cup: bool=not data.is_empty() and data.get("id")==snapshot.get("id")
			var old_count:=WorkbenchSession.ice_batches(old).size() if same_cup else 0
			var new_count:=WorkbenchSession.ice_batches(new).size()
			if same_cup and new_count>old_count: ice_effects[id]=clock
			if not ice_batch_effects.has(id): ice_batch_effects[id]=[]
			if ice_batch_effects[id].size()>new_count: ice_batch_effects[id].resize(new_count)
			while ice_batch_effects[id].size()<new_count:
				ice_batch_effects[id].append(clock if same_cup and ice_batch_effects[id].size()>=old_count else clock-10)
			var old_garnishes:=WorkbenchSession.garnishes(old).size() if same_cup else 0
			if not garnish_effects.has(id): garnish_effects[id]=[]
			if garnish_effects[id].size()>WorkbenchSession.garnishes(new).size(): garnish_effects[id].resize(WorkbenchSession.garnishes(new).size())
			while garnish_effects[id].size()<WorkbenchSession.garnishes(new).size():
				garnish_effects[id].append(clock if same_cup and garnish_effects[id].size()>=old_garnishes else clock-10)
			var old_mint:=int(old.get("solids",{}).get("sku_mint_leaf",0)) if same_cup else 0
			var new_mint:=int(new.get("solids",{}).get("sku_mint_leaf",0))
			if not mint_effects.has(id): mint_effects[id]=[]
			if mint_effects[id].size()>new_mint: mint_effects[id].resize(new_mint)
			while mint_effects[id].size()<new_mint:
				mint_effects[id].append(clock if same_cup and mint_effects[id].size()>=old_mint else clock-10)
		transition_from=previous_contents
		transition_layers=previous_layers
		transition_progress = 0.0 if not data.is_empty() and data.get("id")==snapshot.get("id") else 1.0
	data = snapshot
	# A click can remove the spoon before the pointer moves again.
	if hover=="spoon" and spoon_geometry().is_empty():
		hover=""
		tooltip_text=""

func contents_for(id: String) -> Dictionary:
	var actual: Dictionary = data.get("vessels",{}).get(id,{}).get("contents",{})
	var blend:=transition_progress
	if animated_source=="shaker" and id in ["shaker",animated_destination]:
		blend=smoothstep(.24,.72,animation_progress)
	var result := Liquid.interpolate(transition_from.get(id,actual),actual,blend)
	if pouring and id==pour_vessel and not bottle.is_empty():
		result = actual.duplicate()
		result[bottle] = float(result.get(bottle,0))+preview_amount
	return result

func layers_for(id: String) -> Array:
	var vessel: Dictionary=data.get("vessels",{}).get(id,{})
	var stack:=LiquidState.layers(vessel)
	if pouring and id==pour_vessel and not bottle.is_empty():
		var preview: Dictionary={"contents":vessel.get("contents",{}).duplicate(true),"layers":stack}
		LiquidState.add(preview,{bottle:preview_amount})
		return preview.layers
	var before: Array=transition_layers.get(id,stack)
	var blend:=transition_progress
	if animated_source=="shaker" and id in ["shaker",animated_destination]: blend=smoothstep(.24,.72,animation_progress)
	# Resample both stacks by volume coordinates, so merges and partial pours animate continuously.
	return Liquid.display_layers(before,stack,blend)

func stream_color() -> Color:
	var stream: Array=[]
	for i in range(data.get("actions",[]).size()-1,-1,-1):
		var action: Dictionary=data.actions[i]
		if action.kind in ["transfer","filter"]:
			stream=action.get("pour",{}).get("layers",[])
			break
	var cursor:=LiquidState.volume(LiquidState.aggregate(stream))*smoothstep(.20,.78,animation_progress)
	for layer in stream:
		cursor-=LiquidState.volume(layer.contents)
		if cursor<=0: return Liquid.color(layer.contents,data.get("liquid_profiles",{}))
	return Liquid.color(stream.back().contents if not stream.is_empty() else contents_for(animated_destination),data.get("liquid_profiles",{}))

func _bottle_slot(index: int) -> Rect2:
	if data.get("mode")=="research_diy": return Rect2(445+maxi(0,index)*118,280,108,270)
	return Rect2(330+maxi(0,index)*128,280,108,270)

func set_materials(next: Array) -> void:
	if materials==next: return
	var origins: Dictionary={}
	for id in materials: origins[id]=bottle_rect(id)
	retired_materials.clear()
	if materials_initialized and not next.is_empty():
		for id in materials:
			if not next.has(id): retired_materials.append({"id":id,"rect":origins[id]})
	materials=next.duplicate()
	material_origins.clear()
	for i in range(materials.size()):
		var slot:=_bottle_slot(i)
		material_origins[materials[i]]=origins.get(materials[i],Rect2(slot.position+Vector2(35,-22),slot.size))
	material_transition=0.0 if materials_initialized else 1.0
	materials_initialized=true

func bottle_rect(id: String) -> Rect2:
	var slot:=_bottle_slot(materials.find(id))
	if material_transition>=1: return slot
	var origin: Rect2=material_origins.get(id,slot)
	return Rect2(origin.position.lerp(slot.position,smoothstep(0,1,material_transition)),slot.size)

func begin_item_drag(tab: String, id: String, point: Vector2) -> void:
	if not input_enabled or data.get("status")!="mixing": return
	stop_gesture()
	item_grabbed.emit(id)
	carry_tab=tab
	carry_id=id
	carry_start=point
	carry_point=point
	drop_target=""

func cancel_carry() -> void:
	carry_id=""
	drop_target=""
	queue_redraw()

func can_target(id: String, tab: String, target: String) -> bool:
	if WorkbenchSession.MATERIALS.has(id): return target in POS and not (target=="shaker" and data.get("lid",false))
	if WorkbenchSession.SOLIDS.has(id): return target in ["shaker","mixing","glass"] and not (target=="shaker" and data.get("lid",false))
	if tab=="冰块": return target in ["shaker","mixing","glass"] and not (target=="shaker" and data.get("lid",false))
	if tab in ["装饰","杯子"]: return target=="glass"
	if id in ["lid","cap"]: return target in ["shaker","lid","cap"]
	if id=="strainer": return target in ["shaker","mixing"]
	if id in ["spoon","tool_yellow_bar_spoon","muddler"]: return target in ["shaker","mixing","glass"]
	return false

func _destination(point: Vector2) -> String:
	if DRAIN_RECT.has_point(point): return "drain"
	if dragging and selected in POS:
		# Test stationary receiving vessels before the lifted source and its tools.
		for id in POS:
			if id!=selected and _rect(id).has_point(point): return id
	if SERVE_RECT.has_point(point): return "serve"
	if Rect2(1260,18,322,864).has_point(point): return "pantry"
	var hit:=_hit(point)
	return selected if hit=="muddler" else hit

func _rect(id: String) -> Rect2:
	if data.get("lid",false):
		if id=="lid": return Rect2(376,440,178,150)
		if id=="cap": return Rect2(439,421,52,50)
	if id=="bottle": return bottle_rect(bottle)
	return RECTS[id]

func prop_visible(id: String) -> bool:
	if id=="strainer": return false
	if id=="spoon": return not str(data.get("spoon_vessel","")).is_empty()
	if id=="muddler": return not (moving_glass or moving_mixing or moving_shaker) and animated_source!=selected and technique=="muddle" and muddler_vessel==selected and selected in ["mixing","glass","shaker"] and not (selected=="shaker" and data.get("lid",false))
	return true

func _hit(point: Vector2) -> String:
	if prop_visible("muddler") and Rect2(muddler_rect().position,Vector2(52,95)).grow(9).has_point(point): return "muddler"
	if DRAIN_RECT.has_point(point): return "drain"
	if prop_visible("spoon"):
		var geometry:=spoon_geometry()
		var handle: Vector2=geometry.handle
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,handle,handle+Vector2(0,32).rotated(float(geometry.angle)-PI)))<(22 if data.get("spoon_tool_id")=="tool_yellow_bar_spoon" else 10): return "spoon"
	if lift_blend>.01:
		var local := shaker_pose().affine_inverse()*point
		for part in ["cap","lid","shaker"]:
			if part!="shaker" and not data.get("lid",false): continue
			if _rect(part).has_point(local): return "shaker"
	var ids: Array = RECTS.keys()
	ids.reverse()
	for id in ids:
		if id in ["strainer","muddler","spoon"]: continue
		if lift_blend>.01 and (id=="shaker" or (id in ["lid","cap"] and data.get("lid",false))): continue
		if id=="bottle" and bottle.is_empty(): continue
		if _rect(id).has_point(point):
			# Grip the lower fitted lid as part of the closed shaker. Its top and cap
			# remain independently clickable to open it; the body grip never toggles it.
			if id=="lid" and data.get("lid",false) and point.y > _rect(id).position.y+_rect(id).size.y*.52:
				return "shaker"
			return id
	for id in materials:
		if bottle_rect(id).has_point(point): return "bottle:"+str(id)
	return ""

func _sprite(id: String, rect: Rect2, angle := 0.0, tint := Color.WHITE, group := Transform2D.IDENTITY) -> void:
	var texture: Texture2D = Art.texture(id)
	if texture == null: return
	var target := rect.size
	var ratio := minf(target.x/texture.get_width(),target.y/texture.get_height())
	var extent := texture.get_size()*ratio
	if id in ["lid","cap"]: extent=target
	var center := rect.position+Vector2(rect.size.x*.5,rect.size.y)
	draw_set_transform_matrix(group*Transform2D(angle,center))
	draw_texture_rect(texture,Rect2(Vector2(-extent.x*.5,-extent.y),extent),false,tint)
	draw_set_transform(Vector2.ZERO)

func _ellipse(center: Vector2, radii: Vector2, color: Color, group:=Transform2D.IDENTITY) -> void:
	draw_set_transform_matrix(group*Transform2D(0,radii,0,center))
	draw_circle(Vector2.ZERO,1,color)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if not is_instance_valid(lighting):
		if background!=null: draw_texture_rect(background,Rect2(0,0,1600,900),false)
		else: draw_rect(Rect2(0,0,1600,900),Color("493021"))
	_draw_drain()
	_draw_bottles()
	if moving_glass:
		var style := _tooltip_style()
		style.bg_color=Color(.18,.12,.06,.65)
		draw_style_box(style,SERVE_RECT)
		draw_string(_font,SERVE_RECT.position+Vector2(35,52),"松手出杯",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("eed7a5"))
	for id in RECTS:
		if id=="spoon" or not prop_visible(id): continue
		if (moving_shaker or animated_source=="shaker") and (id=="shaker" or (id in ["lid","cap"] and data.get("lid",false))): continue
		if lift_blend>.01 and (id=="shaker" or (id in ["lid","cap"] and data.get("lid",false))): continue
		if id=="bottle" and bottle.is_empty(): continue
		var rect := _rect(id)
		var angle := 0.0
		var texture_id: String = id
		if id=="glass": texture_id=str(data.get("cup","coupe")) if data.get("cup")!="rocks" else "highball"
		if id=="bottle": texture_id=bottle
		if id==selected and dragging:
			if id=="jigger" or (id=="glass" and moving_glass) or (id=="mixing" and moving_mixing): rect.position+=movement
		if id==animated_source and RECTS.has(animated_destination):
			var pose:=transfer_pose(id,animated_destination,animation_progress)
			rect=pose.rect
			angle=pose.angle
		if id=="bottle" and pouring:
			rect=Rect2(840,352,115,265)
			angle=-1.0
		if id=="muddler": rect=muddler_rect()
		if id=="muddler" and muddle_gripped:
			var rail:=rect.position+Vector2(65,25)
			draw_line(rail,rail+Vector2(0,85),Color(.92,.83,.62,.65),5,true)
			draw_circle(rail+Vector2(0,85*muddle_depth),6,Color("c89544") if motion_is_active() else Color("f0dab0"))
			if motion_is_active():
				_ellipse(rect.end-Vector2(rect.size.x*.5,8),Vector2(22,5),Color(.53,.72,.30,.18))
		_ellipse(rect.position+Vector2(rect.size.x*.53,rect.size.y-3),Vector2(rect.size.x*.44,9),Color(0,0,0,.23))
		var vessel: Dictionary = data.get("vessels",{}).get(id,{})
		var contents := contents_for(id)
		var qty := Liquid.volume(contents)
		var texture: Texture2D = Art.texture(texture_id)
		var extent := texture.get_size()*minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
		var liquid_rect := Rect2(rect.position+Vector2((rect.size.x-extent.x)*.5,rect.size.y-extent.y),extent)
		var fill_rect:=liquid_rect
		var coupe_shape:=texture_id in ["coupe","glass_cocktail_glass"]
		var shape:=texture_id if id=="glass" else ("mixing" if id=="mixing" else "")
		var ice_age:=clock-float(ice_effects.get(id,clock-10))
		var ice_fraction:=ice_fraction_for(id)
		var ripple := stir_energy if id==data.get("spoon_vessel","") else (absf(sin(clock*9)) if dragging or transition_progress<1 or (pouring and pour_vessel==id) else 0.0)
		if id==data.get("spoon_vessel","") and id!="mixing": _draw_attached_spoon(spoon_geometry())
		if qty>0 and id=="glass":
			var pivot:=rect.position+Vector2(rect.size.x*.5,rect.size.y)
			draw_set_transform_matrix(Transform2D(0,pivot)*Transform2D(angle,Vector2.ZERO)*Transform2D(0,-pivot))
			Liquid.draw(self,fill_rect,contents,WorkbenchSession.capacity(data,id),coupe_shape,ripple,vessel.get("ice","none")!="none",clock,false,ice_fraction,shape,layers_for(id),data.get("liquid_profiles",{}))
			draw_set_transform(Vector2.ZERO)
		if id=="glass": _draw_mint_vessel(id,fill_rect,rect,angle,contents,coupe_shape,ice_fraction,ripple,shape,0)
		if id=="glass" and vessel.get("ice","none")!="none":
			_draw_ice(fill_rect,rect,angle,str(vessel.ice),contents,WorkbenchSession.capacity(data,id),coupe_shape,false,ice_age,ripple,false,id)
		if id=="glass": _draw_mint_vessel(id,fill_rect,rect,angle,contents,coupe_shape,ice_fraction,ripple,shape,1)
		_sprite(texture_id,rect,angle)
		if id=="mixing" and id==data.get("spoon_vessel",""): _draw_attached_spoon(spoon_geometry())
		if qty>0 and id=="mixing":
			# The shared art has an opaque, thick glass floor. Tint its inner basin
			# above the texture so small pours remain visible, inside the wall edges.
			var pivot := rect.position+Vector2(rect.size.x*.5,rect.size.y)
			draw_set_transform_matrix(Transform2D(0,pivot)*Transform2D(angle,Vector2.ZERO)*Transform2D(0,-pivot))
			Liquid.draw(self,liquid_rect,contents,WorkbenchSession.capacity(data,id),false,ripple,vessel.get("ice","none")!="none",clock,true,ice_fraction,shape,layers_for(id),data.get("liquid_profiles",{}))
			draw_set_transform(Vector2.ZERO)
		# Opaque metal jigger: quantity is shown by the measuring UI, not a floating color disc.
		if id==animated_source and RECTS.has(animated_destination) and animation_progress>.2 and animation_progress<.8:
			var mouth := transfer_lip(id,rect,angle)
			var target := liquid_impact_point(animated_destination)
			var flow:=smoothstep(.20,.29,animation_progress)*(1-smoothstep(.64,.78,animation_progress))
			Liquid.stream(self,mouth,target,stream_color(),clock,flow,maxf(0,(animation_progress-.64)/.20))
		if id=="mixing": _draw_mint_vessel(id,fill_rect,rect,angle,contents,coupe_shape,ice_fraction,ripple,shape,0)
		if id in ["mixing","shaker","jigger"] and vessel.get("ice","none")!="none" and not (id=="shaker" and data.get("lid",false)):
			_draw_ice(fill_rect,rect,angle,str(vessel.ice),contents,WorkbenchSession.capacity(data,id),false,id=="mixing",ice_age,ripple,id in ["shaker","jigger"],id)
		if id==data.get("spoon_vessel","") and stir_energy>.01 and qty>0:
			_draw_stir_swirl(fill_rect,contents,WorkbenchSession.capacity(data,id),coupe_shape,id=="mixing",vessel.get("ice","none")!="none",ice_fraction,shape)
		var solid_index := 0
		for solid in vessel.get("solids",{}):
			if solid=="sku_mint_leaf": continue
			var solid_top:=fill_rect.size.y*Liquid.surface_fraction(qty,WorkbenchSession.capacity(data,id),coupe_shape,vessel.get("ice","none")!="none",id=="mixing",ice_fraction,shape)
			var solid_point:=fill_rect.position+Vector2(fill_rect.size.x*.35+solid_index*20,solid_top)
			if WorkbenchSession.SOLIDS[solid].unit=="g":
				Garnish.piece(self,solid_point,13,"sku_white_cane_sugar",0)
			else: _sprite(solid,Rect2(solid_point-Vector2(0,18),Vector2(27,25)))
			solid_index+=1
		if id!="glass": _draw_mint_vessel(id,fill_rect,rect,angle,contents,coupe_shape,ice_fraction,ripple,shape,1 if id=="mixing" else -1)
		if vessel.get("garnish",false):
			var ages: Array=[]
			for time in garnish_effects.get(id,[]): ages.append(clock-float(time))
			Garnish.draw(self,fill_rect,WorkbenchSession.garnishes(vessel),ages,clock,coupe_shape,shape)
		if id=="jigger" and not dragging: _draw_jigger_marks(rect,qty)
		if (id==hover or id==selected) and not pouring:
			_ellipse(rect.position+Vector2(rect.size.x*.5,rect.size.y+3),Vector2(rect.size.x*.48,5),Color(.93,.72,.34,.30))
	if not returning_spoon.is_empty() and clock-spoon_change_time<.28:
		var return_pose:=returning_spoon.duplicate()
		var progress:=smoothstep(0.0,1.0,clampf((clock-spoon_change_time)/.28,0,1))
		return_pose.tip+=Vector2(0,-55*progress)
		_draw_attached_spoon(return_pose,1-progress)
	if moving_shaker or animated_source=="shaker": _draw_pourable_shaker()
	elif lift_blend>.01: _draw_held_shaker()
	if pour_blend>0.0: _draw_pouring()
	if not carry_id.is_empty():
		if RECTS.has(drop_target) and can_target(carry_id,carry_tab,drop_target):
			var target: Rect2 = _rect(drop_target)
			_ellipse(target.position+Vector2(target.size.x*.5,16),Vector2(target.size.x*.5,10),Color(.94,.79,.38,.5))
		var ghost := Rect2(carry_point-Vector2(45,130),Vector2(90,160))
		_ellipse(carry_point+Vector2(12,30),Vector2(40,7),Color(0,0,0,.16))
		if carry_id in ["cube","crushed"]: Ice.preview(self,Rect2(carry_point-Vector2(45,60),Vector2(90,75)),carry_id)
		elif WorkbenchSession.GARNISHES.has(carry_id) or carry_id in ["sku_mint_leaf","sku_white_cane_sugar"]: Garnish.piece(self,carry_point-Vector2(0,28),30,carry_id,-.12)
		else: _sprite(carry_id,ghost,-.08)
	if hover!="drain" and ToolHelp.description(hover).is_empty() and not hover.is_empty() and input_enabled and not dragging and carry_id.is_empty() and (hover!="spoon" or not spoon_geometry().is_empty()):
		var hovered_material := hover.trim_prefix("bottle:") if hover.begins_with("bottle:") else ""
		var label: String = NAMES.get(hover,"")
		var hover_rect: Rect2 = Rect2(spoon_geometry().handle-Vector2(0,10),Vector2(30,50)) if hover=="spoon" else (_rect(hover) if hovered_material.is_empty() else bottle_rect(hovered_material))
		if not hovered_material.is_empty(): label=WorkbenchSession.MATERIALS[hovered_material].name+" · 拖到杯子或制作容器"
		elif hover=="jigger": label+=" · 拖到容器倒入"
		elif hover=="shaker": label+=" · 拖到成品杯松手倒酒"
		elif hover=="spoon": label+=" · 按住画圈 / 单击收回"
		elif hover in ["lid","cap"]: label+=" · 拖到壶口 / 点击开合"
		else: label+=" · 点击选取"
		var width := _font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+22
		var p := hover_rect.position-Vector2(0,34)
		p.x=clampf(p.x,15,1220-width)
		draw_style_box(_tooltip_style(),Rect2(p,Vector2(width,30)))
		draw_string(_font,p+Vector2(11,22),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("eed7a5"))

func spoon_geometry() -> Dictionary:
	var id:=str(data.get("spoon_vessel",""))
	if not POS.has(id): return {}
	var rect:=_rect(id)
	if (id=="glass" and moving_glass) or (id=="mixing" and moving_mixing): rect.position+=movement
	var skin:=str(data.get("cup","coupe")) if id=="glass" else id
	if skin=="rocks": skin="highball"
	var texture:=Art.texture(skin)
	var extent:=texture.get_size()*minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
	var fill:=Rect2(rect.position+Vector2((rect.size.x-extent.x)*.5,rect.size.y-extent.y),extent)
	var profile:=Ice.profile(fill,skin in ["coupe","glass_cocktail_glass"],id=="mixing",skin if id in ["mixing","glass"] else "")
	var height:=clampf(profile.floor-profile.rim+85,150,265)
	var tip:=Vector2(profile.center,profile.floor-14)
	var orbit:=minf(18,fill.size.x*.12)
	tip+=Vector2(cos(stir_angle)*orbit,sin(stir_angle)*orbit*.2)*stir_energy
	var lean: float=.08+sin(stir_angle)*.06*stir_energy
	return {"tip":tip,"height":height,"angle":PI+lean,"handle":tip+Vector2(0,height*.82).rotated(PI+lean),"tool_id":data.get("spoon_tool_id","tool_bar_spoon")}

func _draw_attached_spoon(geometry: Dictionary, opacity:=1.0) -> void:
	if geometry.is_empty(): return
	var legendary: bool=geometry.get("tool_id")=="tool_yellow_bar_spoon"
	var texture:=Art.texture("tool_yellow_bar_spoon" if legendary else "spoon")
	var height: float=geometry.height
	var width:=height*texture.get_width()/texture.get_height()
	draw_set_transform(geometry.tip,geometry.angle-PI if legendary else geometry.angle)
	draw_texture_rect(texture,Rect2(-width*.5,-height*.90 if legendary else -height*.12,width,height),false,Color(1,1,1,opacity))
	draw_set_transform(Vector2.ZERO)

func _draw_stir_swirl(rect: Rect2, contents: Dictionary, capacity: float, coupe: bool, mixing: bool, ice: bool, ice_fraction:=1.0, shape:="") -> void:
	var surface:=Liquid.surface_fraction(Liquid.volume(contents),capacity,coupe,ice,mixing,ice_fraction,shape)
	var center:=rect.position+rect.size*Vector2(.435 if mixing else .5,surface)
	var radius:=rect.size.x*(.20 if coupe else .25)
	if not shape.is_empty(): radius=rect.size.x*Liquid.Shape.radius(shape,surface)*.8
	for band in range(3):
		var arc:=PackedVector2Array()
		for i in range(23):
			var a:=stir_angle+band*2.1+i/22.0*2.6
			var r:=radius*(.38+band*.24)
			arc.append(center+Vector2(cos(a)*r,sin(a)*r*.18))
		draw_polyline(arc,Color(.97,.96,.82,.38*stir_energy),1.3,true)

func motion_is_active() -> bool:
	if not dragging or moving_shaker or moving_glass or moving_mixing or clock-last_motion_time>.16: return false
	var vessel: Dictionary=data.get("vessels",{}).get(selected,{})
	if vessel.is_empty() or (Liquid.volume(vessel.contents)<=0 and vessel.get("solids",{}).is_empty()): return false
	if technique=="muddle": return selected in ["glass","mixing","shaker"] and not (selected=="shaker" and data.get("lid",false))
	if technique=="stir": return data.get("spoon_vessel","")==selected
	return technique=="shake" and selected=="shaker" and data.get("lid",false)

func _draw_ice(fill: Rect2, vessel: Rect2, angle: float, kind: String, contents: Dictionary, capacity: float, coupe: bool, mixing: bool, age: float, motion: float, metal:=false, vessel_id:="") -> void:
	var pivot:=vessel.position+Vector2(vessel.size.x*.5,vessel.size.y)
	draw_set_transform_matrix(Transform2D(0,pivot)*Transform2D(angle,Vector2.ZERO)*Transform2D(0,-pivot))
	var batches:=WorkbenchSession.ice_batches(data.get("vessels",{}).get(vessel_id,{}))
	if batches.is_empty(): Ice.draw(self,fill,kind,contents,capacity,coupe,mixing,age,clock,motion,metal)
	for i in range(batches.size()):
		var times: Array=ice_batch_effects.get(vessel_id,[])
		var batch_age:=clock-float(times[i]) if i<times.size() else 10.0
		if vessel_id==animated_source: batch_age=maxf(batch_age,2.0)
		Ice.draw(self,fill,batches[i].kind,contents,capacity,coupe,mixing,batch_age,clock,motion,metal,i,ice_fraction_for(vessel_id),str(data.get("cup","coupe")) if vessel_id=="glass" else ("mixing" if vessel_id=="mixing" else ""),int(batches[i].get("pieces",4 if batches[i].kind=="cube" else 10)))
	draw_set_transform(Vector2.ZERO)

func ice_fraction_for(id: String) -> float:
	var batches:=WorkbenchSession.ice_batches(data.get("vessels",{}).get(id,{}))
	var times: Array=ice_batch_effects.get(id,[])
	var result:=0.0
	for i in range(batches.size()):
		var age:=clock-float(times[i]) if i<times.size() else 10.0
		result+=Ice.displacement(age,batches[i].kind)*float(batches[i].volume)/40.0
	return result

func _draw_jigger_marks(rect: Rect2, qty: float) -> void:
	for ml in [15,30,45,60]:
		var y: float=rect.position.y+rect.size.y*(.43-float(ml)/60.0*.30)
		draw_line(Vector2(rect.position.x+rect.size.x*.36,y),Vector2(rect.position.x+rect.size.x*.60,y),Color(.29,.20,.11,.78),1.0,true)
		draw_string(_font,Vector2(rect.position.x+rect.size.x*.67,y+4),str(ml),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("eedbb0"))

func _tooltip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=Color(.12,.08,.04,.9)
	style.border_color=Color("b68c48")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func _draw_mint_vessel(id: String,fill: Rect2,rect: Rect2,angle: float,contents: Dictionary,coupe: bool,ice_fraction: float,motion: float,shape: String,depth_pass: int) -> void:
	var count:=int(data.get("vessels",{}).get(id,{}).get("solids",{}).get("sku_mint_leaf",0))
	if count<=0 or (id=="shaker" and data.get("lid",false)): return
	var ages: Array=[]
	for time in mint_effects.get(id,[]): ages.append(clock-float(time))
	var pivot:=rect.position+Vector2(rect.size.x*.5,rect.size.y)
	draw_set_transform_matrix(Transform2D(0,pivot)*Transform2D(angle,Vector2.ZERO)*Transform2D(0,-pivot))
	Mint.in_vessel(self,fill,count,contents,WorkbenchSession.capacity(data,id),coupe,id=="mixing",ice_fraction,clock,ages,motion,id=="shaker",shape,depth_pass,data.get("liquid_profiles",{}),mint_display.get(id,WorkbenchSession.Muddle.leaves(data.vessels[id])))
	draw_set_transform(Vector2.ZERO)

func _draw_bottles() -> void:
	for retired in retired_materials:
		var rect: Rect2=retired.rect
		rect.position+=Vector2(100,-55)*smoothstep(0,1,material_transition)
		_sprite(retired.id,rect,0,Color(1,1,1,1-material_transition))
	for id in materials:
		var rect := bottle_rect(id)
		if (id==bottle and pour_blend>0) or id==carry_id: continue
		_ellipse(rect.end-Vector2(rect.size.x*.5,2),Vector2(42,7),Color(0,0,0,.24))
		_sprite(id,rect)
		draw_string(_font,rect.position+Vector2(-7,rect.size.y+22),WorkbenchSession.MATERIALS[id].name,HORIZONTAL_ALIGNMENT_LEFT,120,16,Color("efd9af"))

func _draw_pouring() -> void:
	if bottle.is_empty(): return
	var rest := bottle_rect(bottle)
	var target := rim_point(pour_vessel)
	var side := 1.0 if target.x>900 else -1.0
	var pouring_angle := side*1.05
	var mouth_goal := target+Vector2(-side*50,-95)
	var texture:=Art.texture(bottle)
	var bottle_height:=texture.get_height()*minf(rest.size.x/texture.get_width(),rest.size.y/texture.get_height())
	var base_goal := mouth_goal-Vector2(0,-bottle_height).rotated(pouring_angle)
	var pouring_rect := Rect2(base_goal-Vector2(rest.size.x*.5,rest.size.y),rest.size)
	var rect := Rect2(rest.position.lerp(pouring_rect.position,pour_blend),rest.size)
	var angle := pouring_angle*pour_blend
	_sprite(bottle,rect,angle)
	if (pouring and pour_blend>.94) or (not pouring and pour_blend>.40):
		var mouth := rect.position+Vector2(rect.size.x*.5,rect.size.y)+Vector2(0,-bottle_height).rotated(angle)
		var flow:=smoothstep(.94,1,pour_blend) if pouring else smoothstep(.84,1,pour_blend)
		Liquid.stream(self,mouth if pouring else mouth_goal,liquid_impact_point(pour_vessel),Liquid.color({bottle:1},data.get("liquid_profiles",{})),clock,flow,0.0 if pouring else (1-pour_blend)/.6)

func rim_point(id: String) -> Vector2:
	var rect := _rect(id)
	var texture_id := str(data.get("cup","coupe")) if data.get("cup")!="rocks" else "highball"
	var texture := Art.texture(texture_id if id=="glass" else id)
	var extent := texture.get_size()*minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
	if id in ["glass","mixing"]:
		var profile:=Liquid.Shape.profile(texture_id if id=="glass" else "mixing")
		return rect.position+Vector2((rect.size.x-extent.x)*.5+extent.x*profile.center,rect.size.y-extent.y+extent.y*profile.walls.front().x)
	return rect.position+Vector2(rect.size.x*.5,rect.size.y-extent.y+extent.y*.085)

func liquid_impact_point(id: String) -> Vector2:
	if id not in ["glass","mixing"]: return rim_point(id)
	var rect:=_rect(id)
	var cup:=str(data.get("cup","coupe")) if id=="glass" else "mixing"
	if cup=="rocks": cup="highball"
	var texture:=Art.texture(cup)
	var extent:=texture.get_size()*minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
	var fill:=Rect2(rect.position+Vector2((rect.size.x-extent.x)*.5,rect.size.y-extent.y),extent)
	var height:=Liquid.surface_fraction(Liquid.volume(contents_for(id)),WorkbenchSession.capacity(data,id),cup in ["coupe","glass_cocktail_glass"],ice_fraction_for(id)>0,id=="mixing",ice_fraction_for(id),cup)
	return fill.position+fill.size*Vector2(.435 if id=="mixing" else .5,height)

func shaker_pose() -> Transform2D:
	var rest := Vector2(465,615)
	var center:=rest+shaker_offset+Vector2(0,-45+12*shake_depth)*lift_blend
	var scale_factor := 1.0+lift_blend*(.16+shake_depth*.18)
	var angle := lift_blend*(-.98+shake_depth*.22)
	return Transform2D(angle,Vector2.ONE*scale_factor,0,center)*Transform2D(0,-rest)

func begin_shaker_pour() -> void:
	shaker_pour_start=released_shaker_pose
	released_shaker_pose=Transform2D.IDENTITY
	lift_blend=0

func shaker_drag_pose() -> Transform2D:
	return Transform2D(0,movement)

func shaker_pour_pose(progress: float=-1.0) -> Transform2D:
	if progress<0: progress=animation_progress
	var rest: Vector2=POS.shaker
	var mouth: Vector2=Vector2(465,440) if data.get("lid",false) else Vector2(465,546)
	var target_id:=animated_destination if animated_destination in POS else "glass"
	var side:=1.0 if rim_point(target_id).x>rest.x else -1.0
	var angle:=side*1.05
	var destination:=rim_point(target_id)+Vector2(-side*38,-72)
	var tilt:=Transform2D(angle,destination-(mouth-rest).rotated(angle))*Transform2D(0,-rest)
	if progress<.24: return shaker_pour_start.interpolate_with(tilt,smoothstep(0,.24,progress))
	if progress<.72: return tilt
	return tilt.interpolate_with(Transform2D.IDENTITY,smoothstep(.72,1,progress))

func _draw_pourable_shaker() -> void:
	var pouring_now:=animated_source=="shaker"
	var pose:=shaker_pour_pose() if pouring_now else shaker_drag_pose()
	_ellipse(Vector2(465,790),Vector2(80,9),Color(0,0,0,.18))
	_sprite("shaker",_rect("shaker"),0,Color.WHITE,pose)
	if data.get("lid",false):
		_sprite("lid",_rect("lid"),0,Color.WHITE,pose)
		# Small cap rests on the counter during the pour; the fitted filter stays on.
		if pouring_now: _sprite("cap",RECTS.cap)
		else: _sprite("cap",_rect("cap"),0,Color.WHITE,pose)
	if pouring_now and animation_progress>.24 and animation_progress<.82:
		var mouth: Vector2=Vector2(465,440) if data.get("lid",false) else Vector2(465,546)
		var flow:=smoothstep(.24,.32,animation_progress)*(1-smoothstep(.62,.72,animation_progress))
		Liquid.stream(self,(pose if animation_progress<.72 else shaker_pour_pose(.65))*mouth,liquid_impact_point(animated_destination),stream_color(),clock,flow,maxf(0,(animation_progress-.62)/.20))
	elif moving_shaker:
		for id in POS:
			if id=="shaker": continue
			_ellipse(rim_point(id),Vector2(_rect(id).size.x*.45,10),Color(.94,.79,.38,.65))
		draw_style_box(_tooltip_style(),Rect2(800,264,420,42))
		draw_string(_font,Vector2(815,293),"拖到另一容器，松手倒酒",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("eed7a5"))

func _draw_held_shaker() -> void:
	# All three pieces share one transform: the lid never drifts away from the body.
	var pose := shaker_pose()
	if motion_is_active():
		for sample in shake_trail:
			var opacity:=.08*(1-(clock-float(sample.time))/.13)
			_sprite("shaker",_rect("shaker"),0,Color(1,.94,.80,opacity),sample.pose)
		var center: Vector2=pose*POS.shaker
		for side in [-1,1]:
			var arc:=PackedVector2Array()
			for i in range(18):
				var t:=i/17.0
				arc.append(center+Vector2(side*(116+sin(t*PI)*12),lerpf(-58,58,t)))
			draw_polyline(arc,Color(.94,.84,.61,.35*motion_energy),1.8,true)
	var shadow := Vector2(465,790).lerp(Vector2(625,790),lift_blend)
	_ellipse(shadow,Vector2(88+lift_blend*40,9+lift_blend*5),Color(0,0,0,.23-lift_blend*.13))
	_sprite("shaker",_rect("shaker"),0,Color.WHITE,pose)
	if data.get("lid",false):
		_sprite("lid",_rect("lid"),0,Color.WHITE,pose)
		_sprite("cap",_rect("cap"),0,Color.WHITE,pose)
	if dragging:
		draw_style_box(_tooltip_style(),Rect2(422,218,575,40))
		var target:=_destination(last_point)
		draw_string(_font,Vector2(440,245),"松手倒入"+str(NAMES[target]) if target in POS and target!="shaker" else ("摇和中 · 快速来回拖动 · 松手放回" if motion_is_active() else "已拿起 · 来回摇和 · 拖到另一容器倒酒"),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("eed7a5"))

func muddler_rect() -> Rect2:
	var vessel:=_rect(selected)
	var base:=vessel.position+vessel.size*Vector2(.5,.87)
	return Rect2(base-Vector2(26,245+(1-muddle_depth)*65),Vector2(52,245))

func grip_muddler(point: Vector2) -> void:
	stop_gesture()
	muddle_gripped=true
	dragging=true
	press_point=point
	last_point=point
	last_tick=Time.get_ticks_msec()
	travel=0
	shake_direction=0

func _gui_input(event: InputEvent) -> void:
	if not input_enabled: return
	if event is InputEventMouseMotion and not dragging:
		hover=_hit(event.position)
		tooltip_text=ToolHelp.description(hover)
		queue_redraw()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		tooltip_text=""
		var id := _hit(event.position)
		if id.is_empty() or (animated_source=="shaker" and id in ["shaker","lid","cap"]): return
		stop_gesture()
		if id=="muddler":
			item_grabbed.emit(id)
			grip_muddler(event.position)
			accept_event()
			return
		if id=="spoon":
			item_grabbed.emit(id)
			spoon_pressed=true
			spoon_moved=false
			id=str(data.get("spoon_vessel",""))
		if id.begins_with("bottle:"):
			begin_item_drag("材料",id.trim_prefix("bottle:"),event.position)
			accept_event()
			return
		if id in ["lid","cap","spoon","muddler","strainer"]:
			begin_item_drag("器具",id,event.position)
			accept_event()
			return
		if POS.has(id):
			if not spoon_pressed: item_grabbed.emit(id)
			selected=id
			vessel_selected.emit(id)
			if not input_enabled: return
			dragging=true
			moving_shaker=not spoon_pressed and id=="shaker" and not data.get("lid",false) and (technique not in ["stir","muddle"] or event.position.y>_rect("shaker").position.y+_rect("shaker").size.y*.65)
			moving_mixing=not spoon_pressed and id=="mixing" and (technique not in ["stir","muddle"] or event.position.y>_rect("mixing").position.y+_rect("mixing").size.y*.65)
			moving_glass=not spoon_pressed and id=="glass" and (technique not in ["stir","muddle"] or event.position.y>_rect("glass").position.y+_rect("glass").size.y*.65)
			press_point=event.position
			stir_origin=event.position if spoon_pressed else POS[id]
			last_point=event.position
			last_tick=Time.get_ticks_msec()
			travel=0
			shake_direction=0
			shake_gesture.reset()
		else:
			prop_selected.emit(id)
		queue_redraw()
		accept_event()

func _input(event: InputEvent) -> void:
	# OS hover events can arrive between held-motion events; they are not a gesture.
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)==0: return
	if not carry_id.is_empty():
		if event is InputEventMouseMotion:
			carry_point=get_global_transform_with_canvas().affine_inverse()*event.position
			drop_target=_destination(carry_point)
			if carry_id=="muddler" and drop_target in ["glass","mixing","shaker"] and not (drop_target=="shaker" and data.get("lid",false)):
				var target:=drop_target
				cancel_carry()
				item_dropped.emit("器具","muddler",target,true)
				if technique=="muddle" and muddler_vessel==target:
					muddle_depth=.25
					grip_muddler(carry_point)
		elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			var point: Vector2 = get_global_transform_with_canvas().affine_inverse()*event.position
			var tab := carry_tab
			var id := carry_id
			var moved: bool = point.distance_to(carry_start)>18
			var destination := _destination(point)
			cancel_carry()
			item_dropped.emit(tab,id,destination,moved)
		return
	if not dragging: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		var destination := _destination(point)
		var should_empty:=not muddle_gripped and destination=="drain" and point.distance_to(press_point)>25 and (selected=="jigger" or moving_glass or moving_mixing or selected=="shaker")
		var should_serve := moving_glass and destination=="serve" and movement.length()>25
		var remove_spoon:=spoon_pressed and not spoon_moved and point.distance_to(press_point)<7
		var source:=selected
		var held_vessel: bool=not muddle_gripped and (source=="jigger" or moving_glass or moving_mixing or (source=="shaker" and not spoon_pressed and (moving_shaker or data.get("lid",false))))
		var should_transfer: bool=held_vessel and destination in POS and destination!=source and point.distance_to(press_point)>25
		if moving_mixing: mixing_pour_offset=movement if should_transfer else Vector2.ZERO
		released_shaker_pose=(shaker_drag_pose() if moving_shaker else shaker_pose()) if source=="shaker" else Transform2D.IDENTITY
		stop_gesture()
		if remove_spoon: spoon_remove_requested.emit()
		elif should_empty: empty_requested.emit(source)
		elif should_transfer: transfer_requested.emit(source,destination)
		elif should_serve: serve_requested.emit()
		released_shaker_pose=Transform2D.IDENTITY
	elif event is InputEventMouseMotion:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		var delta: Vector2=point-last_point
		if spoon_pressed and point.distance_to(press_point)>7: spoon_moved=true
		var now := Time.get_ticks_msec()
		var seconds := clampf((now-last_tick)/1000.0,0,.08)
		pointer_speed=delta.length()/maxf(.001,(now-last_tick)/1000.0)
		var valid: bool=delta.length()>3 and delta.length()<180
		if selected=="jigger" or moving_glass or moving_shaker or moving_mixing:
			movement=(point-press_point).limit_length(800)
			valid=false
		elif technique=="stir":
			# Pointer speed controls the motor; no circular-path recognition is required.
			if delta.length()>=1 and delta.length()<180 and data.get("spoon_vessel","")==selected:
				stir_pointer_time=clock
			valid=false # Stir duration is integrated by the render clock, not mouse events.
		elif technique=="shake":
			movement=point-press_point
			valid=selected=="shaker" and data.get("lid",false) and shake_gesture.sample(delta,(now-last_tick)/1000.0,clock)
			var stroke_axis: float=delta.x if absf(delta.x)>absf(delta.y) else delta.y
			depth_target=clampf(stroke_axis/32.0,-1,1) if valid else 0.0
		else:
			var axis: float=delta.y
			var direction:=int(signf(axis))
			if direction!=shake_direction:
				travel=0
				shake_direction=direction
			travel+=absf(axis)
			var previous_depth:=muddle_depth
			if muddle_gripped: muddle_depth=clampf(muddle_depth+axis/100.0,0,1)
			valid=muddle_gripped and muddle_depth>previous_depth and axis>.5 and delta.length()<180 and absf(axis)>absf(delta.x)*1.2 and travel<160
			var vessel: Dictionary=data.get("vessels",{}).get(selected,{})
			valid=valid and not (selected=="shaker" and data.get("lid",false)) and not vessel.get("solids",{}).is_empty()
			if axis< -.5: muddle_down_played=false
			if valid and travel>8 and not muddle_down_played:
				muddle_down_played=true
				muddle_contact.emit(muddle_pressure())
			movement=(point-press_point).limit_length(40)
		if valid:
			last_motion_time=clock
			motion_energy=1.0
			control_integral+=seconds*control_quality()
			pressure_integral+=seconds*muddle_pressure()
			accumulated+=seconds
			if accumulated>=.25:
				motion_completed.emit(technique,minf(accumulated,.5))
				accumulated=0
				control_integral=0
				pressure_integral=0
		last_point=point
		last_tick=now
		queue_redraw()

func muddle_pressure() -> float:
	return clampf(pointer_speed/650.0,0,1)

func control_quality() -> float:
	var low:=260.0 if technique=="shake" else 100.0
	var high:=1200.0 if technique=="shake" else 500.0
	if pointer_speed<low: return lerpf(.55,1,clampf(pointer_speed/low,0,1))
	if pointer_speed>high: return maxf(.55,1-(pointer_speed-high)/(high*2))
	return 1.0

func pace_text() -> String:
	if technique=="muddle":
		if not motion_is_active(): return "握住棒柄 · 向上提起，再向下轻压"
		return "偏重 · 放慢下压" if muddle_pressure()>.72 else ("轻柔 · 保持节奏" if muddle_pressure()>.12 else "很轻 · 稍加深下压")
	if not dragging or clock-last_motion_time>.18: return "等待来回摇动" if technique=="shake" else "按住杯口或勺柄移动鼠标"
	var low:=260.0 if technique=="shake" else 100.0
	var high:=1200.0 if technique=="shake" else 500.0
	return "偏弱 · 稍加快" if pointer_speed<low else ("偏急 · 放缓一点" if pointer_speed>high else "适中 · 保持节奏")

func stop_gesture() -> void:
	if accumulated>.01: motion_completed.emit(technique,minf(accumulated,.5))
	accumulated=0
	control_integral=0
	pressure_integral=0
	muddle_down_played=false
	muddle_gripped=false
	pointer_speed=0
	shake_gesture.reset()
	dragging=false
	spoon_pressed=false
	motion_energy=0
	last_motion_time=-10
	moving_glass=false
	moving_shaker=false
	moving_mixing=false
	stir_pointer_time=-10
	depth_target=0.0
	movement=Vector2.ZERO
	queue_redraw()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		stop_gesture()
		cancel_carry()


func transfer_lip(id: String, rect: Rect2, angle: float) -> Vector2:
	var pivot:=rect.position+Vector2(rect.size.x*.5,rect.size.y)
	# The mixing glass has a spout on the right of the shared texture.
	var lip:=Vector2(rect.size.x*.43,-rect.size.y*.91) if id=="mixing" else Vector2(0,-rect.size.y*.94)
	return pivot+lip.rotated(angle)

func transfer_pose(source: String, destination: String, progress: float) -> Dictionary:
	var rect:=_rect(source)
	if source=="mixing" and progress<.5: rect.position+=mixing_pour_offset
	var wave:=sin(clampf(progress,0,1)*PI)
	var side:=1.0 if rim_point(destination).x>_rect(source).get_center().x else -1.0
	var angle:=side*1.05*wave
	var target:=rim_point(destination)+Vector2(-side*25,-40)
	var offset:=transfer_lip(source,Rect2(Vector2.ZERO,rect.size),side*1.05)
	rect.position=rect.position.lerp(target-offset,wave)
	return {"rect":rect,"angle":angle}


func _advance_stir(delta: float) -> void:
	var engaged: bool=dragging and technique=="stir" and not moving_mixing and not moving_glass and not moving_shaker and data.get("spoon_vessel","")==selected
	var responding: bool=engaged and clock-stir_pointer_time<.18 and pointer_speed>=15
	# Visual motion has a gentle speed ceiling; grading still uses actual input.
	var target_rate:=clampf(pointer_speed/360.0,.25,1.25)*TAU if responding else 0.0
	var previous_rate:=stir_rate
	stir_rate=lerpf(stir_rate,target_rate,1-exp(-delta*7))
	stir_angle=fmod(stir_angle+(previous_rate+stir_rate)*.5*delta,TAU)
	var target_energy:=clampf(stir_rate/(TAU*.65),0,1)
	stir_energy=lerpf(stir_energy,target_energy,1-exp(-delta*8))
	if not responding: return
	last_motion_time=clock
	motion_energy=1.0
	var seconds:=minf(delta,.08)
	control_integral+=seconds*control_quality()
	accumulated+=seconds
	if accumulated>=.25:
		motion_completed.emit("stir",minf(accumulated,.5))
		accumulated=0
		control_integral=0

func _make_custom_tooltip(text: String) -> Object:
	return ToolHelp.popup(text)

func _draw_drain() -> void:
	var active:=dragging and selected in POS and DRAIN_RECT.has_point(last_point)
	var center:=DRAIN_RECT.get_center()
	_ellipse(center+Vector2(0,7),Vector2(145,27),Color(0,0,0,.5))
	_ellipse(center,Vector2(144,27),Color("c9a46b") if active else Color("8c7860"))
	_ellipse(center-Vector2(0,2),Vector2(135,21),Color("342e26"))
	_ellipse(center-Vector2(0,3),Vector2(123,16),Color("1e2323"))
	for i in range(5):
		var x:=DRAIN_RECT.position.x+16+i*6
		draw_line(Vector2(x,center.y-10),Vector2(x,center.y+9),Color("746c5c"),2,true)
	if drain_flash>0:
		draw_arc(center,20+(1-drain_flash)*95,0,TAU,40,Color(.86,.79,.62,drain_flash*.6),2,true)
	var text:="松手倒掉 · 不退库存" if active else "弃液槽 · 拖入倒掉"
	draw_string(_font,Vector2(84,790),text,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("f8e5bf"))
