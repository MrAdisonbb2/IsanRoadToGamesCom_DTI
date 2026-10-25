@tool
extends Control
## Save select: 3 one-life slots. An empty slot = be born now with a random class.
## A dead slot is sealed and cannot be opened or deleted until the cycle ends.
## The ending scene sits at the bottom, showing the shared demon lord HP.


func _ready() -> void:
	Game.play_bgm("title")
	Game.add_background(self, "backgrounds/saves.png", "", Color(0.8, 0.8, 0.9))
	var head := Game.label("เลือกเซฟ  ·  มีชีวิตได้ทีละหนึ่ง ตายแล้วจึงเกิดใหม่ในเซฟถัดไป", 20, Color("f5d76e"))
	head.position = Vector2(20, 12)
	add_child(head)
	var back := Game.button("กลับ", func(): Game.goto("title"), 14)
	back.position = Vector2(872, 10)
	add_child(back)
	for i in Game.SLOT_COUNT:
		var card := _slot_card(i)
		card.position = Vector2(20 + i * 315, 44)
		card.size = Vector2(290, 236)
		add_child(card)
	var ending := _ending_panel()
	ending.position = Vector2(20, 306)
	ending.size = Vector2(920, 222)
	add_child(ending)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	# Developer reset for testing: Ctrl+Shift+R wipes every save.
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and event.ctrl_pressed and event.shift_pressed:
		Game.data = Game.new_data()
		Game.save_game()
		get_tree().reload_current_scene()


func _slot_card(i: int) -> PanelContainer:
	var s: Dictionary = Game.data.slots[i]
	var card := PanelContainer.new()
	var dead: bool = s.state == "dead"
	card.add_theme_stylebox_override("panel", Game.panel_style(Color("1c1820") if dead else Game.C_PANEL, Color("5a5266") if dead else Game.C_BORDER))
	var v := VBoxContainer.new()
	card.add_child(v)
	v.add_child(Game.label("เซฟ %d" % (i + 1), 22, Game.C_DIM if dead else Color("f5d76e")))
	var stage_holder := Control.new()
	stage_holder.custom_minimum_size = Vector2(0, 66)
	v.add_child(stage_holder)
	var info := Game.label("", 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(260, 60)
	v.add_child(info)
	var btn: Button
	match s.state:
		"empty":
			var q := Game.label("?", 48, Game.C_DIM)
			q.position = Vector2(122, 0)
			stage_holder.add_child(q)
			info.text = "ชีวิตที่ยังไม่ถือกำเนิด\nกรรมที่จะติดตัว: %s" % Game.karma_text(int(Game.data.karma))
			btn = Game.button("ถือกำเนิด", func():
				Game.birth(i)
				Game.goto("class_reveal"))
			# One life at a time: the next one can only be born after the current hero dies.
			if Game.has_living():
				btn.disabled = true
				btn.text = "รอชีวิตปัจจุบันจบก่อน"
				btn.tooltip_text = "เกิดใหม่ได้เมื่อตัวละครที่ยังมีชีวิตอยู่ตายแล้วเท่านั้น"
				info.text = "ชีวิตที่ยังไม่ถือกำเนิด\nจะเกิดได้หลังชีวิตปัจจุบันตาย"
		"active":
			var spr := Game.hero_sprite(s.cls, 3.0)
			spr.position = Vector2(135, 30)
			stage_holder.add_child(spr)
			info.text = "%s Lv%d · HP %d/%d\n%s" % [Game.CLASSES[s.cls].name, s.lv, s.hp, s.max_hp, Game.STAGES[int(s.stage)].name]
			btn = Game.button("เล่นต่อ", func():
				Game.slot_index = i
				Game.goto("stage_map"))
		"dead":
			var spr := Game.hero_sprite(s.cls, 3.0)
			spr.play("die")
			spr.frame = spr.sprite_frames.get_frame_count("die") - 1
			spr.pause()
			spr.position = Vector2(110, 22)
			spr.modulate = Color(0.5, 0.5, 0.6)
			stage_holder.add_child(spr)
			var sk := Game.icon("icons/skull.png", 40)
			sk.position = Vector2(170, 8)
			stage_holder.add_child(sk)
			info.text = "ผนึกแล้ว · %s Lv%d\nตายที่ %s\nสาเหตุ: %s" % [Game.CLASSES[s.cls].name, s.lv, Game.STAGES[int(s.died_stage)].name, s.cause]
			info.add_theme_color_override("font_color", Game.C_DIM)
			btn = Button.new()
			btn.text = "ล็อก · ลบหรือแก้ไม่ได้"
			btn.disabled = true
			btn.tooltip_text = "ปลดผนึกได้เมื่อมีคนปราบจอมมาร หรือทุกเซฟตายหมด"
	v.add_child(btn)
	return card


func _ending_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Game.panel_style(Color("140f1c")))
	var stage := Control.new()
	stage.clip_contents = true
	p.add_child(stage)
	var bg := TextureRect.new()
	bg.texture = Game.tex("backgrounds/stage3.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.45, 0.35, 0.5)
	stage.add_child(bg)
	var sil := Sprite2D.new()
	sil.texture = Game.tex("backgrounds/sil_spikes.png")
	sil.centered = false
	sil.scale = Vector2(2.9, 2.0)
	sil.position = Vector2(0, 208 - sil.texture.get_height() * 2)
	sil.modulate = Color(0, 0, 0, 0.8)
	stage.add_child(sil)

	stage.add_child(_pos(Game.label("ฉากจบ", 18, Color("f5d76e")), Vector2(4, 0)))
	var lord := Game.enemy_sprite("demon_lord", 0.62)
	lord.position = Vector2(840, 100)
	stage.add_child(lord)
	var hb := Game.bar(Color("9b3fd1"), 200, 14)
	hb.max_value = Game.BOSS_MAX_HP
	hb.value = Game.data.boss_hp
	stage.add_child(_pos(hb, Vector2(560, 150)))
	stage.add_child(_pos(Game.label("%s  เฟส %d/3 · %d%%" % [Game.boss_title(), Game.boss_phase(), roundi(float(Game.data.boss_hp) / Game.BOSS_MAX_HP * 100)], 15, Color("d9a0ff")), Vector2(560, 126)))

	# The three lives marching toward the throne.
	for i in Game.SLOT_COUNT:
		var s: Dictionary = Game.data.slots[i]
		var x := 80 + i * 150
		if s.state == "empty":
			stage.add_child(_pos(Game.label("เซฟ %d\n(ยังไม่เกิด)" % (i + 1), 13, Game.C_DIM), Vector2(x - 30, 100)))
			continue
		var spr := Game.hero_sprite(s.cls, 2.5)
		spr.position = Vector2(x, 118)
		if s.state == "dead":
			spr.play("die")
			spr.frame = spr.sprite_frames.get_frame_count("die") - 1
			spr.pause()
			spr.modulate = Color(0.45, 0.45, 0.55)
		stage.add_child(spr)
		var dmg := Game.label("ตีบอส %d" % s.boss_dmg, 13, Game.C_DIM)
		stage.add_child(_pos(dmg, Vector2(x - 30, 156)))

	var text := ""
	match Game.data.last_ending:
		"victory":
			text = "ฉากจบล่าสุด: ผู้กล้าปราบจอมมาร... แล้วกลายเป็นจอมมารตนใหม่ (ลูปที่ %d)" % Game.data.loop
		"all_dead":
			text = "ฉากจบล่าสุด: สามชีวิตดับสูญ จอมมารฟื้นพลังเต็ม"
		_:
			text = "ปราบจอมมารเพื่อปลดผนึกทุกเซฟ · ความเสียหายต่อบอสคงอยู่ข้ามเซฟ"
	var tl := Game.label(text, 15)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(640, 0)
	stage.add_child(_pos(tl, Vector2(70, 26)))
	return p


func _pos(c: Control, at: Vector2) -> Control:
	c.position = at
	return c
