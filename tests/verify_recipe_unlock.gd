extends "res://tests/verify_workbench_scene.gd"

func _ready() -> void:
	if "--unlock-resume" in OS.get_cmdline_user_args():
		call_deferred("resume_check")
	else: super._ready()

func run() -> void:
	MenuCatalog.reset_game()
	OpeningFlow.state = OpeningFlow.fresh()
	for ingredient in MenuCatalog.get_recipe("echo_world").ingredients:
		check(Supplies.inventory.purchase(ingredient.sku_id,1),"stock echo ingredient "+ingredient.sku_id)
	check(Supplies._write(Supplies.inventory.serialize(),Supplies.workbench),"private warehouse persisted")
	check(Supplies._sync_menu(),"supply sync")
	check(not MenuCatalog.get_recipe("echo_world").unlocked,"all ingredients cannot bypass tutorial gate")
	check(OpeningFlow.begin_story() and OpeningFlow.begin_tutorial(),"begin tutorial")
	var wallet := SlotWallet.balance
	var stock: Dictionary = Supplies.inventory.serialize()
	check(not OpeningFlow.finish_tutorial(),"unfinished tutorial cannot grant reward")
	check(not MenuCatalog.get_recipe("echo_world").unlocked,"rejected finish keeps echo locked")
	check(OpeningFlow.finish_tutorial(true),"explicit skip ends tutorial")
	check(MenuCatalog.get_recipe("echo_world").unlocked and MenuCatalog.is_recipe_new("echo_world"),"echo is new immediately after tutorial, before departure scene")
	check(MenuCatalog.entries.is_empty() and SlotWallet.balance==wallet and Supplies.inventory.serialize()==stock,"unlock neither lists drink nor consumes stock or coins")
	check(MenuCatalog.load_state() and MenuCatalog.is_recipe_new("echo_world"),"unread unlock survives reload")
	var path := MenuCatalog.save_path
	MenuCatalog.save_path += "/unwritable"
	check(not MenuCatalog.mark_recipe_seen("echo_world") and MenuCatalog.is_recipe_new("echo_world"),"failed acknowledgement does not lose unread flag")
	MenuCatalog.save_path = path
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	check(home.find_child("NewRecipesHighlight",true,false).active,"catalogue entry points to unread unlocks")
	Navigation.go_to(&"codex")
	await settle()
	bench = home.active_page
	var card: Button
	for item in bench.page_content.find_children("CardSlot*","Button",true,false):
		if item.get_meta("cocktail_id","")=="echo_world": card=item
	check(card!=null and card.find_child("NewRecipeBadge",true,false)!=null,"echo card displays new badge")
	var glow: Control = card.get_node("NewRecipeHighlight")
	var clock_before: float=glow.clock
	await get_tree().create_timer(.25).timeout
	check(glow.clock!=clock_before and glow.mouse_filter==Control.MOUSE_FILTER_IGNORE,"highlight animates without intercepting input")
	await capture("echo-new-unlock")
	click(card)
	await settle()
	check(bench.detail_id=="echo_world" and not MenuCatalog.is_recipe_new("echo_world"),"native detail click acknowledges exactly this recipe")
	check(MenuCatalog.load_state() and not MenuCatalog.is_recipe_new("echo_world"),"acknowledgement survives reload")
	check(MenuCatalog.unlock_recipe("echo_world") and not MenuCatalog.is_recipe_new("echo_world"),"idempotent reward does not relight viewed recipe")
	bench.close_detail()
	await settle()
	await capture("echo-seen-unlock")
	# Simulate an older valid menu. Previously unlocked recipes do not all flash.
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var legacy:=original.duplicate(true)
	legacy.erase("seen_recipe_ids")
	check(MenuCatalog._atomic_write(legacy) and MenuCatalog.load_state(),"legacy menu loads without notification field")
	check(not MenuCatalog.is_recipe_new("echo_world"),"old acquired echo is treated as already known")
	check(MenuCatalog._atomic_write(original) and MenuCatalog.load_state(),"restore private fixture")
	# Simulate interruption after durable tutorial completion but before its unlock.
	check(MenuCatalog.reset_game(),"private reset for recovery test")
	MenuCatalog.bind_research(WorkbenchSession)
	check(MenuCatalog.is_recipe_new("echo_world"),"startup reconciliation repairs missing tutorial reward")
	check(MenuCatalog.save_state(),"persist unread state for fresh process")
	home.queue_free()
	await settle()
	print("RECIPE UNLOCK: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func resume_check() -> void:
	check(MenuCatalog.get_recipe("echo_world").unlocked and MenuCatalog.is_recipe_new("echo_world"),"fresh process retains unread reward")
	check(MenuCatalog.mark_recipe_seen("echo_world") and MenuCatalog.load_state() and not MenuCatalog.is_recipe_new("echo_world"),"fresh process can acknowledge durably")
	print("RECIPE UNLOCK RESTORE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
