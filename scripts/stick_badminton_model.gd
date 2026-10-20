extends RefCounted
## Deterministic fixed-step side-view badminton, independent of the tavern/UI.
const Rules := preload("res://scripts/stick_memory_rules.gd")
const GROUND := 650.0
const NET_X := 800.0
const NET_TOP := 434.0
const GRAVITY := 850.0
const PLAYER_SPEED := 425.0
const AI_SPEED := 325.0
const JUMP_SPEED := -520.0
const PLAYER_REACH := 170.0
const SWING_DURATION := 0.32
const SHOULDER_HEIGHT := 118.0
const RACKET_REACH := 137.0
const RACKET_RADII := Vector2(16, 25)
const RACKET_HANDLE_LENGTH := 62.0
const ARM_SEGMENT_LENGTH := 48.0
const CONTACT_RADIUS := 7.0
const ACTIVE_FROM := 0.18
const ACTIVE_TO := 0.72
var rng := RandomNumberGenerator.new()
var phase := "ready"
var player_x := 410.0
var ai_x := 1185.0
var player_jump := 0.0
var ai_jump := 0.0
var player_vy := 0.0
var ai_vy := 0.0
var player_move := 0.0
var ai_move := 0.0
var shuttle := Vector2(440, 552)
var velocity := Vector2.ZERO
var server := 0
var last_hitter := 0
var player_score := 0
var ai_score := 0
var rally := 0
var longest_rally := 0
var player_actions := 0
var practice_left := 0
var assist_used := false
var player_swing := 0.0
var ai_swing := 0.0
var player_swing_type := "underhand"
var ai_swing_type := "underhand"
var _player_aim := 0.0
var _ai_aim := 0.0
var _player_radius := 90.0
var _ai_radius := 90.0
var _player_contact := false
var _ai_contact := false
var player_cooldown := 0.0
var ai_cooldown := 0.0
var point_delay := 0.0
var ai_delay := 0.0
var ai_target := 1185.0
var ai_misses := false
var toast := "轮到你发球"
var match_id := ""
# Feedback stays in the simulation so a fixed-step hit produces one UI event.
var hit_serial := 0
var point_serial := 0
var hit_flash := 0.0
var hit_position := Vector2.ZERO
var hit_quality := ""
var miss_flash := 0.0
var swing_feedback := ""
var point_winner := 0
var _swing_buffer := 0.0
var _ai_serve_wait := 0.0
var _hit_stop := 0.0
var _shot_direction := 0.0
var _jump_buffer := 0.0

func begin(id: String, practice: int = 0, seed_value: int = -1) -> void:
	match_id = id
	if seed_value >= 0: rng.seed = seed_value
	else: rng.randomize()
	player_score = 0
	ai_score = 0
	longest_rally = 0
	player_actions = 0
	assist_used = false
	hit_serial = 0
	point_serial = 0
	hit_flash = 0
	player_swing = 0
	ai_swing = 0
	hit_quality = ""
	swing_feedback = ""
	practice_left = maxi(0, practice)
	_prepare_serve(0)

func jump() -> void:
	if phase != "rally": return
	# A press just before landing is kept briefly instead of being swallowed.
	_jump_buffer = 0.12
	if player_jump == 0.0:
		player_vy = JUMP_SPEED
		_jump_buffer = 0

func swing() -> void:
	if phase == "ready" and server == 0:
		shuttle = Vector2(player_x + 35, GROUND - 98)
		_start_swing(0, true)
		_hit(0, true)
	elif phase == "rally" and player_cooldown <= 0:
		_start_swing(0)
		miss_flash = 0

func _shoulder(who: int) -> Vector2:
	return Vector2(player_x, GROUND + player_jump - SHOULDER_HEIGHT) if who == 0 else Vector2(ai_x, GROUND + ai_jump - SHOULDER_HEIGHT)

func _predicted_shoulder(who: int, lead_time: float) -> Vector2:
	var jump_offset := player_jump if who == 0 else ai_jump
	var jump_velocity := player_vy if who == 0 else ai_vy
	var future_jump := minf(0, jump_offset + jump_velocity * lead_time + 0.5 * GRAVITY * lead_time * lead_time)
	var horizontal_velocity := player_move * PLAYER_SPEED if who == 0 else ai_move * AI_SPEED
	var future_x := clampf((player_x if who == 0 else ai_x) + horizontal_velocity * lead_time, 180 if who == 0 else 875, 715 if who == 0 else 1410)
	return Vector2(future_x, GROUND + future_jump - SHOULDER_HEIGHT)

func _swing_progress(who: int) -> float:
	var remaining := player_swing if who == 0 else ai_swing
	return clampf(1.0 - remaining / SWING_DURATION, 0, 1)

func _sweep_offset(kind: String, progress: float) -> float:
	# The racket travels down through a high contact and up through a low one.
	var sweep := lerpf(-1.15, 1.15, smoothstep(0.04, 0.92, progress))
	return sweep if kind == "overhand" else -sweep

func _aim_stroke(who: int, lead_time: float) -> void:
	var direction := 1.0 if who == 0 else -1.0
	var anticipated := shuttle + velocity * lead_time + Vector2(0, GRAVITY * lead_time * lead_time * 0.5)
	var delta := anticipated - _predicted_shoulder(who, lead_time)
	# Aim is a joint rotation, never a teleport of the shuttle to the player's body.
	var angle := Vector2(delta.x * direction, delta.y).angle()
	var radius := clampf(delta.length(), 54, RACKET_REACH)
	if who == 0:
		_player_aim = angle
		_player_radius = radius
	else:
		_ai_aim = angle
		_ai_radius = radius

func _start_swing(who: int, serve: bool = false) -> void:
	var lead_time := 0.0 if serve else SWING_DURATION * 0.5
	var anticipated := shuttle + velocity * lead_time + Vector2(0, GRAVITY * lead_time * lead_time * 0.5)
	var kind := "underhand" if serve or anticipated.y > _predicted_shoulder(who, lead_time).y + 8 else "overhand"
	if who == 0:
		player_swing_type = kind
		player_swing = SWING_DURATION * (0.5 if serve else 1.0)
		player_cooldown = SWING_DURATION + 0.025
		_player_contact = false
		_swing_buffer = SWING_DURATION * ACTIVE_TO
	else:
		ai_swing_type = kind
		ai_swing = SWING_DURATION * (0.5 if serve else 1.0)
		ai_cooldown = SWING_DURATION + 0.065
		_ai_contact = false
	_aim_stroke(who, lead_time)

func racket_pose(who: int, progress: float = -1.0) -> Dictionary:
	var shoulder := _shoulder(who)
	var remaining := player_swing if who == 0 else ai_swing
	var kind := player_swing_type if who == 0 else ai_swing_type
	var direction := 1.0 if who == 0 else -1.0
	var active_stroke := remaining > 0
	var p := _swing_progress(who) if progress < 0 else clampf(progress, 0, 1)
	var angle := (_player_aim if who == 0 else _ai_aim) + _sweep_offset(kind, p)
	var radius := _player_radius if who == 0 else _ai_radius
	if p < ACTIVE_FROM:
		var windup := smoothstep(0.0, ACTIVE_FROM, p)
		angle = lerp_angle(-0.38, (_player_aim if who == 0 else _ai_aim) + _sweep_offset(kind, ACTIVE_FROM), windup)
		radius = lerpf(90, radius, windup)
	elif p > ACTIVE_TO:
		var recovery := smoothstep(ACTIVE_TO, 1.0, p)
		angle = lerp_angle((_player_aim if who == 0 else _ai_aim) + _sweep_offset(kind, ACTIVE_TO), -0.38, recovery)
		radius = lerpf(radius, 90, recovery)
	if not active_stroke and progress < 0:
		angle = -0.38
		radius = 90
	var arm_direction := Vector2(cos(angle) * direction, sin(angle))
	# The low sweep skims above the floor instead of pushing the racket underground.
	var ellipse_angle := arm_direction.angle() - PI / 2
	var lower_extent := sqrt(pow(RACKET_RADII.x * sin(ellipse_angle), 2) + pow(RACKET_RADII.y * cos(ellipse_angle), 2))
	if arm_direction.y > 0:
		radius = minf(radius, maxf(30, (GROUND - 3 - lower_extent - shoulder.y) / arm_direction.y))
	var center := shoulder + arm_direction * radius
	# A rigid racket has enough exposed shaft to distinguish it from the bent arm.
	var hand := center - arm_direction * RACKET_HANDLE_LENGTH
	# Two linked segments keep the elbow bent rather than moving a detached racket.
	var hand_delta := hand - shoulder
	var hand_direction := hand_delta.normalized() if hand_delta.length_squared() > 0.0001 else arm_direction
	var along := minf(hand_delta.length() * 0.5, ARM_SEGMENT_LENGTH)
	var bend := sqrt(maxf(0, ARM_SEGMENT_LENGTH * ARM_SEGMENT_LENGTH - along * along))
	var perpendicular := Vector2(-hand_direction.y, hand_direction.x) * direction
	var elbow := shoulder + hand_direction * along + perpendicular * bend
	return {"shoulder": shoulder, "elbow": elbow, "hand": hand, "center": center,
		"angle": arm_direction.angle() - PI / 2, "type": kind, "active": active_stroke and p >= ACTIVE_FROM and p <= ACTIVE_TO,
		"racket_radii": RACKET_RADII, "progress": p, "contact": _player_contact if who == 0 else _ai_contact}

func _reachable(who: int, position: Vector2) -> bool:
	if position.y >= GROUND - 7: return false
	if (position.x >= NET_X) if who == 0 else (position.x <= NET_X): return false
	var delta := position - _shoulder(who)
	var facing := 1.0 if who == 0 else -1.0
	# A circle follows arm length, excluding the old rectangle's unreachable corners.
	return delta.length() <= RACKET_REACH + RACKET_RADII.y + CONTACT_RADIUS and delta.x * facing >= -82

func _swept_contact(who: int, previous: Vector2, current: Vector2, old_progress: float, new_progress: float) -> Dictionary:
	if (_player_contact if who == 0 else _ai_contact): return {}
	var begin := maxf(ACTIVE_FROM, old_progress)
	var finish := minf(ACTIVE_TO, new_progress)
	if begin > finish or is_equal_approx(old_progress, new_progress): return {}
	var old_center: Vector2 = racket_pose(who, old_progress).center
	var new_center: Vector2 = racket_pose(who, new_progress).center
	var samples := maxi(3, ceili((old_center.distance_to(new_center) + previous.distance_to(current)) / 8.0))
	for i in range(samples + 1):
		var p := lerpf(begin, finish, float(i) / samples)
		var t := clampf((p - old_progress) / (new_progress - old_progress), 0, 1)
		var ball := previous.lerp(current, t)
		if not _reachable(who, ball): continue
		var pose := racket_pose(who, p)
		var local: Vector2 = (ball - Vector2(pose.center)).rotated(-float(pose.angle))
		var radius := RACKET_RADII + Vector2.ONE * CONTACT_RADIUS
		if pow(local.x / radius.x, 2) + pow(local.y / radius.y, 2) <= 1.0:
			return {"position": ball, "progress": p}
	return {}

func predicted_landing() -> float:
	var distance := maxf(0, GROUND - 8 - shuttle.y)
	var t := (-velocity.y + sqrt(velocity.y * velocity.y + 2 * GRAVITY * distance)) / GRAVITY
	return shuttle.x + velocity.x * t

func can_hit(who: int) -> bool:
	return _reachable(who, shuttle)

func player_can_return() -> bool:
	return phase == "rally" and last_hitter == 1 and can_hit(0) and player_cooldown <= 0

func action_hint() -> String:
	if phase == "point": return "稍歇一下 · 下一球马上开始"
	if phase == "finished": return "这一局结束了"
	if phase == "ready": return "空格 / S / 点击发球" if server == 0 else "小线准备发球 · 注意左侧落点"
	if miss_flash > 0: return swing_feedback
	if last_hitter == 0: return "回到中间，准备接下一球"
	if player_can_return(): return "球到身边了 · 挥拍！左右移动可调整落点"
	if shuttle.y < _shoulder(0).y - RACKET_REACH and absf(shuttle.x - player_x) < 175: return "高球 · W / ↑ / 点击跳跃"
	return "跟着左侧落点移动 · 球靠近再挥拍"

func step(dt: float, move: float, assisted: bool) -> void:
	if phase == "finished": return
	var player_old_progress := _swing_progress(0)
	var ai_old_progress := _swing_progress(1)
	if _hit_stop > 0:
		_hit_stop = maxf(0, _hit_stop - dt)
		return
	player_swing = maxf(0, player_swing - dt)
	ai_swing = maxf(0, ai_swing - dt)
	player_cooldown = maxf(0, player_cooldown - dt)
	ai_cooldown = maxf(0, ai_cooldown - dt)
	hit_flash = maxf(0, hit_flash - dt)
	miss_flash = maxf(0, miss_flash - dt)
	_jump_buffer = maxf(0, _jump_buffer - dt)
	# Shot steering uses only deliberate movement, never automatic positioning.
	_shot_direction = clampf(move, -1, 1)
	var was_buffered := _swing_buffer > 0
	_swing_buffer = maxf(0, _swing_buffer - dt)
	if was_buffered and _swing_buffer <= 0 and last_hitter == 1:
		miss_flash = 0.7
		if absf(shuttle.x - player_x) > PLAYER_REACH: swing_feedback = "挥早了 · 等球靠近再接"
		elif shuttle.y < _shoulder(0).y - RACKET_REACH: swing_feedback = "球还太高 · 跳起来接"
		else: swing_feedback = "稍早一点挥拍，别等球落到脚边"
	if assisted:
		assist_used = true
		# Manual input can override assistance for a chosen shot position.
		if is_zero_approx(move):
			var target := clampf(predicted_landing() - 20, 210, 708) if phase == "rally" and last_hitter == 1 else 420.0
			move = clampf((target - player_x) / 32, -1, 1)
	player_move = move if phase in ["ready", "rally"] else 0.0
	ai_move = 0
	if phase in ["ready", "rally"]:
		player_x = clampf(player_x + move * PLAYER_SPEED * dt, 180, 715)
	if phase in ["ready", "rally", "point"]:
		player_jump += player_vy * dt
		if player_jump < 0: player_vy += GRAVITY * dt
		else:
			player_jump = 0
			player_vy = 0
			if phase == "rally" and _jump_buffer > 0:
				player_vy = JUMP_SPEED
				_jump_buffer = 0
		ai_jump += ai_vy * dt
		if ai_jump < 0: ai_vy += GRAVITY * dt
		else:
			ai_jump = 0
			ai_vy = 0
	if phase == "point":
		point_delay -= dt
		if point_delay <= 0: _prepare_serve(server)
		return
	if phase == "ready":
		shuttle = Vector2(player_x + 35, GROUND - 98) if server == 0 else Vector2(ai_x - 35, GROUND - 98)
		if server == 1:
			_ai_serve_wait -= dt
			if _ai_serve_wait <= 0:
				_start_swing(1, true)
				_hit(1, true)
		return
	if player_swing > 0 and not _player_contact and player_old_progress < ACTIVE_FROM:
		_aim_stroke(0, maxf(0, SWING_DURATION * (0.5 - player_old_progress)))
	if ai_swing > 0 and not _ai_contact and ai_old_progress < ACTIVE_FROM:
		_aim_stroke(1, maxf(0, SWING_DURATION * (0.5 - ai_old_progress)))
	var previous := shuttle
	shuttle += velocity * dt + Vector2(0, 0.5 * GRAVITY * dt * dt)
	velocity.y += GRAVITY * dt
	if (previous.x - NET_X) * (shuttle.x - NET_X) <= 0 and not is_equal_approx(previous.x, shuttle.x):
		var crossing_y := lerpf(previous.y, shuttle.y, (NET_X - previous.x) / (shuttle.x - previous.x))
		if crossing_y >= NET_TOP:
			_point(1 - last_hitter, "挂网了 · 贴网球要早一点接")
			return
	if shuttle.y >= GROUND - 8:
		var out := shuttle.x < 155 or shuttle.x > 1445
		_point(1 - last_hitter if out else (1 if shuttle.x < NET_X else 0), "出界" if out else "落地")
		return
	if last_hitter == 1 and player_swing > 0:
		var contact := _swept_contact(0, previous, shuttle, player_old_progress, _swing_progress(0))
		if not contact.is_empty():
			shuttle = contact.position
			player_swing = SWING_DURATION * (1 - float(contact.progress))
			_hit(0)
	if last_hitter == 0:
		ai_delay -= dt
		if ai_delay <= 0:
			var old_x := ai_x
			ai_x = move_toward(ai_x, ai_target, AI_SPEED * dt)
			ai_move = signf(ai_x - old_x)
			if shuttle.y < GROUND - 190 and absf(shuttle.x - ai_x) < 112 and velocity.y > 0 and ai_jump == 0: ai_vy = JUMP_SPEED * 0.72
			if not ai_misses and ai_cooldown <= 0 and can_hit(1) and velocity.y > -80:
				_start_swing(1)
				ai_old_progress = 0.0
		if ai_swing > 0:
			var contact := _swept_contact(1, previous, shuttle, ai_old_progress, _swing_progress(1))
			if not contact.is_empty():
				shuttle = contact.position
				ai_swing = SWING_DURATION * (1 - float(contact.progress))
				_hit(1)
	else:
		var old_x := ai_x
		ai_x = move_toward(ai_x, 1185, AI_SPEED * dt * 0.4)
		ai_move = signf(ai_x - old_x)

func _hit(who: int, serve: bool = false) -> void:
	last_hitter = who
	phase = "rally"
	rally += 1
	longest_rally = maxi(longest_rally, rally)
	hit_serial += 1
	hit_position = shuttle
	hit_flash = 0.23
	_hit_stop = 0.025
	miss_flash = 0
	hit_quality = "发球" if serve else "好球"
	if who == 0:
		player_actions += 1
		_swing_buffer = 0
		_player_contact = true
		player_cooldown = maxf(player_cooldown, 0.24)
		if not serve:
			if player_jump < -35 and shuttle.y < GROUND - 170: hit_quality = "跳击"
			elif absf(shuttle.x - player_x) > 115 or shuttle.y > GROUND + player_jump - 75: hit_quality = "救球"
	else:
		_ai_contact = true
		ai_cooldown = maxf(ai_cooldown, 0.30)
	var target := 1100.0
	if who == 1:
		# Small positional tactics: usually send the return away from the player.
		if rng.randf() < 0.74:
			target = rng.randf_range(560, 660) if player_x < 460 else rng.randf_range(245, 350)
		else: target = rng.randf_range(380, 535)
	if who == 0:
		# Position controls the shot: stand forward for a deep shot, back for a short one.
		var neutral_target := clampf(1060 + (player_x - 400) * 0.65 + rng.randf_range(-42, 42), 925, 1380)
		target = clampf(neutral_target + _shot_direction * 90, 925, 1380)
		# Low saves retain their neutral arc if steering would demand an off-screen lob.
		if _flight_needed(target) > 1.55: target = neutral_target
	var minimum_flight := _flight_needed(target)
	var kind := player_swing_type if who == 0 else ai_swing_type
	# Low underhand saves lift noticeably; high contacts permit a faster flat return.
	var shot_time := 1.36 if serve else (1.43 if kind == "underhand" else 0.96)
	var duration := clampf(maxf(shot_time, minimum_flight), 0.90, 1.55)
	var upward := (GROUND - 8 - shuttle.y - 0.5 * GRAVITY * duration * duration) / duration
	# Keep the apex on the court: a very late low ball may legitimately hit the net.
	var most_upward := -sqrt(maxf(0, 2 * GRAVITY * (shuttle.y - 170)))
	if upward < most_upward:
		upward = most_upward
		duration = (-upward + sqrt(upward * upward + 2 * GRAVITY * (GROUND - 8 - shuttle.y))) / GRAVITY
	velocity = Vector2((target - shuttle.x) / duration, upward)
	if who == 0:
		var pressure := clampf(float(rally - 1) / 14, 0, 1)
		ai_delay = rng.randf_range(0.20, 0.34)
		ai_target = clampf(predicted_landing() + rng.randf_range(-60, 60), 875, 1410)
		ai_misses = not serve and rng.randf() < 0.075 + pressure * 0.09
	toast = ("你 · " + hit_quality + "    " if who == 0 else "") + "来回 %d 拍" % rally

func _flight_needed(target: float) -> float:
	var ratio := clampf((NET_X - shuttle.x) / (target - shuttle.x), 0.03, 0.97)
	return sqrt(maxf(0.01, 2 * (shuttle.y + (GROUND - 8 - shuttle.y) * ratio - (NET_TOP - 42)) / (GRAVITY * ratio * (1 - ratio))))

func _point(winner: int, reason: String) -> void:
	if phase in ["point", "finished"]: return
	server = winner
	point_winner = winner
	point_serial += 1
	player_move = 0
	ai_move = 0
	if practice_left > 0:
		practice_left -= 1
		toast = "找到感觉了吗？正式比赛要开始了。" if practice_left == 0 else "热身还剩一球，不记分。"
		server = 0
		if practice_left == 0:
			player_actions = 0
			longest_rally = 0
	else:
		if winner == 0: player_score += 1
		else: ai_score += 1
		toast = ("你得分" if winner == 0 else "小线得分") + " · " + reason
	if player_score >= Rules.TARGET or ai_score >= Rules.TARGET:
		phase = "finished"
	else:
		phase = "point"
		point_delay = 1.35

func _prepare_serve(who: int) -> void:
	phase = "ready"
	server = who
	last_hitter = who
	player_x = 410
	ai_x = 1185
	player_jump = 0
	ai_jump = 0
	player_vy = 0
	ai_vy = 0
	player_move = 0
	ai_move = 0
	rally = 0
	player_cooldown = 0
	ai_cooldown = 0
	player_swing = 0
	ai_swing = 0
	player_swing_type = "underhand"
	ai_swing_type = "underhand"
	_player_contact = false
	_ai_contact = false
	_swing_buffer = 0
	_jump_buffer = 0
	_shot_direction = 0
	_hit_stop = 0
	miss_flash = 0
	velocity = Vector2.ZERO
	_ai_serve_wait = 1.15
	shuttle = Vector2(player_x + 35, GROUND - 98) if who == 0 else Vector2(ai_x - 35, GROUND - 98)
	toast = "轮到你发球 · 挥拍开始" if who == 0 else "小线准备发球"

func result() -> Dictionary:
	return {"match_id": match_id, "minigame_id": Rules.GAME_ID, "guest_id": "stick",
		"target_score": Rules.TARGET,
		"finish_reason": "target_score_reached", "player_score": player_score, "stick_score": ai_score,
		"outcome": "win" if player_score >= Rules.TARGET else "lose", "longest_rally": longest_rally,
		"player_legal_actions": player_actions, "assist_used": assist_used}
