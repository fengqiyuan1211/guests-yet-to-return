extends Control
## Scenery is a painted layer; all hit areas, moving pieces and state are live.
const FONT=preload("res://assets/fonts/NotoSerifSC.ttf")
const Watch=preload("res://scripts/watch_repair_rules.gd")
const MECHANICS=preload("res://assets/activities/v2/mechanics.png")
const PEOPLE=preload("res://assets/activities/v3/police-prisoners.png")
const OBJECTS=preload("res://assets/activities/v2/objects.png")
const BACKGROUNDS={"milo_ferry":preload("res://assets/activities/v2/milo-river.png"),"ada_watch_memory":preload("res://assets/activities/v2/ada-bench.png"),"hank_lantern":preload("res://assets/activities/v2/hank-theater.png")}
const INK=Color("493321")
var game: Control
var time:=0.0
var people: Array=[]
var passengers: Array=[]
var press:=Vector2.ZERO
var dragging:=false
var held:=-1
var selected:=-1
var pickup:=Vector2.ZERO
var pointer:=Vector2.ZERO
var lamp_drag:=false
var crown_drag:=false
var crown_distance:=0.0
var landing:=0.0
var pulse:=0.0
var reject_time:=0.0
var lamp_y:=440.0
var angles: Dictionary={}
var watch_motion=preload("res://scripts/watch_repair_motion.gd").new()
var drag_kind:=-1
var drag_origin:=""

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	clip_contents=true
func advance(delta: float) -> void:
	time+=delta; landing=maxf(0,landing-delta); pulse=maxf(0,pulse-delta); reject_time=maxf(0,reject_time-delta)
	if game.activity_id=="hank_lantern": lamp_y=lerpf(lamp_y,lane_y(int(game.state().lane))-50,1-exp(-delta*22))
	if game.activity_id=="ada_watch_memory" and game.state().get("model")==2:
		watch_motion.advance(delta,game.state())
		for i in range(game.state().pieces.size()):
			var target:=int(game.state().pieces[i].turns)*PI/2
			angles[i]=lerp_angle(float(angles.get(i,target)),target,1-exp(-delta*24))
func cancel_drag() -> void:
	held=-1; dragging=false; lamp_drag=false; crown_drag=false; drag_kind=-1
func _text(at: Vector2, value: String, px:=22, color:=INK) -> void:
	draw_string(FONT,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,px,color)
func _box(rect: Rect2, fill: Color, border:=Color("9f7d4d"), radius:=8) -> void:
	var s:=StyleBoxFlat.new(); s.bg_color=fill; s.border_color=border; s.set_border_width_all(2); s.set_corner_radius_all(0); draw_style_box(s,rect)
func _tag(rect: Rect2, value: String, px:=22) -> void:
	_box(rect,Color("f1ddaf")); _text(rect.position+Vector2(13,rect.size.y*.68),value,px)
func sprite_region(index: int) -> Rect2:
	# Cropped regions of the original transparent sheet, no duplicated backgrounds.
	var normalized: Array=[Rect2(.135,.013,.24,.475),Rect2(.623,.015,.231,.477),Rect2(.017,.637,.499,.25),Rect2(.645,.505,.218,.465)]
	if index<2:
		var crop: Rect2=[Rect2(.135,.01,.26,.98),Rect2(.6,.025,.26,.97)][index]
		return Rect2(crop.position*PEOPLE.get_size(),crop.size*PEOPLE.get_size())
	var r: Rect2=normalized[index]; var dim:=OBJECTS.get_size()
	return Rect2(r.position*dim,r.size*dim)
func _sprite(rect: Rect2, index: int, tint:=Color.WHITE) -> void:
	var texture: Texture2D=preload("res://scripts/pixel_art.gd").sprite(["police","prisoner","boat","lantern"][index])
	if index<2:
		# Keep both people on the same foot line without stretching their bodies.
		var extent:=texture.get_size()*minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
		rect=Rect2(rect.position+Vector2((rect.size.x-extent.x)*.5,rect.size.y-extent.y),extent)
	draw_texture_rect(texture,rect,false,tint)
func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points:=PackedVector2Array()
	for i in range(40): points.append(center+Vector2(cos(i*TAU/40),sin(i*TAU/40))*radius)
	draw_colored_polygon(points,color)
func _draw() -> void:
	draw_texture_rect(preload("res://scripts/pixel_art.gd").scene(game.activity_id),Rect2(Vector2.ZERO,size),false)
	if game.activity_id=="milo_ferry": _ferry()
	elif game.activity_id=="ada_watch_memory": _watch()
	else: _lantern()

func boat_rect() -> Rect2:
	var fraction:=float(game.state().get("side",0))
	if game.sailing>0:
		var t:=clampf(1-game.sailing/.85,0,1); t=t*t*(3-2*t)
		fraction=lerpf(game.sail_from,1-game.sail_from,t)
	return Rect2(505+230*fraction,510+sin(time*2)*2+sin(landing*36)*landing*12,350,174)
func _token(center: Vector2, kind: int, chosen:=false) -> void:
	_ellipse(center+Vector2(0,62),Vector2(39,12),Color(0.08,.05,.03,.3))
	_sprite(Rect2(center-Vector2(41,77),Vector2(82,148)),kind)
	if chosen: draw_arc(center+Vector2(0,61),42,0,PI,32,Color("f4dc9d"),2,true)
func _ferry() -> void:
	var s: Dictionary=game.state(); people=[]; passengers=[]
	for y in range(215,755,43):
		for x in range(580,1030,74):
			var phase:=fmod(time*.3+x*.014+y*.02,1.0)
			draw_arc(Vector2(x+sin(time+x)*9,y+phase*8),14+phase*13,.15,2.6,14,Color(.86,.98,.90,.12*(1-phase)),1.4,true)
	for bank in [0,1]:
		var counts: Array=[int(s.left_p),int(s.left_d)] if bank==0 else [3-int(s.left_p),3-int(s.left_d)]
		if game.sailing>0 and bank==int(s.side):
			counts[0]-=game.sail_load[0]; counts[1]-=game.sail_load[1]
		elif game.sailing<=0 and bank==int(s.side):
			counts[0]-=game.selection[0]; counts[1]-=game.selection[1]
		for kind in [0,1]:
			for i in range(counts[kind]):
				var center:=Vector2(195+bank*1000+i*93,330+kind*156)
				if not (dragging and drag_origin=="shore" and Rect2(center-Vector2(41,77),Vector2(82,148)).has_point(press)): _token(center,kind)
				if bank==int(s.side) and game.sailing<=0: people.append({"rect":Rect2(center-Vector2(41,77),Vector2(82,148)),"kind":kind})
		_tag(Rect2(146+bank*1000,169,320,44),"%s %d 人 · 警 %d / 囚 %d" % ["此岸" if bank==0 else "对岸",counts[0]+counts[1],counts[0],counts[1]],21)
	var boat:=boat_rect()
	if game.sailing>0 or landing>0:
		for k in range(4):
			var r:=fmod(time*1.2+k*.24,1.0)
			draw_arc(boat.get_center()+Vector2(0,54),120+r*100,.05,3.1,45,Color(.95,.96,.78,(1-r)*.28),2,true)
	if reject_time>0: boat.position.x+=sin(reject_time*80)*7
	_sprite(boat,2)
	var load_pair: Array=game.sail_load if game.sailing>0 else game.selection
	var occupants: Array=[]
	for kind in [0,1]:
		for i in range(load_pair[kind]): occupants.append(kind)
	for i in range(2):
		var center:=boat.position+Vector2(100+i*150,39)
		if occupants.size()>i:
			if not (dragging and drag_origin=="boat" and Rect2(center-Vector2(42,76),Vector2(84,147)).has_point(press)): _token(center,occupants[i],true)
			passengers.append({"rect":Rect2(center-Vector2(42,76),Vector2(84,147)),"kind":occupants[i]})
		else:
			_ellipse(center+Vector2(0,42),Vector2(40,14),Color(1,.90,.60,.17 if not dragging else .5))
			_text(center+Vector2(-17,48),str(i+1),22,Color("fff0c9"))
	_tag(Rect2(boat.get_center()+Vector2(-48,52),Vector2(96,33)),"%d / 2" % occupants.size(),20)
	_tag(Rect2(660,710,282,44),"开船 · 空格",25)

func grid_rect() -> Rect2:
	return Rect2(535,251,384,384)
func cell_rect(cell: int) -> Rect2:
	var width: int=Watch.level(int(game.state().get("stage",0))).width
	var span:=grid_rect().size.x/width
	return Rect2(grid_rect().position+Vector2(cell%width,cell/width)*span,Vector2.ONE*span).grow(-5)
func piece_rect(id: int) -> Rect2:
	var s: Dictionary=game.state(); var cell:=int(s.pieces[id].cell)
	if cell>=0: return cell_rect(cell)
	return Rect2(1210+(id%3)*93,276+(id/3)*105,81,81)
func cell_at(at: Vector2) -> int:
	var width: int=Watch.level(int(game.state().stage)).width
	if not grid_rect().has_point(at): return -2
	var pos: Vector2=(at-grid_rect().position)/(grid_rect().size.x/width)
	return floori(pos.y)*width+floori(pos.x)
func mechanics_region(index: int) -> Rect2:
	var regions: Array=[Rect2(.046,.048,.414,.377),Rect2(.548,.047,.403,.384),Rect2(.127,.525,.29,.433),Rect2(.711,.499,.073,.456)]
	return regions[index]
func _mechanic(rect: Rect2, index: int, tint:=Color.WHITE) -> void:
	draw_texture_rect(preload("res://scripts/pixel_art.gd").sprite(["mechanism","gear","spring","hand"][index]),rect,false,tint)
func _gear(at: Vector2, radius: float, angle: float, alive: bool) -> void:
	draw_set_transform(at,angle)
	draw_texture_rect(preload("res://scripts/pixel_art.gd").sprite("gear"),Rect2(Vector2.ONE*-radius*1.1,Vector2.ONE*radius*2.2),false,Color(1.14,1.1,.96) if alive else Color(.78,.75,.67))
	draw_set_transform(Vector2.ZERO)
func _plate(rect: Rect2, id: int, alive: bool) -> void:
	var s: Dictionary=game.state(); var cfg:=Watch.level(int(s.stage)); var center:=rect.get_center()
	var angle:=float(angles.get(id,int(s.pieces[id].turns)*PI/2))
	draw_set_transform(center+Vector2(3,5),angle)
	_box(Rect2(-rect.size*.5,rect.size),Color(0,0,0,.3),Color(0,0,0,.05),9)
	draw_set_transform(center,angle)
	var r:=Rect2(-rect.size*.5,rect.size)
	_mechanic(r,0)
	var ports: int=cfg.masks[id]
	for d in range(4):
		if not ports&(1<<d): continue
		var v:=Vector2(Watch.DIRS[d]); var edge:=v*(rect.size.x*.5+4)
		draw_line(Vector2.ZERO,edge,Color("3b2d1d"),13,true)
		draw_line(Vector2.ZERO,edge,Color("a5834e"),9,true)
		draw_line(Vector2.ZERO-Vector2(1,2),edge-Vector2(1,2),Color("e0c58a"),3,true)
		for k in range(3):
			var a:=v*(rect.size.x*.38+k*3); var cross:=Vector2(-v.y,v.x)*7
			draw_line(a-cross,a+cross,Color("4e3c23"),1,true)
	_gear(Vector2.ZERO,rect.size.x*.28,watch_motion.gear_angle(id),alive)
	draw_set_transform(Vector2.ZERO)
	if id in cfg.fixed:
		_box(Rect2(rect.end-Vector2(30,25),Vector2(28,23)),Color("4c3b29")); _text(rect.end-Vector2(27,7),"固",16,Color("ebdbb9"))
	if id==selected: draw_rect(rect.grow(4),Color("ffedba"),false,3)
	_text(rect.position+Vector2(8,21),str(id+1),17,Color("fff1c6"))
func _watch() -> void:
	var s: Dictionary=game.state()
	if s.get("model")!=2: return
	var cfg:=Watch.level(int(s.stage)); var reached:=Watch.connected(int(s.stage),s.pieces)
	for cell in range(cfg.width*cfg.width):
		var r:=cell_rect(cell)
		_box(r,Color(.12,.10,.065,.68),Color("6c5536"),6)
		_text(r.position+Vector2(7,21),"%d·%d" % [cell/int(cfg.width)+1,cell%int(cfg.width)+1],16,Color("a58c61"))
		if held>=0 and dragging and cell_at(pointer)==cell and Watch.occupied(s.pieces,cell)<0: draw_rect(r,Color(1,.9,.6,.28))
	var source_y:=cell_rect(cfg.source).get_center().y
	var source:=Vector2(486,source_y)
	for i in range(11): draw_arc(source,5+i*3,0,TAU,48,Color("d0ae70"),1.6,true)
	draw_line(source+Vector2(33,0),Vector2(grid_rect().position.x,source_y),Color("ceb477"),7,true)
	_tag(Rect2(source-Vector2(50,77),Vector2(97,34)),"发条",20)
	for t in range(cfg.targets.size()):
		var y:=cell_rect(cfg.targets[t]).get_center().y; var id:=Watch.occupied(s.pieces,cfg.targets[t]); var live:=id>=0 and id in reached and Watch.mask(cfg.masks[id],int(s.pieces[id].turns))&2
		draw_line(Vector2(grid_rect().end.x,y),Vector2(979,y),Color("b7985d"),7,true)
		_gear(Vector2(983,y),29,watch_motion.target_angle(t),live)
		_tag(Rect2(946,y+38,100,31),"秒针" if t==0 else "摆轮",18)
	for i in range(s.pieces.size()):
		if held==i and dragging: continue
		_plate(piece_rect(i),i,i in reached)
	if held>=0 and dragging: _plate(Rect2(pointer-pickup,piece_rect(held).size),held,false)
	_tag(Rect2(1210,206,275,43),"备用组件 · 可放回",22)
	if Watch.solved(int(s.stage),s.pieces):
		_tag(Rect2(548,681,370,45),"传动已接通 · 空格继续",24)
		if s.stage==2:
			draw_arc(Vector2(708,46),52,-PI/2,-PI/2+TAU*maxf(.03,float(s.wind)/4),40,Color("ffdd85"),5,true)
	else: _tag(Rect2(534,685,405,42),"空格旋转组件座 · R 重置本段",21)

func lane_y(index: int) -> float: return 317+219*index
func lamp_rect() -> Rect2: return Rect2(749,lamp_y-91,74,150)
func _traveler(at: Vector2, wave: bool) -> void:
	_ellipse(at+Vector2(15,3),Vector2(43,7),Color(0,0,0,.27))
	var bob:=sin(time*(7 if wave else 15))*(1.5 if wave else 2.5)
	_mechanic(Rect2(at+Vector2(-39,-119+bob),Vector2(79,122)),2)
func _lantern() -> void:
	var s: Dictionary=game.state(); var lane:=int(s.lane)
	_mechanic(Rect2(773,170,27,563),3)
	for i in range(3):
		var y:=lane_y(i)
		if lane==i:
			for k in range(7):
				var alpha:=.023
				draw_colored_polygon(PackedVector2Array([Vector2(786,y-50),Vector2(350-k*14,y-150-k*3),Vector2(1252+k*5,y-12)]),Color(1,.82,.43,alpha))
			for k in range(8): draw_circle(Vector2(786,y-50),30+k*7,Color(1,.81,.37,.021))
		else: draw_arc(Vector2(786,y-50),25,0,TAU,28,Color(.88,.73,.45,.6),2,true)
		_tag(Rect2(69,y-120,94,35),["上路","中路","下路"][i],20)
		if s.index<6 and game.Rules.LANES[int(s.index)]==i:
			var walking:=float(s.get("walking",0.0))
			var x:=lerpf(238,588,clampf(float(s.elapsed)/1.5,0,1)) if walking<=0 else lerpf(588,1370,clampf(walking/.55,0,1))
			_traveler(Vector2(x,y),s.elapsed>=1.5 and walking<=0)
			if s.elapsed>=1.5 and walking<=0:
				_tag(Rect2(x-92,y-161,184,36),"在这里，借个光！",18)
				var flag:=Vector2(x+37,y-100); draw_line(flag,flag+Vector2(0,-25),Color("d5ba83"),2,true)
				draw_colored_polygon(PackedVector2Array([flag+Vector2(0,-25),flag+Vector2(30,-22+sin(time*5)*3),flag+Vector2(0,-8)]),Color("e7b96c"))
			if s.lit>0: draw_arc(Vector2(786,y-50),60,-PI/2,-PI/2+TAU*minf(float(s.lit)/.6,1),40,Color("ffe0a0"),5,true)
		if s.index>i:
			draw_circle(Vector2(1390,y-60),12,Color(1,.84,.45,.2+pulse*.3))
	var r:=lamp_rect()
	draw_set_transform(r.get_center(),sin(time*7)*pulse*.3)
	_sprite(Rect2(-r.size*.5,r.size),3)
	draw_set_transform(Vector2.ZERO)
	_tag(Rect2(543,733,518,34),"玛莎的灯 · 齐恩的油 · 车夫的路",21)

func _hit(rows: Array, at: Vector2) -> int:
	for row in rows:
		if row.rect.has_point(at): return int(row.kind)
	return -1
func _gui_input(event: InputEvent) -> void:
	if not game.playing or game.paused or is_instance_valid(game.overlay): return
	if event is InputEventMouseMotion:
		pointer=event.position
		if lamp_drag:
			var target:=clampi(roundi((pointer.y+50-317)/219),0,2)
			if absf(pointer.y-(lane_y(int(game.state().lane))-50))>119: game.lantern_lane(target)
			if event.relative.length()>3: game.audio.cue("scrape")
		elif crown_drag:
			crown_distance+=event.relative.length()
			if crown_distance>32:
				crown_distance=0
				if game.act("wind"): game.audio.cue("rotate")
		elif held>=0 and pointer.distance_to(press)>5: dragging=true; queue_redraw()
		return
	if not event is InputEventMouseButton: return
	if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and game.activity_id in ["milo_ferry","ada_watch_memory"]: cancel_drag(); game._undo(); accept_event(); return
	if event.button_index!=MOUSE_BUTTON_LEFT: return
	if event.pressed:
		press=event.position; pointer=press
		if game.activity_id=="hank_lantern":
			lamp_drag=lamp_rect().grow(25).has_point(press)
			if lamp_drag: game.audio.cue("metal")
			else: game.lantern_lane(clampi(roundi((press.y+50-317)/219),0,2))
		elif game.activity_id=="ada_watch_memory":
			if Rect2(650,0,120,108).has_point(press): crown_drag=true; return
			for i in range(game.state().pieces.size()):
				if piece_rect(i).has_point(press):
					selected=i
					if i not in Watch.level(int(game.state().stage)).fixed: held=i; pickup=press-piece_rect(i).position; game.audio.cue("metal")
					else: game.hint_label.text="带铆钉的组件已经固定，调整其余组件即可。"
					queue_redraw(); break
		return
	if game.activity_id=="ada_watch_memory":
		if held>=0 and dragging:
			var cell:=-1 if Rect2(1167,205,377,516).has_point(event.position) else cell_at(event.position)
			if game.act("move",{"piece":held,"cell":cell}): game.audio.cue("snap"); pulse=.25
		held=-1; dragging=false; crown_drag=false; queue_redraw(); return
	if game.activity_id=="hank_lantern": lamp_drag=false; return
	if dragging or event.position.distance_to(press)>10: return
	if game.sailing>0: return
	var kind:=_hit(passengers,event.position)
	if kind>=0: game.remove_person(kind)
	else:
		kind=_hit(people,event.position)
		if kind>=0: game.select_person(kind)
		elif Rect2(660,710,282,44).has_point(event.position): game._cross()
	accept_event()
func _get_drag_data(at: Vector2) -> Variant:
	if game.activity_id!="milo_ferry" or game.sailing>0 or not game.playing or game.paused or is_instance_valid(game.overlay): return null
	var origin:="shore"; var kind:=_hit(people,at)
	if kind<0: kind=_hit(passengers,at); origin="boat"
	if kind<0: return null
	dragging=true; drag_kind=kind; drag_origin=origin; game.audio.cue("pick")
	var wrapper:=Control.new(); var preview:=TextureRect.new()
	preview.texture=preload("res://scripts/pixel_art.gd").sprite("police" if drag_kind==0 else "prisoner")
	var extent:=preview.texture.get_size()*minf(82.0/preview.texture.get_width(),148.0/preview.texture.get_height())
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	preview.size=extent*game.surface.scale.x
	preview.position=Vector2(-extent.x*.5,71-extent.y)*game.surface.scale.x
	preview.mouse_filter=Control.MOUSE_FILTER_IGNORE; wrapper.add_child(preview); set_drag_preview(wrapper)
	return {"kind":kind,"origin":origin}
func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if game.paused or not game.playing or is_instance_valid(game.overlay) or game.sailing>0: return false
	if not data is Dictionary or not data.has("kind"): return false
	if data.origin=="shore": return boat_rect().grow(35).has_point(at) and game.selection[0]+game.selection[1]<2
	return Rect2(120 if game.state().side==0 else 1110,220,340,370).has_point(at)
func _drop_data(_at: Vector2, data: Variant) -> void:
	if data.origin=="shore": game.select_person(int(data.kind))
	else: game.remove_person(int(data.kind))
func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_END and dragging:
		if not is_drag_successful() and game.playing and not game.paused:
			game.hint_label.text="放到船上的空位，或拖回当前岸边；小船最多坐两人。"; game.audio.cue("reject")
		set_deferred("dragging",false); drag_kind=-1
