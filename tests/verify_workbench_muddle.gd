extends "res://tests/verify_workbench_drag.gd"
const Muddle=preload("res://scripts/workbench_muddle.gd")
const Preview=preload("res://scripts/workbench_drink_preview.gd")

func _ready() -> void:
	if "--muddle-resume" in OS.get_cmdline_user_args():
		if not str(Supplies.save_path).begins_with("/tmp/"): get_tree().quit(2); return
		call_deferred("restored")
	else: super._ready()

func restored() -> void:
	check(WorkbenchSession._valid(WorkbenchSession.state),"new process valid save")
	check(WorkbenchSession.state.session.status=="finished" and WorkbenchSession.state.session.result.contents.mint_processing==WorkbenchSession.state.session.vessels.glass.mint_processing,"finished preview survives restart")
	check(Muddle.summary(WorkbenchSession.state.session.vessels.glass).max_work>=9,"crushed mint survives process restart")
	print("MUDDLE RESTORE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func move(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=local_point(point)
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion,true)

func op(kind: String,payload: Dictionary={}) -> void:
	check(bench._issue(kind,payload),kind+": "+WorkbenchSession.last_error)

func run() -> void:
	Supplies.inventory.purchase(Muddle.LEAF,2)
	check(Supplies._write(Supplies.inventory.serialize(),Supplies.workbench),"private mint fixture")
	Supplies.changed.emit()
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	op("cup",{"cup":"highball"})
	for i in range(3): op("add_solid",{"material":Muddle.LEAF,"vessel":"glass"})
	op("withdraw",{"material":"soda","ml":180,"vessel":"glass"})
	bench._show_category("器具")
	var tool: Button=bench.item_buttons.muddler
	pointer(tool.get_global_transform_with_canvas()*(tool.size*.5),true)
	move(bench.table.POS.glass)
	check(bench.table.muddle_gripped and bench.table.carry_id.is_empty(),"drag from cabinet engages tool without releasing mouse")
	pointer(local_point(bench.table.POS.glass),false)
	await settle()
	check(bench.technique=="muddle" and bench.technique_panel.visible,"drag muddler opens its own guidance")
	check(bench.technique_title.text.contains("轻压") and bench.technique_detail.text.contains("2–4"),"muddle-specific timing guidance")
	check(bench.data.get("spoon_vessel","").is_empty(),"muddling does not leave an active spoon in cup")
	check(bench.table.prop_visible("muddler"),"muddler remains inserted after release")
	var initial: Dictionary=WorkbenchSession.snapshot()
	var point: Vector2=bench.table.muddler_rect().position+Vector2(26,30)
	pointer(local_point(point),true)
	check(bench.table.muddle_gripped and bench.table.dragging,"visible handle is grabbed directly")
	await get_tree().create_timer(.3).timeout
	check(WorkbenchSession.snapshot()==initial and bench.sfx.press_count==0,"holding still creates no processing or sound")
	for i in range(4):
		await get_tree().create_timer(.02).timeout
		move(point+Vector2(20 if i%2==0 else 0,0))
	check(Muddle.summary(bench.data.vessels.glass).max_work==0,"horizontal motion does not crush mint")
	pointer(local_point(point),false)
	await capture("muddle-01-whole")
	var stages: Array=[bench.data.vessels.glass.duplicate(true)]
	pointer(local_point(point),true)
	for stroke in range(8):
		for i in range(1,7):
			await get_tree().create_timer(.04).timeout
			move(point+Vector2(0,i*6))
		for i in range(5,-1,-1):
			await get_tree().create_timer(.02).timeout
			move(point+Vector2(0,i*6))
	check(bench.sfx.press_count>=6 and bench.sfx.press_count<=8,"one wet impact per downstroke, never per mouse event")
	pointer(local_point(point),false)
	await get_tree().create_timer(.15).timeout
	for player in bench.sfx.presses: check(not player.playing,"release stops impact audio")
	var progress:=Muddle.summary(bench.data.vessels.glass)
	check(progress.max_work>0 and progress.seconds>0,"native downward gesture advances persisted mint processing")
	check(WorkbenchSession.state.stock==initial.stock,"muddling never consumes leaves a second time")
	point=bench.table.muddler_rect().position+Vector2(26,30)
	pointer(local_point(point),true)
	await get_tree().create_timer(.04).timeout
	move(point+Vector2(0,18))
	check(bench.table.muddle_gripped and bench.table.motion_is_active(),"held stick drives pressing feedback")
	bench.table.set_process(false)
	await capture("muddle-05-gripped")
	bench.table.set_process(true)
	pointer(local_point(point+Vector2(0,18)),false)
	var contents_before: Dictionary=bench.data.vessels.glass.duplicate(true)
	point=bench.table.muddler_rect().position+Vector2(26,30)
	pointer(local_point(point),true)
	move(bench.table.DRAIN_RECT.get_center())
	pointer(local_point(bench.table.DRAIN_RECT.get_center()),false)
	check(bench.data.vessels.glass==contents_before,"dragging tool over drain cannot empty its cup")
	stages.append(bench.data.vessels.glass.duplicate(true))
	await capture("muddle-02-bruised")
	for i in range(10): op("muddle",{"vessel":"glass","seconds":.5,"pressure":1.0})
	check(Muddle.summary(bench.data.vessels.glass).max_work>=9,"continued firm pressure tears leaf into fragments")
	await get_tree().create_timer(.7).timeout
	await capture("muddle-03-fragments")
	stages.append(bench.data.vessels.glass.duplicate(true))
	var action: Dictionary=bench.data.actions.back()
	var before:=WorkbenchSession.snapshot()
	check(WorkbenchSession.command(action.command_id,bench.data.id,action.kind,action.payload) and WorkbenchSession.snapshot()==before,"retried press is idempotent")
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/blocked.json"
	check(not bench._issue("muddle",{"vessel":"glass","seconds":.5,"pressure":1}) and WorkbenchSession.snapshot()==before,"failed write rolls back leaf damage")
	Supplies.save_path=path
	op("add_solid",{"material":Muddle.LEAF,"vessel":"glass"})
	check(bench.data.vessels.glass.mint_processing.back().work==0 and bench.data.vessels.glass.mint_processing[0].work>=9,"fresh leaf never inherits previous crushing")
	op("transfer",{"source":"glass","vessel":"mixing"})
	check(Muddle.summary(bench.data.vessels.mixing).count==4 and Muddle.summary(bench.data.vessels.glass).count==0,"unfiltered transfer carries exact leaf condition")
	op("filter",{"source":"mixing","vessel":"glass"})
	check(Muddle.summary(bench.data.vessels.mixing).count==4 and Muddle.summary(bench.data.vessels.glass).count==0,"filter retains mint and fragments in source")
	op("transfer",{"source":"mixing","vessel":"glass"})
	check(Muddle.summary(bench.data.vessels.glass).count==4,"solid-only transfer carries fragments")
	check(WorkbenchSession.load_state() and WorkbenchSession._valid(WorkbenchSession.state),"leaf processing restores with consistent containers")
	var legacy: Dictionary={"solids":{Muddle.LEAF:2}}
	check(Muddle.valid(legacy) and Muddle.leaves(legacy).size()==2,"old save without condition remains readable")
	var invalid: Dictionary=bench.data.vessels.glass.duplicate(true)
	invalid.mint_processing[0].work=-1
	check(not Muddle.valid(invalid),"invalid leaf condition rejected")
	var a: Dictionary={"solids":{Muddle.LEAF:1}}
	var b: Dictionary=a.duplicate(true)
	Muddle.press(a,.5,.2)
	Muddle.press(b,.5,.9)
	check(Muddle.summary(b).max_work>Muddle.summary(a).max_work,"equal duration but stronger pressure causes more damage")
	var source: Dictionary=bench.data.vessels.glass.duplicate(true)
	var target: Dictionary={"contents":{},"layers":[],"solids":{},"ice":"none","ice_batches":[],"garnish":false,"garnishes":[]}
	WorkbenchSession._pour_contents(source,target,90,false)
	check(Muddle.valid(source) and Muddle.valid(target) and Muddle.summary(target).count==2,"partial pour partitions leaf processing alongside leaf counts")
	bench.sfx._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var hits: int=bench.sfx.press_count
	bench.sfx.muddle(.5)
	check(bench.sfx.press_count==hits,"unfocused workspace cannot play impacts")
	bench.sfx._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var gallery:=Control.new()
	gallery.size=Vector2(1600,900)
	bench.surface.add_child(gallery)
	var bg:=ColorRect.new()
	bg.size=gallery.size
	bg.color=Color("30251d")
	gallery.add_child(bg)
	bench._text(gallery,Rect2(30,15,1540,60),"薄荷轻压过程 · Godot 实际渲染",32)
	for i in range(3):
		var preview:=Preview.new()
		preview.position=Vector2(20+i*525,95)
		preview.size=Vector2(510,680)
		preview.result={"cup":"highball","contents":stages[i],"capacity_ml":350,"liquid_profiles":bench.data.liquid_profiles}
		gallery.add_child(preview)
		bench._text(gallery,Rect2(105+i*525,800,450,40),["完整叶片","轻压后：压软、轻微破边","持续重压：逐渐碎裂"][i],22)
	await capture("muddle-04-stages")
	op("finish")
	check(bench.data.result.contents.mint_processing==bench.data.vessels.glass.mint_processing,"finished drink freezes the same leaf condition")
	print("MUDDLE: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
