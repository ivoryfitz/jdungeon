extends CharacterBody2D

class_name GMFEnemyBody2D

enum STATE { IDLE, MOVE, INTERACT, ATTACK, LOOT, NPC }

const ARRIVAL_DISTANCE = 8
const SPEED = 300.0

signal state_changed(new_state: STATE, direction: Vector2, duration: float)
signal attacked(target: String, damage: int)
signal got_hurt(from: String, hp: int, damage: int)

@export var peer_id := 1:
	set(id):
		peer_id = id

@export var enemy_class: String = "":
	set(new_class):
		enemy_class = new_class
		Gmf.register_enemy_scene(enemy_class, scene_file_path)

var entity_type: Gmf.ENTITY_TYPE = Gmf.ENTITY_TYPE.ENEMY

var state: String = "Idle"

var moving := false
var move_target := Vector2()

var server_synchronizer: Node2D

var hp: int = 100


func _ready():
	collision_layer = Gmf.PHYSICS_LAYER_WORLD + Gmf.PHYSICS_LAYER_ENEMIES

	if Gmf.is_server():
		collision_mask = Gmf.PHYSICS_LAYER_WORLD
	else:
		# Don't handle physics on client side
		collision_mask = 0

	server_synchronizer = load("res://gmf/common/scripts/serverSynchronizer.gd").new()
	server_synchronizer.name = "ServerSynchronizer"
	add_child(server_synchronizer)


func _physics_process(_delta):
	pass


func hurt(from: CharacterBody2D, damage: int):
	server_synchronizer.sync_hurt(from.name, hp, damage)
