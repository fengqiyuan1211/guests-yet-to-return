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
	var first: Dictionary=C.apply(s,"move",{"direction":"R"}).state
	check(C.apply(first,"undo",{}).state==s,"undo exact initial board")
	check(C.apply(first,"reset",{}).state==s,"reset exact initial board")
	var forged:=s.duplicate(true); forged.boxes=[14]; forged.player=15
	check(not C.valid(forged),"forged positions rejected without valid move proof")
	var cfg:=C.layout(0)
	check(not C.step(cfg,7,[8,9],"R").ok,"cannot push two crates")
	check(not C.step(cfg,7,[8],"U").ok,"cannot walk through wall")
	check(C.cornered({"stage":0,"boxes":[7]}),"non-goal corner detected")
	for stage in range(3):
		check(C.hint(s) in C.DIRS,"solver gives legal next step")
		for direction in C.SOLUTIONS[stage]:
			var result:=C.apply(s,"move",{"direction":direction})
			check(result.ok,"authored move legal")
			if not result.ok: quit(1); return
			s=result.state
			check(C.valid(JSON.parse_string(JSON.stringify(s))),"all intermediate saves roundtrip")
		check(C.solved(s),"stage actually solved")
		check(C.hint(s)=="next","solved hint suggests next")
		s=C.apply(s,"next",{}).state
	check(s.won and C.valid(s),"only three solved levels grant victory")
	forged=s.duplicate(true); forged.completed[0]=[]
	check(not C.valid(forged),"cannot forge completed previous stage")
	check(not C.apply(s,"next",{}).ok,"repeat win rejected")
	check(Rules.safe(0,3) and Rules.safe(2,2) and not Rules.safe(1,2),"police riot rule and zero-police exception")
	var ferry:=Rules.fresh("milo_ferry")
	check(Rules.crossing_failure(ferry,1,0).message.contains("囚犯发动了暴动"),"riot reason names police and prisoners")
	check(Rules.crossing_failure(ferry,0,2).is_empty(),"two prisoners can depart safely")
	print("CRATE RULES: %d checks, %d failures" % [count,failures]); quit(1 if failures else 0)
