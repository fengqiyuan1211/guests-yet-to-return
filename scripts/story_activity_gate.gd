extends RefCounted
## One settled story cup per authored chapter. Never use craft points or repeat visits.
const PATH := "res://data/minigames/story_activity_gate.json"

static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))

static func episodes(guest: String) -> Array:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/story_dialogues/manifest.json"))
	for person: Dictionary in manifest.characters:
		if person.guest_id==guest: return person.episodes
	return []

static func total(record: Dictionary) -> Variant:
	var review: Dictionary=record.get("review",{})
	if review.get("status")=="rejected": return 0.0
	var score: Variant=review.get("satisfaction")
	if review.get("status")!="scored" or not (score is float or score is int) or not is_finite(float(score)) or score<0: return null
	return clampf(float(score),0,100)

static func sequence(record: Dictionary) -> int:
	var drink:=str(record.get("drink_id",""))
	if drink.begins_with("practice-") and drink.ends_with("-drink"):
		var part:=drink.trim_prefix("practice-").trim_suffix("-drink")
		if part.is_valid_int() and int(part)>0: return int(part)
	var serial: Variant=record.get("visit_serial")
	return int(serial) if (serial is int or serial is float) and is_finite(float(serial)) and serial>0 and serial==floor(serial) else -1

static func summarize(guest: String, story: Dictionary, chapters: Array, deliveries: Dictionary, legacy: Dictionary={}, settings: Dictionary={}) -> Dictionary:
	var rule:=config() if settings.is_empty() else settings
	var threshold:=float(rule.get("minimum_average_total_score",60))
	var expected: Array=[]
	for chapter: Dictionary in chapters: expected.append(str(chapter.id))
	var candidates: Array=[]
	var drinks: Dictionary={}
	for row: Variant in deliveries.values():
		if not row is Dictionary or row.get("play_mode")=="mixing" or row.get("guest_id")!=guest or row.get("status")!="settled": continue
		var id:=str(row.get("story_episode_id",row.get("demand",{}).get("episode_id","")))
		if id not in expected: continue
		var heard: Variant=story.get("heard",{}).get(id)
		var completed: bool=row.get("story_completed",heard is Array and not heard.is_empty() and row.get("story")==heard)
		if not completed or total(row)==null or sequence(row)<0: continue
		var record: Dictionary=row.duplicate(true); record.story_episode_id=id
		candidates.append(record); drinks[str(record.get("drink_id",""))]=true
	# Old locked orders keep their frozen receipt. Only explicitly linked chapters count.
	for tx: Dictionary in legacy.values():
		var order: Dictionary=tx.get("order",{}); var receipt: Dictionary=tx.get("receipt",{})
		var drink:=str(tx.get("drink_id","")); var id:=str(order.get("demand",{}).get("event_id",""))
		if tx.get("phase")!="complete" or order.get("guest_id")!=guest or tx.get("play_mode")=="mixing" or drinks.has(drink) or id not in expected: continue
		if int(story.get("completed",0))<expected.find(id)+1 or story.get("heard",{}).get(id,[]).is_empty(): continue
		var record:={"id":str(receipt.get("id","")),"drink_id":drink,"visit_id":str(order.get("visit_id","")),"story_episode_id":id,
			"review":{"status":"rejected" if receipt.get("status")=="rejected" else "scored","satisfaction":receipt.get("score")}}
		if receipt.get("status") not in ["accepted","rejected"] or total(record)==null or sequence(record)<0: continue
		candidates.append(record)
	candidates.sort_custom(func(a,b):
		if sequence(a)==sequence(b): return str(a.id)<str(b.id)
		return sequence(a)<sequence(b))
	var visits: Dictionary={}; var selected: Dictionary={}
	for row: Dictionary in candidates:
		var visit:=str(row.get("visit_id","")); var chapter:=str(row.story_episode_id)
		if visit.is_empty() or visits.has(visit) or selected.has(chapter): continue
		visits[visit]=true; selected[chapter]=row
	var sum_score:=0.0; var ids: Array=[]; var missing: Array=[]
	for chapter in expected:
		if not selected.has(chapter): missing.append(chapter); continue
		sum_score+=float(total(selected[chapter])); ids.append(str(selected[chapter].id))
	var complete: bool=not expected.is_empty() and missing.is_empty() and int(story.get("completed",0))>=expected.size()
	var average: Variant=sum_score/expected.size() if complete else null
	return {"eligible":complete and float(average)>threshold,"story_completed":int(story.get("completed",0)),
		"score_count":ids.size(),"required_scores":expected.size(),"average":average,"minimum_average":threshold,
		"comparison":"gt","score_window":"fixed_story_chapters","score_source":"review.satisfaction",
		"delivery_ids":ids,"missing_chapters":missing,"final_delivery_id":str(selected.get(expected.back(),{}).get("id","")) if not expected.is_empty() else ""}
