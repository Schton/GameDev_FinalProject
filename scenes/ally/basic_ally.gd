extends CharacterBody2D

enum Faction { PLAYER, ENEMY }
@export var faction = Faction.PLAYER  # ally default

# =====================================================
# ADVANCED SOULSLIKE ENEMY AI (Godot 4)
# Features:
# - Idle patrol
# - Aggro detection
# - Chase player
# - Strafe / surround player
# - Attack combos
# - Cooldowns
# - Hit stun
# - Knockback
# - Return home if player escapes
# - Multi-enemy attack slot system
# =====================================================

enum State {
	FOLLOW,
	ENGAGE,
	IDLE,
	PATROL,
	CHASE,
	STRAFE,
	ATTACK,
	STUN,
	DEAD,
	RETURN_HOME
}

var player
var state = State.FOLLOW
var offset = Vector2.ZERO

# ==========================
# SETTINGS
# ==========================

@export var move_speed := 130.0
@export var detect_range := 420.0
@export var lose_range := 700.0
@export var attack_range := 55.0
@export var strafe_range := 95.0

@export var max_health := 100
@export var attack_damage := 15

@export var attack_cooldown := 1.2
@export var stun_time := 0.35

# ==========================
# REFERENCES
# ==========================
@onready var anim = $AnimatedSprite2D
var target

# ==========================
# RUNTIME
# ==========================
var health := 100
var facing_dir := Vector2.DOWN
var last_move_dir := Vector2.DOWN
var spawn_position := Vector2.ZERO
var attack_dir := Vector2.DOWN

var can_attack := true
var strafe_dir := 1
var stun_timer := 0.0
var attack_timer := 0.0

var current_anim := ""

# =====================================================
# READY
# =====================================================
func _ready():
	health = max_health
	spawn_position = global_position
	target = get_tree().get_first_node_in_group("player")
	add_to_group("units")

	player = get_tree().get_first_node_in_group("player")

	# Assign random formation offset
	offset = Vector2(randf_range(-60, 60), randf_range(-60, 60))

	randomize()

# =====================================================
# MAIN LOOP
# =====================================================
func _physics_process(delta):

	if target == null or not is_instance_valid(target):
		find_target()
		if target == null:
			return

		if player == null:
			return

	match state:

		State.FOLLOW:
			state_follow()

		State.ENGAGE:
			state_engage()

		State.IDLE:
			state_idle()

		State.PATROL:
			state_patrol()

		State.CHASE:
			state_chase()

		State.STRAFE:
			state_strafe()

		State.ATTACK:
			state_attack()

		State.STUN:
			state_stun(delta)

		State.RETURN_HOME:
			state_return_home()

		State.DEAD:
			velocity = Vector2.ZERO

	if velocity.length() < 5:
		velocity = Vector2.ZERO

	move_and_slide()
	update_animation()

# =====================================================
# STATES
# =====================================================

func state_follow():

	var desired_pos = player.global_position + offset
	var dist = global_position.distance_to(desired_pos)

	if dist > 10:
		var dir = global_position.direction_to(desired_pos)
		velocity = (dir * move_speed) + separation_force()
	else:
		velocity = Vector2.ZERO

	find_target()

	if target != null and distance_to_target() < detect_range:
		state = State.ENGAGE

func state_engage():

	if not is_instance_valid(target):
		state = State.FOLLOW
		return

	var dist = distance_to_target()
	var dir = direction_to_target()

	if dist > detect_range:
		target = null
		state = State.FOLLOW
		return

	if dist <= attack_range:
		try_attack()
		return

	velocity = dir * move_speed + separation_force()


func state_idle():
	velocity = Vector2.ZERO

	if distance_to_target() < detect_range:
		state = State.CHASE

func state_patrol():
	velocity = Vector2.ZERO

func state_chase():

	var dist = distance_to_target()
	var dir = direction_to_target()

	if dist > lose_range:
		state = State.RETURN_HOME
		return

	if dist <= attack_range:
		try_attack()
		return

	if dist <= strafe_range:
		state = State.STRAFE
		return

	velocity = (dir * move_speed) + apply_separation()
	velocity = velocity.limit_length(move_speed)
	last_move_dir = dir

func state_strafe():

	if not is_instance_valid(target):
		state = State.CHASE
		return

	var to_target = direction_to_target()
	var dist = distance_to_target()

	# --- ORBIT SETTINGS ---
	var desired_radius = strafe_range
	var orbit_speed = move_speed * 0.9
	var radius_tolerance = 8.0

	# --- 1. TANGENTIAL (circle movement) ---
	var tangent = to_target.rotated(deg_to_rad(90 * strafe_dir))

	# --- 2. RADIAL CORRECTION (stay in ring) ---
	var radial_force = Vector2.ZERO

	if dist > desired_radius + radius_tolerance:
		radial_force = -to_target * move_speed * 0.6
	elif dist < desired_radius - radius_tolerance:
		radial_force = to_target * move_speed * 0.6

	# --- COMBINE ---
	var sep = apply_separation() * 0.6
	velocity = (tangent * orbit_speed) + radial_force + sep
	velocity = velocity.limit_length(move_speed)

	# --- FACE TARGET (VERY IMPORTANT) ---
	last_move_dir = to_target

	# --- RANDOM ORBIT DIRECTION CHANGE (RARE) ---
	if randf() < 0.005:
		strafe_dir *= -1

	# --- ATTACK CHECK ---
	if dist <= attack_range:
		try_attack()

func state_attack():
	velocity = Vector2.ZERO

func state_stun(delta):
	velocity = Vector2.ZERO

	stun_timer -= delta
	if stun_timer <= 0:
		state = State.CHASE

func state_return_home():

	var dist = global_position.distance_to(spawn_position)

	if dist < 10:
		state = State.IDLE
		return

	var dir = global_position.direction_to(spawn_position)
	velocity = (dir * move_speed) + apply_separation()
	velocity = velocity.limit_length(move_speed)
	last_move_dir = dir

# =====================================================
# ATTACK SYSTEM
# =====================================================

func try_attack():

	if not can_attack:
		state = State.STRAFE
		return

	var attackers = get_tree().get_nodes_in_group("attackers")

	# max 2 enemies attack simultaneously
	if attackers.size() >= 2:
		state = State.STRAFE
		return

	start_attack()

func start_attack():

	state = State.ATTACK
	can_attack = false
	add_to_group("attackers")

	velocity = Vector2.ZERO

	attack_dir = direction_to_target()
	anim.play("attack_" + get_dir(attack_dir))

	# Wait for animation
	await anim.animation_finished

	# DAMAGE CHECK
	if distance_to_target() <= attack_range + 10:
		if target.has_method("take_damage") and target.faction != faction:
			target.take_damage(attack_damage)

	remove_from_group("attackers")

	state = State.CHASE

	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func find_target():
	var units = get_tree().get_nodes_in_group("units")

	var closest = null
	var closest_dist = INF

	for u in units:
		if u == self:
			continue
		if not u.has_method("take_damage"):
			continue
		if u.faction == faction:
			continue

		var d = global_position.distance_to(u.global_position)
		if d < closest_dist:
			closest = u
			closest_dist = d

	target = closest

# =====================================================
# DAMAGE / HITSTUN
# =====================================================

func take_damage(amount, knock_dir := Vector2.ZERO):
	if state == State.DEAD:
		return

	health -= amount

	if health <= 0:
		die()
		return

	state = State.STUN
	stun_timer = stun_time

	velocity = knock_dir * 220

	anim.play("hurt_" + get_dir(direction_to_target()))
	print("Enemy HP:", health)

func die():

	state = State.DEAD
	velocity = Vector2.ZERO
	anim.play("death")

	await anim.animation_finished
	queue_free()

# =====================================================
# HELPERS
# =====================================================

func distance_to_target():
	return global_position.distance_to(target.global_position)

func direction_to_target():
	return global_position.direction_to(target.global_position)

func update_animation():

	if state == State.ATTACK or state == State.STUN or state == State.DEAD:
		return

	var next_anim

	if velocity.length() > 10:
		next_anim = "walk_" + get_dir(last_move_dir)
	else:
		next_anim = "idle_" + get_dir(last_move_dir)

	if current_anim != next_anim:
		anim.play(next_anim)
		current_anim = next_anim

func get_dir(dir: Vector2) -> String:

	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"

	return "front" if dir.y > 0 else "back"

func apply_separation():
	var units = get_tree().get_nodes_in_group("units")
	var push = Vector2.ZERO

	for u in units:
		if u == self:
			continue

		var dist = global_position.distance_to(u.global_position)
		if dist < 32:
			push += (global_position - u.global_position).normalized()

	return push * 25

# =========================
# SEPARATION (ANTI-CLUMP)
# =========================

func separation_force():

	var units = get_tree().get_nodes_in_group("units")
	var push = Vector2.ZERO

	for u in units:
		if u == self:
			continue

		var dist = global_position.distance_to(u.global_position)

		if dist < 32:
			push += (global_position - u.global_position).normalized()

	return push * 60
