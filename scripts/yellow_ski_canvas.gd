extends Control
const FONT := preload("res://assets/fonts/NotoSerifSC.ttf")
const RIDER_PATH := "res://assets/minigames/yellow_ski/rider.png"
var model: RefCounted
var rider: Texture2D
var rider_region := Rect2()
var camera_y := 0.0
var visual_time := 0.0
var trails: Array[Vector2] = []
var trail_clock := 0.0
var particles: Array[Dictionary] = []
var last_event := -1
var air_trails: Array[Dictionary] = []
var previous_grounded := true

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	rider=load(RIDER_PATH)
	if rider:
		var im:=rider.get_image()
		rider_region=Rect2(im.get_used_rect())

func reset_camera() -> void:
	camera_y=model.ground(model.x)-620
	trails.clear(); air_trails.clear(); particles.clear(); trail_clock=0; last_event=-1; previous_grounded=true

func advance(dt: float) -> void:
	visual_time+=dt
	camera_y=lerpf(camera_y,model.ground(model.x)-620,1-exp(-dt*6))
	trail_clock+=dt
	if not model.grounded or model.boost>0:
		air_trails.append({"p":Vector2(model.x,model.y-58),"age":0.0})
	for i in range(air_trails.size()-1,-1,-1):
		air_trails[i].age+=dt
		if air_trails[i].age>0.28: air_trails.remove_at(i)
	if model.grounded and not previous_grounded:
		for i in range(20):
			particles.append({"p":Vector2(model.x,model.y-8),"v":Vector2(randf_range(-240,170),randf_range(-170,-45)),"age":0.0,"life":0.6,"r":randf_range(2,6)})
	previous_grounded=model.grounded
	if model.state=="running" and model.grounded and trail_clock>0.025:
		trail_clock=0
		particles.append({"p":Vector2(model.x-60,model.y-5),"v":Vector2(-100-randf()*90,-60-randf()*70),"age":0.0,"life":0.45+randf()*0.25,"r":2+randf()*4})
	if model.event_serial!=last_event:
		last_event=model.event_serial
		if model.last_event in ["crash","flip"]:
			for i in range(18): particles.append({"p":Vector2(model.x,model.y-30),"v":Vector2(randf_range(-220,160),randf_range(-220,-70)),"age":0.0,"life":0.65,"r":randf_range(2,6)})
	for i in range(particles.size()-1,-1,-1):
		var p: Dictionary=particles[i]
		p.age+=dt; p.p+=p.v*dt; p.v.y+=280*dt
		if p.age>=p.life: particles.remove_at(i)
	queue_redraw()

func screen_point(world: Vector2) -> Vector2:
	return Vector2(world.x-model.x+370,world.y-camera_y)

func _draw() -> void:
	if model==null: return
	# Sky, original layered terrain, and sparse foreground all stay lightweight in Compatibility.
	for i in range(45):
		var c:=Color("6babbc").lerp(Color("e5e9d8"),i/44.0)
		draw_rect(Rect2(0,i*20,1600,21),c)
	draw_circle(Vector2(1180,178),72,Color("f9e5b1"))
	draw_circle(Vector2(1180,178),89,Color(1,.94,.76,.10))
	for layer in range(3): _mountains(layer)
	for i in range(36):
		var sx:=fposmod(i*137.7-visual_time*(12+i%5),1680)-40
		var sy:=fposmod(i*93.9+visual_time*(15+i%4),900)
		draw_circle(Vector2(sx,sy),1.2+(i%3)*0.5,Color(1,1,1,.43))
	# Trees on the far edge of the slope.
	var first:=int(floor((model.x-800)/380))
	for i in range(first,first+9):
		var wx:=i*380.0+sin(i*18.4)*100
		var p:=screen_point(Vector2(wx,model.ground(wx)-20))
		_tree(p,80+fposmod(i*67,85),Color("4e8590"))
	var points:=PackedVector2Array()
	for i in range(-1,83):
		var sx:=i*20.0
		points.append(Vector2(sx,model.ground(model.x+sx-370)-camera_y))
	var fill:=points.duplicate(); fill.append(Vector2(1640,950)); fill.append(Vector2(-30,950))
	draw_colored_polygon(fill,Color("d9e9e8"))
	var top:=PackedVector2Array()
	for p in points: top.append(p+Vector2(0,24))
	var ribbon:=points.duplicate()
	for i in range(top.size()-1,-1,-1): ribbon.append(top[i])
	draw_colored_polygon(ribbon,Color("fff9e9"))
	draw_polyline(points,Color("fffef7"),4,true)
	for i in range(10):
		var wx: float=floor(model.x/420)*420+i*420-840
		var p:=screen_point(Vector2(wx,model.ground(wx)+90+fposmod(i*37,170)))
		draw_line(p,p+Vector2(85,12),Color(.63,.77,.78,.27),2,true)
	for obstacle in model.obstacles:
		var p:=screen_point(Vector2(obstacle.x,model.ground(obstacle.x)))
		if p.x< -120 or p.x>1720: continue
		if obstacle.kind=="rock": _rock(p,obstacle.hit)
		else: _log(p,obstacle.hit)
	for pickup in model.pickups:
		if pickup.taken: continue
		var p:=screen_point(Vector2(pickup.x,pickup.y))
		if p.x> -40 and p.x<1640: _star(p+Vector2(0,sin(visual_time*3+pickup.x)*4),10,Color("e5ac48"))
	_chalet()
	# Soft shadow remains on the surface while the rider jumps above it.
	var gp:=screen_point(Vector2(model.x,model.ground(model.x)))
	var altitude:=maxf(0,model.ground(model.x)-model.y)
	draw_set_transform(gp+Vector2(0,10),atan(model.slope(model.x)),Vector2(1,0.17))
	draw_circle(Vector2.ZERO,maxf(24,80-altitude*.12),Color(.19,.37,.40,.18))
	draw_set_transform(Vector2.ZERO)
	for i in range(1,air_trails.size()):
		var alpha: float=(1-air_trails[i].age/0.28)*0.42
		draw_line(screen_point(air_trails[i-1].p),screen_point(air_trails[i].p),Color(1,.86,.47,alpha),5,true)
	_draw_rider()
	_trick_hint()
	for particle in particles:
		var p:=screen_point(particle.p)
		draw_circle(p,particle.r,Color(1,1,1,(1-particle.age/particle.life)*.9))
	_avalanche()

func _mountains(layer: int) -> void:
	var parallax: float=[0.05,0.12,0.23][layer]
	var color: Color=[Color("a4c7ca"),Color("82abb5"),Color("61909e")][layer]
	var spacing:=330.0-layer*40
	var offset:=fposmod(model.x*parallax,spacing)
	for i in range(-1,7):
		var xx:=i*spacing-offset
		var index:=i+int(floor(model.x*parallax/spacing))
		var peak:=Vector2(xx+spacing*.5,260+layer*70+sin(index*2.1)*55)
		var left:=Vector2(xx-170,620+layer*25)
		var right:=Vector2(xx+spacing+170,620+layer*25)
		draw_colored_polygon(PackedVector2Array([left,peak,right]),color)
		var cap:=PackedVector2Array([peak,left.lerp(peak,.75),peak+Vector2(-10,54),peak+Vector2(18,43),right.lerp(peak,.78)])
		draw_colored_polygon(cap,Color("e3eddf").lerp(color,layer*.16))

func _tree(p: Vector2, height: float, c: Color) -> void:
	draw_line(p,p+Vector2(0,-height),Color("46636a"),6)
	for level in range(3):
		var y:=p.y-height+level*height*.25
		var w:=height*(.20+level*.075)
		var tri:=PackedVector2Array([Vector2(p.x,y),Vector2(p.x-w,y+height*.48),Vector2(p.x+w,y+height*.48)])
		draw_colored_polygon(tri,c)
		tri[1].y-=height*.13; tri[1].x+=w*.25; tri[2].y-=height*.13; tri[2].x-=w*.25
		draw_colored_polygon(tri,Color("d9e9e5"))

func _rock(p: Vector2, hit: bool) -> void:
	var r:=PackedVector2Array([p+Vector2(-44,2),p+Vector2(-35,-24),p+Vector2(-15,-42),p+Vector2(17,-38),p+Vector2(38,-15),p+Vector2(43,3)])
	draw_colored_polygon(r,Color("829092") if hit else Color("627579"))
	draw_polyline(r,Color("4e6368"),3,true)
	draw_colored_polygon(PackedVector2Array([r[1],r[2],r[3],p+Vector2(26,-24),p+Vector2(-5,-29)]),Color("f6f4df"))

func _log(p: Vector2, hit: bool) -> void:
	var body:=Rect2(p+Vector2(-55,-29),Vector2(110,29))
	draw_style_box(_round(Color("9b714d") if not hit else Color("a9896d"),14),body)
	draw_line(p+Vector2(-42,-10),p+Vector2(30,-10),Color("725036"),3)
	draw_line(p+Vector2(-36,-22),p+Vector2(27,-22),Color("ead7b0"),5)
	draw_circle(p+Vector2(40,-14),14,Color("caa571"))
	draw_arc(p+Vector2(40,-14),8,0,TAU,24,Color("8d6743"),2,true)

func _round(c: Color,r: int) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new(); box.bg_color=c; box.set_corner_radius_all(r); return box

func _star(p: Vector2,r: float,c: Color) -> void:
	var points:=PackedVector2Array()
	for i in range(10): points.append(p+Vector2.from_angle(-PI/2+i*PI/5)*(r if i%2==0 else r*.42))
	draw_circle(p,r*1.6,Color(1,.9,.5,.16))
	draw_colored_polygon(points,c)
	draw_circle(p,2,Color("fff8d7"))

func rider_pose() -> Dictionary:
	var p:=screen_point(Vector2(model.x,model.y))
	var width:=228.0
	if model.state=="ready":
		p=Vector2(410,model.ground(model.x+40)-camera_y); width=380
	var height:=width*rider_region.size.y/maxf(1,rider_region.size.x)
	# Rotate around the torso in the air, with the board still reaching the snow at angle 0.
	var lift:=height*0.48 if not model.grounded else 0.0
	var tuck:=clampf(model.spin_velocity/model.SPIN_RATE,0,1) if not model.grounded else 0.0
	var pivot:=Vector2(0,-lift)
	var squash: float=model.squash
	return {"origin":p+pivot,"rect":Rect2(-width*.5,-height+lift,width,height),
		"scale":Vector2(1+squash*.10-tuck*.045,1-squash*.14-tuck*.065),"angle":model.angle}

func _draw_rider() -> void:
	if not rider: return
	var pose:=rider_pose()
	var shake:=sin(visual_time*45)*3 if model.immunity>0.8 else 0.0
	draw_set_transform(pose.origin+Vector2(shake,0),pose.angle,pose.scale)
	draw_texture_rect_region(rider,pose.rect,rider_region,Color(1,1,1,.55 if model.immunity>0 and sin(visual_time*25)>0 else 1))
	draw_set_transform(Vector2.ZERO)

func _trick_hint() -> void:
	if model.state!="running": return
	var p:=screen_point(Vector2(model.x,model.y))+Vector2(0,-190)
	if not model.grounded and model.rotation_travel>0.3:
		var progress:=fposmod(model.rotation_travel,TAU)/TAU
		draw_circle(p,29,Color(.10,.24,.27,.82))
		draw_arc(p,24,-PI/2,-PI/2+TAU*progress,40,Color("f7cf77"),3,true)
		var count: int=model.pending_turns
		var text:=str(count) if count>0 else "↺"
		var length:=FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,23).x
		draw_string(FONT,p+Vector2(-length/2,8),text,HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("fff1ca"))
		if model.vy>0 and model.altitude()<145:
			var prompt:="松手，收稳！" if model.spin_velocity>1 else ("稳住落地" if model.landing_error()<.6 else "正在收势")
			var length2:=FONT.get_string_size(prompt,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
			draw_string(FONT,p+Vector2(-length2/2,57),prompt,HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("284b52"))
	elif model.landing_flash>0 and model.last_turns>0:
		var alpha:=minf(1,model.landing_flash*2)
		draw_arc(p+Vector2(0,155),110,PI,TAU,40,Color(1,.8,.36,alpha*.7),3,true)

func _avalanche() -> void:
	var gap: float=model.gap()
	var edge:=clampf(270-gap*.30,-160,250)
	for i in range(12):
		var yy:=240+i*62.0
		var xx:=edge-70+sin(visual_time*2.5+i)*27
		draw_circle(Vector2(xx,yy),100+i%3*14,Color("b8d5de"))
		draw_circle(Vector2(xx-23,yy-14),84,Color("e2edf0"))
	if gap<350:
		draw_rect(Rect2(0,0,1600,900),Color(.75,.9,1,clampf((350-gap)/1800,0,.15)))

func _chalet() -> void:
	var p:=screen_point(Vector2(model.LENGTH+300,model.ground(model.LENGTH+300)))
	if p.x>1900: return
	draw_rect(Rect2(p+Vector2(-100,-150),Vector2(200,150)),Color("8c6141"))
	draw_colored_polygon(PackedVector2Array([p+Vector2(-130,-145),p+Vector2(0,-245),p+Vector2(130,-145)]),Color("f7f1dd"))
	draw_rect(Rect2(p+Vector2(-22,-83),Vector2(44,83)),Color("573d2c"))
	for xx in [-68,42]:
		draw_rect(Rect2(p+Vector2(xx,-110),Vector2(34,41)),Color("ffda7d"))
		draw_line(p+Vector2(xx+17,-110),p+Vector2(xx+17,-69),Color("725038"),3)
