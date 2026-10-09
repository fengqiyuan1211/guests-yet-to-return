extends "res://scripts/guest_activity_board.gd"
## Art follows discrete, saved moves. Dragging requests a push, never teleports a crate.
const Crates=preload("res://scripts/hank_crate_rules.gd")
const SHED=preload("res://assets/activities/v3/hank-shed.png")
const CARGO=preload("res://assets/activities/v3/crates.png")
var travel:=0.0
var duration:=.16
var previous: Dictionary={}
var facing:=Vector2.DOWN
var pressed_box:=-1

func grid_rect() -> Rect2:
	var cfg:=Crates.layout(int(game.state().get("stage",0)))
	var dimensions:=Vector2(cfg.width,cfg.height)*80
	return Rect2(Vector2(810,449)-dimensions*.5,dimensions)
func cell_rect(cell: int) -> Rect2:
	var w: int=Crates.layout(int(game.state().get("stage",0))).width
	return Rect2(grid_rect().position+Vector2(cell%w,cell/w)*80,Vector2(80,80))
func cell_at(at: Vector2) -> int:
	if not grid_rect().has_point(at): return -1
	var w: int=Crates.layout(int(game.state().get("stage",0))).width
	var v: Vector2=(at-grid_rect().position)/80
	return floori(v.y)*w+floori(v.x)
func animate_move(before: Dictionary, after: Dictionary) -> void:
	previous=before.duplicate(true)
	var pushed: bool=before.boxes!=after.boxes
	duration=.20 if pushed else .12; travel=duration
	facing=(cell_rect(int(after.player)).get_center()-cell_rect(int(before.player)).get_center()).normalized()
	if Crates.filled(after)>Crates.filled(before): pulse=.75
func finish_motion() -> void:
	travel=0; previous={}; cancel_drag(); queue_redraw()
func advance(delta: float) -> void:
	time+=delta; travel=maxf(0,travel-delta); pulse=maxf(0,pulse-delta); reject_time=maxf(0,reject_time-delta)
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
func _draw() -> void:
	draw_texture_rect(SHED,Rect2(Vector2.ZERO,size),false)
	var s: Dictionary=game.state()
	if s.get("model")!=2: return
	var cfg:=Crates.layout(int(s.stage)); var grid:=grid_rect()
	_box(grid.grow(15),Color("33281f"),Color("b28a53"),8)
	for cell in range(cfg.width*cfg.height):
		var rect:=cell_rect(cell)
		if cell not in cfg.floor:
			_box(rect.grow(-1),Color("423428"),Color("705239"),3)
			draw_line(rect.position+Vector2(6,16),rect.position+Vector2(74,16),Color("896649"),3,true)
			draw_line(rect.position+Vector2(7,61),rect.position+Vector2(73,61),Color("241c16"),3,true)
			for x in [11,69]: draw_circle(rect.position+Vector2(x,16),2,Color("c59b61"))
		else:
			draw_rect(rect.grow(-1),Color("947249") if cell%2 else Color("9e7c52"))
			for y in [24,50]: draw_line(rect.position+Vector2(3,y),rect.position+Vector2(77,y+2),Color(.25,.16,.08,.25),1,true)
			if cell in cfg.goals:
				var occupied: bool=cell in s.boxes
				_box(rect.grow(-8),Color(.94,.74,.33,.35 if occupied else .12),Color("f6d081"),5)
				for k in range(3): draw_arc(rect.get_center(),13+k*4,0,TAU,32,Color(.98,.84,.52,.55),1.5,true)
				if occupied and pulse>0: draw_rect(rect.grow(-3),Color(1,.9,.52,pulse*.35))
	var actors: Array=[]
	for i in range(s.boxes.size()):
		var old_cell: int=int(previous.boxes[i]) if not previous.is_empty() else int(s.boxes[i])
		actors.append({"at":_location(int(s.boxes[i]),old_cell),"kind":i})
	var old_player: int=int(previous.get("player",s.player))
	actors.append({"at":_location(int(s.player),old_player),"kind":3})
	actors.sort_custom(func(a: Dictionary,b: Dictionary): return a.at.y<b.at.y)
	for actor in actors:
		var at: Vector2=actor.at
		_ellipse(at+Vector2(0,24),Vector2(32,10),Color(0,0,0,.27))
		if actor.kind==3:
			var bob:=sin((1-travel/duration)*PI)*3 if travel>0 else 0.0
			_cargo(Rect2(at-Vector2(31,46+bob),Vector2(62,77)),3)
			draw_circle(at+facing*33,3,Color("ffe3a0"))
		else: _cargo(Rect2(at-Vector2(35,40),Vector2(70,71)),actor.kind)
	if pressed_box>=0 and dragging:
		var delta:=pointer-press
		var direction:=Vector2(signf(delta.x),0) if absf(delta.x)>absf(delta.y) else Vector2(0,signf(delta.y))
		var at:=cell_rect(int(s.boxes[pressed_box])).get_center()
		draw_line(at,at+direction*55,Color("ffedb9"),5,true)
		draw_circle(at+direction*55,6,Color("ffedb9"))
	_tag(Rect2(596,133,427,47),"第 %d 关 · %s" % [int(s.stage)+1,Crates.NAMES[int(s.stage)]],23)
	_box(Rect2(46,244,330,278),Color("ebd6aa"),Color("957344"),6)
	_text(Vector2(70,285),"风沙前的货棚",28)
	_text(Vector2(70,329),"玛莎 · 擦亮的灯",22)
	_text(Vector2(70,367),"齐恩 · 备货的账",22)
	_text(Vector2(70,405),"尼尔 · 回来的路",22)
	_text(Vector2(70,461),"箱子不挑位置，路要留给人。",19)
	_text(Vector2(70,495),"黄铜框 = 备货位",20)
	_tag(Rect2(1190,575,347,48),"走了 %d 步 · 推了 %d 次" % [s.steps,s.pushes],22)
	_tag(Rect2(1190,636,347,48),"Z 撤回   /   R 重来本关",21)
func _gui_input(event: InputEvent) -> void:
	if not game.playing or game.paused or is_instance_valid(game.overlay): return
	if event is InputEventMouseMotion:
		pointer=event.position
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
