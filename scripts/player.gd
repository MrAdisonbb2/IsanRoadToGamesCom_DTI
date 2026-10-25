@tool
extends CharacterBody2D
## Hero on the stage map. WASD moves, the mouse aims, holding M1 attacks,
## 1/2/3 cast the class skills from Game.CLASSES[cls].skills, Q drinks a potion, R an ether.

const SPEED := 82.0
const MP_REGEN := 1.2
const IFRAMES := 0.6

var world
var s: Dictionary
var cls := ""
var kit: Array = []
var spr: AnimatedSprite2D
var cd := [0.0, 0.0, 0.0, 0.0]
var mp := 0.0
var invuln := 0.0
var guard := 0.0
## Sin curse from an angry villager's bullets: slower and bleeding HP (never below 1).
var curse_t := 0.0
## Cutscenes walk the hero here (Vector2.INF = stand still).
var auto_target := Vector2.INF
## Parry (F): 0.2 s shield that blocks any hit and heals 20 HP. 7 s cooldown.
const PARRY_TIME := 0.2
const PARRY_CD := 7.0
const PARRY_HEAL := 20
var parry_t := 0.0
var parry_cd := 0.0
var _curse_tick := 0.0
var dead := false
var _dash_t := 0.0
var _dash_vel := Vector2.ZERO
var _dash_hit: Array = []
var _anim_t := 0.0
var _bob := 0.0


func setup(w, slot: Dictionary) -> void:
	world = w
	s = slot
	cls = s.cls
	kit = Game.CLASSES[cls].skills
	mp = float(s.mp)
	spr = Game.hero_sprite(cls, 1.0)
	spr.position = Vector2(0, -14)
	add_child(spr)
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 5.0
	col.shape = sh
	add_child(col)
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func hit_pos() -> Vector2:
	return global_position + Vector2(0, -10)


## Mouse in world space; in the window-mode boss fight it is mapped from the desktop.
func mouse_world() -> Vector2:
	if world.win_mode:
		return world.screen_to_world(Vector2(DisplayServer.mouse_get_position()))
	return get_global_mouse_position()


func aim() -> Vector2:
	var v := mouse_world() - hit_pos()
	return v.normalized() if v.length() > 1.0 else Vector2.RIGHT


func _move_dir() -> Vector2:
	var d := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	return d.normalized()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or dead or world == null:
		return
	if world.cutscene:
		_cutscene_walk(delta)
		return
	for i in 4:
		cd[i] = maxf(0.0, cd[i] - delta)
	invuln = maxf(0.0, invuln - delta)
	parry_cd = maxf(0.0, parry_cd - delta)
	if parry_t > 0.0:
		parry_t -= delta
		queue_redraw()
		if parry_t <= 0.0:
			queue_redraw()
	guard = maxf(0.0, guard - delta)
	# Thirst halves MP regeneration.
	var regen := MP_REGEN * (0.5 if float(s.get("water", 100.0)) <= 0.0 else 1.0)
	mp = minf(float(s.max_mp), mp + regen * delta)
	s.mp = int(mp)
	if curse_t > 0.0:
		curse_t -= delta
		_curse_tick += delta
		if _curse_tick >= 0.5:
			_curse_tick = 0.0
			s.hp = maxi(1, int(s.hp) - 1)
	spr.modulate = Color(1.0, 0.5, 1.2) if curse_t > 0.0 else Color(0.7, 0.85, 1.4) if guard > 0.0 else (Color(1, 1, 1, 0.5) if invuln > 0.0 and fmod(invuln, 0.12) < 0.06 else Color.WHITE)

	if _dash_t > 0.0:
		_dash_t -= delta
		velocity = _dash_vel
		move_and_slide()
		if cls == "knight":
			for e in world.enemies_near(hit_pos(), 18.0):
				if not _dash_hit.has(e):
					_dash_hit.append(e)
					world.damage_enemy(e, 2.2, false, _dash_vel.normalized() * 120.0)
		return

	_poll_keys()
	var dir := _move_dir()
	velocity = dir * SPEED * (0.6 if curse_t > 0.0 else 1.0)
	move_and_slide()
	spr.flip_h = aim().x < 0.0
	_anim_t = maxf(0.0, _anim_t - delta)
	if _anim_t <= 0.0:
		if spr.animation != "idle":
			spr.play("idle")
		# No walk row in the sheets, so walking is a small hop.
		_bob = _bob + delta * 14.0 if dir != Vector2.ZERO else 0.0
		spr.position.y = -14 - absf(sin(_bob)) * 2.0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not world.ui_blocking():
		cast(0)


func _cutscene_walk(delta: float) -> void:
	velocity = Vector2.ZERO
	if auto_target != Vector2.INF:
		var to := auto_target - global_position
		if to.length() > 2.0:
			velocity = to.normalized() * SPEED * 0.55
			spr.flip_h = to.x < 0.0
		else:
			auto_target = Vector2.INF
	move_and_slide()
	_bob = _bob + delta * 12.0 if velocity != Vector2.ZERO else 0.0
	spr.position.y = -14 - absf(sin(_bob)) * 2.0
	spr.modulate = Color.WHITE


const HOTKEYS := [KEY_1, KEY_2, KEY_3, KEY_Q, KEY_R, KEY_F]
var _held := {}


## Hotkeys are polled (not input events) so they also work while a boss-fight sub-window has focus.
func _poll_keys() -> void:
	for k in HOTKEYS:
		var down := Input.is_physical_key_pressed(k)
		if down and not _held.get(k, false) and not world.ui_blocking():
			match k:
				KEY_1:
					cast(1)
				KEY_2:
					cast(2)
				KEY_3:
					cast(3)
				KEY_Q:
					_potion()
				KEY_R:
					_ether()
				KEY_F:
					parry()
		_held[k] = down


func _play_attack() -> void:
	spr.play("attack")
	spr.position.y = -14
	_anim_t = 0.3


func cast(i: int) -> void:
	var sk: Dictionary = kit[i]
	if cd[i] > 0.0 or _dash_t > 0.0:
		return
	if mp < float(sk.mp):
		if i > 0:
			world.say_over(self, "MP ไม่พอ", Color("8fb4ff"))
			cd[i] = 0.3
		return
	mp -= float(sk.mp)
	cd[i] = float(sk.cd)
	_play_attack()
	var a := aim()
	var o := hit_pos()
	match cls + str(i):
		"knight0":
			Game.sfx("swing")
			world.fx_arc(o, a, 26.0, deg_to_rad(120), Color("fff2c0"))
			world.hit_arc(o, a, 28.0, deg_to_rad(120), 1.0, false)
		"knight1":
			Game.sfx("swing")
			_dash(a, 330.0, 0.22)
		"knight2":
			Game.sfx("swing")
			world.fx_ring(o, 38.0, Color("ffd27a"))
			world.hit_circle(o, 38.0, 1.6, false)
		"knight3":
			Game.sfx("heal")
			guard = 4.0
			_heal(roundi(float(s.max_hp) * 0.15))
		"ranger0":
			Game.sfx("swing")
			world.shoot(o, a, 300.0, 1.0, {"tex": "characters/ranger_projectile.png"})
		"ranger1":
			Game.sfx("swing")
			for k in [-0.22, 0.0, 0.22]:
				world.shoot(o, a.rotated(k), 300.0, 0.9, {"tex": "characters/ranger_projectile.png"})
		"ranger2":
			Game.sfx("swing")
			var d := _move_dir()
			_dash(d if d != Vector2.ZERO else a, 240.0, 0.25)
			invuln = maxf(invuln, 0.4)
		"ranger3":
			world.arrow_rain(mouse_world(), 30.0, 0.6, 5)
		"wizard0":
			Game.sfx("fire")
			world.shoot(o, a, 260.0, 1.0, {"tex": "characters/wizard_projectile.png"})
		"wizard1":
			Game.sfx("fire")
			world.shoot(o, a, 180.0, 1.8, {"tex": "characters/wizard_projectile.png", "scale": 1.8, "explode": 30.0, "ignore_def": true})
		"wizard2":
			Game.sfx("thunder")
			var to := mouse_world()
			var off := to - global_position
			if off.length() > 110.0:
				to = global_position + off.normalized() * 110.0
			to = world.nearest_open(to, global_position)
			Game.spawn_vfx(world, "magic", hit_pos(), 0.8)
			global_position = to
			Game.spawn_vfx(world, "magic", hit_pos(), 0.8)
			invuln = maxf(invuln, 0.3)
		"wizard3":
			Game.sfx("explosion")
			world.fx_ring(o, 52.0, Color("9fe8ff"))
			world.hit_circle(o, 52.0, 2.0, false, 2.5)


func _dash(dir: Vector2, speed: float, t: float) -> void:
	_dash_vel = dir.normalized() * speed
	_dash_t = t
	_dash_hit.clear()
	invuln = maxf(invuln, t)


func _heal(n: int) -> void:
	s.hp = mini(int(s.max_hp), int(s.hp) + n)
	Game.spawn_vfx(world, "heal", hit_pos(), 0.6)
	world.say_over(self, "+%d" % n, Game.C_GOOD)


## Q / R quick keys draw from the bag like using the item from the inventory.
func _potion() -> void:
	world.use_item("potion")


func _ether() -> void:
	world.use_item("ether")


func parry() -> void:
	if parry_cd > 0.0 or dead:
		return
	parry_t = PARRY_TIME
	parry_cd = PARRY_CD
	Game.sfx("swing")
	world.fx_ring(hit_pos(), 18.0, Color("8fe8ff"))
	queue_redraw()


func _draw() -> void:
	if parry_t > 0.0:
		var c := Vector2(0, -10)
		draw_circle(c, 15.0, Color(0.55, 0.9, 1.0, 0.25))
		draw_arc(c, 15.0, 0.0, TAU, 32, Color(0.75, 0.97, 1.0, 0.95), 2.0)


## Returns the damage actually taken, 0 when ignored, -1 when parried (blocked + healed).
func take_hit(power: float) -> int:
	if dead:
		return 0
	if parry_t > 0.0:
		s.hp = mini(int(s.max_hp), int(s.hp) + PARRY_HEAL)
		return -1
	if invuln > 0.0 or _dash_t > 0.0:
		return 0
	var d := maxi(1, roundi(power * randf_range(0.85, 1.15) - float(s.def) * 0.5))
	if guard > 0.0:
		d = maxi(1, roundi(d * 0.3))
	s.hp = maxi(0, int(s.hp) - d)
	invuln = IFRAMES
	spr.play("hurt")
	_anim_t = 0.25
	return d


func die() -> void:
	dead = true
	velocity = Vector2.ZERO
	spr.modulate = Color.WHITE
	spr.play("die")
