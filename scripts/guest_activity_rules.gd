extends RefCounted
## Pure reducers. Animation never changes counts or grants rewards.
const IDS := ["milo_ferry", "ada_watch_memory", "hank_lantern"]
const INVITATION_IDS := ["milo_ferry", "ada_watch_memory", "hank_lantern", "yellow_ski"]
const Crates=preload("res://scripts/hank_crate_rules.gd")
const Watch=preload("res://scripts/watch_repair_rules.gd")
const SEQUENCES := [[2,1,2], [0,2,3,1], [1,0,3,2,1]]
const LANES := [1,0,2,1,2,0]

static func fresh(id: String) -> Dictionary:
	match id:
		"milo_ferry": return {"left_p":3,"left_d":3,"side":0,"moves":[],"undos":0,"hints":0,"won":false}
		"ada_watch_memory": return Watch.fresh()
		"hank_lantern": return Crates.fresh()
	return {}

static func whole(v: Variant, maximum: int) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v>=0 and v<=maximum and v==floor(v)

static func same_indices(value: Variant, expected: Array) -> bool:
	# JSON numbers reload as floats. Validate whole values, not Variant array types.
	if not value is Array or value.size()!=expected.size(): return false
	for i in range(expected.size()):
		if not whole(value[i],100000) or int(value[i])!=int(expected[i]): return false
	return true

static func safe(p: int, d: int) -> bool:
	return p==0 or p>=d

static func crossing(p: int, d: int, side: int, load_p: int, load_d: int) -> Array:
	if load_p<0 or load_d<0 or load_p+load_d<1 or load_p+load_d>2: return []
	var np:=p+load_p*(-1 if side==0 else 1)
	var nd:=d+load_d*(-1 if side==0 else 1)
	if np<0 or np>3 or nd<0 or nd>3 or not safe(np,nd) or not safe(3-np,3-nd): return []
	return [np,nd,1-side]

static func crossing_failure(s: Dictionary, p: int, d: int) -> Dictionary:
	# A physically possible departure may fail the puzzle's bank safety rule.
	# Return a presentation outcome; never place an invalid bank into the save.
	var side:=int(s.side)
	var available_p:=int(s.left_p) if side==0 else 3-int(s.left_p)
	var available_d:=int(s.left_d) if side==0 else 3-int(s.left_d)
	if p<0 or d<0 or p+d<1 or p+d>2 or p>available_p or d>available_d: return {}
	var np:=int(s.left_p)+p*(-1 if side==0 else 1)
	var nd:=int(s.left_d)+d*(-1 if side==0 else 1)
	for bank in [0,1]:
		var bp:=np if bank==0 else 3-np
		var bd:=nd if bank==0 else 3-nd
		if not safe(bp,bd):
			return {"bank":bank,"p":bp,"d":bd,"message":"这趟安排让%s留下 %d 名警察、%d 名囚犯，警察少于囚犯，囚犯发动了暴动。" % ["此岸" if bank==0 else "对岸",bp,bd]}
	return {}

static func hint(s: Dictionary) -> Array:
	var start: Array=[int(s.left_p),int(s.left_d),int(s.side)]
	var queue: Array=[{"state":start,"path":[]}]
	var seen: Dictionary={str(start):true}
	while not queue.is_empty():
		var row: Dictionary=queue.pop_front()
		if row.state[0]==0 and row.state[1]==0: return row.path[0] if not row.path.is_empty() else []
		for load_pair in [[0,1],[0,2],[1,0],[1,1],[2,0]]:
			var next:=crossing(row.state[0],row.state[1],row.state[2],load_pair[0],load_pair[1])
			if next.is_empty() or seen.has(str(next)): continue
			seen[str(next)]=true
			var path: Array=row.path.duplicate(true)
			path.append(load_pair)
			queue.append({"state":next,"path":path})
	return []

static func apply(id: String, s: Dictionary, action: String, data: Dictionary={}) -> Dictionary:
	if id=="ada_watch_memory" and s.get("model")==2: return Watch.apply(s,action,data)
	if id=="hank_lantern" and s.get("model")==2: return Crates.apply(s,action,data)
	var n:=s.duplicate(true)
	if s.get("won",false): return {"ok":false,"message":"本局已完成，可以返回手帐或再玩一局。"}
	match id:
		"milo_ferry":
			if action=="cross":
				if not whole(data.get("p"),2) or not whole(data.get("d"),2): return {"ok":false,"message":"船上只能坐一至两个人。"}
				var next:=crossing(int(s.left_p),int(s.left_d),int(s.side),int(data.p),int(data.d))
				if next.is_empty(): return {"ok":false,"message":"无法开船：每趟 1–2 人；有警察的一岸，囚犯人数不能更多。"}
				n.moves.append([int(data.p),int(data.d)])
				n.left_p=next[0]; n.left_d=next[1]; n.side=next[2]
			elif action=="undo":
				if n.moves.is_empty(): return {"ok":false,"message":"已经回到起点。"}
				n.moves.pop_back(); n.undos+=1
				var pos: Array=[3,3,0]
				for move in n.moves: pos=crossing(pos[0],pos[1],pos[2],move[0],move[1])
				n.left_p=pos[0]; n.left_d=pos[1]; n.side=pos[2]
			elif action=="hint": n.hints+=1
			else: return {"ok":false,"message":"无效的渡河操作。"}
			n.won=n.left_p==0 and n.left_d==0
		"ada_watch_memory":
			if action=="replay": n.replays+=1; n.input=[]
			elif action=="assist": n.assist=true
			elif action=="press" and whole(data.get("key"),3):
				var seq: Array=SEQUENCES[int(n.round)]
				if int(data.key)!=seq[n.input.size()]: n.mistakes+=1; n.input=[]
				else:
					n.input.append(int(data.key))
					if n.input.size()==seq.size():
						n.completed.append(n.input.duplicate()); n.input=[]; n.round+=1
						n.won=n.round==3
			else: return {"ok":false,"message":"无效的听音操作。"}
		"hank_lantern":
			if action=="assist": n.assist=true
			elif action=="lane" and whole(data.get("lane"),2): n.lane=int(data.lane)
			elif action=="tick":
				var dt: Variant=data.get("delta")
				if not (dt is int or dt is float) or not is_finite(float(dt)) or dt<=0 or dt>.1: return {"ok":false,"message":"无效的时间步。"}
				var step:=float(dt)*(.7 if n.assist else 1.0)
				if float(n.get("walking",0.0))>0:
					n.walking=float(n.walking)+step
					if n.walking>=.55:
						n.rescued.append(int(n.index)); n.index+=1; n.elapsed=0.0; n.lit=0.0; n.walking=0.0
						n.won=n.index==6
					return {"ok":true,"state":n}
				n.elapsed+=step
				if n.elapsed>=1.5 and n.lane==LANES[int(n.index)]: n.lit+=step
				elif n.elapsed>=1.5: n.lit=0.0
				if n.lit>=.6:
					n.walking=.001
				elif n.elapsed>=2.9:
					n.misses+=1; n.elapsed=0.0; n.lit=0.0
			else: return {"ok":false,"message":"无效的灯位操作。"}
		_: return {"ok":false,"message":"活动不存在。"}
	return {"ok":true,"state":n}

static func valid(id: String, s: Variant) -> bool:
	if not s is Dictionary or not s.get("won") is bool: return false
	if id=="ada_watch_memory" and s.get("model")==2: return Watch.valid(s)
	if id=="hank_lantern" and s.get("model")==2: return Crates.valid(s)
	match id:
		"milo_ferry":
			if not s.get("moves") is Array or s.moves.size()>2000 or not whole(s.get("undos"),100000) or not whole(s.get("hints"),100000): return false
			var pos: Array=[3,3,0]
			for move in s.moves:
				if not move is Array or move.size()!=2 or not whole(move[0],2) or not whole(move[1],2): return false
				pos=crossing(pos[0],pos[1],pos[2],move[0],move[1])
				if pos.is_empty(): return false
			return s.get("left_p")==pos[0] and s.get("left_d")==pos[1] and s.get("side")==pos[2] and s.won==(pos[0]==0 and pos[1]==0)
		"ada_watch_memory":
			if not whole(s.get("round"),3) or not s.get("input") is Array or not s.get("completed") is Array or not s.get("assist") is bool: return false
			if not whole(s.get("mistakes"),100000) or not whole(s.get("replays"),100000) or s.completed.size()!=int(s.round): return false
			for i in range(s.completed.size()):
				if not same_indices(s.completed[i],SEQUENCES[i]): return false
			if s.won: return s.round==3 and s.input.is_empty()
			return s.round<3 and s.input.size()<SEQUENCES[int(s.round)].size() and same_indices(s.input,SEQUENCES[int(s.round)].slice(0,s.input.size()))
		"hank_lantern":
			if not whole(s.get("index"),6) or not whole(s.get("lane"),2) or not whole(s.get("misses"),100000) or not s.get("assist") is bool or not s.get("rescued") is Array: return false
			var walking: Variant=s.get("walking",0.0)
			if not (walking is int or walking is float) or not is_finite(float(walking)) or walking<0 or walking>.65: return false
			for key in ["elapsed","lit"]:
				var v: Variant=s.get(key)
				if not (v is int or v is float) or not is_finite(float(v)) or v<0 or v>3: return false
			return same_indices(s.rescued,range(int(s.index))) and s.won==(s.index==6)
	return false

static func fresh_book() -> Dictionary:
	return {"version":1,"unlocks":{},"runs":{},"rewards":{}}

static func valid_book(book: Variant) -> bool:
	if not book is Dictionary or book.get("version")!=1: return false
	for key in ["unlocks","runs","rewards"]:
		if not book.get(key) is Dictionary: return false
	for id in book.unlocks:
		if id not in INVITATION_IDS or not book.unlocks[id] is Dictionary or not book.unlocks[id].get("source") is String: return false
	for id in book.runs:
		var run: Variant=book.runs[id]
		if id not in IDS or not run is Dictionary or not run.get("id") is String or run.get("activity_id")!=id or run.get("version")!=1 or not valid(id,run.get("state")): return false
	for id in book.rewards:
		var reward: Variant=book.rewards[id]
		if id not in IDS or not book.unlocks.has(id) or not reward is Dictionary or reward.get("key")!="first-clear:"+id or not reward.get("recipe_id") is String or not whole(reward.get("inspiration"),100): return false
	return true
