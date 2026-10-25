@tool
extends Control
## "You can't choose how you are born": spins through the classes, lands on the
## one already rolled in Game.birth(), then shows the prologue.

var _holder: Node2D
var _name: Label
var _text: Label
var _go: Button


func _ready() -> void:
	Game.play_bgm("title")
	Game.add_background(self, "backgrounds/title.png", "backgrounds/sil_castle.png", Color(0.7, 0.7, 0.8))
	var s := Game.slot()
	var t := Game.label("ชีวิตที่ %d · เซฟ %d" % [s.life, Game.slot_index + 1], 26, Color("f5d76e"))
	t.position = Vector2(24, 16)
	add_child(t)
	_holder = Node2D.new()
	_holder.position = Vector2(480, 170)
	add_child(_holder)
	_name = Game.label("", 34, Color.WHITE)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.position = Vector2(280, 250)
	_name.size = Vector2(400, 40)
	add_child(_name)
	var panel := PanelContainer.new()
	panel.position = Vector2(110, 300)
	panel.size = Vector2(740, 170)
	add_child(panel)
	_text = Game.label("", 17)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(710, 0)
	panel.add_child(_text)
	_go = Game.button("ออกผจญภัย ▶", func(): Game.goto("intro"), 22)
	_go.position = Vector2(380, 482)
	_go.custom_minimum_size = Vector2(200, 0)
	_go.visible = false
	add_child(_go)
	_spin()


func _spin() -> void:
	var keys := Game.CLASSES.keys()
	var target: String = Game.slot().cls
	var steps := 14 + keys.find(target)
	for i in steps + 1:
		var cls: String = keys[i % keys.size()]
		_show(cls)
		Game.sfx("hover")
		await Game.wait(0.06 + i * 0.012)
	_show(target)
	Game.sfx("reborn")
	Game.spawn_vfx(self, "heal", Vector2(480, 160), 2.0)
	_reveal(target)


func _show(cls: String) -> void:
	for c in _holder.get_children():
		c.queue_free()
	var spr := Game.hero_sprite(cls, 6.0)
	_holder.add_child(spr)
	_name.text = Game.CLASSES[cls].name


func _reveal(cls: String) -> void:
	var c: Dictionary = Game.CLASSES[cls]
	var s := Game.slot()
	var lines := []
	lines.append("คุณเกิดมาเป็น \"%s\"  HP %d · MP %d · ATK %d · DEF %d" % [c.name, s.max_hp, s.max_mp, s.atk, s.def])
	var kit: Array = c.skills
	lines.append("คลิกซ้าย: %s · 1: %s · 2: %s · 3: %s" % [kit[0].name, kit[1].name, kit[2].name, kit[3].name])
	lines.append(Game.CONTROLS_TEXT)
	lines.append("อย่าทำร้ายชาวบ้าน — บาปจะตามไปทุกชาติ")
	var k := int(s.karma_at_birth)
	if k > 0:
		lines.append("กรรมดีจากชาติก่อนส่งผล: เงินเริ่มต้น +%d, ยา +%d, HP สูงสุด +%d" % [25 * k, k, 10 * k])
	elif k < 0:
		lines.append("กรรมชั่วจากชาติก่อนตามมา: มอนสเตอร์มากขึ้น แข็งขึ้น · XP x%.2f · เงิน x%.1f" % [s.xp_mult, s.gold_mult])
	lines.append("")
	lines.append("พระราชา: \"ผู้กล้าเอ๋ย จงไปปราบจอมมารที่ปราสาททางเหนือ\"")
	if Game.boss_ratio() < 1.0:
		lines.append("ข่าวลือว่าจอมมารบาดเจ็บจากผู้กล้าคนก่อน เหลือพลังชีวิต %d%%..." % roundi(Game.boss_ratio() * 100))
	else:
		lines.append("...ในฝัน คุณเห็นปราสาทนั้นชัดเจนราวกับเคยอยู่ที่นั่นมาก่อน")
	_text.text = "\n".join(lines)
	_go.visible = true
