extends "res://scripts/guest_activity_board.gd"
## Painted tiles, smooth saved motion and transient feedback; no visual changes mutate the puzzle.
const Crates=preload("res://scripts/hank_crate_rules.gd")
const SHED=preload("res://assets/activities/v3/hank-shed.png")
const CARGO=preload("res://assets/activities/v3/crates.png")
const TILES=preload("res://assets/activities/v4/hank-tiles.png")
const PAPER=preload("res://assets/codex/journal-paper-v1.png")
var travel:=0.0
var duration:=.16
var previous: Dictionary={}
var facing:=Vector2.DOWN
var pressed_box:=-1
var dust: Array=[]
var landing_cells: Dictionary={}
var hint_direction:=""
var hint_life:=0.0
var hover_cell:=-1

func tile_size() -> float:
	var cfg:=Crates.config_for(game.state())
	return minf(80,minf(640.0/cfg.width,510.0/cfg.height))
func grid_rect() -> Rect2:
	var cfg:=Crates.config_for(game.state())
	var dimensions:=Vector2(cfg.width,cfg.height)*tile_size()
	return Rect2(Vector2(810,465)-dimensions*.5,dimensions)
func cell_rect(cell: int) -> Rect2:
	var w: int=Crates.config_for(game.state()).width
	return Rect2(grid_rect().position+Vector2(cell%w,cell/w)*tile_size(),Vector2.ONE*tile_size())
func cell_at(at: Vector2) -> int:
	if not grid_rect().has_point(at): return -1
	var w: int=Crates.config_for(game.state()).width
	var v: Vector2=(at-grid_rect().position)/tile_size()
	return floori(v.y)*w+floori(v.x)
func animate_move(before: Dictionary, after: Dictionary) -> void:
	previous=before.duplicate(true)
	var pushed: bool=before.boxes!=after.boxes
	duration=.24 if pushed else .13; travel=duration
	hint_life=0
	facing=(cell_rect(int(after.player)).get_center()-cell_rect(int(before.player)).get_center()).normalized()
	if pushed:
		for i in range(after.boxes.size()):
			if after.boxes[i]==before.boxes[i]: continue
			var at:=cell_rect(int(before.boxes[i])).get_center()+Vector2(0,tile_size()*.35)
			for j in range(7): dust.append({"at":at+Vector2((j-3)*4,0),"v":Vector2((j-3)*9,-14-j*2),"life":.65,"seed":j})
			if after.boxes[i] in Crates.config_for(after).goals: landing_cells[int(after.boxes[i])]=.9
	if Crates.filled(after)>Crates.filled(before): pulse=.75
func finish_motion() -> void:
	travel=0; previous={}; cancel_drag(); queue_redraw()
func clear_feedback() -> void:
	dust=[]; landing_cells={}; hint_life=0; hint_direction=""; hover_cell=-1; previous={}
func advance(delta: float) -> void:
	time+=delta; travel=maxf(0,travel-delta); pulse=maxf(0,pulse-delta); reject_time=maxf(0,reject_time-delta); hint_life=maxf(0,hint_life-delta)
	for particle in dust:
		particle.life-=delta; particle.at+=particle.v*delta
	dust=dust.filter(func(p): return p.life>0)
	for cell in landing_cells.keys():
		landing_cells[cell]-=delta
		if landing_cells[cell]<=0: landing_cells.erase(cell)
func cancel_drag() -> void:
	super.cancel_drag(); pressed_box=-1
func _location(cell: int, old_cell: int) -> Vector2:
	var to:=cell_rect(cell).get_center()
	if travel<=0: return to
	var t:=clampf(1-travel/duration,0,1); t=t*t*(3-2*t)
	return cell_rect(old_cell).get_center().lerp(to,t)
func _cargo(rect: Rect2, index: int) -> void:
	var regions: Array=[Rect2(.068,.046,.39,.423),Rect2(.546,.046,.402,.425),Rect2(.068,.522,.395,.438),Rect2(.581,.493,.378,.451)]
	var r: Rect2=regions[index]; var dim:=CARGO.get_size()
	draw_texture_rect_region(CARGO,rect,Rect2(r.position*dim,r.size*dim))
func _tile(rect: Rect2, index: int, tint:=Color.WHITE) -> void:
	var extent:=TILES.get_size()*.5
	draw_texture_rect_region(TILES,rect,Rect2(Vector2(index%2,index/2)*extent,extent),tint)
func _arrow(at: Vector2, direction: Vector2, tint: Color) -> void:
	var tip:=at+direction*28
	draw_line(at-direction*12,tip,tint,4,true)
	draw_line(tip,tip-direction.rotated(.65)*13,tint,4,true)
	draw_line(tip,tip-direction.rotated(-.65)*13,tint,4,true)
func _paper_card(rect: Rect2) -> void:
	_box(Rect2(rect.position+Vector2(4,8),rect.size),Color(0,0,0,.3),Color.TRANSPARENT,8)
	draw_texture_rect(PAPER,rect,false,Color(.95,.9,.8))
func _draw() -> void:
	draw_texture_rect(SHED,Rect2(Vector2.ZERO,size),false)
	draw_rect(Rect2(Vector2.ZERO,size),Color(.075,.055,.035,.30))
	var s: Dictionary=game.state()
	if s.get("model")!=2: return
	var cfg:=Crates.config_for(s); var grid:=grid_rect(); var unit:=tile_size()
	var plate:=grid.grow(20)
	_box(Rect2(plate.position+Vector2(0,13),plate.size),Color(0,0,0,.48),Color.TRANSPARENT,9)
	_tile(plate,1,Color(.78,.75,.69))
	_box(grid.grow(7),Color("211c17"),Color("c29856"),4)
	for corner in [plate.position+Vector2(8,8),plate.position+Vector2(plate.size.x-8,8),plate.end-Vector2(8,8),plate.position+Vector2(8,plate.size.y-8)]:
		draw_circle(corner,3,Color("b68a4c")); draw_line(corner-Vector2(2,0),corner+Vector2(2,0),Color("503b28"),1,true)
	for cell in range(cfg.width*cfg.height):
		var rect:=cell_rect(cell)
		if cell not in cfg.floor:
			_tile(rect,1,Color("827463"))
			_tile(Rect2(rect.position-Vector2(0,5),rect.size-Vector2(1,3)),2,Color(.68,.69,.68))
			draw_rect(Rect2(rect.position+Vector2(0,unit-7),Vector2(unit,7)),Color(0,0,0,.38))
		else:
			_tile(rect,3 if cell in cfg.goals else 0,Color(.83,.77,.65) if cell not in cfg.goals else Color(1,.97,.85))
			draw_rect(rect,Color(0,0,0,.18),false,1)
			if cell in cfg.goals:
				draw_rect(rect.grow(-4),Color("e4be68"),false,1.5)
			if cell in cfg.goals and cell in s.boxes:
				_box(rect.grow(-2),Color(.98,.8,.4,.13),Color("f6d892"),4)
			if hover_cell==cell and not dragging and game.playing and not game.paused:
				draw_rect(rect.grow(-2),Color(1,.93,.74,.10))
	var actors: Array=[]
	for i in range(s.boxes.size()):
		var old_cell: int=int(previous.boxes[i]) if not previous.is_empty() and previous.boxes.size()==s.boxes.size() else int(s.boxes[i])
		actors.append({"at":_location(int(s.boxes[i]),old_cell),"index":i,"player":false,"moving":old_cell!=int(s.boxes[i]),"cell":s.boxes[i]})
	actors.append({"at":_location(int(s.player),int(previous.get("player",s.player))),"index":3,"player":true,"moving":travel>0,"cell":s.player})
	actors.sort_custom(func(a: Dictionary,b: Dictionary): return a.at.y<b.at.y)
	for actor in actors:
		var at: Vector2=actor.at
		_ellipse(at+Vector2(0,unit*.31),Vector2(unit*.39,unit*.12),Color(0,0,0,.42))
		if actor.player:
			var bob:=sin((1-travel/duration)*TAU)*2 if travel>0 else sin(time*1.8)*.5
			draw_set_transform(at,0,Vector2(-1 if facing.x>0 else 1,1))
			_cargo(Rect2(Vector2(-unit*.39,-unit*.55-bob),Vector2(unit*.78,unit*.98)),3)
			draw_set_transform(Vector2.ZERO)
			if travel<=0: draw_arc(at+Vector2(0,unit*.36),unit*.25,.12,PI-.12,16,Color(1,.89,.61,.5),1.5,true)
		else:
			var wobble:=sin((1-travel/duration)*PI)*.025*facing.x if travel>0 and actor.moving else 0.0
			draw_set_transform(at,wobble)
			_cargo(Rect2(Vector2(-unit*.43,-unit*.51),Vector2(unit*.86,unit*.89)),int(actor.index)%3)
			draw_set_transform(Vector2.ZERO)
			if actor.cell in cfg.goals:
				draw_circle(at+Vector2(unit*.30,-unit*.31),unit*.085,Color("f1d38a"))
				draw_line(at+Vector2(unit*.26,-unit*.31),at+Vector2(unit*.29,-unit*.27),Color("493321"),2,true)
				draw_line(at+Vector2(unit*.29,-unit*.27),at+Vector2(unit*.35,-unit*.36),Color("493321"),2,true)
	for particle in dust:
		draw_circle(particle.at,1.6+particle.seed*.2,Color(.95,.80,.54,float(particle.life)*.48))
	for cell in landing_cells:
		var fade: float=landing_cells[cell]/.9; var at:=cell_rect(int(cell)).get_center()
		draw_arc(at,unit*(.38+(1-fade)*.25),0,TAU,40,Color(1,.85,.47,fade*.75),2,true)
		for j in range(8):
			var ray:=Vector2.from_angle(j*TAU/8); var center:=at+ray*unit*(.48+(1-fade)*.18)
			draw_line(center-ray*4,center+ray*4,Color(1,.94,.68,fade),2,true)
	if pressed_box>=0 and dragging:
		var delta:=pointer-press
		var direction:=Vector2(signf(delta.x),0) if absf(delta.x)>absf(delta.y) else Vector2(0,signf(delta.y))
		_arrow(cell_rect(int(s.boxes[pressed_box])).get_center(),direction,Color("fff0b5"))
	elif hint_life>0 and Crates.DIRS.has(hint_direction):
		_arrow(cell_rect(int(s.player)).get_center(),Vector2(Crates.DIRS[hint_direction]),Color(1,.92,.57,.65+.25*sin(time*5)))
	if reject_time>0:
		draw_rect(cell_rect(int(s.player)).grow(-2),Color(.86,.42,.23,reject_time),false,3)
	_tag(Rect2(487,141,646,47),"第 %d / %d 关 · %s" % [int(s.stage)+1,Crates.stage_count(s),Crates.stage_name(s)],25)
	_paper_card(Rect2(44,241,334,337))
	_text(Vector2(76,290),"风沙前的备货单",26)
	draw_line(Vector2(76,306),Vector2(346,306),Color("a98957"),1,true)
	_text(Vector2(76,345),"玛莎的灯 · 齐恩的账",21)
	_text(Vector2(76,382),"车夫带回来的那条路",21)
	var lessons: Array={0:["先绕到箱后，","再决定从哪一侧推。"],1:["窄门先别堵。","给自己留个转身处。"],2:["要去近处的箱子，","也可能得先绕远路。"],3:["已备妥的箱子，","有时也要暂时让路。"],4:["别急着填满眼前的格子。","先看看最后一箱的路。"]}[int(s.stage)]
	_text(Vector2(76,446),lessons[0],21)
	_text(Vector2(76,481),lessons[1],21)
	_text(Vector2(76,543),"不限时 · 可以随时撤回",19,Color("80613c"))
	_paper_card(Rect2(1184,245,368,341))
	_text(Vector2(1218,291),"待出发的物资",26)
	for i in range(s.boxes.size()):
		var y:=333+i*43; var done: bool=s.boxes[i] in cfg.goals
		_text(Vector2(1218,y),["提灯箱","灯油箱","绳索箱"][i%3]+"  %02d" % (i+1),21)
		_text(Vector2(1431,y),"已备妥" if done else "待就位",19,Color("576241") if done else Color("987441"))
	_text(Vector2(1218,540),"备妥 %d / %d" % [Crates.filled(s),s.boxes.size()],22)
	_tag(Rect2(1190,604,360,46),"走了 %d 步 · 推了 %d 次" % [s.steps,s.pushes],21)
	_tag(Rect2(1190,666,360,46),"Z 撤回  ·  H 提示  ·  R 重来",20)
	if Crates.solved(s):
		_tag(Rect2(625,724,370,41),"本关备妥 · 稍后自动继续",23)
func _gui_input(event: InputEvent) -> void:
	if not game.playing or game.paused or is_instance_valid(game.overlay): return
	if event is InputEventMouseMotion:
		pointer=event.position; hover_cell=cell_at(pointer)
		if pressed_box>=0 and pointer.distance_to(press)>12: dragging=true
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: cancel_drag(); game._undo(); accept_event(); return
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		if event.pressed:
			if travel>0: return
			press=event.position; pointer=press; pressed_box=game.state().boxes.find(cell_at(press)); dragging=false
		else:
			if pressed_box>=0 and dragging:
				var delta: Vector2=event.position-press
				var direction: String=("R" if delta.x>0 else "L") if absf(delta.x)>absf(delta.y) else ("D" if delta.y>0 else "U")
				game.crate_drag_push(pressed_box,direction)
			elif cell_at(event.position)>=0: game.crate_walk_to(cell_at(event.position))
			cancel_drag()
		accept_event()
