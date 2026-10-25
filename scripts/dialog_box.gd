@tool
extends Panel
## Undertale-style dialogue box: black fill, thick white border, portrait on the left,
## speaker name, "* " lines typed out with a blip, yellow keywords via bbcode, ▼ to continue
## (E / Space / Enter / Z / click), Esc skips. choose() shows answer buttons.

signal chosen(index: int)

var skippable := true
var _face: TextureRect
var _name: Label
var _text: RichTextLabel
var _arrow: Label
var _choices: HBoxContainer
var _next := false
var _skip := false
var _choosing := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.border_color = Color.WHITE
	sb.set_border_width_all(5)
	add_theme_stylebox_override("panel", sb)
	position = Vector2(40, 16)
	size = Vector2(880, 170)
	_face = TextureRect.new()
	_face.position = Vector2(18, 22)
	_face.size = Vector2(124, 124)
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_face)
	_name = Game.label("", 18, Color("f5d76e"))
	_name.position = Vector2(160, 10)
	add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.position = Vector2(160, 40)
	_text.size = Vector2(700, 110)
	_text.scroll_active = false
	_text.add_theme_font_size_override("normal_font_size", 24)
	_text.add_theme_color_override("default_color", Color.WHITE)
	add_child(_text)
	_arrow = Game.label("▼", 20, Color.WHITE)
	_arrow.position = Vector2(846, 138)
	add_child(_arrow)
	_choices = HBoxContainer.new()
	_choices.position = Vector2(160, 118)
	_choices.add_theme_constant_override("separation", 40)
	add_child(_choices)


## lines: [[speaker key, text], ...]; faces / names: speaker key -> Texture2D / display name.
func say(lines: Array, faces: Dictionary, names: Dictionary) -> void:
	_skip = false
	for line in lines:
		_face.texture = faces.get(line[0])
		_face.flip_h = line[0] == "hero"
		_name.text = names.get(line[0], "")
		_text.text = "* " + line[1]
		_text.visible_characters = 0
		_arrow.visible = false
		_next = false
		var total := _text.get_total_character_count()
		var shown := 0.0
		while _text.visible_characters < total and not _skip:
			await get_tree().process_frame
			if _next:
				_next = false
				break
			shown += 32.0 * get_process_delta_time()
			if int(shown) != _text.visible_characters:
				_text.visible_characters = int(shown)
				if _text.visible_characters % 2 == 0:
					Game.sfx("hover")
		_text.visible_characters = -1
		_arrow.visible = true
		while not _next and not _skip:
			await get_tree().process_frame
			_arrow.modulate.a = 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() / 200.0))
		if _skip:
			return


## Shows the answers as "* answer" buttons and waits for one; returns its index.
func choose(options: Array) -> int:
	_choosing = true
	_arrow.visible = false
	for c in _choices.get_children():
		c.queue_free()
	for i in options.size():
		var b := Button.new()
		b.text = "* " + options[i]
		b.flat = true
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color("f5d76e"))
		b.add_theme_color_override("font_focus_color", Color("f5d76e"))
		b.pressed.connect(func():
			Game.sfx("click")
			chosen.emit(i))
		_choices.add_child(b)
	_choices.get_child(0).grab_focus()
	var idx: int = await chosen
	for c in _choices.get_children():
		c.queue_free()
	_choosing = false
	return idx


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _choosing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_Z]:
			_next = true
		elif event.physical_keycode == KEY_ESCAPE and skippable:
			_skip = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_next = true
		get_viewport().set_input_as_handled()
