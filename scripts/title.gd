@tool
extends Control
## Title screen: start -> save select.


func _ready() -> void:
	Game.play_bgm("title")
	Game.add_background(self, "backgrounds/title.png", "backgrounds/sil_castle.png")
	var lord := Game.enemy_sprite("demon_lord", 0.75)
	lord.position = Vector2(480, 290)
	lord.modulate = Color(1, 1, 1, 0.0)
	add_child(lord)
	var tw := lord.create_tween().set_loops()
	tw.tween_property(lord, "modulate:a", 0.55, 2.0)
	tw.tween_property(lord, "modulate:a", 0.25, 2.0)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var t := Game.label("Karma Loop", 64, Color("f5d76e"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 10)
	box.add_child(t)
	var sub := Game.label("เซฟเดียว · ชีวิตเดียว · ตายแล้วผนึกถาวร", 20, Game.C_TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 170)
	box.add_child(gap)
	for b in [Game.button("เริ่มเกม", func(): Game.goto("save_select"), 24), Game.button("ออกจากเกม", func(): get_tree().quit(), 18)]:
		b.custom_minimum_size = Vector2(240, 0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(b)
	var loop := Game.label("ลูปที่ %d" % Game.data.loop, 14, Game.C_DIM)
	loop.position = Vector2(12, 514)
	add_child(loop)
