extends "res://tests/verify_workbench_scene.gd"
const State=preload("res://scripts/workbench_liquid_state.gd")
const Appearance=preload("res://scripts/workbench_liquid_appearance.gd")
const Liquid=preload("res://scripts/workbench_liquid.gd")
var serial:=0

func op(kind: String,payload: Dictionary={}) -> bool:
	serial+=1
	var ok: bool=WorkbenchSession.command("liquid-test-%d" % serial,str(WorkbenchSession.state.session.get("id","")),kind,payload)
	check(ok,kind+": "+WorkbenchSession.last_error)
	return ok

func equal_amounts(a: Dictionary,b: Dictionary) -> bool:
	var keys:=a.duplicate()
	keys.merge(b)
	for id in keys:
		if absf(float(a.get(id,0))-float(b.get(id,0)))>.00001: return false
	return true

func run() -> void:
	var profiles:=Appearance.profiles()
	check(profiles.size()==16,"every catalog liquid has an appearance profile")
	for p in profiles.values(): check(p.version!="missing" and p.rgb.size()==3,"configured RGB profile")
	var alias:=Appearance.sample({"lime":30},profiles)
	check(alias==Appearance.sample({"sku_lime_juice":30},profiles),"SKU and legacy alias use identical appearance")
	var diluted:=Appearance.sample({"lime":30,"soda":90},profiles)
	check(is_equal_approx(diluted.strength,alias.strength*.25) and diluted.color.a<alias.color.a,"clear mixer reduces concentration and opacity")
	var v: Dictionary={"contents":{}}
	State.add(v,{"gin":40})
	State.add(v,{"lime":60})
	State.add(v,{"lime":20})
	check(v.layers.size()==2 and v.layers[0].contents.gin==40 and v.layers[1].contents.lime==80,"add order, merge same neighboring liquid")
	var initial: Dictionary=v.contents.duplicate(true)
	State.mix(v,.5,"stir",0)
	check(v.layers[0].contents=={"gin":40},"zero control produces no mixing")
	State.mix(v,.5,"stir",1)
	check(v.layers.size()==2 and v.layers[0].contents.lime>0 and State.valid(v),"partial mixing exchanges liquid but keeps layers")
	check(equal_amounts(initial,v.contents),"mixing preserves each ingredient")
	for i in range(30): State.mix(v,.5,"stir",1)
	check(v.layers.size()==1 and equal_amounts(initial,v.contents),"long mixing reaches one conserved homogeneous layer")
	State.add(v,{"soda":30})
	check(v.layers.size()==2 and equal_amounts(v.layers[0].contents,initial),"new liquid adds one layer without unmixing previous blend")
	var stream:=State.take(v,40)
	check(stream.size()==2 and stream[0].contents=={"soda":30} and is_equal_approx(stream[1].contents.gin,10.0/3),"top layer leaves first, mixed layer retains ratio")
	check(State.valid(v) and is_equal_approx(State.volume(v.contents),110),"partial remainder is consistent")
	var legacy: Dictionary={"contents":{"gin":20,"lime":10}}
	State.ensure(legacy)
	check(legacy.layers.size()==1,"legacy totals migrate as one mixed layer")
	var corrupt:=legacy.duplicate(true)
	corrupt.layers[0].contents.gin=21
	check(not State.valid(corrupt),"reject layer vs aggregate mismatch")
	var frozen:=profiles.duplicate(true)
	var old:=Appearance.sample({"lime":30},frozen)
	profiles.sku_lime_juice.rgb=[255,0,0]
	check(Appearance.sample({"lime":30},frozen)==old,"appearance snapshot survives live profile edits")
	var forward: Dictionary={"contents":{}}
	var reverse: Dictionary={"contents":{}}
	State.add(forward,{"lime":20}); State.add(forward,{"gin":40})
	State.add(reverse,{"gin":40}); State.add(reverse,{"lime":20})
	for i in range(30):
		State.mix(forward,.5,"shake",1)
		State.mix(reverse,.5,"shake",1)
	check(Liquid.color(forward.contents)==Liquid.color(reverse.contents) and forward.layers==reverse.layers,"fully mixed appearance independent of pour order")
	var stable: Dictionary=forward.duplicate(true)
	Liquid.display_layers(State.layers(legacy),forward.layers,.5)
	check(forward==stable,"visual interpolation never changes actual amounts")
	var rng:=RandomNumberGenerator.new()
	rng.seed=73021
	var pair: Array=[{"contents":{}},{"contents":{}}]
	var ledger: Dictionary={}
	var conserved:=true
	for i in range(300):
		var source: Dictionary=pair[i%2]
		var target: Dictionary=pair[(i+1)%2]
		if i%3==0:
			var material: String=["gin","lime","soda"][rng.randi_range(0,2)]
			var ml:=rng.randf_range(.001,30)
			State.add(source,{material:ml})
			ledger[material]=float(ledger.get(material,0))+ml
		elif i%3==1: State.mix(source,.5,"shake",rng.randf())
		else:
			for part in State.take(source,rng.randf_range(0,100)): State.add(target,part.contents)
		conserved=conserved and State.valid(source) and State.valid(target) and equal_amounts(State.aggregate(pair),ledger)
	check(conserved,"300 seeded additions, mixes and reciprocal partial pours conserve every ingredient")
	var lineage_actions: Array=[
		{"kind":"withdraw","liquid_layered":true,"payload":{"vessel":"mixing","material":"gin","ml":90}},
		{"kind":"stir","liquid_model":State.config(),"payload":{"vessel":"mixing","seconds":8,"control":1}},
		{"kind":"withdraw","liquid_layered":true,"payload":{"vessel":"mixing","material":"soda","ml":90}},
		{"kind":"filter","pour":{"ml":60,"layers":[],"fraction":1.0/3},"payload":{"source":"mixing","vessel":"glass"}}
	]
	var layered_trace:=WorkbenchSession.Evaluation.replay(lineage_actions,{"mix":"stir"},WorkbenchSession.MATERIALS)
	check(is_equal_approx(layered_trace.carbonated,60) and layered_trace.mixed==0,"evaluation follows unmixed upper soda, not average of earlier stirred gin")
	var invalid_profiles:=Appearance.profiles()
	invalid_profiles.sku_lime_juice.rgb=[-1,2,3]
	check(not Appearance.valid_snapshot(invalid_profiles) and not State.valid_model({"version":"unknown"}),"invalid appearance and model versions rejected")
	# Real command/warehouse/recovery path, isolated by the base fixture.
	WorkbenchSession.reset_game()
	op("start")
	op("cup",{"cup":"coupe"})
	op("withdraw",{"vessel":"mixing","material":"gin","ml":90})
	op("withdraw",{"vessel":"mixing","material":"lime","ml":90})
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	op("filter",{"source":"mixing","vessel":"glass"})
	var s: Dictionary=WorkbenchSession.state.session
	check(equal_amounts(s.vessels.glass.contents,{"gin":30,"lime":90}) and equal_amounts(s.vessels.mixing.contents,{"gin":60}),"capacity fill uses actual upper layers and retains remainder")
	check(s.vessels.glass.layers.size()==2 and equal_amounts(s.vessels.glass.layers[0].contents,{"lime":90}),"receiving vessel respects incoming order")
	check(WorkbenchSession.state.stock==stock,"transfer does not consume stock twice")
	var before: Dictionary=WorkbenchSession.snapshot()
	check(WorkbenchSession.command("liquid-test-%d" % serial,s.id,"filter",{"source":"mixing","vessel":"glass"}),"duplicate command succeeds idempotently")
	check(WorkbenchSession.snapshot()==before,"retry neither transfers nor bills again")
	check(WorkbenchSession.load_state(),"restore session")
	check(WorkbenchSession.state.session==s,"reload preserves exact layers and profiles")
	var trace:=WorkbenchSession.Evaluation.replay(s.actions,{},WorkbenchSession.MATERIALS)
	check(is_equal_approx(trace.traced,120),"evaluation traces actual partial pour volume")
	op("spoon",{"target":"glass"})
	for i in range(16): op("stir",{"vessel":"glass","seconds":.5,"control":1})
	check(WorkbenchSession.state.session.vessels.glass.layers.size()==1,"normal stir commands mix rendered cup")
	op("finish")
	s=WorkbenchSession.state.session
	check(s.result.liquid_profiles==s.liquid_profiles and s.result.contents.layers==s.vessels.glass.layers,"result freezes actual appearance and layers")
	check(WorkbenchSession._valid_session(s),"finished session validates")
	op("start")
	op("withdraw",{"vessel":"jigger","material":"gin","ml":10})
	op("empty",{"vessel":"jigger"})
	s=WorkbenchSession.state.session
	check(s.vessels.jigger.layers.is_empty() and s.waste.gin==10,"discard clears layers and records waste")
	print("LIQUID: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
