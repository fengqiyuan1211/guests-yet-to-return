extends SceneTree
const Watch=preload("res://scripts/watch_repair_rules.gd")
const Rules=preload("res://scripts/guest_activity_rules.gd")
var checks:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize() -> void:
	var state:=Watch.fresh()
	check(Watch.valid(state),"initial state valid")
	check(not Watch.apply(state,"wind",{}).ok,"cannot wind disconnected clock")
	check(not Watch.apply(state,"rotate",{"piece":0}).ok,"fixed source cannot rotate")
	check(not Watch.apply(state,"move",{"piece":1,"cell":3}).ok,"occupied cells reject replacement")
	check(not Watch.apply(state,"move",{"piece":1,"cell":100}).ok,"outside grid rejected")
	check(not Watch.apply(state,"move",{"piece":1,"cell":1.5}).ok,"fractional cell rejected")
	var rotated:=Watch.apply(state,"rotate",{"piece":1})
	check(rotated.ok and state.pieces[1].turns==1,"reducer never mutates caller")
	var undo:=Watch.apply(rotated.state,"undo",{})
	check(undo.ok and undo.state.pieces==state.pieces,"undo restores exact assembly")
	var proof:=0
	for turn in range(200):
		check(Watch.valid(state),"valid intermediate state")
		check(Watch.valid(JSON.parse_string(JSON.stringify(state))),"JSON restore each action")
		if state.won: break
		var next:=Watch.hint(state)
		if next.action in ["next","wind"]: check(Watch.solved(int(state.stage),state.pieces),"hint reaches genuinely connected targets"); proof+=1
		var result:=Watch.apply(state,next.action,next)
		check(result.ok,"authored solution step accepted")
		if not result.ok: break
		state=result.state
	check(state.won and proof==6,"three authored stages solvable, four winding steps")
	check(not Watch.apply(state,"wind",{}).ok,"repeat win action rejected")
	var corrupt:=state.duplicate(true); corrupt.pieces[1].cell=corrupt.pieces[0].cell
	check(not Watch.valid(corrupt),"overlapping save rejected")
	corrupt=state.duplicate(true); corrupt.completed[0][1].turns=1
	check(not Watch.valid(corrupt),"forged disconnected completed stage rejected")
	var old:={"round":1,"input":[],"completed":[[2,1,2]],"mistakes":0,"replays":0,"assist":false,"won":false}
	check(Rules.valid("ada_watch_memory",old),"old mid-run readable before migration")
	old.round=3; old.completed=Rules.SEQUENCES.duplicate(true); old.won=true
	check(Rules.valid("ada_watch_memory",JSON.parse_string(JSON.stringify(old))),"old completed unclaimed run remains claimable")
	var lantern:={"lane":1,"index":0,"elapsed":0.0,"lit":0.0,"walking":0.0,"rescued":[],"assist":false,"won":false}
	for i in range(43): lantern=Rules.apply("hank_lantern",lantern,"tick",{"delta":.05}).state
	check(lantern.index==0 and lantern.get("walking",0)>0,"traveler does not count before walking in")
	lantern=Rules.apply("hank_lantern",lantern,"lane",{"lane":0}).state
	for i in range(12): lantern=Rules.apply("hank_lantern",lantern,"tick",{"delta":.05}).state
	check(lantern.index==1 and lantern.rescued==[0],"walking completes once even after lamp leaves")
	print("WATCH REPAIR RULES: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
