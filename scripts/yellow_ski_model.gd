extends RefCounted
## Pure fixed-step simulation. Coordinates in pixels; 30 pixels = one displayed metre.
const LENGTH := 60000.0
const GRAVITY := 880.0
const JUMP := 500.0
const SPIN_RATE := 10.8
const SPIN_ACCEL := 38.0
const JUMP_BUFFER := 0.16
var x := 0.0
var y := 0.0
var speed := 590.0
var vy := 0.0
var angle := 0.0
var grounded := true
var elapsed := 0.0
var air_time := 0.0
var rotation_travel := 0.0
var spin_velocity := 0.0
var jump_buffer := 0.0
var landing_flash := 0.0
var landing_quality := ""
var last_turns := 0
var max_combo := 0
var pending_turns := 0
var boost := 0.0
var immunity := 0.0
var squash := 0.0
var snow_x := -1050.0
var stars := 0
var flips := 0
var crashes := 0
var score := 0
var combo := 0
var state := "ready"
var notice := ""
var notice_time := 0.0
var event_serial := 0
var last_event := ""
var obstacles: Array[Dictionary] = []
var pickups: Array[Dictionary] = []

func ground(at: float) -> float:
	return 560.0 + at * 0.16 + sin(at / 680.0) * 65.0 + sin(at / 265.0) * 20.0

func slope(at: float) -> float:
	return 0.16 + cos(at / 680.0) * 65.0 / 680.0 + cos(at / 265.0) * 20.0 / 265.0

func reset() -> void:
	x=0; y=ground(0); speed=590; vy=0; angle=atan(slope(0)); grounded=true
	elapsed=0; air_time=0; rotation_travel=0; boost=0; immunity=0; squash=0
	spin_velocity=0; jump_buffer=0; landing_flash=0; landing_quality=""; last_turns=0; max_combo=0; pending_turns=0
	snow_x=-1050; stars=0; flips=0; crashes=0; score=0; combo=0
	state="ready"; notice=""; notice_time=0; event_serial=0; last_event=""
	obstacles.clear(); pickups.clear()
	var rng:=RandomNumberGenerator.new()
	rng.seed=3152026
	var at:=2050.0
	while at<LENGTH-1800:
		var kind:="rock" if rng.randf()<0.58 else "log"
		obstacles.append({"x":at,"kind":kind,"height":38.0 if kind=="rock" else 30.0,"hit":false})
		for j in range(3):
			var px:=at-90+j*100
			pickups.append({"x":px,"y":ground(px)-130.0-sin(j*PI/2)*38.0,"taken":false})
		at+=rng.randf_range(1450,2100)

func start() -> void:
	if state=="ready": state="running"

func announce(text: String, event: String="") -> void:
	notice=text; notice_time=1.6
	if not event.is_empty(): event_serial+=1; last_event=event

func crash(reason: String) -> void:
	if immunity>0 or state!="running": return
	crashes+=1; combo=0; speed=maxf(230,speed*0.45); boost=0; immunity=1.35; squash=0.9
	announce(reason,"crash")

func distance() -> int:
	return mini(2000,int(x/30.0))

func gap() -> float:
	return x-snow_x

func landing_error() -> float:
	return absf(wrapf(angle-atan(slope(x)),-PI,PI))

func altitude() -> float:
	return maxf(0,ground(x)-y)

func step(dt: float, held: bool, jump_edge: bool) -> void:
	if state!="running": return
	elapsed+=dt; immunity=maxf(0,immunity-dt); boost=maxf(0,boost-dt)
	landing_flash=maxf(0,landing_flash-dt)
	jump_buffer=JUMP_BUFFER if jump_edge else maxf(0,jump_buffer-dt)
	squash=move_toward(squash,0,dt*3); notice_time=maxf(0,notice_time-dt)
	if jump_buffer>0 and grounded:
		grounded=false; vy=speed*slope(x)-JUMP; air_time=0; rotation_travel=0
		jump_buffer=0; spin_velocity=0; pending_turns=0
		event_serial+=1; last_event="jump"
	var target:=690.0+slope(x)*270.0+(150.0 if boost>0 else 0.0)
	speed=move_toward(speed,target,dt*(115.0 if grounded else 32.0))
	var old_x:=x
	x+=speed*dt
	var floor_y:=ground(x)
	if grounded:
		y=floor_y; angle=lerp_angle(angle,atan(slope(x)),minf(1,dt*14))
	else:
		air_time+=dt; vy+=GRAVITY*dt; y+=vy*dt
		var spinning:=held and air_time>0.12
		spin_velocity=move_toward(spin_velocity,SPIN_RATE if spinning else 0.0,dt*(SPIN_ACCEL if spinning else 90.0))
		angle-=spin_velocity*dt
		rotation_travel+=spin_velocity*dt
		pending_turns=int(floor(rotation_travel/TAU))
		if not held and spin_velocity<0.5 and vy>0:
			# Only match the nearest slope angle after braking. Assistance earns no rotations.
			angle=rotate_toward(angle,atan(slope(x)),dt*7.5)
		if y>=floor_y and air_time>0.12:
			y=floor_y; grounded=true; vy=0; squash=0.55
			var error:=landing_error()
			last_turns=0; landing_flash=0.85
			if error>1.05:
				landing_quality="rough"; crash("落地没站稳，早点松手！")
			else:
				landing_quality="perfect" if error<0.30 else "clean"
				var turns:=int(floor((rotation_travel+0.10)/TAU))
				if turns>0:
					last_turns=turns; flips+=turns; combo+=1; max_combo=maxi(max_combo,combo)
					var points:=150*turns*mini(combo,4)+(50 if landing_quality=="perfect" else 0)
					score+=points; boost=3.1 if landing_quality=="perfect" else 2.5
					announce(("完美落地" if landing_quality=="perfect" else "稳稳落地")+"  +%d" % points,"flip")
			angle=atan(slope(x))
			spin_velocity=0; pending_turns=0
	for obstacle in obstacles:
		var ox:=float(obstacle.x)
		if not obstacle.hit and old_x<=ox+70 and x>=ox-65:
			if y>ground(ox)-float(obstacle.height)-18:
				obstacle.hit=true; crash("撞到石头了！" if obstacle.kind=="rock" else "小心倒木！")
	for pickup in pickups:
		if not pickup.taken and absf(x-float(pickup.x))<88 and absf((y-65)-float(pickup.y))<100:
			pickup.taken=true; stars+=1; score+=20; event_serial+=1; last_event="star"
	var snow_speed:=minf(760,620+elapsed*1.35)
	snow_x+=snow_speed*dt
	# Keep the chase present without punishing a successful streak with an invisible wall.
	snow_x=maxf(snow_x,x-1500)
	if gap()<65:
		state="lost"; announce("被雪崩追上了。","lost")
	elif x>=LENGTH:
		x=LENGTH; state="won"; score+=2000+maxi(0,500-crashes*50); announce("到酒馆了！","won")
