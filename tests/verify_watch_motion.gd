extends SceneTree
const Motion=preload("res://scripts/watch_repair_motion.gd")
const Watch=preload("res://scripts/watch_repair_rules.gd")
var checks:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize() -> void:
	var cfg:=Watch.level(2)
	var state:={"model":2,"stage":2,"pieces":[]}
	for cell in cfg.cells: state.pieces.append({"cell":cell,"turns":0})
	var motion:=Motion.new(); var max_speed:=0.0; var bounded:=true
	for frame in range(60*600):
		var before:=motion.target_angle(1); motion.advance(1.0/60,state)
		max_speed=maxf(max_speed,absf(motion.target_angle(1)-before)*60)
		bounded=bounded and absf(motion.target_angle(1))<=Motion.BALANCE_AMPLITUDE+.00001
	check(bounded,"ten minutes never expands balance swing")
	check(max_speed<=Motion.BALANCE_SPEED*Motion.BALANCE_AMPLITUDE+.001,"balance speed remains bounded over long play")
	var phase:=motion.target_angle(0); motion.advance(.01,state)
	check(absf(angle_difference(phase,motion.target_angle(0))-.02)<.000001,"seconds gear keeps constant angular speed after long play")
	var disconnected:=state.duplicate(true); disconnected.pieces[0].turns=1
	var frozen:=motion.gears.duplicate(); var frozen_targets:=motion.targets.duplicate()
	for i in range(120): motion.advance(1.0/30,disconnected)
	check(motion.gears==frozen and motion.targets==frozen_targets,"disconnected parts freeze without resetting orientation")
	phase=motion.target_angle(0); motion.advance(.01,state)
	check(absf(angle_difference(phase,motion.target_angle(0))-.02)<.000001,"reconnection resumes without accumulated-time jump")
	var slow:=Motion.new(); var fast:=Motion.new()
	for i in range(300): slow.advance(1.0/30,state)
	for i in range(1440): fast.advance(1.0/144,state)
	check(absf(angle_difference(slow.target_angle(0),fast.target_angle(0)))<.00001 and absf(slow.target_angle(1)-fast.target_angle(1))<.00001,"same speed at 30 and 144 fps")
	phase=motion.target_angle(0); motion.advance(90,state)
	check(absf(angle_difference(phase,motion.target_angle(0))-.2)<.00001,"long frame cannot fast-forward gear")
	motion.reset(); check(motion.gears.is_empty() and motion.targets.is_empty(),"new run resets visual phases")
	print("WATCH MOTION: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
