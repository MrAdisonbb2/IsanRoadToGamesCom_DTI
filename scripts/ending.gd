@tool
extends Control
## Death screen, total-wipe ending, and the true ending where the hero becomes the new lord.

var _text: Label
var _btn: Button


func _ready() -> void:
	Game.play_bgm("ending")
	Game.add_background(self, "backgrounds/stage3.png", "backgrounds/sil_spikes.png", Color(0.35, 0.3, 0.4))
	var panel := PanelContainer.new()
	panel.position = Vector2(140, 330)
	panel.size = Vector2(680, 150)
	add_child(panel)
	_text = Game.label("", 18)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(650, 0)
	panel.add_child(_text)
	_btn = Game.button("กลับหน้าเซฟ", func(): Game.goto("save_select"), 20)
	_btn.position = Vector2(390, 492)
	_btn.visible = false
	add_child(_btn)
	if Engine.is_editor_hint():
		Game.ending_info = {"slot": 0, "cls": "knight", "cause": "ถูกจอมมารสังหาร", "stage": 2, "lv": 4, "boss_dmg": 320}
	match Game.ending_mode:
		"victory":
			_victory()
		"all_dead":
			_all_dead()
		_:
			_death()


func _title(t: String, color: Color) -> void:
	var l := Game.label(t, 42, color)
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 30)
	l.size = Vector2(960, 60)
	add_child(l)


func _say(lines: Array) -> void:
	for line in lines:
		_text.text = line
		await Game.wait(2.4)


func _death() -> void:
	var i: Dictionary = Game.ending_info
	_title("เซฟ %d ถูกผนึก" % (int(i.slot) + 1), Game.C_BAD)
	var spr := Game.hero_sprite(i.cls, 6.0)
	spr.position = Vector2(480, 220)
	spr.play("die")
	add_child(spr)
	var sk := Game.icon("icons/skull.png", 64)
	sk.position = Vector2(560, 150)
	add_child(sk)
	var alive := 0
	for s in Game.data.slots:
		if s.state != "dead":
			alive += 1
	_text.text = "%s Lv%d %s ที่ %s\nชีวิตนี้ทำดาเมจใส่จอมมาร %d · บาดแผลนั้นจะคงอยู่ในทุกเซฟ\nร่างของคุณจะเป็นหลุมศพให้ชีวิตถัดไปเก็บของ · กรรมที่ส่งต่อ: %s\nเหลือเซฟที่ยังไม่ผนึก %d เซฟ" % [Game.CLASSES[i.cls].name, i.lv, i.cause, Game.STAGES[int(i.stage)].name, i.boss_dmg, Game.karma_text(int(Game.data.karma)), alive]
	_btn.visible = true


func _all_dead() -> void:
	_title("สามชีวิตดับสูญ", Game.C_BAD)
	var lord := Game.enemy_sprite("demon_lord", 1.0)
	lord.position = Vector2(480, 200)
	add_child(lord)
	Game.sfx("thunder")
	await _say([
		"จอมมาร: ฮ่าๆๆ... อีกครั้งแล้วสินะ",
		"จอมมาร: ข้าจะรอ... รอวันที่เจ้าแข็งแกร่งพอจะปลดปล่อยข้า",
	])
	_text.text = "ทุกเซฟตายหมด ผนึกทั้งหมดถูกปลด แต่จอมมารฟื้นพลังกลับมาเต็ม 100%\nวงจรการตายเกิดเริ่มต้นใหม่"
	_btn.visible = true


func _victory() -> void:
	var i: Dictionary = Game.ending_info
	_title("จอมมารล้มลง", Color("f5d76e"))
	var lord := Game.enemy_sprite("demon_lord", 1.0)
	lord.position = Vector2(620, 200)
	add_child(lord)
	var hero := Game.hero_sprite(i.cls, 6.0)
	hero.position = Vector2(340, 230)
	add_child(hero)
	await _say(["จอมมาร: ขอบใจ... ในที่สุดข้าก็หลุดพ้น"])
	Game.sfx("explosion")
	Game.spawn_vfx(self, "explosion", lord.position, 4.0)
	var tw := create_tween()
	tw.tween_property(lord, "modulate:a", 0.0, 1.0)
	await _say(["จอมมาร: ...ตอนนี้ คำสาปแห่งการตายเกิดเป็นของเจ้าแล้ว"])
	Game.sfx("thunder")
	Game.spawn_vfx(self, "magic", hero.position, 5.0)
	var tw2 := create_tween()
	tw2.tween_property(hero, "modulate", Color(0.5, 0.2, 0.8), 1.5)
	await tw2.finished
	var new_lord := Game.enemy_sprite("demon_lord", 1.0)
	new_lord.position = hero.position + Vector2(0, -30)
	new_lord.modulate.a = 0.0
	add_child(new_lord)
	var tw3 := create_tween()
	tw3.tween_property(hero, "modulate:a", 0.0, 1.2)
	tw3.parallel().tween_property(new_lord, "modulate:a", 1.0, 1.2)
	await tw3.finished
	await _say([
		"มงกุฎดำลอยมาสวมบนศีรษะของคุณ... บัลลังก์ว่างรอคุณอยู่",
		"ผู้กล้า%sกลายเป็นจอมมารตนใหม่ รอคอยผู้กล้าคนถัดไปมาปลดปล่อย" % Game.CLASSES[i.cls].name,
	])
	_text.text = "ฉากจบ: วงจรแห่งคำสาป\nทุกเซฟถูกปลดผนึก · เริ่มลูปที่ %d · จอมมารตนใหม่ (อดีต%s) แข็งแกร่งขึ้นเล็กน้อย" % [Game.data.loop, Game.CLASSES[i.cls].name]
	_btn.text = "เริ่มลูปใหม่"
	_btn.visible = true
