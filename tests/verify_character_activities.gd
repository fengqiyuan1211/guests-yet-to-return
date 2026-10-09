extends "res://tests/verify_workbench_scene.gd"
const Rules=preload("res://scripts/guest_activity_rules.gd")
var serial:=0

func ferry_drag() -> void:
	if DisplayServer.get_name()=="headless": return
	var board: Control=bench.board
	var from: Vector2=board.get_global_transform_with_canvas()*Vector2(195,486)
	var to: Vector2=board.get_global_transform_with_canvas()*board.boat_rect().get_center()
	get_viewport().warp_mouse(from)
	pointer(from,true); await settle()
	for i in range(1,6):
		var motion:=InputEventMouseMotion.new()
		motion.position=from.lerp(to,i/5.0); motion.relative=(to-from)/5; motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		get_viewport().warp_mouse(motion.position)
		get_viewport().push_input(motion,true); await settle()
	pointer(to,false); await settle()
	check(bench.selection[1]==1,"native drag puts one prisoner into the boat")
	bench.remove_person(1)

func ferry_failure() -> void:
	bench.set_process(false)
	var before: Dictionary=bench.state().duplicate(true)
	bench.select_person(0); bench._cross()
	check(bench.sailing>0 and not bench.failure_outcome.is_empty() and not bench.failure_shown,"unsafe but boardable trip departs before failure scene")
	check(bench.state()==before,"failed departure does not corrupt stable bank record")
	bench._pause(); bench._process(2)
	check(bench.sailing>0 and not bench.failure_shown,"failed trip animation also pauses")
	bench._resume(); bench._process(1)
	check(bench.failure_shown and is_instance_valid(bench.overlay) and not bench.playing,"departure resolves into illustrated failure scene")
	check(bench.failure_outcome.p==2 and bench.failure_outcome.d==3 and bench.failure_outcome.bank==0,"failure explains exact problematic bank and counts")
	await capture("character-milo-failure")
	bench._cross(); check(bench.state()==before,"repeated input during failure cannot move or award")
	key_press(KEY_SPACE); await settle()
	check(not bench.failure_shown and bench.playing and bench.state()==before and bench.selection==[0,0],"space retry returns to exact prior stable crossing")
	bench.set_process(true)

func move_pointer(point: Vector2, previous: Vector2, pressed:=false) -> void:
	var event:=InputEventMouseMotion.new(); event.position=point; event.relative=point-previous; event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().warp_mouse(point); get_viewport().push_input(event,true)

func key_press(code: Key) -> void:
	var event:=InputEventKey.new(); event.keycode=code; event.pressed=true; get_viewport().push_input(event,true)

func watch_drag() -> void:
	if DisplayServer.get_name()=="headless": return
	bench.set_process(false)
	var board: Control=bench.board
	var before: Dictionary=bench.state().duplicate(true)
	var from: Vector2=board.get_global_transform_with_canvas()*board.piece_rect(1).get_center()
	var to: Vector2=board.get_global_transform_with_canvas()*board.cell_rect(0).get_center()
	get_viewport().warp_mouse(from); pointer(from,true); await settle()
	move_pointer(to,from,true); await settle()
	check(board.held==1 and board.dragging,"actual pointer picks component and follows drag")
	key_press(KEY_SPACE); await settle()
	check(bench.state().pieces[1].turns==(int(before.pieces[1].turns)+1)%4,"space rotates component while held")
	pointer(to,false); await settle()
	check(bench.state().pieces[1].cell==0,"release installs component into hovered empty slot")
	key_press(KEY_Z); await settle(); key_press(KEY_Z); await settle()
	check(bench.state().pieces==before.pieces,"keyboard undo restores move and rotation separately")
	# Invalid drop retains component; pausing releases pointer without unintended placement.
	get_viewport().warp_mouse(from); pointer(from,true); await settle()
	move_pointer(Vector2(20,400),from,true); pointer(Vector2(20,400),false); await settle()
	check(bench.state().pieces==before.pieces,"outside drop returns component without state change")
	get_viewport().warp_mouse(from); pointer(from,true); await settle(); move_pointer(to,from,true); await settle()
	bench._pause(); pointer(to,false); bench._resume(); await settle()
	check(board.held==-1 and bench.state().pieces==before.pieces,"pause cancels held component safely")
	bench.set_process(true)

func crate_input() -> void:
	bench.set_process(false)
	var board: Control=bench.board
	var before: Dictionary=bench.state().duplicate(true)
	key_press(KEY_RIGHT); await settle()
	check(bench.state().steps==1 and board.travel>0,"keyboard moves cowboy with animation")
	bench._pause(); bench._process(2)
	check(bench.state().steps==1 and board.travel>0,"pause freezes queued moves and animation")
	bench._resume(); key_press(KEY_Z); await settle()
	check(bench.state()==before,"undo restores exact board")
	if DisplayServer.get_name()!="headless":
		var from: Vector2=board.get_global_transform_with_canvas()*board.cell_rect(int(bench.state().boxes[0])).get_center()
		var to: Vector2=from-Vector2(60,0)*bench.surface.scale.x
		get_viewport().warp_mouse(from); pointer(from,true); await settle()
		move_pointer(to,from,true); await settle(); pointer(to,false); await settle()
		for i in range(12): bench._process(.25)
		check(Rules.Crates.solved(bench.state()) and bench.state().steps==4,"drag walks around crate and pushes once into goal")
		key_press(KEY_R); await settle()
		check(is_instance_valid(bench.overlay),"reset requests current-stage confirmation")
		bench._crate_reset(); await settle()
		check(bench.state()==before,"reset keeps clean initial board")
	bench.set_process(true)

func migration_checks() -> void:
	var id:="ada_watch_memory"; var original:=GuestActivities.book(); var b:=original.duplicate(true)
	var old:={"round":1,"input":[],"completed":[[2,1,2]],"mistakes":1,"replays":0,"assist":false,"won":false}
	b.runs[id].state=old
	check(GuestActivities._commit(b),"old unfinished watch state accepted by save loader")
	var save_path: String=Supplies.save_path; Supplies.save_path=save_path+"/blocked.json"
	check(not GuestActivities.begin(id) and GuestActivities.active.is_empty(),"failed migration write does not expose unsaved new game")
	Supplies.save_path=save_path
	check(GuestActivities.book().runs[id].state.get("model",1)==1,"failed migration retains old checkpoint")
	check(GuestActivities.begin(id) and GuestActivities.active.state.model==2,"old unfinished watch migrates to new mechanics")
	check(not GuestActivities.migration_notice.is_empty(),"migration gives explicit player explanation")
	check(GuestActivities.book().rewards==original.rewards,"migration preserves old first-clear receipts")
	GuestActivities.end()
	b=original.duplicate(true); old.round=3; old.completed=Rules.SEQUENCES.duplicate(true); old.won=true; b.runs[id].state=old; b.rewards.erase(id)
	check(GuestActivities._commit(b) and GuestActivities.begin(id) and GuestActivities.active.state.won,"old completed unclaimed game resumes without replay")
	var inspiration: int=WorkbenchSession.research_state().inspiration
	check(GuestActivities.claim() and GuestActivities.claim() and WorkbenchSession.research_state().inspiration==inspiration+3,"old unclaimed win rewarded once")
	GuestActivities.end()
	# Remove only the artificial second fixture award; original live paths remain untouched.
	var research:=WorkbenchSession.research_state(); research.inspiration=inspiration
	check(GuestActivities._commit(original,research),"restore fixture after legacy migration checks")

func crate_migration_checks() -> void:
	var id:="hank_lantern"; var original:=GuestActivities.book(); var b:=original.duplicate(true)
	var legacy:={"lane":1,"index":1,"elapsed":0.0,"lit":0.0,"walking":0.0,"rescued":[0],"misses":0,"assist":false,"won":false}
	b.runs[id].state=legacy
	check(GuestActivities._commit(b),"legacy lantern checkpoint readable")
	var path: String=Supplies.save_path; Supplies.save_path=path+"/blocked.json"
	check(not GuestActivities.begin(id) and GuestActivities.active.is_empty(),"failed crate migration leaves no unsaved active run")
	Supplies.save_path=path
	check(GuestActivities.begin(id) and GuestActivities.active.state.model==2 and GuestActivities.active.state.stage==0,"legacy unfinished lamp game migrates to crates")
	check(GuestActivities.book().rewards==original.rewards and not GuestActivities.migration_notice.is_empty(),"crate migration retains reward receipt and explains restart")
	GuestActivities.end()
	b=original.duplicate(true); legacy.index=6; legacy.rescued=[0,1,2,3,4,5]; legacy.won=true; b.runs[id].state=legacy; b.rewards.erase(id)
	check(GuestActivities._commit(b) and GuestActivities.begin(id) and GuestActivities.active.state.won,"old unclaimed Hank victory remains claimable")
	var inspiration: int=WorkbenchSession.research_state().inspiration
	check(GuestActivities.claim() and GuestActivities.claim() and WorkbenchSession.research_state().inspiration==inspiration+3,"legacy Hank award exactly once")
	GuestActivities.end()
	var research:=WorkbenchSession.research_state(); research.inspiration=inspiration
	check(GuestActivities._commit(original,research),"restore crate migration fixture")

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--activities-resume"):
		if not Supplies.save_path.begins_with("/tmp/"): get_tree().quit(2); return
		TimeManager.set_process(false); call_deferred("restored")
	else: super._ready()

func op(kind: String, payload: Dictionary={}) -> void:
	serial+=1
	check(WorkbenchSession.command("characters-%d" % serial,str(WorkbenchSession.state.session.get("id","")),kind,payload),kind+": "+WorkbenchSession.last_error)

func talk_chapter() -> void:
	var turns:=0
	while StoryDialogue.phase=="story" and turns<80:
		turns+=1
		if StoryDialogue.current_choices().is_empty(): StoryDialogue.continue_talking()
		else: StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
	check(turns<80,"chapter reaches closing and taste clue")

func complete_game() -> void:
	bench.set_process(false)
	var id: String=bench.activity_id
	if id=="milo_ferry":
		var moves:=0
		while not bench.state().won and moves<20:
			moves+=1; bench.sailing=0
			var pair:=Rules.hint(bench.state())
			if pair.is_empty(): break
			for i in range(pair[0]): bench.select_person(0)
			for i in range(pair[1]): bench.select_person(1)
			bench._cross()
			if moves==1: bench.sailing=.425; await capture("character-milo-sailing")
		check(bench.state().won and bench.state().moves.size()==11,"native ferry controls reach verified 11-crossing solution")
	elif id=="ada_watch_memory":
		for turn in range(160):
			if bench.state().won: break
			var next:=Rules.Watch.hint(bench.state())
			if next.action=="wind" and bench.state().wind==0: await capture("character-ada-connected")
			if next.action in ["next","wind"]: bench.board.held=-1; bench.watch_space()
			elif next.action=="rotate": bench.board.selected=int(next.piece); bench.watch_space()
			else: bench.act("move",next)
		check(bench.state().won,"three connected mechanical stages and winding complete")
	else:
		for stage in range(3):
			if stage==2: await capture("character-hank-crates-stage3")
			for direction in Rules.Crates.SOLUTIONS[stage]:
				bench.crate_move(direction); bench.board.finish_motion()
			check(Rules.Crates.solved(bench.state()),"authored crate stage completed through controls")
			bench.crate_next()
		check(bench.state().won and bench.state().completed.size()==2,"all three crate stages proved before victory")
	if bench.activity_id=="milo_ferry" and bench.end_pending: bench._process(1.0)
	await settle()

func run() -> void:
	home=load("res://scenes/home.tscn").instantiate(); add_child(home); await settle()
	check(Rules.hint(Rules.fresh("milo_ferry"))==[0,2],"ferry shortest-path hint starts with two prisoners")
	check(not Rules.apply("milo_ferry",Rules.fresh("milo_ferry"),"cross",{"p":1,"d":0}).ok,"illegal bank balance rejected")
	check(not Rules.apply("milo_ferry",Rules.fresh("milo_ferry"),"cross",{"p":0,"d":0}).ok,"empty boat rejected")
	var inventory: Dictionary=Supplies.inventory.serialize().duplicate(true)
	var money: int=SlotWallet.balance
	var original: Dictionary=WorkbenchSession.snapshot()
	var story: Dictionary=StoryDialogue.progress.duplicate(true)
	for id in Rules.IDS:
		Navigation.journal_focus_guest=GuestActivities.config(id).guest_id
		Navigation.go_to(&"journal"); await settle(); bench=home.active_page
		check(button_named("开始游戏")!=null,"journal exposes demo for "+id)
		click(button_named("开始游戏")); await settle(); bench=home.active_page
		check(bench.activity_id==id and not TimeManager.running,"route and clock for "+id)
		click(button_named("开始演示")); await settle()
		get_window().grab_focus(); await settle()
		if bench.paused: bench._resume(); await settle()
		await capture("character-"+id+"-play")
		if id=="milo_ferry":
			await ferry_drag(); await ferry_failure()
		elif id=="ada_watch_memory": await watch_drag()
		else: await crate_input()
		bench._pause(); check(bench.paused,"pause "+id); bench._resume()
		await complete_game()
		await capture("character-"+id+"-demo-result")
		check(GuestActivities.book().rewards.is_empty(),"demo never grants reward "+id)
		bench._close(); await settle()
		check(Navigation.current_route==&"journal" and home.active_page.tab==3,"return to activity tab "+id)
	check(WorkbenchSession.snapshot()==original and StoryDialogue.progress==story,"all demos leave production and story unchanged")
	check(Supplies.inventory.serialize()==inventory and SlotWallet.balance==money,"demos never consume materials or money")
	Navigation.go_to(&"home"); await settle()
	MenuCatalog.unlock_recipe("gin_and_tonic")
	check(MenuCatalog.save_menu([{"id":"gin_and_tonic","price":50}],MenuCatalog.design),"test business menu")
	TimeManager.advance_minutes(1200-TimeManager.minutes_since_midnight); await settle()
	for index in range(3):
		var guest: String=["milo","ada","hank"][index]
		var id: String=Rules.IDS[index]
		for chapter in range(5):
			home.get_node("%GuestLayer").show_guest(index)
			await settle()
			check(StoryDialogue.taste_event_id.is_empty(),"new visit starts before new clue")
			talk_chapter(); await settle()
			check(StoryDialogue.taste_event_id=="%s_%02d" % [guest,chapter+1],"spoken clue records stable episode")
			if chapter<2:
				var who:={"id":guest,"visit_id":home.reception_id,"day":TimeManager.day,"visit":home.guest_count}
				var order:=GuestService.make_order(who,"gin_and_tonic")
				check(not order.is_empty() and order.demand.event_id==StoryDialogue.taste_event_id,"order locks spoken event")
				var fixed: Dictionary=order.demand.duplicate(true)
				StoryDialogue.taste_event_id=""
				check(GuestService.ensure_demand(who)==fixed,"locked demand cannot change after dialogue updates")
				op("select_recipe",{"recipe_id":"gin_and_tonic","guest":who,"order":order})
				for pair in [["gin",30],["lime",10],["soda",30]]: op("withdraw",{"material":pair[0],"ml":pair[1],"vessel":"glass"})
				op("finish")
				check(GuestService.deliver(WorkbenchSession.state.session.result.drink_id),"real guest delivery "+guest)
				check(WorkbenchSession.state.session.result.customer_receipt.score!=null and WorkbenchSession.state.session.result.customer_receipt.score>=70,"candidate meets current guest event")
				await settle()
		check(GuestActivities.progress(id).unlocked and not GuestActivities.progress(id).keepsake.is_empty(),"five chapters and two distinct satisfied visits grant invitation and keepsake")
		check(StoryDialogue.progress[guest].activity_unlocks.has(id),"unlock mirrors into journal")
		var before: Dictionary=WorkbenchSession.state.session.duplicate(true)
		var count_before: int=WorkbenchSession.research_state().inspiration
		var valid_path: String=Supplies.save_path
		var fail_reward: Callable=func():
			var run: Dictionary=GuestActivities.book().runs.get(id,{})
			if run.get("state",{}).get("won",false) and not GuestActivities.book().rewards.has(id): Supplies.save_path=valid_path+"/blocked.json"
		if index==0: GuestActivities.changed.connect(fail_reward)
		Navigation.go_to(StringName(id)); await settle(); bench=home.active_page
		check(GuestActivities.active.mode=="normal","unlocked scene starts real run")
		click(button_named("开始游戏")); await settle()
		await complete_game()
		if index==0:
			GuestActivities.changed.disconnect(fail_reward)
			check(GuestActivities.book().runs[id].state.won and GuestActivities.book().rewards.is_empty(),"failed reward write preserves completed run without grant receipt")
			check(WorkbenchSession.research_state().inspiration==count_before and not MenuCatalog.get_recipe("character_milo").unlocked,"failed claim changes neither inspiration nor recipe")
			Supplies.save_path=valid_path
			check(GuestActivities.begin(id) and GuestActivities.active.state.won,"unclaimed completed formal game resumes for retry")
			bench._result()
		check(WorkbenchSession.research_state().inspiration==count_before+3,"first clear grants exactly three inspiration")
		check(MenuCatalog.get_recipe("character_"+guest).get("unlocked",false),"reward recipe accessible through shared catalog")
		check(GuestActivities.claim() and WorkbenchSession.research_state().inspiration==count_before+3,"repeated claim idempotent")
		check(WorkbenchSession.state.session==before,"activities do not change the customer cup")
		await capture("character-"+id+"-reward")
		bench._close(); await settle()
		check(Supplies._sync_menu(),"material synchronization accepts role recipes without auto-unlocking them")
		Navigation.go_to(&"home"); await settle()
	await migration_checks()
	await crate_migration_checks()
	# Real run restores intermediate state; failed write must not move anybody.
	Navigation.go_to(&"milo_ferry"); await settle(); bench=home.active_page
	click(button_named("开始游戏")); await settle()
	bench.select_person(1); bench.select_person(1)
	var path: String=Supplies.save_path
	var old: Dictionary=GuestActivities.active.duplicate(true)
	Supplies.save_path=path+"/blocked.json"
	bench._cross()
	check(GuestActivities.active==old,"failed save rolls back ferry action")
	Supplies.save_path=path
	bench._cross(); bench.sailing=0; bench._close(); await settle()
	Navigation.go_to(&"milo_ferry"); await settle(); bench=home.active_page
	check(bench.state().moves.size()==1,"return resumes unfinished formal game")
	bench._close(); await settle()
	check(GuestActivities.begin("ada_watch_memory",true),"start new formal mechanical checkpoint")
	while GuestActivities.active.state.stage==0:
		var next:=Rules.Watch.hint(GuestActivities.active.state)
		check(GuestActivities.action(next.action,next),"complete first mechanical stage")
	check(GuestActivities.action("move",{"piece":0,"cell":0}),"install component before process restart")
	check(GuestActivities.action("rotate",{"piece":0}),"rotate component before process restart")
	check(GuestActivities.end(),"checkpoint second stage with tray and undo history")
	check(GuestActivities.begin("hank_lantern",true),"start new formal crate checkpoint")
	for direction in Rules.Crates.SOLUTIONS[0]: check(GuestActivities.action("move",{"direction":direction}),"crate checkpoint first stage")
	check(GuestActivities.action("next") and GuestActivities.action("move",{"direction":"L"}),"second crate stage saves walk")
	var crate_before: Dictionary=GuestActivities.active.duplicate(true)
	Supplies.save_path=path+"/blocked.json"
	check(not GuestActivities.action("move",{"direction":"U"}) and GuestActivities.active==crate_before,"failed crate write rolls back logical board")
	Supplies.save_path=path
	check(GuestActivities.end(),"checkpoint crates with proof and undo history")
	# Every gift is a real, producible recipe using the shared inventory and quality model.
	var trial_inspiration: int=WorkbenchSession.research_state().inspiration
	for guest in ["milo","ada","hank"]:
		var recipe:=MenuCatalog.get_recipe("character_"+guest)
		for row in recipe.ingredients:
			check(Supplies.inventory.purchase(row.sku_id,1),"seed gift recipe ingredient "+row.sku_id)
		check(Supplies._write(Supplies.inventory.serialize(),{}),"save private recipe fixture")
		op("begin_research",{"mode":"research_legendary","recipe_id":recipe.id})
		op("ice",{"ice":"cube","vessel":"glass"})
		op("ice",{"ice":"cube","vessel":"glass"})
		var recipe_amounts: Dictionary=WorkbenchSession.state.session.recipe.ingredients
		for material in recipe_amounts:
			if material!="soda": op("withdraw",{"material":material,"ml":recipe_amounts[material],"vessel":"glass"})
		op("withdraw",{"material":"soda","ml":recipe_amounts.soda,"vessel":"glass"})
		op("spoon",{"target":"glass"})
		for i in range(8): op("stir",{"seconds":.5,"control":1,"vessel":"glass"})
		op("finish")
		check(WorkbenchSession.state.session.result.evaluation.tier=="perfect","gift recipe achieves perfect with stated technique: "+guest)
		check(WorkbenchSession.research_state().mastered.has(recipe.id),"gift recipe can be mastered: "+guest)
	check(WorkbenchSession.research_state().inspiration==trial_inspiration,"gift recipe study has no DIY inspiration charge")
	check(MenuCatalog.save_menu([{"id":"character_milo","price":60}],MenuCatalog.design),"reward recipe may be explicitly published")
	check(WorkbenchSession._valid(WorkbenchSession.state),"combined activity and research save validates")
	var roundtrip: Dictionary=JSON.parse_string(JSON.stringify(WorkbenchSession.state))
	for id in Rules.IDS: check(Rules.valid(id,roundtrip.activities.runs[id].state),"JSON activity roundtrip "+id)
	check(WorkbenchSession._valid(roundtrip),"combined save survives JSON roundtrip")
	GameSession.save_game()
	var f:=FileAccess.open(Supplies.save_path+".activity-expected",FileAccess.WRITE)
	f.store_string(JSON.stringify({"inspiration":WorkbenchSession.research_state().inspiration,"book":GuestActivities.book()})); f.close()
	print("CHARACTER ACTIVITIES: %d checks, %d failures" % [count,failures.size()])
	home.queue_free(); await settle(); get_tree().quit(0 if failures.is_empty() else 1)

func restored() -> void:
	await settle()
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Supplies.save_path+".activity-expected"))
	check(WorkbenchSession.writable and MenuCatalog.writable,"new process loads reward menu and activity save")
	if not WorkbenchSession.writable or not MenuCatalog.writable:
		print("RESTORE DIAGNOSTIC: ",WorkbenchSession.last_error," / ",MenuCatalog.last_error)
		get_tree().quit(1); return
	check(WorkbenchSession.research_state().inspiration==expected.inspiration,"relaunch does not repeat rewards")
	check(GuestActivities.book().rewards.size()==3,"three first-clear receipts survive")
	check(GuestActivities.book().runs.milo_ferry.state.moves.size()==1,"ferry checkpoint survives process restart")
	check(GuestActivities.book().runs.ada_watch_memory.state.stage==1 and GuestActivities.book().runs.ada_watch_memory.state.pieces[0].cell==0 and GuestActivities.book().runs.ada_watch_memory.state.history.size()==2,"mechanical stage, placed component and undo history survive process restart")
	check(GuestActivities.book().runs.hank_lantern.state.stage==1 and GuestActivities.book().runs.hank_lantern.state.moves==["L"],"crate stage and undo proof survive restart")
	check(MenuCatalog.entries[0].id=="character_milo","published role recipe survives autoload ordering")
	for id in Rules.IDS: check(GuestActivities.progress(id).unlocked,"formal unlock survives "+id)
	print("CHARACTER RESTORE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
