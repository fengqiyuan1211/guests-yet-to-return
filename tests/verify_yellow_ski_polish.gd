extends Node
const Model=preload("res://scripts/yellow_ski_model.gd")
var failures: Array=[]
var checks:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--ski-verify") or GameSession.save_path.begins_with("user://"):
		push_error("Run this verification only with explicit isolated save paths and --ski-verify.")
		get_tree().quit(2); return
	await frames()
	var m=Model.new(); m.reset(); m.start()
	m.step(1.0/120,true,true)
	check(not m.grounded,"jump leaves snow")
	for i in range(250): m.step(1.0/120,false,false)
	check(m.grounded,"released jump lands")
	check(m.crashes==0,"ordinary jump forgiving landing")
	m.reset(); m.start()
	for i in range(25000):
		m.step(1.0/120,false,false)
		if m.state!="running": break
	check(m.state=="lost" and m.crashes>0,"obstacles and avalanche can cause loss")
	m.reset(); m.start()
	for i in range(22000):
		var jump:=false
		if m.grounded:
			for o in m.obstacles:
				if o.x>m.x and o.x-m.x<330: jump=true; break
		m.step(1.0/120,false,jump)
		if m.state!="running": break
	print("BOT: ",m.state," seconds=",m.elapsed," crashes=",m.crashes," stars=",m.stars)
	check(m.state=="won","route can be completed with timed single jumps")
	check(m.crashes==0,"clean route has no invisible obstacle hits")
	check(m.stars>0,"jumping collects snow stars")
	check(m.elapsed>60 and m.elapsed<120,"route lasts 60-120 seconds")
	var terminal: float=m.x; m.step(1,false,true); check(m.x==terminal,"terminal simulation frozen")
	m.reset(); m.start(); m.step(1.0/120,true,true)
	for i in range(300):
		m.step(1.0/120,m.rotation_travel<TAU,false)
		if m.grounded: break
	print("FLIP: ",m.flips," crashes=",m.crashes," rotation=",m.rotation_travel," air=",m.air_time)
	check(m.flips==1 and m.crashes==0 and m.boost>0,"held flip and release lands with bonus")
	m.reset(); check(m.score==0 and m.flips==0 and m.crashes==0,"restart clears run only")
	# Momentum, buffering and dangerous landings introduced in the polish pass.
	m.reset(); m.start()
	for i in range(18): m.step(1.0/120,true,i==0)
	check(m.spin_velocity>0 and m.spin_velocity<m.SPIN_RATE,"spin accelerates instead of instant full rate")
	var spin: float=m.spin_velocity
	m.step(1.0/120,false,false)
	check(m.spin_velocity<spin,"release brakes the spin")
	m.reset(); m.start()
	m.grounded=false; m.y=m.ground(m.x)-1; m.vy=300; m.air_time=.5
	m.step(1.0/120,false,true)
	for i in range(5): m.step(1.0/120,false,false)
	check(not m.grounded and m.vy<0,"press just before landing buffers next jump")
	m.reset(); m.start()
	for i in range(200):
		m.step(1.0/120,true,i==0)
		if m.grounded and i>10: break
	check(m.crashes==1 and m.flips==0,"holding into unsafe landing still has a consequence")
	m.reset();m.start()
	for i in range(200):
		m.step(1.0/120,m.rotation_travel<TAU,i==0)
		if m.grounded and i>10: break
	check(m.last_turns==1 and m.max_combo==1 and m.landing_quality in ["clean","perfect"],"completed flip records landing feedback")
	check(m.pending_turns==0 and m.spin_velocity==0,"landing clears airborne rotation state")
	check(m.score>=150 and m.boost>=2.5,"safe landing awards points and sustained boost")
	m.reset();m.start()
	for i in range(200):
		m.step(1.0/120,i<30,i==0)
		if m.grounded and i>10: break
	check(m.flips==0,"landing assistance does not invent a full flip")
	# Real scene, journal entry, clock and save boundaries.
	TimeManager.set_running(true)
	var h=load("res://scenes/home.tscn").instantiate(); get_tree().root.add_child(h)
	await frames()
	var money:=SlotWallet.balance
	var cup=WorkbenchSession.state.session.duplicate(true)
	var story=StoryDialogue.session_snapshot().duplicate(true)
	var original_clock=TimeManager.snapshot().duplicate(true)
	Navigation.journal_focus_guest="yellow_creature"; Navigation.go_to(&"journal")
	await frames()
	var journal=h.active_page
	var acts=preload("res://scripts/guest_journal_data.gd").activities("yellow_creature",StoryDialogue.progress)
	check(acts.size()>0 and acts[0].accessible,"yellow minigame accessible in journal")
	journal._launch_activity("yellow_ski")
	await frames()
	check(Navigation.current_route==&"yellow_ski","journal enters skiing")
	var game=h.active_page
	check(not TimeManager.running,"tavern clock suspended")
	check(is_instance_valid(game.world.rider),"transparent rider texture loaded")
	var im=game.world.rider.get_image()
	print("RIDER size ",im.get_size()," used=",im.get_used_rect()," alpha corner=",im.get_pixel(0,0).a)
	check(im.get_pixel(0,0).a==0,"sprite background transparent")
	var intro_bounds: Rect2=Rect2(game.overlay.position,game.overlay.size)
	check(intro_bounds.end.x<=1600 and intro_bounds.end.y<=900,"new intro fits logical viewport")
	game.model.grounded=false
	var pose: Dictionary=game.world.rider_pose()
	check(pose.rect.position.y+pose.rect.size.y>0,"air rotation pivot lies inside rider instead of under board")
	game.model.grounded=true
	game._start()
	var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true
	click.position=game.get_global_transform()*Vector2(650,450); click.global_position=click.position
	get_viewport().push_input(click,true)
	await frames()
	check(not game.model.grounded,"viewport click reaches skiing controls")
	click=click.duplicate(); click.pressed=false; get_viewport().push_input(click,true)
	check(game.held_sources.is_empty(),"mouse release clears hold")
	var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true
	get_viewport().push_input(escape,true)
	check(game.paused and Navigation.current_route==&"yellow_ski","Escape pauses before home can handle it")
	game._resume(); game._start()
	var touch:=InputEventScreenTouch.new(); touch.index=4; touch.pressed=true; touch.position=Vector2(650,450)
	get_viewport().push_input(touch,true); await frames()
	check(not game.model.grounded,"touch jump supported")
	touch=touch.duplicate(); touch.pressed=false;get_viewport().push_input(touch,true)
	check(game.held_sources.is_empty(),"touch release clears hold")
	game._start(); game._hold("key32",true); game.model.step(1.0/120,true,game.queued_jump)
	check(not game.model.grounded,"scene jump input")
	game._toggle_pause(); var px=game.model.x; game._process(.5)
	check(game.paused and game.model.x==px and game.held_sources.is_empty(),"pause freezes and clears held input")
	game._resume(); check(not game.paused,"resume works")
	game.model.x=30000; game.model.score=500; game.model.state="lost"; game._finish()
	check(game.best_distance==1000 and game.best_score==1500,"best record saves result")
	game._start(); check(game.best_distance==1000 and game.model.x==0,"retry preserves record only")
	game._leave(); await frames()
	check(Navigation.current_route==&"journal" and TimeManager.running,"exit restores journal and clock")
	check(SlotWallet.balance==money and WorkbenchSession.state.session==cup,"no wallet or cup changes")
	check(StoryDialogue.session_snapshot()==story,"story cursor preserved")
	Navigation.go_to(&"yellow_ski"); await frames()
	game=h.active_page
	check(game.best_distance==1000,"best record reloads")
	TimeManager.set_running(false)
	Navigation.go_to(&"home"); await frames()
	# Starting with a deliberately paused clock must restore paused, not force it to run.
	TimeManager.set_running(false); Navigation.go_to(&"yellow_ski"); await frames()
	h.active_page._leave(); await frames(); check(not TimeManager.running,"pre-existing paused clock restored")
	print(JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
