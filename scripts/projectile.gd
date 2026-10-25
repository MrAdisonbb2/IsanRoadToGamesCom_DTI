@tool
extends Node2D
## Straight-flying shot on the stage map. Hero shots damage monsters (optionally
## exploding), hostile shots damage the hero. Dies on walls and closed doors.

var world
var vel := Vector2.ZERO
var mult := 1.0
var hostile := false
var power := 0.0
var source := ""
var color := Color.WHITE
var radius := 4.0
var life := 1.6
var explode := 0.0
var ignore_def := false
var curse := false
## Hostile orbs that steer toward the hero for a while.
var homing_t := 0.0


func setup(w, opts: Dictionary) -> void:
	world = w
	if opts.has("tex"):
		var s := Sprite2D.new()
		s.texture = Game.tex(opts.tex)
		var sc: float = opts.get("scale", 1.0)
		s.scale = Vector2(sc, sc)
		add_child(s)
		radius = 4.0 * sc
	explode = opts.get("explode", 0.0)
	ignore_def = opts.get("ignore_def", false)
	rotation = vel.angle()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or world == null:
		return
	position += vel * delta
	life -= delta
	if life <= 0.0 or not world.is_open(position):
		_end()
		return
	if hostile and homing_t > 0.0 and world.player:
		homing_t -= delta
		var want: Vector2 = (world.player.hit_pos() - position).normalized() * vel.length()
		vel = vel.lerp(want, minf(1.0, 2.2 * delta))
	if hostile:
		var p = world.player
		if p and not p.dead and position.distance_to(p.hit_pos()) < radius + 5.0:
			world.hurt_player(power, source, curse)
			queue_free()
		return
	for e in world.enemies:
		if not e.dead and position.distance_to(e.hit_pos()) < radius + e.radius:
			if explode <= 0.0:
				world.damage_enemy(e, mult, ignore_def, vel.normalized() * 60.0)
			_end()
			return
	if explode <= 0.0 and world.shot_hits_npc(position, radius, mult):
		queue_free()


func _end() -> void:
	if explode > 0.0 and not hostile:
		Game.sfx("explosion")
		Game.spawn_vfx(world, "explosion", position, 1.2)
		world.hit_circle(position, explode, mult, ignore_def)
	queue_free()


func _draw() -> void:
	if hostile:
		draw_circle(Vector2.ZERO, radius + 1.5, Color(color, 0.35))
		draw_circle(Vector2.ZERO, radius, color)
		draw_circle(Vector2.ZERO, radius * 0.45, Color(1, 1, 1, 0.9))
