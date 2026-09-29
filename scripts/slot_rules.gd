extends RefCounted
## Rewards are gross payouts; the 20-coin stake is deducted once at spin start.
const COST := 20
const WEIGHTS := [3, 7, 20, 30, 40]
const NAMES := ["发", "金币", "酒杯", "星星", "柠檬", "隐藏大奖"]
const HIDDEN_SYMBOL := 5
const HIDDEN_CHANCE_DENOMINATOR := 200 # 1 / 200 = 0.5%, before pity.
const HIDDEN_PITY := 100
const TRIPLES := [2000, 400, 160, 80, 40]
const PAIRS := [120, 50, 30, 18, 12]

static func draw_result(rng: RandomNumberGenerator, misses: int) -> Array:
	if misses >= HIDDEN_PITY - 1 or rng.randi_range(1, HIDDEN_CHANCE_DENOMINATOR) == 1:
		return [HIDDEN_SYMBOL, HIDDEN_SYMBOL, HIDDEN_SYMBOL]
	return [draw_symbol(rng), draw_symbol(rng), draw_symbol(rng)]

static func is_hidden(symbols: Array) -> bool:
	return symbols.size() == 3 and symbols[0] == HIDDEN_SYMBOL and symbols[1] == HIDDEN_SYMBOL and symbols[2] == HIDDEN_SYMBOL

static func draw_symbol(rng: RandomNumberGenerator) -> int:
	var roll := rng.randi_range(1, 100)
	var cumulative := 0
	for i in range(WEIGHTS.size()):
		cumulative += WEIGHTS[i]
		if roll <= cumulative:
			return i
	return 4

static func payout(symbols: Array) -> int:
	if not valid_result(symbols):
		return 0
	if is_hidden(symbols):
		return 0 # Reserved collectible reward; no invented coin payout.
	if symbols[0] == symbols[1] and symbols[1] == symbols[2]:
		return TRIPLES[int(symbols[0])]
	for i in range(3):
		for j in range(i + 1, 3):
			if symbols[i] == symbols[j]:
				return PAIRS[int(symbols[i])]
	return 0

static func valid_result(symbols: Array) -> bool:
	if is_hidden(symbols):
		return true
	if symbols.size() != 3:
		return false
	for value in symbols:
		if not (value is int or value is float):
			return false
		if value != int(value) or int(value) < 0 or int(value) >= WEIGHTS.size():
			return false
	return true

static func expected_payout() -> float:
	var total := 0.0
	for a in range(5):
		for b in range(5):
			for c in range(5):
				total += WEIGHTS[a] * WEIGHTS[b] * WEIGHTS[c] / 1000000.0 * payout([a, b, c])
	return total
