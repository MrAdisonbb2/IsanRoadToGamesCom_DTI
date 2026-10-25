@tool
extends Control
## Opening scene of every new life: the village elder's little house. He asks the newborn hero
## to slay the demon lord; refusing gets the house blown up and this life lost on the spot.

const DialogScript := preload("res://scripts/dialog_box.gd")
const S := 3.0  # room art scale

var _room: Node2D
var _hero: AnimatedSprite2D
var _box


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("120c0a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_room = Room.new()
	_room.scale = Vector2(S, S)
	_room.position = Vector2(480 - 7 * 16 * S, 200)
	add_child(_room)
	var dung := Game.tex("tiles/dungeon.png")
	_room_prop(dung, Rect2(288, 256, 16, 16), Vector2(2.5, 2.2))
	_room_prop(dung, Rect2(240, 240, 32, 16), Vector2(7, 0.9))
	_room_prop(dung, Rect2(256, 255, 16, 17), Vector2(1.2, 6.6))
	_room_prop(dung, Rect2(272, 255, 16, 17), Vector2(12.8, 6.6))
	_room_prop(dung, Rect2(256, 285, 16, 19), Vector2(11.4, 2.2))
	var vil := Game.tex("props/village.png")
	_room_prop(vil, Rect2(208, 182, 16, 28), Vector2(12.6, 2.4))
	_room_prop(vil, Rect2(400, 103, 16, 25), Vector2(4.6, 1.6))
	# Hearth fire.
	var fire := CPUParticles2D.new()
	fire.position = Vector2(2.5 * 16, 1.8 * 16)
	fire.amount = 14
	fire.lifetime = 0.7
	fire.direction = Vector2.UP
	fire.spread = 25.0
	fire.gravity = Vector2(0, -10)
	fire.initial_velocity_min = 6.0
	fire.initial_velocity_max = 12.0
	fire.scale_amount_min = 1.0
	fire.scale_amount_max = 2.0
	fire.color = Color(1.0, 0.6, 0.2, 0.9)
	_room.add_child(fire)
	var elder := Game.npc_sprite("king", 1.0)
	elder.position = Vector2(9.5 * 16, 4.0 * 16)
	_room.add_child(elder)
	var cls: String = Game.slot().cls
	_hero = Game.hero_sprite(cls, 1.0)
	_hero.position = Vector2(5.5 * 16, 4.3 * 16)
	_room.add_child(_hero)
	if Engine.is_editor_hint():
		return
	Game.play_bgm("title")
	_play()


func _room_prop(tex: Texture2D, region: Rect2, cell: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.region_enabled = true
	s.region_rect = region
	s.position = cell * 16
	_room.add_child(s)


func _faces() -> Dictionary:
	var elder := AtlasTexture.new()
	elder.atlas = Game.tex("npcs/king.png")
	elder.region = Rect2(0, 0, 26, 36)
	var hero := AtlasTexture.new()
	hero.atlas = Game.tex(Game.CLASSES[Game.slot().cls].sheet)
	hero.region = Rect2(0, 0, 32, 32)
	return {"elder": elder, "hero": hero}


func _play() -> void:
	await get_tree().create_timer(0.8).timeout
	_box = DialogScript.new()
	_box.theme = get_tree().root.theme
	add_child(_box)
	var faces := _faces()
	var names := {"elder": "ตาแก่", "hero": Game.CLASSES[Game.slot().cls].name}
	await _box.say([
		["elder", "แกช่วยไป ช่วยไป..."],
		["hero", "...."],
		["elder", "ลืมแล้วอ่ะ"],
		["hero", "ฆ่า[color=yellow]จอมมาร[/color]เพื่อช่วยโลก"],
		["elder", "เอ่อใช่ๆ อันนั้นแหละ แกพอจะไปฆ่า[color=yellow]จอมมาร[/color]เพื่อช่วยโลกให้สงบสุขได้หรือป่าว"],
	], faces, names)
	var pick: int = await _box.choose(["ได้สิ", "ไม่เอา"])
	if pick == 0:
		await _box.say([["hero", "แน่นอนท่านผู้เฒ่า ฉันเบียวเกม RPG อยู่พอดี คนในหมู่บ้านต้องภูมิใจแน่ๆ"]], faces, names)
		_box.queue_free()
		var fade := ColorRect.new()
		fade.color = Color.BLACK
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade.modulate.a = 0.0
		add_child(fade)
		var tw := create_tween()
		tw.tween_property(fade, "modulate:a", 1.0, 0.7)
		await tw.finished
		Game.goto("stage_map")
		return
	_box.skippable = false
	await _box.say([
		["hero", "บ่"],
		["elder", "บักห่านี่แหม เลี้ยงเสียข้าวสุก [color=red]ตายซะ[/color] แกไม่สมควรเป็นคนในหมู่บ้านนี้"],
	], faces, names)
	# "Hey, wait-" gets cut off by the explosion.
	_box.say([["hero", "เฮ้ เดี๋ยวก่อน-"]], faces, names)
	await get_tree().create_timer(1.1).timeout
	_box.queue_free()
	await _explode()


func _explode() -> void:
	var flash := ColorRect.new()
	flash.color = Color.WHITE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.modulate.a = 0.0
	add_child(flash)
	for k in 8:
		var p := Vector2(randf_range(200, 760), randf_range(240, 500))
		Game.spawn_vfx(self, "explosion", p, randf_range(3.0, 5.0))
		Game.sfx("explosion")
		_room.position += Vector2(randf_range(-10, 10), randf_range(-8, 8))
		flash.modulate.a = 0.5 if k % 2 == 0 else 0.0
		await get_tree().create_timer(0.12).timeout
	_hero.play("die")
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 1.0, 0.25)
	tw.tween_property(flash, "color", Color.BLACK, 0.8)
	await tw.finished
	var msg := Game.label("บ้านระเบิด และเสียเซฟไปเลยฟรีๆ", 34, Color("ff6a6a"))
	msg.add_theme_constant_override("outline_size", 8)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.position = Vector2(0, 240)
	msg.size = Vector2(960, 60)
	add_child(msg)
	Game.sfx("bad")
	await get_tree().create_timer(2.2).timeout
	Game.die("บ้านระเบิดเพราะปฏิเสธผู้เฒ่า")
	Game.goto("ending")


## Floor and walls of the little wooden house (16px tiles, drawn at scale S by the parent).
class Room extends Node2D:
	func _draw() -> void:
		var t := Game.tex("tiles/dungeon.png")
		for y in range(0, 7):
			for x in range(0, 14):
				var reg := Vector2(0, 80) if (x * 7 + y * 3) % 5 else Vector2(16, 80)
				draw_texture_rect_region(t, Rect2(x * 16, y * 16, 16, 16), Rect2(reg, Vector2(16, 16)))
		for x in range(0, 14):
			draw_texture_rect_region(t, Rect2(x * 16, -16, 16, 16), Rect2(112, 128, 16, 16))
			draw_rect(Rect2(x * 16, -32, 16, 16), Color("1c140f"))
		draw_rect(Rect2(-6, -32, 6, 7 * 16 + 32), Color("1c140f"))
		draw_rect(Rect2(14 * 16, -32, 6, 7 * 16 + 32), Color("1c140f"))
		draw_rect(Rect2(-6, 7 * 16, 14 * 16 + 12, 6), Color("1c140f"))
		# Window light on the floor.
		draw_rect(Rect2(10 * 16, 0, 32, 112), Color(1.0, 0.9, 0.6, 0.08))
