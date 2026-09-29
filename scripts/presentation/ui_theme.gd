extends RefCounted

const INK := Color("#234956")
const MUTED := Color("#627e88")
const TEAL := Color("#256b78")
const GOLD := Color("#edc982")
const PAPER := Color("#f5fafb")

static func panel(fill := PAPER, radius := 16, margin := 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = Color("#cbdde1")
	style.shadow_color = Color(0.03, 0.13, 0.18, 0.12)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, margin)
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 20
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "RichTextLabel"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, INK)
		result.set_color("font_pressed_color", type, INK)
		result.set_color("font_focus_color", type, INK)
		result.set_color("font_disabled_color", type, MUTED)
	for type in ["Button", "OptionButton", "LineEdit"]:
		result.set_stylebox("normal", type, panel(Color("#f6fbfc"), 12, 14))
		result.set_stylebox("hover", type, panel(Color("#e2f1f4"), 12, 14))
		var selected := panel(Color("#fff2d5"), 12, 14)
		selected.border_color = GOLD
		result.set_stylebox("pressed", type, selected)
		result.set_stylebox("disabled", type, panel(Color("#e8eef0"), 12, 14))
		var focus := panel(Color(0, 0, 0, 0), 12, 14)
		focus.border_color = TEAL
		focus.set_border_width_all(3)
		focus.shadow_size = 0
		result.set_stylebox("focus", type, focus)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_stylebox("panel", "PanelContainer", panel())
	result.set_stylebox("panel", "PopupMenu", panel())
	result.set_stylebox("hover", "PopupMenu", panel(Color("#e2f1f4"), 8, 8))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_stylebox("panel", "TooltipPanel", panel(Color("#f5fafb"), 10, 12))
	result.set_color("font_color", "TooltipLabel", INK)
	result.set_font_size("font_size", "TooltipLabel", 18)
	return result

static func primary(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var fill := TEAL if state == "normal" else Color("#347f8c")
		var style := panel(fill, 12, 16)
		style.border_color = GOLD if state == "focus" else fill
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_%s_color" % state, Color.WHITE)
	button.add_theme_color_override("font_color", Color.WHITE)

static func label(text: String, pixels := 20, color := INK) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", pixels)
	result.add_theme_color_override("font_color", color)
	return result

# Cover controls use translucent naval glass, independent of the paper content panels.
static func cover_button(button: Button, hero := false) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var active: bool = state in ["hover", "pressed", "focus"]
		var fill := Color(0.035, 0.12, 0.16, 0.66 if hero else 0.48)
		if active: fill = Color(0.09, 0.29, 0.34, 0.91)
		var style := panel(fill, 5, 20 if hero else 14)
		style.border_color = Color(0.89, 0.77, 0.52, 0.85) if active else Color(0.77, 0.87, 0.89, 0.30)
		style.shadow_size = 0
		if hero:
			style.border_width_left = 3
			style.border_color = Color(0.89, 0.77, 0.52, 0.90 if active else 0.55)
		button.add_theme_stylebox_override(state, style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, Color("#fff4db") if hero else Color("#e7f3f4"))
