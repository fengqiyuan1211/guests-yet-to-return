extends "res://tests/verify_workbench_drag.gd"

func run() -> void:
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	bench._act("cup",{"cup":"highball"})
	await capture("14-mixing-empty")
	from_pantry("gin","mixing")
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=.2 if bench.measure.precise else bench.measure.target*.3/bench.measure.volume_limit()
	bench._process(0)
	var low: float=Liquid.volume(bench.table.contents_for("mixing"))
	bench.measure.progress=bench.measure.target/bench.measure.volume_limit()
	bench._process(0)
	var high: float=Liquid.volume(bench.table.contents_for("mixing"))
	check(high>low and low>0,"direct pouring preview grows in mixing glass")
	check(WorkbenchSession.state.stock.gin==600 and WorkbenchSession.state.session.vessels.mixing.contents.is_empty(),"animated preview does not consume stock")
	space()
	await get_tree().create_timer(1.2).timeout
	check(is_equal_approx(Liquid.volume(bench.table.contents_for("mixing")),30),"direct pour settles to actual amount")
	await capture("15-mixing-30ml")
	var clear_color := Liquid.color(bench.table.contents_for("mixing"))
	click(bench.category_buttons[1])
	await settle()
	bench.dose_overrides.lime=60
	from_pantry("lime","jigger")
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=bench.measure.target/bench.measure.volume_limit()
	space()
	await get_tree().create_timer(1.2).timeout
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	drag_between(local_point(bench.table.POS.jigger),local_point(bench.table.POS.mixing))
	await get_tree().create_timer(.35).timeout
	var partial: float=Liquid.volume(bench.table.contents_for("mixing"))
	check(partial>30 and partial<90,"jigger transfer raises liquid progressively")
	check(WorkbenchSession.state.stock==stock,"transfer animation never debits a second time")
	# Another harmless vessel change during a fill must not skip the interpolation.
	bench._act("ice",{"vessel":"glass","ice":"cube"})
	check(absf(Liquid.volume(bench.table.contents_for("mixing"))-partial)<1,"interrupted fill preserves its current visible amount")
	await get_tree().create_timer(1.2).timeout
	check(is_equal_approx(Liquid.volume(bench.table.contents_for("mixing")),90),"mixing glass converges to combined dose")
	check(Liquid.color(bench.table.contents_for("mixing"))!=clear_color,"adding lime changes mixing glass color")
	check(Liquid.surface_fraction(90,500,false,false,true)<Liquid.surface_fraction(30,500,false,false,true),"larger volume has a higher mixing surface")
	await capture("16-mixing-90ml")
	bench._act("filter",{"source":"mixing","vessel":"glass"})
	await get_tree().create_timer(.35).timeout
	var draining: float=Liquid.volume(bench.table.contents_for("mixing"))
	check(draining>0 and draining<90,"filtering progressively lowers mixing glass contents")
	await get_tree().create_timer(1.2).timeout
	check(is_zero_approx(Liquid.volume(bench.table.contents_for("mixing"))) and WorkbenchSession.amount(WorkbenchSession.state.session.vessels.glass)==90,"filter ends with empty mixing glass and full receiving dose")
	check(WorkbenchSession.state.stock==stock,"all visual effects leave committed stock unchanged")
	print("WORKBENCH MIXING: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
