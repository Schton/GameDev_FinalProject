extends CharacterBody2D

enum Faction { PLAYER, ENEMY }
@export var faction = Faction.ENEMY  # enemy default

var current_duelist: CharacterBody2D = null # The person currently fighting me
@export var is_ally := false # Set true for followers, false for enemies

@export var strafe_time_limit := 2.5 # How long they circle before charging back in
@export var hits_to_trigger_strafe := 2 # How many hits they take before backing off

signal unit_died(pos)

var strafe_timer := 0.0
var hits_taken_recently := 0

var is_attacking_anim := false
var think_offset = randi() % 120

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
	IDLE,
	PATROL,
	CHASE,
	STRAFE,
	ATTACK,
	STUN,
	DEAD,
	RETURN_HOME
}

var state = State.IDLE

# ==========================
# SETTINGS
# ==========================
@export var move_speed := 130.0
@export var detect_range := 420.0
@export var lose_range := 700.0
@export var attack_range := 55.0
@export var strafe_range := 70.0

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

	randomize()

# =====================================================
# MAIN LOOP
# =====================================================
func _physics_process(delta):

	if target == null or not is_instance_valid(target):
		find_target()

# If STILL no target, just idle safely
	if target == null:
		velocity = Vector2.ZERO
		move_and_slide()
		update_animation()
		return

	match state:
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

	if state != State.STUN and state != State.DEAD:
	# Every 2 seconds, allow the enemy to re-evaluate their target 
	# in case the player has gotten much closer than the current duelist
		if (Engine.get_frames_drawn() + think_offset) % 120 == 0:
			find_target()

	if velocity.length() < 5:
		velocity = Vector2.ZERO

# === PUSH LOGIC ===
	# Check all collisions that happened during move_and_slide()
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()    
		# If the player is the one who hit us
		if collider is CharacterBody2D and "faction" in collider:
			if collider.faction == Faction.PLAYER and not is_ally:
					# Apply a slight shove in the direction the player is moving
				velocity += collider.velocity * 0.5 
			elif collider.faction == Faction.PLAYER and is_ally:
					# Allies are easier to push (friendliness!)
				velocity += collider.velocity * 0.8

	move_and_slide()
	update_animation()

# =====================================================
# STATES
# =====================================================

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

	# 1. ALWAYS check for attack first if in range
	if dist <= attack_range + 5:
		try_attack()
		return

	# 2. Check for strafing ONLY if we are in strafe range AND have been hit
	if dist <= strafe_range:
		# 10% chance every frame to start strafing instead of charging blindly
		if randf() < 0.01 or hits_taken_recently >= hits_to_trigger_strafe:
			state = State.STRAFE
			strafe_timer = strafe_time_limit
			return
		# If we haven't been hit enough, we DON'T return; 
		# we let the code fall through to the movement logic below.

	# 3. Movement logic
	velocity = (dir * move_speed) + apply_separation()
	velocity = velocity.limit_length(move_speed)
	last_move_dir = dir

func state_strafe():
	if not is_instance_valid(target):
		state = State.CHASE
		return

	var health_pct = float(health) / max_health

# --- TIMER LOGIC ---
	strafe_timer -= get_physics_process_delta_time()
	if strafe_timer <= 0:
		hits_taken_recently = 0 # Reset hit counter to be aggressive again
		state = State.CHASE
		return

	var to_target = direction_to_target()
	var dist = distance_to_target()

	# --- ORBIT SETTINGS ---
	var desired_radius = 65.0 
	var push_weight = 0.2     

	if health_pct < 0.3:
		desired_radius = 110.0 # Back up even further than 90
		push_weight = 0.8      # Retreat much faster

	var orbit_speed = move_speed * 0.8
	
	# 1. Calculate the raw sideways vector
	var tangent = to_target.rotated(deg_to_rad(90 * strafe_dir))
	
	# 2. BLEND: Instead of just going sideways, we mix in a "Seek" vector
	# If they are too far, they steer significantly toward the player while orbiting
	var spiral_dir = tangent # Default to pure sideways
	
	if dist > desired_radius:
		# PULL IN: Same as your current logic
		var weight = clamp((dist - desired_radius) / 20.0, 0.0, 1.0)
		spiral_dir = tangent.lerp(-to_target, weight).normalized()
	elif dist < desired_radius - 10.0:
		# PUSH BACK: This is where you control the "Back Off"
		# Increase the 0.5 to push back harder, or decrease it to drift back slowly
		spiral_dir = tangent.lerp(to_target, push_weight).normalized()

	# 3. SEPARATION: Keep this very low during strafe so it doesn't push them out
	var sep = apply_separation() * 0.2 

	velocity = (spiral_dir * orbit_speed) + sep

	# Face target
	last_move_dir = to_target

	# Randomly change direction
	if randf() < 0.005:
		strafe_dir *= -1

	# ATTACK CHECK (Close the gap if they are in range)
	if dist <= attack_range + 5:
		try_attack()
	elif dist > detect_range: # If they somehow drift too far, go back to chase
		state = State.CHASE

func state_attack():
	velocity = Vector2.ZERO

func state_stun(delta):
	velocity = Vector2.ZERO

	stun_timer -= delta
	if stun_timer <= 0:
# Instead of going straight to CHASE, decide based on hits
		if hits_taken_recently >= hits_to_trigger_strafe:
			state = State.STRAFE
			strafe_timer = strafe_time_limit
		else:
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

	is_attacking_anim = true

	attack_dir = direction_to_target()
	anim.play("attack_" + get_dir(attack_dir))

	# DAMAGE TIMING (instead of waiting whole animation)
	await get_tree().create_timer(0.15).timeout

	# Apply damage mid-swing
	if is_instance_valid(target) and distance_to_target() <= attack_range + 10:
		if target.has_method("take_damage") and target.faction != faction:
			target.take_damage(attack_damage, attack_dir, self)

	# Finish animation WITHOUT blocking
	await get_tree().create_timer(0.2).timeout

	is_attacking_anim = false

	remove_from_group("attackers")

	state = State.CHASE

	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func find_target():
	var units = get_tree().get_nodes_in_group("units")
	var best_target = null
	var best_score = INF # Lower score is better

	for u in units:
		if u == self: continue
		if not is_instance_valid(u):
			continue
		if "state" in u and u.state == State.DEAD:
			continue
		if u.faction == faction: continue # Don't hit friends

		var dist = global_position.distance_to(u.global_position)
		var score = dist

		# 1. Identify Target Type
		var is_target_player = (u.faction == Faction.PLAYER and u.get("is_ally") == false)

		# 2. Ally Priority (If I am an Enemy, I want to fight the Player's Allies)
		if not is_target_player and u.get("current_duelist") == null:
			score -= 200.0 # Huge discount for free targets
		
		# 3. Duel Penalty
		if u.get("current_duelist") != null and u.current_duelist != self:
			if not is_target_player:
				score += 500.0 # Don't interrupt other duels

		if score < best_score:
			best_score = score
			best_target = u

	# 5. Assignment
	if best_target != target:
		# Clean up old duel reference
		if is_instance_valid(target) and target.get("current_duelist") == self:
			target.current_duelist = null
			
		target = best_target
		
		# Lock into the new duel
		if is_instance_valid(target) and "current_duelist" in target:
			target.current_duelist = self

# =====================================================
# DAMAGE / HITSTUN
# =====================================================

func take_damage(amount, knock_dir := Vector2.ZERO, attacker = null):
	if state == State.DEAD:
		return

	var final_damage = amount
	if attacker and attacker.faction != Faction.PLAYER:
		final_damage = amount * 0.5 # AI deals 50% less damage to each other

	health -= final_damage

# INTERVENTION LOGIC:
	# If the player hits us, drop the current duel and target the player
	if attacker and "faction" in attacker and attacker.faction == Faction.PLAYER:
		if is_instance_valid(target) and "current_duelist" in target:
			target.current_duelist = null
		target = attacker
		state = State.CHASE # Force switch to player pursuit

		await get_tree().create_timer(1.5).timeout
		find_target()

	if health <= 0:
		die()
		return

	state = State.STUN
	stun_timer = stun_time

	velocity = knock_dir * 220

	# anim.play("hurt_" + get_dir(direction_to_target()))
	print("Enemy HP:", health)

func die():
	unit_died.emit(global_position)

	state = State.DEAD

	if is_instance_valid(target) and "current_duelist" in target:
		target.current_duelist = null

	velocity = Vector2.ZERO
	anim.play("death")

	await anim.animation_finished

# Notify all units that this one is gone
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		if not u.has_method("distance_to_target"): # or check variable instead
			continue
		if "target" in u and u.target == self:
			u.target = null

	queue_free()

# =====================================================
# HELPERS
# =====================================================

func distance_to_target():
	if target == null or not is_instance_valid(target):
		return INF
	return global_position.distance_to(target.global_position)

func direction_to_target():
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	return global_position.direction_to(target.global_position)

func update_animation():

	if is_attacking_anim:
		return

	if state == State.STUN or state == State.DEAD:
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
		if dist < 25: # Smaller radius
		# The further away they are, the less they push
			var strength = 1.0 - (dist / 25.0)
			push += (global_position - u.global_position).normalized() * strength

	return push * 15.0 # Lowered multiplier
