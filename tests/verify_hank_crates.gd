extends SceneTree
const C=preload("res://scripts/hank_crate_rules.gd")
const Rules=preload("res://scripts/guest_activity_rules.gd")
var count:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	count+=1
	if not ok: failures+=1; push_error(label)
func _initialize() -> void:
	var s:=C.fresh()
	check(C.valid(s),"fresh crate board")
	check(not C.apply(s,"next",{}).ok,"cannot skip unsolved level")
	var first: Dictionary=C.apply(s,"move",{"direction":"L"}).state
	check(C.apply(first,"undo",{}).state==s,"undo exact initial board")
	check(C.apply(first,"reset",{}).state==s,"reset exact initial board")
	var forged:=s.duplicate(true); forged.boxes=[14]; forged.player=15
	check(not C.valid(forged),"forged positions rejected without valid move proof")
	var cfg:=C.layout(0,1)
	check(not C.step(cfg,7,[8,9],"R").ok,"cannot push two crates")
	check(not C.step(cfg,7,[8],"U").ok,"cannot walk through wall")
	check(C.cornered({"stage":0,"boxes":[7]}),"non-goal corner detected")
	# Leave the authored solution so the incremental solver is exercised too.
	var detour: Dictionary=C.apply(C.fresh(),"move",{"direction":"U"}).state
	var before:=detour.duplicate(true)
	var search:=C.hint_search(detour)
	check(not search.done,"off-plan position starts incremental search")
	C.advance_hint(search,0)
	check(not search.done,"zero time budget yields without blocking")
	var slices:=0
	while not search.done and slices<1000:
		C.advance_hint(search); slices+=1
	check(search.done and search.answer in C.DIRS,"off-plan search returns a direction")
	check(detour==before,"hint does not mutate the saved board")
	check(C.apply(detour,"move",{"direction":search.answer}).ok,"off-plan hint is legal")
	for stage in range(C.LEVELS.size()):
		var started:=Time.get_ticks_msec()
		var hint_direction:=C.hint(s)
		check(hint_direction in C.DIRS,"solver gives legal next step")
		print("HANK HINT stage %d: %d ms" % [stage+1,Time.get_ticks_msec()-started])
		check(C.layout(stage).boxes.size()==C.layout(stage).goals.size(),"one loading bay per crate")
		for direction in C.SOLUTIONS[stage]:
			var result:=C.apply(s,"move",{"direction":direction})
			check(result.ok,"authored move legal")
			if not result.ok: quit(1); return
			s=result.state
			check(C.valid(JSON.parse_string(JSON.stringify(s))),"all intermediate saves roundtrip")
		check(C.solved(s),"stage actually solved")
		check(C.hint(s)=="next","solved hint suggests next")
		s=C.apply(s,"next",{}).state
	check(s.won and C.valid(s),"all five solved levels grant victory")
	# Both old layouts and their move proofs remain playable after upgrading.
	var old:=C.fresh(1); old.erase("layout_version")
	check(C.valid(old),"pre-upgrade unversioned layout remains valid")
	for stage in range(3):
		for direction in C.LEGACY_SOLUTIONS[stage]: old=C.apply(old,"move",{"direction":direction}).state
		check(C.solved(old) and C.valid(old),"old stage proof stays valid")
		old=C.apply(old,"next",{}).state
	check(old.won and C.valid(old),"legacy three-stage victory remains claimable")
	var corrupt:=C.fresh(); corrupt.layout_version=99
	check(not C.valid(corrupt),"unknown layouts rejected without remapping")
	forged=s.duplicate(true); forged.completed[0]=[]
	check(not C.valid(forged),"cannot forge completed previous stage")
	check(not C.apply(s,"next",{}).ok,"repeat win rejected")
	check(Rules.safe(0,3) and Rules.safe(2,2) and not Rules.safe(1,2),"police riot rule and zero-police exception")
	var ferry:=Rules.fresh("milo_ferry")
	check(Rules.crossing_failure(ferry,1,0).message.contains("囚犯发动了暴动"),"riot reason names police and prisoners")
	check(Rules.crossing_failure(ferry,0,2).is_empty(),"two prisoners can depart safely")
	print("CRATE RULES: %d checks, %d failures" % [count,failures]); quit(1 if failures else 0)
