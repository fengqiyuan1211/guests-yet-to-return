extends Node
var failures: Array=[]
var checks:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func _ready() -> void:
	var outcomes: Array=[]
	for fps in [30,60,144]:
		var table=load("res://scripts/workbench_table.gd").new()
		table.data={"spoon_vessel":"glass"}
		table.selected="glass"; table.technique="stir"; table.dragging=true
		var dt: float=1.0/fps
		for i in range(fps*2):
			table.clock+=dt; table.stir_pointer_time=table.clock; table.pointer_speed=400
			table._advance_stir(dt)
		outcomes.append([table.stir_angle,table.stir_energy])
		check(table.stir_rate<=TAU*1.25,"speed ceiling %d"%fps)
		var earned: float=table.accumulated
		table.dragging=false
		var previous_energy: float=table.stir_energy
		for i in range(fps*2):
			table.clock+=dt; table._advance_stir(dt)
			check(absf(table.stir_energy-previous_energy)<.15,"no amplitude snap %d"%fps)
			previous_energy=table.stir_energy
		check(table.accumulated==earned,"coasting grants no stirring credit %d"%fps)
		check(table.stir_energy<.001 and table.stir_rate<.001,"settles fully %d"%fps)
		table.free()
	for result in outcomes:
		check(absf(angle_difference(result[0],outcomes[1][0]))<.03,"frame rate independent phase")
		check(absf(result[1]-outcomes[1][1])<.01,"frame rate independent amplitude")
	print("SPOON SMOOTHING: %d checks, %d failures"%[checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
