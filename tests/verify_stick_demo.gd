extends "res://tests/verify_workbench_scene.gd"
const JournalData = preload("res://scripts/guest_journal_data.gd")

func run() -> void:
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	var progress: Dictionary=StoryDialogue.progress.duplicate(true)
	var inventory: Dictionary=Supplies.inventory.serialize().duplicate(true)
	var production: Dictionary=WorkbenchSession.snapshot()
	var gold: int=SlotWallet.balance
	check(not StoryDialogue.is_known("stick"),"no story progress is required for demo")
	Navigation.go_to(&"journal")
	await settle()
	bench=home.active_page
	click(bench.guest_buttons.stick)
	await settle()
	var start: Button=button_named("开始游戏")
	check(start!=null and not start.disabled,"unknown guest has accessible demo button")
	check(start.tooltip_text.contains("内测演示"),"launch hover discloses demo status")
	var motion:=InputEventMouseMotion.new()
	motion.position=start.get_global_transform_with_canvas()*(start.size*.5)
	get_viewport().push_input(motion,true)
	await get_tree().create_timer(1.1).timeout
	await capture("stick-demo-01-tooltip")
	click(button_named("开始游戏"))
	await settle()
	bench=home.active_page
	check(Navigation.current_route==&"stick_demo" and bench.model!=null,"opens actual badminton scene")
	check(not TimeManager.running,"tavern clock pauses")
	var minute: int=TimeManager.minutes_since_midnight
	TimeManager._process(5)
	check(TimeManager.minutes_since_midnight==minute,"playing demo cannot consume service time")
	var play: Button=button_named("开始游戏")
	check(play!=null and play.tooltip_text.contains("内测演示"),"in-game start hover also discloses demo")
	click(play)
	await settle()
	check(bench.playing,"native start begins game")
	var game: Control=bench
	game.set_process(false)
	game.model.practice_left=0
	game._swing()
	for i in range(480): game.model.step(1.0/120,0.0,true)
	check(game.model.player_actions>0,"space swing produces legal game action")
	await capture("stick-demo-02-court")
	game._pause()
	check(game.paused,"pause works")
	game._resume()
	check(not game.paused,"resume works")
	game.model.player_score=5
	game.model.ai_score=2
	game.model.phase="finished"
	game._result()
	check(game.recorded,"demo result is accepted locally")
	check(StoryDialogue.progress==progress and WorkbenchSession.snapshot()==production,"demo win leaves story, recipes and production unchanged")
	check(SlotWallet.balance==gold and Supplies.inventory.serialize()==inventory,"demo win gives no coins or items")
	await capture("stick-demo-03-result")
	game._close()
	await settle()
	bench=home.active_page
	check(Navigation.current_route==&"journal" and bench.selected_id=="stick" and bench.tab==3,"return restores small-line game tab")
	check(TimeManager.running,"return resumes original tavern clock")
	TimeManager.set_running(false)
	bench._launch_activity("stick_minigame")
	await settle()
	home.active_page._close()
	await settle()
	check(not TimeManager.running,"previously paused clock stays paused after demo")
	check(StoryDialogue.progress==progress,"entry and return do not mark character as met")
	print("STICK DEMO: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
