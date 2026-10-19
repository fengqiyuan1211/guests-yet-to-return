extends "res://tests/verify_character_activities.gd"
const Gate=preload("res://scripts/story_activity_gate.gd")
const Eval=preload("res://scripts/customer_evaluation.gd")

func _ready() -> void:
	if not Supplies.save_path.begins_with("/tmp/") or not CustomerService.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	CustomerService.endpoint=""; TimeManager.set_process(false)
	if "--flow-resume" in OS.get_cmdline_user_args(): call_deferred("flow_restored")
	else:
		check(preload("res://tests/workbench_fixture.gd").seed(Supplies,WorkbenchSession),"private inventory seeded")
		call_deferred("run")

func gate_checks() -> void:
	for guest in ["stick","milo","ada","hank","yellow_creature"]:
		var chapters:=Gate.episodes(guest); var story:={"completed":5,"heard":{}}; var cups:={}
		for i in range(5):
			var key:=str(i); cups[key]={"id":key,"guest_id":guest,"status":"settled","play_mode":"story","visit_serial":i+1,"visit_id":"v"+key,"story_episode_id":chapters[i].id,"story_completed":true,"review":{"status":"scored","satisfaction":60.0},"craft":{"score":100.0}}
		check(not Gate.summarize(guest,story,chapters,cups).eligible,"exactly 60 never qualifies: "+guest)
		cups["4"].review.satisfaction=60.01
		check(Gate.summarize(guest,story,chapters,cups).eligible,"unrounded average strictly >60: "+guest)
		cups["4"].review.satisfaction=0.0
		check(not Gate.summarize(guest,story,chapters,cups).eligible,"final cup is included: "+guest)
		cups["4"].review.satisfaction=100; cups["4"].play_mode="mixing"
		check(not Gate.summarize(guest,story,chapters,cups).eligible,"free mode excluded: "+guest)
		cups["4"].play_mode="story"; cups["4"].status="prepared"
		check(not Gate.summarize(guest,story,chapters,cups).eligible,"unsettled cup excluded: "+guest)
		cups["4"].status="settled"; cups["4"].story_completed=false
		check(not Gate.summarize(guest,story,chapters,cups).eligible,"unfinished story excluded: "+guest)
		cups["4"].story_completed=true; cups["0"].review={"status":"rejected","satisfaction":null}
		check(Gate.summarize(guest,story,chapters,cups).average==56,"refusal is zero and retains slot: "+guest)
		var duplicate: Dictionary=cups["0"].duplicate(true); duplicate.id="repeat"; duplicate.visit_id="repeat"; duplicate.visit_serial=20; duplicate.review={"status":"scored","satisfaction":100}
		cups.repeat=duplicate
		check(Gate.summarize(guest,story,chapters,cups).average==56,"repeats cannot replace first chapter cup: "+guest)
	var crate:=Rules.Crates.fresh()
	crate=Rules.Crates.apply(crate,"move",{"direction":"L"}).state
	var restored_crate: Dictionary=JSON.parse_string(JSON.stringify(crate))
	check(Rules.Crates.valid(restored_crate),"partly played crate board survives JSON roundtrip")
	check(Rules.Crates.apply(restored_crate,"move",{"direction":"U"}).state==Rules.Crates.apply(crate,"move",{"direction":"U"}).state,"restored crate collision uses integer cells")
	var chapters:=Gate.episodes("milo"); var old_story:={"completed":5,"heard":{}}; var legacy:={}
	for i in range(5):
		old_story.heard[chapters[i].id]=["heard"]
		legacy[str(i)]={"phase":"complete","drink_id":"practice-%d-drink" % (i+1),"order":{"guest_id":"milo","visit_id":"old-%d" % i,"demand":{"event_id":chapters[i].id}},"receipt":{"id":"sale-%d" % i,"status":"accepted","score":80}}
	check(Gate.summarize("milo",old_story,chapters,{},legacy).eligible,"linked legacy receipts count without rewriting their scores")
	legacy["2"].order.demand.event_id=""
	check(not Gate.summarize("milo",old_story,chapters,{},legacy).eligible,"unknown legacy chapter cannot fabricate eligibility")
	# Independent hand calculation from the document, including all deductions.
	var target:={"target":{"alcohol_intensity":60,"sweetness":80,"sourness":50,"bitterness":40},"weights":{},"tolerances":{},"constraints":[],"soft_state_penalties":[],"buff_affinities":{"test":10}}
	for attr in Eval.ATTRS: target.weights[attr]=1.0; target.tolerances[attr]=5.0
	var actual:={"status":"complete","attributes":{"alcohol_intensity":40,"sweetness":65,"sourness":50,"bitterness":40},"states":{},"facts":{},"items":{}}
	var result:=Eval.evaluate(target,actual,false,CustomerService.rules,{"active":[{"id":"test","kind":"ordinary"}]})
	check(result.base_score==87.5 and result.satisfaction==97.5,"document weighted-error example 87.5+10=97.5")
	actual.attributes=target.target.duplicate(true)
	check(Eval.evaluate(target,actual,false,CustomerService.rules,{"active":[{"id":"test","kind":"ordinary"}]}).satisfaction==100,"bonus total capped at 100")
	check(Eval.evaluate(target,actual,true,CustomerService.rules).satisfaction==90,"late service subtracts ten before gate")

func finish_matching_cup() -> void:
	var defs:=WorkbenchSession.MATERIALS.duplicate(true); defs.merge(WorkbenchSession.SOLIDS); defs.merge(WorkbenchSession.GARNISHES)
	var best: Dictionary={}; var highest:=-1.0
	for gin in [20,40,60]:
		for lime in [0,5,10,15]:
			for syrup in [0,5,10]:
				for tonic in [0,80]:
					var amounts:={"gin":float(gin),"lime":float(lime),"syrup":float(syrup),"soda":80.0,"sku_tonic_water":float(tonic)}
					var actual:=Eval.sensory({"contents":{"contents":amounts,"solids":{},"garnishes":[]}},defs,CustomerService.state.active.rules_snapshot)
					actual.reference_items={}
					var score:=Eval.evaluate(CustomerService.state.active.order.demand,actual,false,CustomerService.state.active.rules_snapshot)
					if score.get("status")=="scored" and float(score.satisfaction)>highest:
						highest=float(score.satisfaction); best=amounts
	check(highest>60,"configured character taste has a feasible cup >60")
	for material in best:
		if best[material]>0: op("withdraw",{"material":material,"ml":best[material],"vessel":"glass"})
	op("finish")

func drain_feedback() -> void:
	for i in range(8):
		await settle()
		var r:=CustomerService.current_record()
		if r.feedback.done: break
		CustomerService.choose_feedback(0,int(r.feedback.round))
	check(CustomerService.current_record().feedback.done,"feedback finishes within three rounds")

func run() -> void:
	gate_checks()
	for sku in ["sku_gin_london_dry","sku_tonic_water","sku_lime_juice","sku_simple_syrup","sku_soda_water"]:
		check(Supplies.inventory.purchase(sku,40),"stock actual cup material "+sku)
	check(Supplies._write(Supplies.inventory.serialize(),{}),"save isolated stock")
	MenuCatalog.unlock_recipe("gin_and_tonic")
	check(MenuCatalog.save_menu([{"id":"gin_and_tonic","price":80}],MenuCatalog.design),"publish test menu")
	home=load("res://scenes/home.tscn").instantiate(); add_child(home); await settle()
	TimeManager.set_process(false); TimeManager.advance_minutes(posmod(1200-TimeManager.minutes_since_midnight,1440)); await settle()
	for row in [["milo",0,"milo_ferry"],["ada",1,"ada_watch_memory"],["hank",2,"hank_lantern"],["yellow_creature",4,"yellow_ski"],["stick",3,"stick_minigame"]]:
		var guest: String=row[0]; var id: String=row[2]
		for chapter in range(5):
			home.get_node("%GuestLayer").show_guest(row[1]); await settle()
			check(CustomerService.state.active.story_episode_id==StoryDialogue.catalog[guest][chapter].id,"current episode demand matches chapter "+guest+str(chapter))
			if chapter<4: talk_chapter(); await settle()
			if guest!="stick": check(not GuestActivities.progress(id).unlocked,"no early invitation before final cup "+guest)
			home._on_open_pressed(); await settle(); bench=home.active_page
			check(Navigation.current_route==&"drink_selection","story opens drink selection")
			bench._select("gin_and_tonic"); bench._start(); await settle(); bench=home.active_page
			finish_matching_cup(); await settle()
			var result: Dictionary=WorkbenchSession.state.session.result.duplicate(true); var money:=SlotWallet.balance
			bench._send_finished_drink(); await settle()
			var record:=CustomerService.current_record()
			check(record.status=="settled" and record.review.satisfaction>60,"actual settled total meets target "+guest)
			check(SlotWallet.balance==money+record.amount and CustomerService.deliver(result) and SlotWallet.balance==money+record.amount,"single payment despite repeat submit")
			bench._return_after_serving(); await settle(); await drain_feedback()
			if chapter==4:
				if guest!="stick": check(not GuestActivities.progress(id).unlocked,"finish drinking alone does not skip remaining story")
				check(CustomerService.resume_served_story(str(record.id)),"can finish story after drinking")
				var stock_path: String=Supplies.save_path
				if guest=="milo": Supplies.save_path=stock_path+"/unwritable"
				talk_chapter(); await settle(); await settle()
				if guest=="milo":
					check(not GuestActivities.progress(id).unlocked and GuestActivities.current_invitation().is_empty(),"failed invitation persistence grants nothing")
					Supplies.save_path=stock_path
					check(GuestActivities.reconcile(),"retry persists final invitation safely")
					await settle()
			var summary: Dictionary=CustomerService.memory_summary() if guest=="stick" else GuestActivities.progress(id).summary
			check(summary.score_count==chapter+1,"one final-score receipt per episode")
			print("FLOW ",guest," chapter=",chapter+1," total=",record.review.satisfaction," craft=",record.craft.score)
			if chapter<4:
				check(not summary.eligible,"four or fewer story cups cannot qualify")
				home.on_drink_served(); await settle()
		check((CustomerService.memory_summary() if guest=="stick" else GuestActivities.progress(id).summary).eligible,"all five qualified "+guest)
		if guest=="stick":
			check(home._memory_inviting,"final stick feedback automatically starts authored invitation")
			while CustomerService.memory_dialogue_step("invitation")<2:
				CustomerService.advance_memory_dialogue("invitation",CustomerService.memory_dialogue_step("invitation"))
			home._show_memory_invitation(); home._accept_memory_invitation(); await settle(); bench=home.active_page
			check(Navigation.current_route==&"stick_badminton" and bench.match_context.mode=="story","accept starts formal badminton")
			# Exercise reducer proof/award separately below; this screen uses the live invitation context.
			await verify_stick_reward()
		elif guest=="yellow_creature":
			check(GuestActivities.current_invitation()==id and home.get_node("%GuestSpeech").text.contains("雪山"),"yellow skiing invitation appears in conversation")
			check(home.story_choices.is_visible_in_tree() and home.story_choices.get_child_count()==2,"invitation choices visible and actionable "+guest)
			home._accept_activity_invitation(id); await settle(); bench=home.active_page
			check(Navigation.current_route==&"yellow_ski","accept enters ski scene")
			bench._leave(); await settle()
			check(not WorkbenchSession.research_state().acquired.has("character_yellow_creature"),"yellow never receives invented cocktail")
		else:
			check(GuestActivities.current_invitation()==id and home.get_node("%GuestTags").text.contains("邀请"),"invitation visible automatically "+guest)
			check(home.story_choices.is_visible_in_tree() and home.story_choices.get_child_count()==2,"invitation choices visible and actionable "+guest)
			home._accept_activity_invitation(id); await settle(); bench=home.active_page
			check(GuestActivities.active.mode=="normal","accept opens formal game "+guest)
			click(button_named("开始游戏")); await settle(); await complete_game()
			check(GuestActivities.book().rewards.has(id) and MenuCatalog.get_recipe("character_"+guest).get("unlocked",false),"win unlocks real special recipe "+guest)
			var inspiration: int=WorkbenchSession.research_state().inspiration
			check(GuestActivities.claim() and WorkbenchSession.research_state().inspiration==inspiration,"reward claimed only once")
			bench._close(); await settle()
		Navigation.go_to(&"home"); await settle()
		if guest!="stick": check(GuestActivities.current_invitation().is_empty(),"acknowledged invitation does not repeat")
		else: check(CustomerService.memory_farewell_active(),"stick farewell after reward")
		home.on_drink_served(); await settle()
		if guest=="yellow_creature":
			home.get_node("%GuestLayer").show_guest(4); await settle()
			check(CustomerService.state.active.story_episode_id.is_empty(),"yellow repeat cannot become a sixth scored story chapter")
	await verify_reward_recipes()
	check(GameSession.save_game() and CustomerService._write() and WorkbenchSession._valid(WorkbenchSession.state),"all flow data saves")
	print("UNIFIED STORY FLOW: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_stick_reward() -> void:
	bench.set_process(false)
	var won:=false
	for seed_value in range(1,7):
		bench.model.begin("memory-flow-"+str(seed_value),0,seed_value)
		for i in range(48000):
			var m: RefCounted=bench.model
			if m.phase=="finished": break
			if m.phase=="ready" and m.server==0: m.swing()
			if m.phase=="rally" and m.last_hitter==1:
				if m.shuttle.y<400 and m.shuttle.x<760 and absf(m.shuttle.x-m.player_x)<180 and m.velocity.y>0: m.jump()
				if m.can_hit(0): m.swing()
			m.step(1.0/120.0,0,true)
		if bench.model.player_score==5: won=true; break
	check(won,"badminton actual simulation can win to five")
	bench._result(); await settle()
	check(bench.recorded and WorkbenchSession.research_state().story_items.has("item_recipe_after_school"),"formal win grants recipe paper")
	check(bench._record_result() and WorkbenchSession.research_state().story_items.item_recipe_after_school.quantity==1,"badminton reward idempotent")
	bench._close(); await settle(); await settle()
	check(Navigation.current_route==&"home" and CustomerService.memory_dialogue_kind()=="reward","badminton returns to reward dialogue")
	while CustomerService.memory_dialogue_step("reward")<2:
		CustomerService.advance_memory_dialogue("reward",CustomerService.memory_dialogue_step("reward"))
	home._finish_memory_reward(); await settle()
	check(not home.get_node("%GuestLayer")._can_arrive(3),"stick retires after reward")

func verify_reward_recipes() -> void:
	for id in ["character_milo","character_ada","character_hank","childhood_keepsake"]:
		var recipe:=MenuCatalog.get_recipe(id)
		for row in recipe.ingredients: check(Supplies.inventory.purchase(row.sku_id,2),"stock gift ingredient "+row.sku_id)
		check(Supplies._write(Supplies.inventory.serialize(),{}),"persist gift stock")
		op("begin_research",{"mode":"research_legendary","recipe_id":id})
		op("ice",{"ice":"cube","vessel":"glass"}); op("ice",{"ice":"cube","vessel":"glass"})
		var amounts: Dictionary=WorkbenchSession.state.session.recipe.ingredients
		for material in amounts:
			if material not in ["soda","sku_cola"]: op("withdraw",{"material":material,"ml":amounts[material],"vessel":"glass"})
		for material in ["soda","sku_cola"]:
			if amounts.has(material): op("withdraw",{"material":material,"ml":amounts[material],"vessel":"glass"})
		op("spoon",{"target":"glass"})
		for i in range(8): op("stir",{"vessel":"glass","seconds":.5,"control":1.0})
		if id=="childhood_keepsake": op("garnish",{"vessel":"glass","material":"sku_cocktail_cherry"})
		op("finish")
		check(WorkbenchSession.state.session.result.evaluation.tier=="perfect","special recipe can actually be made perfectly "+id)
		check(WorkbenchSession.research_state().mastered.has(id) and MenuCatalog.get_recipe(id).unlocked,"mastery makes recipe available "+id)
		check(MenuCatalog.save_menu([{"id":id,"price":80}],MenuCatalog.design),"special recipe can be put on menu "+id)
		if id=="childhood_keepsake": check(WorkbenchSession.state.session.result.get("legendary_buff",{}).get("name")=="未完待续","childhood golden buff attached to perfect cup")

func flow_restored() -> void:
	await settle()
	for id in Rules.INVITATION_IDS:
		check(GuestActivities.progress(id).unlocked,"invitation survives restart "+id)
		check(GuestActivities.book().unlocks.get(id,{}).get("invitation_seen",false),"ack survives restart "+id)
	for recipe in ["character_milo","character_ada","character_hank","childhood_keepsake"]:
		check(MenuCatalog.get_recipe(recipe).get("unlocked",false),"special recipe survives restart "+recipe)
	check(CustomerService.memory_summary().eligible,"stick score evidence survives restart")
	print("STORY FLOW RESTORE: %d checks, %d failures" % [count,failures.size()]); get_tree().quit(0 if failures.is_empty() else 1)
