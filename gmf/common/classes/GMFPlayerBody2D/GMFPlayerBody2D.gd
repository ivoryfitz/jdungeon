extends CharacterBody2D

class_name GMFPlayerBody2D

enum STATE { IDLE, MOVE, INTERACT, ATTACK, LOOT, NPC }
enum INTERACT_TYPE { ENEMY, NPC, ITEM }

const ARRIVAL_DISTANCE = 8
const SPEED = 300.0

signal state_changed(new_state: STATE, direction: Vector2, duration: float)
signal attacked(target: String, damage: int)
signal got_hurt(from: String, hp: int, damage: int)

@export var peer_id := 1:
	set(id):
		peer_id = id

var entity_type

var username: String = ""

var state: STATE = STATE.IDLE

var server_synchronizer: Node2D
var stats: Node

var mouse_area: Area2D

var moving: bool = false
var move_target: Vector2 = Vector2()

var interacting: bool = false
var interact_target: Variant = null
var interact_type: INTERACT_TYPE = INTERACT_TYPE.ENEMY

var enemies_in_attack_range: Array = []

var attack_timer: Timer


func _input(event):
	if event.is_action_pressed("gmf_right_click"):
		# move(get_global_mouse_position())
		_handle_right_click()


func _ready():
	entity_type = Gmf.ENTITY_TYPE.PLAYER

	collision_layer = Gmf.PHYSICS_LAYER_WORLD + Gmf.PHYSICS_LAYER_PLAYERS

	if Gmf.is_server():
		collision_mask = Gmf.PHYSICS_LAYER_WORLD
	else:
		# Don't handle physics on client side
		collision_mask = 0

	server_synchronizer = load("res://gmf/common/scripts/serverSynchronizer.gd").new()
	server_synchronizer.name = "ServerSynchronizer"
	add_child(server_synchronizer)

	stats = load("res://gmf/common/classes/GMFPlayerBody2D/stats.gd").new()
	stats.name = "Stats"
	add_child(stats)

	if Gmf.is_server():
		# Don't handle input on server side
		set_process_input(false)

		var attack_area = Area2D.new()
		attack_area.name = "AttackArea"
		attack_area.collision_layer = 0
		attack_area.collision_mask = Gmf.PHYSICS_LAYER_ENEMIES

		var cs_attack_area = CollisionShape2D.new()
		cs_attack_area.name = "AttackAreaCollisionShape2D"
		attack_area.add_child(cs_attack_area)

		var cs_attack_area_circle = CircleShape2D.new()

		cs_attack_area_circle.radius = 64.0
		cs_attack_area.shape = cs_attack_area_circle

		add_child(attack_area)

		attack_area.body_entered.connect(_on_attack_area_body_entered)
		attack_area.body_exited.connect(_on_attack_area_body_exited)

		Gmf.signals.server.player_moved.connect(_on_player_moved)
		Gmf.signals.server.player_interacted.connect(_on_player_interacted)

		attack_timer = Timer.new()
		attack_timer.name = "AttackTimer"

		attack_timer.timeout.connect(_on_attack_timer_timeout)
		add_child(attack_timer)

	else:
		mouse_area = Area2D.new()
		mouse_area.name = "MouseArea"
		mouse_area.collision_layer = 0
		mouse_area.collision_mask = (
			Gmf.PHYSICS_LAYER_PLAYERS
			+ Gmf.PHYSICS_LAYER_ENEMIES
			+ Gmf.PHYSICS_LAYER_NPCS
			+ Gmf.PHYSICS_LAYER_ITEMS
		)
		var cs_mouse_area = CollisionShape2D.new()
		cs_mouse_area.name = "MouseAreaCollisionShape2D"
		mouse_area.add_child(cs_mouse_area)

		var cs_mouse_area_circle = CircleShape2D.new()

		cs_mouse_area_circle.radius = 1.0
		cs_mouse_area.shape = cs_mouse_area_circle

		add_child(mouse_area)


func _physics_process(delta: float):
	if Gmf.is_server():
		logic(delta)

		move_and_slide()


func logic(_delta: float):
	if moving:
		if position.distance_to(move_target) > ARRIVAL_DISTANCE:
			velocity = position.direction_to(move_target) * SPEED
			set_new_state(STATE.MOVE)
		else:
			moving = false
			velocity = Vector2.ZERO
	elif interacting:
		if not is_instance_valid(interact_target):
			interacting = false
			interact_target = null
			return

		match interact_type:
			INTERACT_TYPE.ENEMY:
				if not enemies_in_attack_range.has(interact_target):
					velocity = position.direction_to(interact_target.position) * SPEED
					set_new_state(STATE.MOVE)
				else:
					velocity = Vector2.ZERO

					if attack_timer.is_stopped():
						_attack(interact_target)
						attack_timer.start(0.8)

					set_new_state(STATE.ATTACK)
			INTERACT_TYPE.NPC:
				set_new_state(STATE.NPC)
			INTERACT_TYPE.ITEM:
				set_new_state(STATE.LOOT)
	else:
		set_new_state(STATE.IDLE)


func set_new_state(new_state: STATE):
	if state != new_state:
		state = new_state
		server_synchronizer.sync_state(state, Vector2.ZERO, 0.0)


func move(pos: Vector2):
	server_synchronizer.move.rpc_id(1, pos)


func interact(target: String):
	server_synchronizer.interact.rpc_id(1, target)


func _attack(target: CharacterBody2D):
	var damage = randi_range(stats.attack_power_min, stats.attack_power_max)

	target.hurt(self, damage)
	server_synchronizer.sync_attack(target.name, damage)


func hurt(from: CharacterBody2D, damage: int):
	# # Reduce the damage according to the defense stat
	var reduced_damage = max(0, damage - stats.defense)

	# # Deal damage if health pool is big enough
	if reduced_damage < stats.hp:
		stats.hp -= reduced_damage
		server_synchronizer.sync_hurt(from.name, stats.hp, reduced_damage)
	# # Die if damage is bigger than remaining hp
	else:
		print("I'm dead")
		# die()

	# update_hp_bar()


func _handle_right_click():
	mouse_area.set_global_position(get_global_mouse_position())

	#The following awaits ensure that the collision cycle has occurred before calling
	#the get_overlapping_bodies function
	await get_tree().physics_frame
	await get_tree().physics_frame

	#Get the bodies under the mouse area
	var bodies = mouse_area.get_overlapping_bodies()

	#Move if nothing is under the mouse area
	if bodies.is_empty():
		move(get_global_mouse_position())
	else:
		#TODO: not sure if this needs to be improved, just take the first
		var target = bodies[0]
		if target != self:
			interact(target.name)


func _on_attack_area_body_entered(body):
	if not enemies_in_attack_range.has(body):
		enemies_in_attack_range.append(body)


func _on_attack_area_body_exited(body):
	if enemies_in_attack_range.has(body):
		enemies_in_attack_range.erase(body)


func _on_player_moved(id: int, pos: Vector2):
	if id != peer_id:
		return

	interacting = false

	moving = true
	move_target = pos


func _on_player_interacted(id: int, target: String):
	if id != peer_id:
		return

	moving = false

	if Gmf.world.enemies.has_node(target):
		interacting = true
		interact_target = Gmf.world.enemies.get_node(target)
		interact_type = INTERACT_TYPE.ENEMY
		return

	if Gmf.world.npcs.has_node(target):
		interacting = true
		interact_target = Gmf.world.npcs.get_node(target)
		interact_type = INTERACT_TYPE.NPC
		return

	if Gmf.world.items.has_node(target):
		interacting = true
		interact_target = Gmf.world.items.get_node(target)
		interact_type = INTERACT_TYPE.ITEM
		return


func _on_attack_timer_timeout():
	attack_timer.stop()
