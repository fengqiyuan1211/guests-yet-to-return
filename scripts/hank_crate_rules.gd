extends RefCounted
## Discrete Sokoban state. Replayable moves prove completion; no art or economy.
const LEVELS=[
	["######","#    #","# .$ #","# @  #","######"],
	["#######","# . . #","# $ $ #","#  #  #","#  @  #","#     #","#######"],
	["########","#  . . #","#  #   #","# $$ $ #","#  .#  #","#  @   #","########"]
]
const SOLUTIONS=["RRUL","LUUDDRRUU","ULUUDDDRRRUUUDLLDLULUURDDLDR"]
const NAMES=["灯不是自己亮的","账上那两笔","先给别人留条路"]
const LINES=["玛莎把灯擦过。风里找人的时候，玻璃脏一点，都不一样。","齐恩记的不是两只箱，是那晚够不够用。账上那两笔，比我的名字早。","东西备齐了，也还得有人知道路。那晚，是尼尔·贝克回来找的我们。"]
const DIRS={"U":Vector2i(0,-1),"D":Vector2i(0,1),"L":Vector2i(-1,0),"R":Vector2i(1,0)}
static func layout(stage: int) -> Dictionary:
	var rows: Array=LEVELS[stage]; var cfg:={"width":rows[0].length(),"height":rows.size(),"floor":[],"goals":[],"boxes":[],"player":0}
	for y in range(rows.size()):
		for x in range(rows[y].length()):
			var c: String=rows[y][x]; var cell: int=y*cfg.width+x
			if c!="#": cfg.floor.append(cell)
			if c==".": cfg.goals.append(cell)
			if c=="$": cfg.boxes.append(cell)
			if c=="@": cfg.player=cell
	return cfg
static func fresh() -> Dictionary:
	var cfg:=layout(0)
	return {"model":2,"stage":0,"player":cfg.player,"boxes":cfg.boxes.duplicate(),"moves":[],"completed":[],"steps":0,"pushes":0,"hints":0,"won":false}
static func step(cfg: Dictionary, player: int, boxes: Array, direction: String) -> Dictionary:
	if not DIRS.has(direction): return {"ok":false,"message":"请选择上下左右方向。"}
	var dir: Vector2i=DIRS[direction]; var offset: int=dir.y*cfg.width+dir.x; var next:=player+offset
	if next not in cfg.floor: return {"ok":false,"message":"前面是墙，换一侧绕过去。"}
	var result:=boxes.duplicate(); var pushed:=boxes.find(next)
	if pushed>=0:
		var dest:=next+offset
		if dest not in cfg.floor: return {"ok":false,"message":"箱子后面是墙，不能继续推。"}
		if dest in boxes: return {"ok":false,"message":"不能同时推两只箱子，先腾出通道。"}
		result[pushed]=dest
	return {"ok":true,"player":next,"boxes":result,"pushed":pushed}
static func replay(stage: int, moves: Variant) -> Dictionary:
	if not moves is Array or moves.size()>2000: return {}
	var cfg:=layout(stage); var player: int=cfg.player; var boxes: Array=cfg.boxes.duplicate(); var pushes:=0
	for direction in moves:
		if not direction is String: return {}
		var result:=step(cfg,player,boxes,direction)
		if not result.ok: return {}
		player=result.player; boxes=result.boxes
		if result.pushed>=0: pushes+=1
	return {"player":player,"boxes":boxes,"pushes":pushes}
static func filled(s: Dictionary) -> int:
	var goals: Array=layout(int(s.stage)).goals; var count:=0
	for cell in s.boxes:
		if cell in goals: count+=1
	return count
static func solved(s: Dictionary) -> bool: return filled(s)==s.boxes.size()
static func whole(v: Variant, maximum: int) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v>=0 and v<=maximum and v==floor(v)
static func valid(s: Dictionary) -> bool:
	if s.get("model")!=2 or not whole(s.get("stage"),2) or not s.get("won") is bool or not s.get("boxes") is Array or not s.get("completed") is Array: return false
	if s.completed.size()!=int(s.stage) or not whole(s.get("hints"),100000): return false
	for i in range(s.completed.size()):
		var proof:=replay(i,s.completed[i])
		if proof.is_empty(): return false
		proof.stage=i
		if not solved(proof): return false
	var replayed:=replay(int(s.stage),s.get("moves"))
	if replayed.is_empty() or s.get("player")!=replayed.player or s.get("steps")!=s.moves.size() or s.get("pushes")!=replayed.pushes or s.boxes.size()!=replayed.boxes.size(): return false
	for i in range(s.boxes.size()):
		if not whole(s.boxes[i],200) or int(s.boxes[i])!=int(replayed.boxes[i]): return false
	return not s.won or (s.stage==2 and solved(s))
static func apply(s: Dictionary, action: String, data: Dictionary) -> Dictionary:
	if s.won: return {"ok":false,"message":"物资已经备妥，可以返回手帐或再玩一局。"}
	var n:=s.duplicate(true); var cfg:=layout(int(s.stage))
	if action=="move":
		if solved(s): return {"ok":false,"message":"这一关备妥了，按空格继续，或撤回调整。"}
		if n.moves.size()>=2000: return {"ok":false,"message":"本关动作记录已满，请撤回或重来这一关。"}
		var result:=step(cfg,int(s.player),s.boxes,str(data.get("direction","")))
		if not result.ok: return result
		n.player=result.player; n.boxes=result.boxes; n.moves.append(str(data.direction)); n.steps+=1
		if result.pushed>=0: n.pushes+=1
	elif action=="undo":
		if n.moves.is_empty(): return {"ok":false,"message":"已经回到这一关的起点。"}
		n.moves.pop_back(); var previous:=replay(int(n.stage),n.moves); n.player=previous.player; n.boxes=previous.boxes; n.steps=n.moves.size(); n.pushes=previous.pushes
	elif action=="reset": n.player=cfg.player; n.boxes=cfg.boxes.duplicate(); n.moves=[]; n.steps=0; n.pushes=0
	elif action=="hint": n.hints+=1
	elif action=="next":
		if not solved(s): return {"ok":false,"message":"先把所有物资箱推到黄铜备货位。"}
		if n.stage==2: n.won=true
		else:
			n.completed.append(n.moves.duplicate()); n.stage+=1; cfg=layout(int(n.stage)); n.player=cfg.player; n.boxes=cfg.boxes.duplicate(); n.moves=[]; n.steps=0; n.pushes=0
	else: return {"ok":false,"message":"无效的备货操作。"}
	return {"ok":true,"state":n}
static func cornered(s: Dictionary) -> bool:
	var cfg:=layout(int(s.stage)); var w: int=cfg.width
	for cell in s.boxes:
		if cell in cfg.goals: continue
		if (int(cell)-1 not in cfg.floor or int(cell)+1 not in cfg.floor) and (int(cell)-w not in cfg.floor or int(cell)+w not in cfg.floor): return true
	return false
static func walk_path(s: Dictionary, destination: int) -> Array:
	var cfg:=layout(int(s.stage)); var queue: Array=[{"cell":int(s.player),"path":[]}]; var seen: Dictionary={int(s.player):true}; var head:=0
	while head<queue.size():
		var row: Dictionary=queue[head]; head+=1
		if row.cell==destination: return row.path
		for d in DIRS:
			var v: Vector2i=DIRS[d]; var cell: int=row.cell+v.y*cfg.width+v.x
			if cell not in cfg.floor or cell in s.boxes or seen.has(cell): continue
			seen[cell]=true; var path: Array=row.path.duplicate(); path.append(d); queue.append({"cell":cell,"path":path})
	return []
static func key(player: int, boxes: Array) -> String:
	var sorted:=boxes.duplicate(); sorted.sort(); return str(player)+":"+str(sorted)
static func hint(s: Dictionary) -> String:
	if solved(s): return "next"
	if cornered(s): return "undo"
	var cfg:=layout(int(s.stage)); var queue: Array=[{"player":int(s.player),"boxes":s.boxes.duplicate(),"first":""}]; var seen: Dictionary={key(int(s.player),s.boxes):true}; var head:=0
	while head<queue.size() and head<65000:
		var row: Dictionary=queue[head]; head+=1
		var complete:=true
		for cell in row.boxes:
			if cell not in cfg.goals: complete=false; break
		if complete: return row.first
		for d in DIRS:
			var result:=step(cfg,row.player,row.boxes,d)
			if not result.ok: continue
			var k:=key(result.player,result.boxes)
			if seen.has(k): continue
			seen[k]=true; queue.append({"player":result.player,"boxes":result.boxes,"first":d if row.first=="" else row.first})
	return "undo"
