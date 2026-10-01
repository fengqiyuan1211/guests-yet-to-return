extends Control
## First-person artwork; interaction hit areas are tied to movable independent sprites.
signal vessel_selected(id: String)
signal prop_selected(id: String)
signal transfer_requested(source: String, destination: String)
signal motion_completed(kind: String, seconds: float)
signal serve_requested
signal item_dropped(tab: String, id: String, target: String, dragged: bool)
const Liquid = preload("res://scripts/workbench_liquid.gd")
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
var carry_id := ""
var carry_tab := ""
var carry_start := Vector2.ZERO
var carry_point := Vector2.ZERO
var drop_target := ""
var preview_amount := 0.0
var pour_blend := 0.0
var transition_from: Dictionary = {}
var transition_progress := 1.0
var animated_destination := ""
var effects: Dictionary = {}
var clock := 0.0
var selected := ""
var technique := "shake"
var data: Dictionary = {}
var bottle := ""
var pouring := false
var pour_vessel := "jigger"
var moving_glass := false
const SERVE_RECT := Rect2(1005,660,220,90)
var input_enabled := true
var hover := ""
var dragging := false
var last_point := Vector2.ZERO
var press_point := Vector2.ZERO
var last_tick := 0
var accumulated := 0.0
var shake_direction := 0
var travel := 0.0
var movement := Vector2.ZERO
var lift_blend := 0.0
var shake_depth := 0.0
var depth_target := 0.0
var animated_source := ""
var animation_progress := 0.0
var _font: Font = preload("res://assets/fonts/NotoSerifSC.ttf")
var background: Texture2D

func _ready() -> void:
	if ResourceLoader.exists(Art.ROOT+"background.png"):
		background = load(Art.ROOT+"background.png")
	mouse_default_cursor_shape = CURSOR_POINTING_HAND

func _process(delta: float) -> void:
	clock += delta
	var held: bool = dragging and selected=="shaker" and technique=="shake" and data.get("lid",false)
	lift_blend = move_toward(lift_blend,1.0 if held else 0.0,delta*4.5)
	shake_depth = lerpf(shake_depth,depth_target if held else 0.0,1-exp(-delta*18))
	pour_blend = move_toward(pour_blend,1.0 if pouring else 0.0,delta*4)
	transition_progress = minf(1.0,transition_progress+delta/1.1)
	if not animated_source.is_empty():
		animation_progress += delta/1.1
		if animation_progress>=1:
			animated_source=""
	queue_redraw()

func apply_snapshot(snapshot: Dictionary) -> void:
	if data.get("vessels",{}) != snapshot.get("vessels",{}):
		var previous_contents := {}
		for id in snapshot.get("vessels",{}):
			previous_contents[id] = contents_for(id)
			var old: Dictionary=data.get("vessels",{}).get(id,{})
			var new: Dictionary=snapshot.vessels[id]
			if old.get("ice","none")!=new.ice or old.get("garnish",false)!=new.garnish: effects[id]=clock
		transition_from=previous_contents
		transition_progress = 0.0 if not data.is_empty() else 1.0
	data = snapshot

func contents_for(id: String) -> Dictionary:
	var actual: Dictionary = data.get("vessels",{}).get(id,{}).get("contents",{})
	var result := Liquid.interpolate(transition_from.get(id,actual),actual,transition_progress)
	if pouring and id==pour_vessel and not bottle.is_empty():
		result = actual.duplicate()
		result[bottle] = float(result.get(bottle,0))+preview_amount
	return result

func bottle_rect(id: String) -> Rect2:
	var index := materials.find(id)
	return Rect2(320+maxi(0,index)*128,350,82,200)

func begin_item_drag(tab: String, id: String, point: Vector2) -> void:
	if not input_enabled or data.get("status")!="mixing": return
	stop_gesture()
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
	if tab=="冰块": return target in ["shaker","mixing","glass"] and not (target=="shaker" and data.get("lid",false))
	if tab in ["装饰","杯子"]: return target=="glass"
	if id in ["lid","cap"]: return target in ["shaker","lid","cap"]
	if id=="strainer": return target in ["shaker","mixing"]
	if id in ["spoon","muddler"]: return target in ["shaker","mixing","glass"]
	return false

func _destination(point: Vector2) -> String:
	if SERVE_RECT.has_point(point): return "serve"
	if Rect2(1260,18,322,864).has_point(point): return "pantry"
	return _hit(point)

func _rect(id: String) -> Rect2:
	if data.get("lid",false):
		if id=="lid": return Rect2(376,440,178,150)
		if id=="cap": return Rect2(439,421,52,50)
	if id=="bottle": return bottle_rect(bottle)
	return RECTS[id]

func prop_visible(id: String) -> bool:
	if id=="strainer": return false
	if id=="muddler": return dragging and technique=="muddle" and selected in ["mixing","glass","shaker"]
	return true

func _hit(point: Vector2) -> String:
	if lift_blend>.01:
		var local := shaker_pose().affine_inverse()*point
		for part in ["cap","lid","shaker"]:
			if part!="shaker" and not data.get("lid",false): continue
			if _rect(part).has_point(local): return "shaker"
	var ids: Array = RECTS.keys()
	ids.reverse()
	for id in ids:
		if id in ["strainer","muddler"]: continue
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

func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	draw_set_transform(center,0,radii)
	draw_circle(Vector2.ZERO,1,color)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if background!=null:
		draw_texture_rect(background,Rect2(0,0,1600,900),false)
	else:
		draw_rect(Rect2(0,0,1600,900),Color("493021"))
	_draw_bottles()
	if moving_glass:
		var style := _tooltip_style()
		style.bg_color=Color(.18,.12,.06,.65)
		draw_style_box(style,SERVE_RECT)
		draw_string(_font,SERVE_RECT.position+Vector2(35,52),"松手出杯",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("eed7a5"))
	for id in RECTS:
		if not prop_visible(id): continue
		if lift_blend>.01 and (id=="shaker" or (id in ["lid","cap"] and data.get("lid",false))): continue
		if id=="bottle" and bottle.is_empty(): continue
		var rect := _rect(id)
		var angle := 0.0
		var texture_id: String = id
		if id=="glass": texture_id="coupe" if data.get("cup","coupe") == "coupe" else "highball"
		if id=="bottle": texture_id=bottle
		if id==selected and dragging:
			if id=="jigger" or (id=="glass" and moving_glass): rect.position+=movement
		if id==animated_source and RECTS.has(animated_destination):
			var wave := sin(animation_progress*PI)
			var destination: Rect2 = _rect(animated_destination)
			var aim := destination.position+Vector2(destination.size.x*.5+95,-100)
			rect.position = rect.position.lerp(aim,wave)
			angle = -1.05*wave
		if id=="bottle" and pouring:
			rect=Rect2(840,352,115,265)
			angle=-1.0
		if id=="spoon" and dragging and technique=="stir" and POS.has(selected):
			rect.position=last_point-Vector2(25,170)
			angle=.24
		if id=="muddler" and dragging and technique=="muddle" and POS.has(selected):
			rect.position=last_point-Vector2(25,145)
		_ellipse(rect.position+Vector2(rect.size.x*.53,rect.size.y-3),Vector2(rect.size.x*.44,9),Color(0,0,0,.23))
		var vessel: Dictionary = data.get("vessels",{}).get(id,{})
		var contents := contents_for(id)
		var qty := Liquid.volume(contents)
		var texture: Texture2D = Art.texture(texture_id)
		var extent := texture.get_size()*minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
		var liquid_rect := Rect2(rect.position+Vector2((rect.size.x-extent.x)*.5,rect.size.y-extent.y),extent)
		var ripple := absf(sin(clock*9)) if dragging or transition_progress<1 or (pouring and pour_vessel==id) else 0.0
		if qty>0 and id=="glass":
			Liquid.draw(self,liquid_rect,contents,float(WorkbenchSession.CAPACITIES[id]),texture_id=="coupe",ripple,vessel.get("ice","none")!="none",clock)
		_sprite(texture_id,rect,angle)
		if qty>0 and id=="mixing":
			# The shared art has an opaque, thick glass floor. Tint its inner basin
			# above the texture so small pours remain visible, inside the wall edges.
			var pivot := rect.position+Vector2(rect.size.x*.5,rect.size.y)
			draw_set_transform_matrix(Transform2D(0,pivot)*Transform2D(angle,Vector2.ZERO)*Transform2D(0,-pivot))
			Liquid.draw(self,liquid_rect,contents,float(WorkbenchSession.CAPACITIES[id]),false,ripple,vessel.get("ice","none")!="none",clock,true)
			draw_set_transform(Vector2.ZERO)
		if qty>0 and id in ["jigger","shaker"] and not (id=="shaker" and data.get("lid",false)):
			_ellipse(rect.position+Vector2(rect.size.x*.5,rect.size.y*.10),Vector2(rect.size.x*.29,3+9*minf(qty/90,1)),Liquid.color(contents))
		if id==animated_source and RECTS.has(animated_destination) and animation_progress>.2 and animation_progress<.8:
			var mouth := rect.position+Vector2(rect.size.x*.5,rect.size.y)+Vector2(0,-rect.size.y).rotated(angle)
			var destination: Rect2 = _rect(animated_destination)
			var target := destination.position+Vector2(destination.size.x*.5,18)
			Liquid.stream(self,mouth,target,Liquid.color(contents_for(animated_destination)),clock)
		if vessel.get("ice","none")!="none" and not (id=="shaker" and data.get("lid",false)):
			var fall := (1.0-clampf((clock-float(effects.get(id,-10)))/.4,0,1))*30
			var ice_y := liquid_rect.size.y*.13
			if id in ["glass","mixing"]:
				ice_y=liquid_rect.size.y*Liquid.surface_fraction(qty,float(WorkbenchSession.CAPACITIES[id]),texture_id=="coupe",true,id=="mixing")+12
			var ice_rect := Rect2(liquid_rect.position+Vector2(liquid_rect.size.x*.24,ice_y-38-fall),Vector2(liquid_rect.size.x*.5,38))
			_sprite(vessel.ice,ice_rect)
		if vessel.get("garnish",false):
			_sprite("garnish",Rect2(liquid_rect.position+Vector2(liquid_rect.size.x*.66,0),Vector2(48,42)))
		if (id==hover or id==selected) and not pouring:
			_ellipse(rect.position+Vector2(rect.size.x*.5,rect.size.y+3),Vector2(rect.size.x*.48,5),Color(.93,.72,.34,.30))
	if lift_blend>.01: _draw_held_shaker()
	if pour_blend>0.0: _draw_pouring()
	if not carry_id.is_empty():
		if RECTS.has(drop_target) and can_target(carry_id,carry_tab,drop_target):
			var target: Rect2 = _rect(drop_target)
			_ellipse(target.position+Vector2(target.size.x*.5,16),Vector2(target.size.x*.5,10),Color(.94,.79,.38,.5))
		var ghost := Rect2(carry_point-Vector2(45,130),Vector2(90,160))
		_ellipse(carry_point+Vector2(12,30),Vector2(40,7),Color(0,0,0,.16))
		_sprite(carry_id,ghost,-.08)
	if not hover.is_empty() and input_enabled and not dragging and carry_id.is_empty():
		var hovered_material := hover.trim_prefix("bottle:") if hover.begins_with("bottle:") else ""
		var label: String = NAMES.get(hover,"")
		var hover_rect: Rect2 = _rect(hover) if hovered_material.is_empty() else bottle_rect(hovered_material)
		if not hovered_material.is_empty(): label=WorkbenchSession.MATERIALS[hovered_material].name+" · 拖到杯子或制作容器"
		elif hover=="jigger": label+=" · 拖到容器倒入"
		elif hover in ["lid","cap"]: label+=" · 拖到壶口 / 点击开合"
		else: label+=" · 点击选取"
		var width := _font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+22
		var p := hover_rect.position-Vector2(0,34)
		p.x=clampf(p.x,15,1220-width)
		draw_style_box(_tooltip_style(),Rect2(p,Vector2(width,30)))
		draw_string(_font,p+Vector2(11,22),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("eed7a5"))

func _tooltip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=Color(.12,.08,.04,.9)
	style.border_color=Color("b68c48")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func _draw_bottles() -> void:
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
	var base_goal := mouth_goal-Vector2(0,-200).rotated(pouring_angle)
	var pouring_rect := Rect2(base_goal-Vector2(41,200),Vector2(82,200))
	var rect := Rect2(rest.position.lerp(pouring_rect.position,pour_blend),rest.size)
	var angle := pouring_angle*pour_blend
	_sprite(bottle,rect,angle)
	if pouring and pour_blend>.94:
		var mouth := rect.position+Vector2(41,200)+Vector2(0,-200).rotated(angle)
		Liquid.stream(self,mouth,target,Liquid.COLORS[bottle],clock)

func rim_point(id: String) -> Vector2:
	var rect := _rect(id)
	var texture_id := "coupe" if data.get("cup","coupe")=="coupe" else "highball"
	var texture := Art.texture(texture_id if id=="glass" else id)
	var extent := texture.get_size()*minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
	return rect.position+Vector2(rect.size.x*.5,rect.size.y-extent.y+extent.y*.085)

func shaker_pose() -> Transform2D:
	var rest := Vector2(465,615)
	var raised := Vector2(670,405)+Vector2(12*shake_depth,52*shake_depth)
	var center := rest.lerp(raised,smoothstep(0,1,lift_blend))
	var scale_factor := 1.0+lift_blend*(.12+shake_depth*.12)
	var angle := lift_blend*(-.98+shake_depth*.12)
	return Transform2D(angle,Vector2.ONE*scale_factor,0,center)*Transform2D(0,-rest)

func _draw_held_shaker() -> void:
	# All three pieces share one transform: the lid never drifts away from the body.
	var pose := shaker_pose()
	var shadow := Vector2(465,790).lerp(Vector2(625,790),lift_blend)
	_ellipse(shadow,Vector2(88+lift_blend*40,9+lift_blend*5),Color(0,0,0,.23-lift_blend*.13))
	_sprite("shaker",_rect("shaker"),0,Color.WHITE,pose)
	if data.get("lid",false):
		_sprite("lid",_rect("lid"),0,Color.WHITE,pose)
		_sprite("cap",_rect("cap"),0,Color.WHITE,pose)
	if dragging:
		draw_style_box(_tooltip_style(),Rect2(422,218,575,40))
		draw_string(_font,Vector2(440,245),"已拿起 · 鼠标上下推拉，前后摇和 · 松手放回",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("eed7a5"))

func _gui_input(event: InputEvent) -> void:
	if not input_enabled: return
	if event is InputEventMouseMotion and not dragging:
		hover=_hit(event.position)
		queue_redraw()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var id := _hit(event.position)
		if id.is_empty(): return
		stop_gesture()
		if id.begins_with("bottle:"):
			begin_item_drag("材料",id.trim_prefix("bottle:"),event.position)
			accept_event()
			return
		if id in ["lid","cap","spoon","muddler","strainer"]:
			begin_item_drag("器具",id,event.position)
			accept_event()
			return
		if POS.has(id):
			selected=id
			vessel_selected.emit(id)
			if not input_enabled: return
			dragging=true
			moving_glass=id=="glass" and (technique not in ["stir","muddle"] or event.position.y>_rect("glass").position.y+_rect("glass").size.y*.65)
			press_point=event.position
			last_point=event.position
			last_tick=Time.get_ticks_msec()
			travel=0
			shake_direction=0
		else:
			prop_selected.emit(id)
		queue_redraw()
		accept_event()

func _input(event: InputEvent) -> void:
	if not carry_id.is_empty():
		if event is InputEventMouseMotion:
			carry_point=get_global_transform_with_canvas().affine_inverse()*event.position
			drop_target=_destination(carry_point)
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
		var should_serve := moving_glass and destination=="serve" and movement.length()>25
		var should_transfer := selected=="jigger" and destination in ["shaker","mixing","glass"] and movement.length()>25
		stop_gesture()
		if should_transfer: transfer_requested.emit("jigger",destination)
		elif should_serve: serve_requested.emit()
	elif event is InputEventMouseMotion:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		var delta: Vector2=point-last_point
		var now := Time.get_ticks_msec()
		var seconds := clampf((now-last_tick)/1000.0,0,.08)
		var valid: bool=delta.length()>3 and delta.length()<180
		if selected=="jigger" or moving_glass:
			movement=(point-press_point).limit_length(800)
			valid=false
		elif technique=="stir":
			var a: Vector2=last_point-POS[selected]
			var b: Vector2=point-POS[selected]
			valid=valid and a.length()>18 and b.length()>18 and b.length()<130 and absf(a.angle_to(b))>.015 and absf(a.angle_to(b))<1.2
		else:
			var axis: float=delta.y
			var direction:=int(signf(axis))
			if direction!=shake_direction:
				travel=0
				shake_direction=direction
			travel+=absf(axis)
			valid=valid and absf(axis)>3 and travel<160
			if technique=="shake":
				depth_target=clampf((point.y-press_point.y)/75.0,-1.0,1.0)
				valid=valid and selected=="shaker" and data.get("lid",false) and lift_blend>.5 and absf(delta.y)>absf(delta.x)*.7
			else:
				movement=(point-press_point).limit_length(40)
		if valid:
			accumulated+=seconds
			if accumulated>=.25:
				motion_completed.emit(technique,minf(accumulated,.5))
				accumulated=0
		last_point=point
		last_tick=now
		queue_redraw()

func stop_gesture() -> void:
	if accumulated>.01: motion_completed.emit(technique,minf(accumulated,.5))
	accumulated=0
	dragging=false
	moving_glass=false
	depth_target=0.0
	movement=Vector2.ZERO
	queue_redraw()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		stop_gesture()
		cancel_carry()
