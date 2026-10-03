extends RefCounted
## Fixed quantities for visual/gesture regression only, always in private /tmp saves.
static func seed(supplies: Node, bench: Node) -> bool:
	if not str(supplies.save_path).begins_with("/tmp/"): return false
	var candidate=preload("res://scripts/supply_inventory.gd").new()
	for alias in ["gin","rum","vodka","lime","syrup","soda"]:
		var definition: Dictionary=bench.MATERIALS[alias]
		var id: String=definition.sku_id
		var capacity: float=candidate.catalog.get_item(id).package.container_capacity
		candidate.purchase(id,ceili(600.0/capacity))
		var surplus: float=candidate.total_remaining(id)-600.0
		if surplus>0: candidate.consume(id,surplus)
	for alias in ["garnish","lemon_slice"]:
		var definition: Dictionary=bench.GARNISHES[alias]
		var id: String=definition.sku_id
		candidate.purchase(id,1)
		var surplus: float=candidate.total_remaining(id)-20.0
		if surplus>0: candidate.consume(id,surplus)
	if not supplies._write(candidate.serialize(),{}): return false
	supplies.inventory.restore(candidate.serialize())
	supplies._sync_menu()
	supplies.changed.emit()
	return true
