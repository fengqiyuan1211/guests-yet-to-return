extends RefCounted
## Discrete Sokoban state. Replayable moves prove completion; no art or economy.
const LEGACY_LEVELS=[
	["######","#    #","# .$ #","# @  #","######"],
	["#######","# . . #","# $ $ #","#  #  #","#  @  #","#     #","#######"],
	["########","#  . . #","#  #   #","# $$ $ #","#  .#  #","#  @   #","########"]
]
const LEGACY_SOLUTIONS=["RRUL","LUUDDRRUU","ULUUDDDRRRUUUDLLDLULUURDDLDR"]
const LEGACY_NAMES=["灯不是自己亮的","账上那两笔","先给别人留条路"]
const LEVELS=[["#######", "#  .  #", "# $ $@#", "# # # #", "#     #", "#  .  #", "#######"], ["########", "#  ..  #", "# $ #  #", "#   @  #", "# #$$# #", "# .    #", "########"], ["########", "# $.@  #", "# #$$# #", "#      #", "#  #   #", "#.   . #", "#      #", "########"], ["#########", "# .   . #", "#   #   #", "# #   # #", "# $     #", "# $$#   #", "# +$  . #", "#########"], ["#########", "# ...   #", "#   #   #", "# #   # #", "#       #", "# $ #$$ #", "#@$ .   #", "#########"]]
const SOLUTIONS=["LULDDDLLUURLDDRRUU", "DURRDDLLLUULULURRLDDRU", "DDDRDLLRUUUULDRDDDDLLLUUURRURDDRDDLLURLLUULUUR", "RRRLLLLUURDURRURURRDDDLLDLLUDRRUUDDLLUURRUDLLURRUDDLLLLUUURRRRDDLLUDRRUULL", "RRUURRRRDDLLUURRDLULLLLLDRURRRUDRDDLURURUUULLLLDDDLDDRULULUURRDRRURRDDDLLULULULLDDDRRURRUDLLUDRRRRUUULLLLRRRDRDDLLUURULDDLLU"]
const NAMES=["给灯留条路","账房的窄门","先放下，再出发","回头的余地","把名字也带上"]
const LESSONS=["先绕到箱后，再决定从哪侧推。","门口的空位，是搬运时的转身处。","有些箱子要先挪远，才能送到近处。","备妥的箱子，也可能需要暂时让路。","先看整条路，再看眼前这一只箱。"]
const LINES=["玛莎擦亮灯，说别急。看不清脚下，再亮的灯也白费。","齐恩在账本上留了一行空白。货棚里，也得给人留个转身的地方。","那个车夫说：先放下，不等于不要了。有时候要退一步，才找得到那条路。","那晚谁都绕过远路。回头去接人，就不能把来路堵死。","灯、油、绳，还有替别人多走的那几步。这次，清单上给每个帮忙的人都留了位置。"]
const TARGET_PUSHES=[6,9,12,16,20]
static var layout_cache: Dictionary={}
static func edition(s: Dictionary) -> int: return int(s.get("layout_version",1))
static func stage_count(s: Dictionary) -> int: return LEVELS.size() if edition(s)==2 else LEGACY_LEVELS.size()
static func stage_name(s: Dictionary) -> String: return str((NAMES if edition(s)==2 else LEGACY_NAMES)[int(s.stage)])
static func config_for(s: Dictionary) -> Dictionary: return layout(int(s.stage),edition(s))

const DIRS={"U":Vector2i(0,-1),"D":Vector2i(0,1),"L":Vector2i(-1,0),"R":Vector2i(1,0)}
static func layout(stage: int, version:=2) -> Dictionary:
	var cache_key: String=str(version)+":"+str(stage)
	if layout_cache.has(cache_key): return layout_cache[cache_key]
	var rows: Array=(LEVELS if version==2 else LEGACY_LEVELS)[stage]; var cfg:={"width":rows[0].length(),"height":rows.size(),"floor":[],"goals":[],"boxes":[],"player":0}
	for y in range(rows.size()):
		for x in range(rows[y].length()):
			var c: String=rows[y][x]; var cell: int=y*cfg.width+x
			if c!="#": cfg.floor.append(cell)
			if c in [".","*","+"]: cfg.goals.append(cell)
			if c in ["$","*"]: cfg.boxes.append(cell)
			if c in ["@","+"]: cfg.player=cell
	cfg["live"]=live_cells(cfg)
	layout_cache[cache_key]=cfg
	return cfg
static func fresh(version:=2) -> Dictionary:
	var cfg:=layout(0,version)
	return {"model":2,"layout_version":version,"stage":0,"player":cfg.player,"boxes":cfg.boxes.duplicate(),"moves":[],"completed":[],"steps":0,"pushes":0,"hints":0,"won":false}
static func step(cfg: Dictionary, player: int, boxes: Array, direction: String) -> Dictionary:
	if not DIRS.has(direction): return {"ok":false,"message":"请选择上下左右方向。"}
	var dir: Vector2i=DIRS[direction]; var offset: int=dir.y*cfg.width+dir.x; var next:=player+offset
	if next not in cfg.floor: return {"ok":false,"message":"前面是墙，换一侧绕过去。"}
	var result: Array=[]
	for cell in boxes: result.append(int(cell))
	var pushed:=result.find(next)
	if pushed>=0:
		var dest:=next+offset
		if dest not in cfg.floor: return {"ok":false,"message":"箱子后面是墙，不能继续推。"}
		if dest in result: return {"ok":false,"message":"不能同时推两只箱子，先腾出通道。"}
		result[pushed]=dest
	return {"ok":true,"player":next,"boxes":result,"pushed":pushed}
static func replay(stage: int, moves: Variant, version:=2) -> Dictionary:
	if not moves is Array or moves.size()>2000: return {}
	var cfg:=layout(stage,version); var player: int=cfg.player; var boxes: Array=cfg.boxes.duplicate(); var pushes:=0
	for direction in moves:
		if not direction is String: return {}
		var result:=step(cfg,player,boxes,direction)
		if not result.ok: return {}
		player=result.player; boxes=result.boxes
		if result.pushed>=0: pushes+=1
	return {"player":player,"boxes":boxes,"pushes":pushes}
static func filled(s: Dictionary) -> int:
	var goals: Array=config_for(s).goals; var count:=0
	for cell in s.boxes:
		if int(cell) in goals: count+=1
	return count
static func solved(s: Dictionary) -> bool: return filled(s)==s.boxes.size()
static func whole(v: Variant, maximum: int) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v>=0 and v<=maximum and v==floor(v)
static func valid(s: Dictionary) -> bool:
	if s.get("model")!=2 or (not whole(s.get("layout_version",1),2) or int(s.get("layout_version",1))<1) or not whole(s.get("stage"),stage_count(s)-1) or not s.get("won") is bool or not s.get("boxes") is Array or not s.get("completed") is Array: return false
	if s.completed.size()!=int(s.stage) or not whole(s.get("hints"),100000): return false
	for i in range(s.completed.size()):
		var proof:=replay(i,s.completed[i],edition(s))
		if proof.is_empty(): return false
		proof.stage=i; proof.layout_version=edition(s)
		if not solved(proof): return false
	var replayed:=replay(int(s.stage),s.get("moves"),edition(s))
	if replayed.is_empty() or s.get("player")!=replayed.player or s.get("steps")!=s.moves.size() or s.get("pushes")!=replayed.pushes or s.boxes.size()!=replayed.boxes.size(): return false
	for i in range(s.boxes.size()):
		if not whole(s.boxes[i],200) or int(s.boxes[i])!=int(replayed.boxes[i]): return false
	return not s.won or (s.stage==stage_count(s)-1 and solved(s))
static func normalized(s: Dictionary) -> Dictionary:
	# JSON numbers are floats; grid membership must compare canonical integer cells.
	var n:=s.duplicate(true)
	n.boxes=s.boxes.map(func(cell): return int(cell))
	for field in ["model","layout_version","stage","player","steps","pushes","hints"]:
		if n.has(field): n[field]=int(n[field])
	return n

static func apply(s: Dictionary, action: String, data: Dictionary) -> Dictionary:
	if s.won: return {"ok":false,"message":"物资已经备妥，可以返回手帐或再玩一局。"}
	var n:=normalized(s); var cfg:=config_for(s)
	if action=="move":
		if solved(s): return {"ok":false,"message":"这一关备妥了，老霍克说完后会自动继续。"}
		if n.moves.size()>=2000: return {"ok":false,"message":"本关动作记录已满，请撤回或重来这一关。"}
		var result:=step(cfg,int(s.player),s.boxes,str(data.get("direction","")))
		if not result.ok: return result
		n.player=result.player; n.boxes=result.boxes; n.moves.append(str(data.direction)); n.steps+=1
		if result.pushed>=0: n.pushes+=1
	elif action=="undo":
		if n.moves.is_empty(): return {"ok":false,"message":"已经回到这一关的起点。"}
		n.moves.pop_back(); var previous:=replay(int(n.stage),n.moves,edition(n)); n.player=previous.player; n.boxes=previous.boxes; n.steps=n.moves.size(); n.pushes=previous.pushes
	elif action=="reset": n.player=cfg.player; n.boxes=cfg.boxes.duplicate(); n.moves=[]; n.steps=0; n.pushes=0
	elif action=="hint": n.hints+=1
	elif action=="next":
		if not solved(s): return {"ok":false,"message":"先把所有物资箱推到黄铜备货位。"}
		if n.stage==stage_count(n)-1: n.won=true
		else:
			n.completed.append(n.moves.duplicate()); n.stage+=1; cfg=config_for(n); n.player=cfg.player; n.boxes=cfg.boxes.duplicate(); n.moves=[]; n.steps=0; n.pushes=0
	else: return {"ok":false,"message":"无效的备货操作。"}
	return {"ok":true,"state":n}
static func live_cells(cfg: Dictionary) -> Dictionary:
	# Reverse pulls from the goals: a box outside this set can never be delivered.
	var live: Dictionary={}; var queue: Array=cfg.goals.duplicate(); var head:=0
	for cell in queue: live[cell]=true
	while head<queue.size():
		var cell: int=queue[head]; head+=1
		for d: Vector2i in DIRS.values():
			var offset: int=d.x+d.y*cfg.width; var previous:=cell-offset
			if previous in cfg.floor and previous-offset in cfg.floor and not live.has(previous):
				live[previous]=true; queue.append(previous)
	return live
static func dead_boxes(s: Dictionary) -> Array:
	var cfg:=config_for(s); var dead: Array=[]
	for cell in s.boxes:
		if not cfg.live.has(int(cell)): dead.append(cell)
	return dead
static func cornered(s: Dictionary) -> bool: return not dead_boxes(s).is_empty()
static func reachable(cfg: Dictionary, player: int, boxes: Array) -> Dictionary:
	boxes=boxes.map(func(cell): return int(cell))
	var paths: Dictionary={player:""}; var queue: Array=[player]; var head:=0
	while head<queue.size():
		var at: int=queue[head]; head+=1
		for d in DIRS:
			var v: Vector2i=DIRS[d]; var cell: int=at+v.y*cfg.width+v.x
			if cell not in cfg.floor or cell in boxes or paths.has(cell): continue
			paths[cell]=str(paths[at])+str(d); queue.append(cell)
	return paths
static func walk_path(s: Dictionary, destination: int) -> Array:
	var path: String=reachable(config_for(s),int(s.player),s.boxes).get(destination,"")
	var result: Array=[]
	for d in path: result.append(d)
	return result
static func key(player: int, boxes: Array) -> String:
	var sorted: Array=boxes.map(func(cell): return int(cell)); sorted.sort(); return str(player)+":"+str(sorted)
static func hint_search(s: Dictionary) -> Dictionary:
	var result:={"cfg":config_for(s),"queue":[{"player":int(s.player),"boxes":s.boxes.map(func(cell): return int(cell)),"first":""}],"seen":{},"head":0,"done":false,"answer":"","visited":0}
	if solved(s): result.done=true; result.answer="next"
	elif cornered(s): result.done=true; result.answer="undo"
	elif s.get("moves") is Array:
		var plan: String=(SOLUTIONS if edition(s)==2 else LEGACY_SOLUTIONS)[int(s.stage)]
		var taken: String="".join(s.moves)
		if plan.begins_with(taken) and taken.length()<plan.length():
			result.done=true; result.answer=plan[taken.length()]
	return result
static func advance_hint(search: Dictionary, slice_usec:=3500) -> bool:
	# Search pushes rather than every footstep, yielding between small UI frames.
	var deadline:=Time.get_ticks_usec()+slice_usec
	var cfg: Dictionary=search.cfg
	while not search.done and search.head<search.queue.size() and Time.get_ticks_usec()<deadline:
		var row: Dictionary=search.queue[search.head]; search.queue[search.head]=null; search.head+=1
		var complete:=true
		for cell in row.boxes:
			if cell not in cfg.goals: complete=false; break
		if complete: search.done=true; search.answer=row.first; break
		var paths:=reachable(cfg,int(row.player),row.boxes)
		var cells: Array=paths.keys(); cells.sort()
		var signature:=key(int(cells[0]),row.boxes)
		if search.seen.has(signature): continue
		search.seen[signature]=true; search.visited+=1
		if search.visited>=20000 or search.queue.size()>=60000:
			search.done=true; search.answer="unknown"; break
		for box in row.boxes:
			for d in DIRS:
				var v: Vector2i=DIRS[d]; var offset: int=v.x+v.y*cfg.width; var destination: int=box+offset
				if not paths.has(int(box)-offset) or not cfg.live.has(destination) or destination in row.boxes: continue
				var next_boxes: Array=row.boxes.duplicate(); next_boxes[next_boxes.find(box)]=destination
				var walking: String=paths[int(box)-offset]
				var first: String=str(row.first) if not str(row.first).is_empty() else (walking[0] if not walking.is_empty() else str(d))
				search.queue.append({"player":int(box),"boxes":next_boxes,"first":first})
	if search.head>=search.queue.size() and not search.done: search.done=true; search.answer="undo"
	return search.done
static func hint(s: Dictionary) -> String:
	var search:=hint_search(s)
	while not advance_hint(search,100000): pass
	return str(search.answer)
