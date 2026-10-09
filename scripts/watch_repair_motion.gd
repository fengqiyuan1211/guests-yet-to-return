extends RefCounted
## Presentation only: bounded, per-mechanism phases. Disconnecting freezes the
## current orientation; reconnecting never jumps to the scene's elapsed time.
const Watch=preload("res://scripts/watch_repair_rules.gd")
const GEAR_SPEED:=0.8
const SECOND_SPEED:=2.0
const BALANCE_SPEED:=7.0
const BALANCE_AMPLITUDE:=0.55
var stage:=-1
var gears: Dictionary={}
var targets: Dictionary={}
func reset() -> void:
	stage=-1; gears.clear(); targets.clear()
func advance(delta: float, state: Dictionary) -> void:
	if state.get("model")!=2 or not is_finite(delta) or delta<=0: return
	if stage!=int(state.stage):
		reset(); stage=int(state.stage)
	# Discard long rendering stalls rather than visibly fast-forwarding machinery.
	var dt:=minf(delta,.1)
	var cfg:=Watch.level(stage); var reached:=Watch.connected(stage,state.pieces)
	for id in reached:
		gears[id]=fposmod(float(gears.get(id,0.0))+dt*GEAR_SPEED*(1 if int(id)%2==0 else -1),TAU)
	for i in range(cfg.targets.size()):
		var id:=Watch.occupied(state.pieces,cfg.targets[i])
		if id<0 or id not in reached or not Watch.mask(cfg.masks[id],int(state.pieces[id].turns))&2: continue
		targets[i]=fposmod(float(targets.get(i,0.0))+dt*(SECOND_SPEED if i==0 else BALANCE_SPEED),TAU)
func gear_angle(id: int) -> float: return float(gears.get(id,0.0))
func target_angle(id: int) -> float:
	var phase:=float(targets.get(id,0.0))
	return phase if id==0 else BALANCE_AMPLITUDE*sin(phase)
