extends RefCounted
## Versioned, deterministic component connectivity; no rendering or inventory writes.
const DIRS=[Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]
const LEVELS=[
	{"name":"让它先动起来","width":3,"source":3,"targets":[5],"cells":[3,4,5],"masks":[10,10,10],"fixed":[0]},
	{"name":"给旧零件换个位置","width":3,"source":3,"targets":[8],"cells":[3,0,1,2,5,4,7,8],"masks":[9,6,10,12,9,6,3,10],"fixed":[2]},
	{"name":"把时间接回来","width":4,"source":4,"targets":[7,15],"cells":[4,5,1,2,3,7,9,10,14,15],"masks":[10,13,6,10,12,3,3,12,3,10],"fixed":[0]}
]
static func level(stage: int) -> Dictionary: return LEVELS[clampi(stage,0,2)]
static func initial(stage: int) -> Array:
	var cfg:=level(stage); var pieces: Array=[]
	for i in range(cfg.cells.size()):
		pieces.append({"cell":cfg.cells[i] if i in cfg.fixed or (stage==0) else -1,"turns":0 if i in cfg.fixed else (1 if stage==0 else i%3+1)})
	return pieces
static func fresh() -> Dictionary:
	return {"model":2,"stage":0,"pieces":initial(0),"history":[],"completed":[],"hints":0,"wind":0,"won":false}
static func integer(v: Variant, low: int, high: int) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v==floor(v) and v>=low and v<=high
static func mask(base: int, turns: int) -> int:
	for i in range(turns): base=((base<<1)&15)|((base>>3)&1)
	return base
static func occupied(pieces: Array, cell: int) -> int:
	for i in range(pieces.size()):
		if int(pieces[i].cell)==cell: return i
	return -1
static func connected(stage: int, pieces: Array) -> Array:
	var cfg:=level(stage); var width: int=cfg.width
	var start:=occupied(pieces,cfg.source); var reached: Array=[]
	if start<0 or (mask(cfg.masks[start],int(pieces[start].turns))&8)==0: return reached
	var pending: Array=[start]
	while not pending.is_empty():
		var id: int=pending.pop_front()
		if id in reached: continue
		reached.append(id)
		var cell: int=int(pieces[id].cell); var pos:=Vector2i(cell%width,cell/width)
		var ports:=mask(cfg.masks[id],int(pieces[id].turns))
		for d in range(4):
			if not ports&(1<<d): continue
			var neighbor: Vector2i=pos+DIRS[d]
			if neighbor.x<0 or neighbor.y<0 or neighbor.x>=width or neighbor.y>=width: continue
			var other:=occupied(pieces,neighbor.y*width+neighbor.x)
			if other>=0 and mask(cfg.masks[other],int(pieces[other].turns))&(1<<((d+2)%4)): pending.append(other)
	return reached
static func solved(stage: int, pieces: Array) -> bool:
	var cfg:=level(stage); var reached:=connected(stage,pieces)
	for target in cfg.targets:
		var id:=occupied(pieces,target)
		if id<0 or id not in reached or not mask(cfg.masks[id],int(pieces[id].turns))&2: return false
	return true
static func valid_pieces(stage: int, pieces: Variant) -> bool:
	var cfg:=level(stage)
	if not pieces is Array or pieces.size()!=cfg.cells.size(): return false
	var seen: Dictionary={}
	for i in range(pieces.size()):
		var p: Variant=pieces[i]
		if not p is Dictionary or not integer(p.get("cell"),-1,cfg.width*cfg.width-1) or not integer(p.get("turns"),0,3): return false
		if i in cfg.fixed and (p.cell!=cfg.cells[i] or p.turns!=0): return false
		if p.cell>=0:
			if seen.has(int(p.cell)): return false
			seen[int(p.cell)]=true
	return true
static func valid(s: Dictionary) -> bool:
	if s.get("model")!=2 or not integer(s.get("stage"),0,2) or not s.get("won") is bool: return false
	if not valid_pieces(int(s.stage),s.get("pieces")) or not s.get("history") is Array or s.history.size()>100: return false
	if not s.get("completed") is Array or s.completed.size()!=int(s.stage) or not integer(s.get("hints"),0,100000) or not integer(s.get("wind"),0,4): return false
	for i in range(s.completed.size()):
		if not valid_pieces(i,s.completed[i]) or not solved(i,s.completed[i]): return false
	for past in s.history:
		if not valid_pieces(int(s.stage),past): return false
	if s.wind>0 and (s.stage!=2 or not solved(2,s.pieces)): return false
	return s.won==(s.wind==4)
static func fail(message: String) -> Dictionary: return {"ok":false,"message":message}
static func apply(s: Dictionary, action: String, data: Dictionary) -> Dictionary:
	var n:=s.duplicate(true); var stage:=int(s.stage); var cfg:=level(stage)
	if s.won: return fail("怀表已经恢复走时。")
	if action=="hint": n.hints+=1
	elif action=="undo":
		if n.history.is_empty(): return fail("已经是这一局的起点。")
		n.pieces=n.history.pop_back(); n.wind=0
	elif action=="reset": n.pieces=initial(stage); n.history=[]; n.wind=0
	elif action=="next":
		if not solved(stage,n.pieces): return fail("先把发条接到右侧目标。")
		if stage>=2: return fail("连接完成，按空格或拖动表冠上弦。")
		n.completed.append(n.pieces.duplicate(true)); n.stage+=1; n.pieces=initial(int(n.stage)); n.history=[]
	elif action=="wind":
		if stage!=2 or not solved(stage,n.pieces): return fail("先接通秒针与摆轮，再上弦。")
		n.wind=mini(4,int(n.wind)+1); n.won=n.wind==4
	elif action in ["move","rotate"]:
		if not integer(data.get("piece"),0,n.pieces.size()-1): return fail("没有选中的组件。")
		var id:=int(data.piece)
		if id in cfg.fixed: return fail("带铆钉的组件已经固定，请调整其余零件。")
		var before: Array=n.pieces.duplicate(true)
		if action=="rotate": n.pieces[id].turns=(int(n.pieces[id].turns)+1)%4
		else:
			if not integer(data.get("cell"),-1,cfg.width*cfg.width-1): return fail("请放进机芯空槽，或放回右侧零件盘。")
			var cell:=int(data.cell)
			if cell==int(n.pieces[id].cell): return fail("组件已在这个位置。")
			if cell>=0 and occupied(n.pieces,cell)>=0: return fail("这个槽已有组件，先把它移到零件盘。")
			n.pieces[id].cell=cell
		n.history.append(before)
		if n.history.size()>100: n.history.pop_front()
		n.wind=0
	else: return fail("无效的机芯操作。")
	return {"ok":true,"state":n}
static func hint(s: Dictionary) -> Dictionary:
	var cfg:=level(int(s.stage))
	# Authored solution, with occupied destinations moved aside first.
	for i in range(s.pieces.size()):
		if i in cfg.fixed: continue
		if s.pieces[i].cell!=cfg.cells[i]:
			var other:=occupied(s.pieces,cfg.cells[i])
			if other>=0: return {"action":"move","piece":other,"cell":-1}
			return {"action":"move","piece":i,"cell":cfg.cells[i]}
		if mask(cfg.masks[i],int(s.pieces[i].turns))!=cfg.masks[i]: return {"action":"rotate","piece":i}
	return {"action":"next" if s.stage<2 else "wind"}
