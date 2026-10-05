extends Node3D
# SleepFrame. You float above the night side of the Earth under the real stars (Bright Star
# Catalogue). Three nebulae open the evening; seven small worlds are the sounds. Rest your eyes
# on one for two seconds and it joins tonight's mix, up to three; then a timer; then the sky
# stays until your eyes close, and everything goes dark while the launcher carries the sound on.
# Stage axes: the viewer is at the origin looking down -Z, +Y is the top of their head at the
# moment the scene starts — whichever way they are lying.

const CHOOSE_SECONDS := 10.0     # untouched, the default begins after this
const DWELL_SECONDS := 2.0       # resting on something this long chooses it (4 felt like 5; 3 is too long to keep eyes open)
const SWELL := 0.14                # how much a thing grows while you rest on it
const EYES_CLOSED_SECONDS := 5.0  # eyes shut this long, straight, and the wind-down begins
const EYES_JUMP_DEG := 2.0       # open eyes flick and blink: a jump this big between frames means open
const WATCH_FALLBACK := 20.0     # if the headset cannot see the eyes at all, go dark this long after the choice
const GRACE_SECONDS := 2.0       # nothing can be chosen this soon after the scene comes to rest
const SETTLE_SECONDS := 2.5      # the head must be this long at rest before the scene stops following it
const FACE_LAT := 38.0           # the part of the Earth that faces you
const FACE_LON := -97.0
const FRONT_LIT := true          # the sun direction is ours to place (not the visible disc on the limb)
const NIGHT_START := 0.78        # how far round behind the Earth the sun already is at the start: night side, thin dawn
const WIND_DOWN_SECONDS := 10.0
const LOOK_DEGREES := 7.0        # how near the gaze must be to count as looking at a light
const DEFAULT_SOUND := "rain"
const STAR_R := 350.0
const BODY_DIST := 6.0
const BODY_R := 0.33
const PLANET_POS := Vector3(0, -75, -95)
const PLANET_R := 60.0

# id, label, colour, azimuth (deg, + is right), elevation (deg), file beside the program, volume dB
const MIX_MAX := 3                 # how many sounds can play together
const MIX_TRIM := [0.0, 0.0, -2.0, -3.5]     # each sound comes down a little as the mix grows: by how many sounds are in it
const SOUNDS := [
	# id, name, (unused colour, angle, height), file beside the program, level in dB
	["rain", "Rain", Color(0.48, 0.62, 0.90), -36.0, 7.0, "rain.ogg", 2.5],
	["ocean", "Ocean", Color(0.20, 0.62, 0.72), -24.0, 17.0, "ocean.ogg", 2.5],
	["wind", "Wind", Color(0.80, 0.72, 0.58), -12.0, 7.0, "wind.ogg", 1.0],
	["thunder", "Thunder", Color(0.50, 0.47, 0.60), 0.0, 19.0, "thunder.ogg", 0.0],
	["white", "White", Color(0.95, 0.96, 1.00), 12.0, 7.0, "white.wav", -13.5],
	["pink", "Pink", Color(1.00, 0.55, 0.72), 24.0, 17.0, "pink.wav", -11.0],
	["brown", "Brown", Color(0.62, 0.38, 0.24), 36.0, 7.0, "brown.wav", -6.0],
]

enum { ORIENT, OPEN, MENU_SOUND, MENU_TIMER, WATCH, WIND_DOWN, DARK, EYETEST }

var origin: XROrigin3D
var cam: XRCamera3D
var xr_on := false
var stage: Node3D
var flat_args := {}
var state := ORIENT
var t_state := 0.0
var t_run := 0.0
var idle := 0.0                  # seconds of CHOOSE spent not looking at any light
var looked := -1
var dwell := 0.0
var chosen := -1
var bodies: Array = []           # the sounds: {id, name, dir, mesh, mat, label, player, base, vol, has, look_deg, ring_deg}
var open_items: Array = []       # the two nebulae: {id, dir, mat, base, label, sub, look_deg, ring_deg}
var timer_items: Array = []      # {id, minutes, dir, mesh, mat, label, base, look_deg, ring_deg}
var headings: Array = []         # [Label3D for the sound menu, Label3D for the timer menu]
var ring: MeshInstance3D
var ring_mat: ShaderMaterial
var g_open := 0.0                # 0..1, how far each group is faded in
var g_sound := 0.0
var g_timer := 0.0
var set_mix: Array = ["rain"]    # tonight's sounds, up to three; saved as "before" for next time
var mix_lock := -1               # the sound just put in or taken out: the eyes must leave it before it can change again
var done_item: Dictionary = {}   # "that's my night": on from the sound menu to the timer
var sound_items: Array = []      # the sounds, then done_item: what can be rested on in the sound menu
var mix_sub: Label3D
var watch_words: Label3D        # shown once the choices are made, while the sky waits for closed eyes
var watch_sub: Label3D
var g_watch := 0.0
var set_timer := 0               # minutes; 0 is all night
var has_saved := false
var said_dark := false
var eye_test := false           # one run that walks the wearer through an eye-tracker test, words in the sky
var test_step := -1
var test_words: Label3D
var test_marks: Array = []
var test_chime: AudioStreamPlayer
# seconds, words, which mark shows (-1 none, 0 left, 1 right), chimes to play as the step begins
const TEST_STEPS := [
	[5.0, "eye test\nkeep your head still", -1, 0],
	[5.0, "with your eyes only\nlook at the star on the left", 0, 0],
	[5.0, "now the star on the right", 1, 0],
	[4.0, "and back here", -1, 0],
	[6.0, "when you hear the chime, close your eyes\nopen them when you hear two", -1, 0],
	[10.0, "eyes closed", -1, 1],
	[6.0, "open\nblink three times", -1, 2],
	[3.0, "done, thank you", -1, 0],
]
var eyes_seen_at := -99.0       # when the tracker last gave a tracked gaze
var eyes_still := 0.0          # seconds since the gaze last flicked or blinked
var eyes_low := false          # the gaze is parked below the head's level, where closed eyes read
var prev_gaze := Vector3.ZERO
var eye_dir := Vector3.ZERO      # where the eyes point, in the scene; zero until the tracker speaks
var look_miss := 0.0           # how long the gaze has been off what it was resting on (a blink is short)
var leaving := false            # "not tonight": fade out and close, without going dark
var eye_log: FileAccess
var eye_next := 0.0
var xr_iface: XRInterface
var star_mat: ShaderMaterial
var milky_mat: ShaderMaterial
var planet_mat: ShaderMaterial
var air_mat: ShaderMaterial
var sun: MeshInstance3D
var sun_mat: ShaderMaterial
var dot_mat: StandardMaterial3D
var dot_node: MeshInstance3D
var threads: Array = []
var perf_next := 5.0
var perf_begun := false        # the frame-rate log is started afresh each run
var shot_done := false
var still_for := 0.0
var away_for := 0.0
var ref_fwd := Vector3.ZERO
var ref_age := 0.0
var appear := 0.0                # 0..1, the whole scene fading in once it has been hung
var last_fwd := Vector3.ZERO
var planet: MeshInstance3D
var sun_lamp: DirectionalLight3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		flat_args[kv[0]] = kv[1] if kv.size() > 1 else "1"

	origin = XROrigin3D.new()
	add_child(origin)
	cam = XRCamera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	origin.add_child(cam)

	var xr := XRServer.find_interface("OpenXR")
	xr_iface = xr
	if xr and xr.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr.render_target_size_multiplier = float(flat_args.get("sharp", "1.4"))   # the headset asks for two-thirds; this scene is light enough for more
		get_viewport().use_xr = true
		xr_on = true
		xr.pose_recentered.connect(func(): state = ORIENT; t_state = 0.0)
	else:
		# flat look on a desktop: --yaw= --pitch= --fov= --state=choose|wind --t=<seconds> --look=<id> --shot=<png>
		cam.fov = float(flat_args.get("fov", "90"))
		cam.basis = Basis(Vector3.UP, deg_to_rad(-float(flat_args.get("yaw", "0")))) \
			* Basis(Vector3.RIGHT, deg_to_rad(float(flat_args.get("pitch", "0")))) \
			* Basis(Vector3.BACK, deg_to_rad(float(flat_args.get("roll", "0"))))

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	stage = Node3D.new()
	add_child(stage)
	build_milky_way()
	build_stars()
	build_planet()
	build_sun()
	build_bodies()
	if bodies.is_empty():
		push_error("SleepFrame: no sound files were found beside the program (rain.ogg, white.wav and so on). See the README.")
		get_tree().quit(1)
		return
	load_settings()
	build_timers()
	build_open()
	build_ring()
	build_dot()
	if FileAccess.file_exists("user://eye-test") or flat_args.has("eyetest"):
		eye_test = true
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://eye-test"))      # one run only
		test_words = words("", dir_of(0.0, 12.0), 84)
		for az in [-22.0, 22.0]:
			var st := star(dir_of(az, 12.0))
			st[1].albedo_color = STAR_COLOUR
			test_marks.append(st[0])
		test_chime = AudioStreamPlayer.new()
		add_child(test_chime)
		if FileAccess.file_exists(beside("chime.wav")):
			test_chime.stream = AudioStreamWAV.load_from_file(beside("chime.wav"))
	set_sun(0.0)


func beside(file: String) -> String:
	var p := OS.get_executable_path().get_base_dir().path_join(file)
	if FileAccess.file_exists(p):
		return p
	return ProjectSettings.globalize_path("res://").path_join("../build").path_join(file)


func dir_of(az_deg: float, el_deg: float) -> Vector3:
	var a := deg_to_rad(az_deg)
	var e := deg_to_rad(el_deg)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))


# ---------------------------------------------------------------- the sky

func build_stars() -> void:
	var f := FileAccess.open("res://stars.dat", FileAccess.READ)
	var rows: Array = []
	while f and not f.eof_reached():
		var p := f.get_csv_line()
		if p.size() == 7 and float(p[3]) <= 6.5:
			rows.append(p)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mm.mesh = quad
	mm.instance_count = rows.size()
	for i in rows.size():
		var p: PackedStringArray = rows[i]
		var mag := float(p[3])
		var size_deg := clampf(0.40 - 0.04 * mag, 0.14, 0.50)
		var strength := clampf(pow(10.0, -0.2 * (mag - 1.5)), 0.16, 2.2)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(float(p[0]), float(p[1]), float(p[2])) * STAR_R))
		mm.set_instance_color(i, Color(float(p[4]), float(p[5]), float(p[6]), 1.0))
		mm.set_instance_custom_data(i, Color(STAR_R * deg_to_rad(size_deg) * 0.5, strength, 0, 0))
	star_mat = ShaderMaterial.new()
	star_mat.shader = Shader.new()
	star_mat.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float fade = 1.0;
varying float strength;
void vertex() {
	strength = INSTANCE_CUSTOM.y;
	VERTEX.xy *= INSTANCE_CUSTOM.x;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.0);
	ALBEDO = COLOR.rgb * a * strength * fade;
}
"""
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = star_mat
	mi.extra_cull_margin = 16000.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mi)


func build_milky_way() -> void:
	# NASA's map of the Milky Way's glow without its stars (SVS Deep Star Maps 2020), laid behind
	# the catalogue stars in the same sky axes: centred on RA 0h, RA increasing to the left.
	var m := SphereMesh.new()
	m.radius = 450.0
	m.height = 900.0
	m.radial_segments = 48
	m.rings = 24
	milky_mat = ShaderMaterial.new()
	milky_mat.shader = Shader.new()
	milky_mat.shader.code = """
shader_type spatial;
render_mode unshaded, cull_front;
uniform sampler2D sky : source_color, filter_linear, repeat_enable;
uniform float fade = 1.0;
uniform float gain = 0.55;
varying vec3 dir;
void vertex() { dir = VERTEX; }
void fragment() {
	vec3 d = normalize(dir);
	float ra = atan(-d.z, d.x);
	float dec = asin(clamp(d.y, -1.0, 1.0));
	vec2 uv = vec2(0.5 - ra / TAU, 0.5 - dec / PI);
	vec3 c = textureLod(sky, uv, 0.0).rgb * gain * fade;
	c += (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
	ALBEDO = max(c, vec3(0.0));
}
"""
	milky_mat.set_shader_parameter("sky", load("res://milkyway.jpg"))
	milky_mat.set_shader_parameter("gain", float(flat_args.get("mw", "0.55")))
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = milky_mat
	mi.extra_cull_margin = 16000.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mi)


func build_planet() -> void:
	var m := SphereMesh.new()
	m.radius = PLANET_R
	m.height = PLANET_R * 2.0
	m.radial_segments = 96
	m.rings = 48
	planet_mat = ShaderMaterial.new()
	planet_mat.shader = Shader.new()
	planet_mat.shader.code = """
shader_type spatial;
render_mode unshaded;
uniform sampler2D day_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 0.0, -1.0);   // world space, toward the sun
uniform float light = 1.0;
uniform float drift = 0.0;
uniform float allday = 0.0;   // test only: light the whole globe
varying vec3 wn;
void vertex() { wn = normalize(mat3(MODEL_MATRIX) * NORMAL); }
void fragment() {
	float ndl = dot(normalize(wn), normalize(sun_dir));
	float day = max(smoothstep(0.02, 0.30, ndl), allday);
	ndl = max(ndl, allday * 0.8);
	vec3 d = texture(day_tex, UV).rgb;
	float c = texture(cloud_tex, UV + vec2(drift, 0.0)).r;
	vec3 day_c = mix(d, vec3(1.0), c * 0.9) * (0.25 + 0.85 * max(ndl, 0.0));
	vec3 night_c = vec3(0.0105, 0.0100, 0.0095) * (0.45 + c * 1.9) + d * 0.012;   // the globe by starlight: no lights overlay, no blue
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 air = vec3(0.55, 0.42, 0.32) * rim * (0.012 + 0.985 * day);
	ALBEDO = (mix(night_c, day_c, day) + air) * light;
	ALBEDO += (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
}
"""
	planet_mat.set_shader_parameter("day_tex", load("res://earth_day.jpg"))
	planet_mat.set_shader_parameter("cloud_tex", load("res://earth_clouds.jpg"))
	planet_mat.set_shader_parameter("allday", 1.0 if flat_args.has("allday") else 0.0)
	var p := MeshInstance3D.new()
	planet = p
	p.mesh = m
	p.material_override = planet_mat
	p.position = PLANET_POS
	# turn the globe so FACE_LAT/FACE_LON is the nearest point, north toward the top
	var lat := deg_to_rad(float(flat_args.get("lat", str(FACE_LAT))))
	var lon := deg_to_rad(float(flat_args.get("lon", str(FACE_LON))) + float(flat_args.get("lonoff", "180")))
	var sgn := float(flat_args.get("lonsign", "1"))
	var l := Vector3(cos(lat) * sin(lon * sgn), sin(lat), cos(lat) * cos(lon * sgn))
	var lx := Vector3.UP.cross(l).normalized()
	var bl := Basis(lx, l.cross(lx), l)
	var v := (-PLANET_POS).normalized()
	var tx := Vector3.UP.cross(v).normalized()
	var bt := Basis(tx, v.cross(tx), v)
	p.basis = bt * bl.inverse()
	stage.add_child(p)
	# a thin shell of air: the bright arc along the edge, strongest where the sun is behind it
	var s := SphereMesh.new()
	s.radius = PLANET_R * 1.018
	s.height = PLANET_R * 2.036
	s.radial_segments = 96
	s.rings = 48
	air_mat = ShaderMaterial.new()
	air_mat.shader = Shader.new()
	air_mat.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec3 sun_view = vec3(0.0, 0.0, -1.0);  // view space, toward the sun
uniform float light = 1.0;
void fragment() {
	float graze = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(graze, 3.0) * (1.0 - smoothstep(0.80, 1.0, graze));
	float toward = pow(clamp(dot(normalize(-VIEW), normalize(sun_view)), 0.0, 1.0), 24.0);
	vec3 c = mix(vec3(0.45, 0.30, 0.22), vec3(1.0, 0.66, 0.40), toward);     // warm, never blue
	ALBEDO = c * edge * (0.05 + 1.9 * toward) * 0.5 * light;
	ALBEDO += (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
}
"""
	var a := MeshInstance3D.new()
	a.mesh = s
	a.material_override = air_mat
	a.position = PLANET_POS
	stage.add_child(a)


func build_sun() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(120, 120)
	sun_mat = ShaderMaterial.new()
	sun_mat.shader = Shader.new()
	sun_mat.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float light = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float core = smoothstep(0.075, 0.05, r);
	float glow = pow(clamp(1.0 - r, 0.0, 1.0), 5.0) * 0.8;
	ALBEDO = (vec3(1.0, 0.96, 0.88) * core * 2.0 + vec3(1.0, 0.80, 0.55) * glow) * light;
}
"""
	sun = MeshInstance3D.new()
	sun.mesh = q
	sun.material_override = sun_mat
	stage.add_child(sun)


func set_sun(k: float) -> void:
	# k 0..1 through the wind-down
	var e := smoothstep(0.0, 1.0, k)
	if FRONT_LIT or sun_lamp:
		# the sun is behind the viewer, lighting the face of the Earth; it swings round behind
		# the Earth and the daylight slides off
		# Nothing bright before sleep: we are over the night side from the start, with a thin
		# crescent of dawn on the edge. The wind-down takes the sun the rest of the way behind.
		# Entirely the night side, no lights overlay, little to no blue. The sun is
		# straight behind the Earth, so all we see is the dark globe and a faint warm ring of air.
		var from := PLANET_POS.normalized()
		if sun_lamp:
			sun_lamp.transform = Transform3D(Basis.looking_at(-from, Vector3.RIGHT), Vector3.ZERO)
		planet_mat.set_shader_parameter("sun_dir", stage.global_transform.basis * from)
		sun.visible = false
		air_mat.set_shader_parameter("sun_view", (cam.global_transform.basis.inverse() * (stage.global_transform.basis * from)))
		return
	var d := dir_of(0.0, lerpf(4.0, -17.0, e))
	sun.position = d * 300.0
	planet_mat.set_shader_parameter("sun_dir", stage.global_transform.basis * d)
	air_mat.set_shader_parameter("sun_view", (cam.global_transform.basis.inverse() * (stage.global_transform.basis * d)))


# ---------------------------------------------------------------- the lights you choose from

func stage_up_for(_d: Vector3) -> Vector3:
	return Vector3.UP


func load_sound(i: int, path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("no sound file at " + path)
		return
	var th := Thread.new()
	threads.append(th)
	th.start(func():
		var s: AudioStream
		if path.ends_with(".ogg"):
			var o := AudioStreamOggVorbis.load_from_file(path)
			if o:
				o.loop = true
			s = o
		else:
			var w := AudioStreamWAV.load_from_file(path)
			if w:
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				w.loop_end = int(w.get_length() * w.mix_rate)
			s = w
		call_deferred("_sound_ready", i, s))


func _sound_ready(i: int, s: AudioStream) -> void:
	if s == null:
		return
	bodies[i].player.stream = s
	bodies[i].has = true
	# each sound begins somewhere different in its loop every night, so no two nights are the same
	bodies[i].player.play(randf() * s.get_length())


# ---------------------------------------------------------------- the things you choose from

const WORDS_COLOUR := Color(0.86, 0.72, 0.56)
const STAR_COLOUR := Color(1.0, 0.82, 0.60)
const TIMERS := [[30, "30 minutes"], [60, "60 minutes"], [90, "90 minutes"], [0, "all night"]]


func nebula(file: String, d: Vector3, across_deg: float) -> Array:
	var q := QuadMesh.new()
	var size := 2.0 * BODY_DIST * tan(deg_to_rad(across_deg * 0.5))
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform sampler2D pic : source_color, filter_linear_mipmap;
uniform float gain = 0.0;
void fragment() { ALBEDO = texture(pic, UV).rgb * gain; }
"""
	m.set_shader_parameter("pic", load("res://" + file))
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	# The pictures must not turn as the head tilts. Pinned: facing where the
	# viewer was hung, upright in the scene, and that is all.
	mi.transform = Transform3D(Basis.looking_at(d, Vector3.UP), d * BODY_DIST)
	stage.add_child(mi)
	return [mi, m]


func words(text: String, d: Vector3, px: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	var fv := FontVariation.new()
	fv.base_font = load("res://cormorant.ttf")
	fv.spacing_glyph = 3
	l.font = fv
	l.font_size = px
	l.pixel_size = 0.0035
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.shaded = false
	l.no_depth_test = true
	l.outline_size = 0
	l.modulate = Color(0, 0, 0, 0)
	l.transform = Transform3D(Basis.looking_at(d, Vector3.UP), d * BODY_DIST)
	stage.add_child(l)
	return l


func star(d: Vector3) -> Array:
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.BLACK
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = m
	mi.position = d * BODY_DIST
	mi.visible = false
	stage.add_child(mi)
	return [mi, m]


const NOISE_GLSL := """
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; } return s; }
"""
const BILLBOARD_GLSL := """
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
"""


func gas_world(d: Vector3, c1: Color, c2: Color, c3: Color, bands: float, swirl: float, speed: float) -> Array:
	# a ball of slow weather: bands that each drift at their own pace, never the same twice
	var sphere := SphereMesh.new()
	sphere.radius = 0.30
	sphere.height = 0.60
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = "shader_type spatial;\nrender_mode unshaded;\n" + NOISE_GLSL + """
uniform vec3 c1 : source_color; uniform vec3 c2 : source_color; uniform vec3 c3 : source_color;
uniform float bands = 6.0; uniform float swirl = 0.6; uniform float speed = 0.02; uniform float gain = 0.0;
varying vec3 op;
void vertex() { op = VERTEX; }
void fragment() {
	vec3 n = normalize(op);
	float lat = n.y;
	float lon = atan(n.z, n.x);
	float drift = TIME * speed * (1.0 + 0.6 * sin(lat * 5.0));
	vec3 q = vec3(cos(lon + drift), lat, sin(lon + drift));
	float w = fbm(q * 3.0 + vec3(0.0, TIME * speed * 0.3, 0.0));
	float t = 0.5 + 0.5 * sin(lat * bands + (w - 0.5) * swirl * 6.0);
	vec3 col = mix(c1, c2, smoothstep(0.05, 0.95, t));
	col = mix(col, c3, smoothstep(0.55, 0.95, fbm(q * 6.0 + 3.0)) * 0.5);
	float limb = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 0.7);
	ALBEDO = col * limb * gain;
}
"""
	m.set_shader_parameter("c1", c1)
	m.set_shader_parameter("c2", c2)
	m.set_shader_parameter("c3", c3)
	m.set_shader_parameter("bands", bands)
	m.set_shader_parameter("swirl", swirl)
	m.set_shader_parameter("speed", speed)
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = m
	mi.position = d * BODY_DIST
	mi.rotation_degrees = Vector3(18.0, 0.0, -14.0)      # a little tilt, so the bands are not ruled lines
	mi.visible = false
	stage.add_child(mi)
	return [mi, m]


func glow_card(d: Vector3, across: float, body: String) -> Array:
	# a soft glowing thing drawn on a card that always faces you: body is the fragment code
	var q := QuadMesh.new()
	q.size = Vector2(across, across)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled;\n" + NOISE_GLSL \
		+ "uniform float gain = 0.0;\nuniform float phase = 1.0;\nuniform sampler2D pic : source_color, filter_linear_mipmap;\n" + "void fragment() {\n\tvec2 p = UV * 2.0 - 1.0;\n\tfloat r = length(p);\n" + body + "}\n"
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.transform = Transform3D(Basis.looking_at(d, Vector3.UP), d * BODY_DIST)
	mi.visible = false
	stage.add_child(mi)
	return [mi, m]


func real_world(d: Vector3, picture: String, clouds: bool, tint: Color, turn: float) -> Array:
	# a small world wearing a real picture: Hubble's map of Jupiter, or NASA's map of Earth's
	# clouds. It turns slowly, its bands slide a little against each other, and it is lit
	# softly from one side so it has a shape.
	var sphere := SphereMesh.new()
	sphere.radius = 0.30
	sphere.height = 0.60
	sphere.radial_segments = 48
	sphere.rings = 24
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """
shader_type spatial;
render_mode unshaded;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float gain = 0.0;
uniform float turn = 0.004;
uniform float clouds = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
void fragment() {
	float lat = UV.y - 0.5;
	float u = UV.x + TIME * turn + 0.010 * sin(TIME * 0.07 + lat * 18.0);
	vec3 col;
	if (clouds > 0.5) {
		float c1 = texture(tex, vec2(u, UV.y)).r;
		float c2 = texture(tex, vec2(u + 0.37 + TIME * turn * 0.6, UV.y * 0.96 + 0.02)).r;
		col = mix(vec3(0.07, 0.07, 0.075), vec3(0.64, 0.60, 0.55), clamp(c1 * 0.80 + c2 * 0.45, 0.0, 1.0));
	} else {
		col = texture(tex, vec2(u, UV.y)).rgb;
	}
	col *= tint;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float lit = 0.26 + 0.74 * smoothstep(-0.35, 0.75, dot(NORMAL, normalize(vec3(-0.55, 0.45, 0.70))));
	float rim = pow(1.0 - facing, 3.0);
	ALBEDO = (col * lit * pow(facing, 0.55) + vec3(0.55, 0.36, 0.22) * rim * 0.22 * lit) * gain;
}
"""
	m.set_shader_parameter("tex", load("res://" + picture))
	m.set_shader_parameter("clouds", 1.0 if clouds else 0.0)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("turn", turn)
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = m
	mi.position = d * BODY_DIST
	mi.rotation_degrees = Vector3(14.0, 0.0, -12.0)
	mi.visible = false
	stage.add_child(mi)
	return [mi, m]


func sound_object(id: String, d: Vector3) -> Array:
	match id:
		"brown":     # a brown dwarf wearing Hubble's map of Jupiter, warmed and dimmed
			return real_world(d, "brown_dwarf.jpg", false, Color(0.80, 0.76, 0.72), 0.0045)
		"rain":      # a world wrapped in real cloud: NASA's map of Earth's weather, two layers sliding
			return real_world(d, "earth_clouds.jpg", true, Color(1.0, 0.97, 0.93), 0.0060)
		"ocean":
			return real_world(d, "earth_clouds.jpg", true, Color(0.78, 0.95, 0.92), 0.0040)
		"wind":      # a banded world of slow weather, sand-coloured
			return gas_world(d, Color(0.80, 0.72, 0.58), Color(0.50, 0.43, 0.36), Color(0.93, 0.88, 0.78), 9.0, 0.55, 0.05)
		"thunder":   # the same cloud, darker and slower: a storm seen from far off. Nothing flashes.
			return real_world(d, "earth_clouds.jpg", true, Color(0.50, 0.47, 0.60), 0.0030)
		"pink":      # rose clouds from Hubble's picture of the Lagoon nebula, drifting very slightly
			var made := glow_card(d, 1.05, """
	vec2 w = vec2(fbm(vec3(p * 1.3, TIME * 0.035)), fbm(vec3(p * 1.3 + 7.0, TIME * 0.035))) - 0.5;
	ALBEDO = texture(pic, UV + w * 0.035).rgb * gain;
""")
			made[1].set_shader_parameter("pic", load("res://neb_pink.jpg"))
			return made
		_:           # white: a white dwarf, a pale ember with a wide soft halo
			return glow_card(d, 1.00, """
	float breathe = 0.92 + 0.08 * sin(TIME * 1.05);
	float core = exp(-r * r * 46.0);
	float halo = exp(-r * 3.4) * 0.30 * (1.0 - smoothstep(0.7, 1.0, r));
	ALBEDO = vec3(1.0, 0.92, 0.80) * (core * 0.9 + halo) * breathe * gain;
""")


func moon_phase(d: Vector3, lit: float) -> Array:
	# the timer: a thin crescent for a short while, a full moon for all night
	var made := glow_card(d, 0.52, """
	float disc = smoothstep(1.0, 0.94, r);
	float edge = sqrt(max(1.0 - p.y * p.y, 0.0)) * (1.0 - 2.0 * phase);
	float day = smoothstep(edge - 0.05, edge + 0.05, p.x);
	float skin = 0.80 + 0.35 * (fbm(vec3(p * 3.2, 7.0)) - 0.5);
	ALBEDO = vec3(0.60, 0.55, 0.47) * disc * (0.05 + 0.95 * day) * skin * gain;
""")
	made[1].set_shader_parameter("phase", lit)
	return made


func timer_words(minutes: int) -> String:
	for t in TIMERS:
		if t[0] == minutes:
			return t[1]
	return "%d minutes" % minutes


func sound_index(id: String) -> int:
	for i in bodies.size():
		if bodies[i].id == id:
			return i
	return 0 if bodies.size() > 0 else -1


func has_body(id: String) -> bool:
	for b in bodies:
		if b.id == id:
			return true
	return false


func mix_words() -> String:
	var names: Array = []
	for id in set_mix:
		names.append(bodies[sound_index(id)].name)
	return " + ".join(names)


func load_settings() -> void:
	var cf := ConfigFile.new()
	has_saved = cf.load("user://settings.cfg") == OK
	# "mix" since the three-sound menu; a settings file from before it holds one "sound"
	var read = cf.get_value("last", "mix", [str(cf.get_value("last", "sound", DEFAULT_SOUND))])
	var wanted: Array = read if read is Array else [DEFAULT_SOUND]      # a damaged file is treated as no file
	if flat_args.has("mix"):
		wanted = Array(str(flat_args["mix"]).split("+", false))
	set_mix = []
	for id in wanted:
		if has_body(str(id)) and not set_mix.has(str(id)) and set_mix.size() < MIX_MAX:      # a saved sound's file may be gone
			set_mix.append(str(id))
	if set_mix.is_empty() and bodies.size() > 0:
		set_mix = [bodies[0].id]
	var tv = cf.get_value("last", "timer", 0)
	set_timer = int(tv) if (tv is int or tv is float) else 0


func build_bodies() -> void:
	# one small warm star and a name for each sound whose file is here
	var have: Array = []
	for snd in SOUNDS:
		if snd[5] != "" and FileAccess.file_exists(beside(snd[5])):
			have.append(snd)
	for i in have.size():
		var snd: Array = have[i]
		var az := (i - (have.size() - 1) * 0.5) * 14.0
		var st := sound_object(snd[0], dir_of(az, 13.5))
		var l := words(str(snd[1]).to_lower(), dir_of(az, 8.6), 76)
		var pl := AudioStreamPlayer.new()
		pl.volume_db = -60.0
		add_child(pl)
		bodies.append({"id": snd[0], "name": str(snd[1]).to_lower(), "dir": dir_of(az, 11.0), "mesh": st[0], "mat": st[1],
			"label": l, "player": pl, "base": STAR_COLOUR, "vol": snd[6], "has": false, "look_deg": 6.8, "ring_deg": 4.3, "ring_dir": dir_of(az, 13.5)})
		if not flat_args.has("mute"):
			load_sound(bodies.size() - 1, beside(snd[5]))
	headings.append(words("what would you like to hear", dir_of(0.0, 23.4), 62))
	mix_sub = words("up to three", dir_of(0.0, 20.6), 44)
	# well beneath the sounds (they are at 11 to 13 degrees up): the eye tracker can be several
	# degrees off, and at ten degrees apart the two were confused
	var ds := star(dir_of(0.0, -7.2))
	done_item = {"id": "done", "dir": dir_of(0.0, -7.2), "mesh": ds[0], "mat": ds[1], "label": words("that's my night", dir_of(0.0, -4.2), 60),
		"base": STAR_COLOUR, "look_deg": 6.0, "ring_deg": 2.4, "ring_dir": dir_of(0.0, -7.2)}
	watch_words = words("close your eyes to turn off the screens", dir_of(0.0, 9.6), 58)
	# Valve's name for it: "the Aux button ... on the right hand side of headset just above the power button"
	watch_sub = words("to end, press the Aux button, just above the power button", dir_of(0.0, 6.4), 44)
	sound_items = bodies.duplicate()
	sound_items.append(done_item)


func build_timers() -> void:
	for i in TIMERS.size():
		var az := (i - (TIMERS.size() - 1) * 0.5) * 15.0
		var st := moon_phase(dir_of(az, 13.5), [0.22, 0.5, 0.78, 1.0][i])
		var l := words(TIMERS[i][1], dir_of(az, 8.9), 68)
		timer_items.append({"id": str(TIMERS[i][0]), "minutes": TIMERS[i][0], "dir": dir_of(az, 11.0), "mesh": st[0], "mat": st[1],
			"label": l, "base": STAR_COLOUR, "look_deg": 6.8, "ring_deg": 3.9, "ring_dir": dir_of(az, 13.5)})
	headings.append(words("for how long", dir_of(0.0, 21.0), 62))


func build_open() -> void:
	# The Orion nebula, large and straight ahead, is "as before";
	# the Ring nebula, smaller and to the right, opens the menu.
	var d1 := dir_of(0.0, 15.0)
	var sub_text := "%s  ·  %s" % [mix_words(), timer_words(set_timer)] if bodies.size() > 0 else ""
	var n1 := nebula("neb_orion.jpg", d1, 30.0)
	open_items.append({"id": "before", "dir": d1, "mat": n1[1], "node": n1[0], "base": 0.8,
		"label": words("as before" if has_saved else "begin", dir_of(0.0, 3.2), 84),
		"sub": words(sub_text, dir_of(0.0, -0.1), 54), "look_deg": 13.0, "ring_deg": 14.5})
	var d2 := dir_of(27.0, 8.0)
	var n2 := nebula("neb_ring.jpg", d2, 11.0)
	open_items.append({"id": "menu", "dir": d2, "mat": n2[1], "node": n2[0], "base": 0.85,
		"label": words("choose", dir_of(27.0, 1.2), 60), "sub": null, "look_deg": 7.5, "ring_deg": 6.5})
	# the way out, small and to the left: never chosen by the countdown, only on purpose
	var d3 := dir_of(-27.0, 8.0)
	var n3 := nebula("neb_catseye.jpg", d3, 10.0)
	open_items.append({"id": "leave", "dir": d3, "mat": n3[1], "node": n3[0], "base": 0.80,
		"label": words("not tonight", dir_of(-27.0, 1.4), 60), "sub": null, "look_deg": 7.5, "ring_deg": 6.0})


func build_ring() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	ring_mat = ShaderMaterial.new()
	ring_mat.shader = Shader.new()
	ring_mat.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled;
uniform float progress = 0.0;
uniform float gain = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float turn = fract(atan(p.x, -p.y) / TAU + 1.0);       // 0 at the top, growing clockwise
	float line = smoothstep(0.022, 0.0, abs(r - 0.95));
	ALBEDO = vec3(0.95, 0.74, 0.50) * line * step(turn, progress) * gain;
}
"""
	ring = MeshInstance3D.new()
	ring.mesh = q
	ring.material_override = ring_mat
	ring.visible = false
	stage.add_child(ring)
	# and a steady ring for each sound, shown while that sound is in tonight's mix
	for b in bodies:
		var hm: ShaderMaterial = ring_mat.duplicate()
		var hr := MeshInstance3D.new()
		hr.mesh = q
		hr.material_override = hm
		hr.visible = false
		var rr: float = BODY_DIST * tan(deg_to_rad(b.ring_deg))
		hr.transform = Transform3D(Basis.looking_at(b.ring_dir, Vector3.UP) * Basis.from_scale(Vector3(rr, rr, 1.0)), b.ring_dir * BODY_DIST)
		stage.add_child(hr)
		b["held"] = hr
		b["held_mat"] = hm


func eyes_live() -> bool:
	return xr_on and t_run - eyes_seen_at < 0.5 and eye_dir != Vector3.ZERO


func gaze_in(list: Array) -> int:
	# Which thing is being looked at. With the eye tracker: the thing nearest the gaze, within a
	# generous reach, because the reading can be several degrees off (measured 10-04: about 3 at
	# the centre and left, about 9 at the right). Without it: where the head points, as before.
	if flat_args.has("look"):
		for i in list.size():
			if list[i].id == flat_args["look"]:
				return i
	var by_eye := eyes_live()
	var fwd := eye_dir if by_eye else stage.global_transform.basis.inverse() * (-cam.global_transform.basis.z)
	var best := -1
	var best_ang := 999.0
	for i in list.size():
		var ang: float = rad_to_deg(fwd.angle_to(list[i].dir))
		var reach: float = maxf(list[i].look_deg * 1.5, 12.0) if by_eye else list[i].look_deg
		if ang < reach and ang < best_ang:
			best_ang = ang
			best = i
	return best


func read_eyes(dt: float) -> void:
	# Measured on this headset 10-04: the tracker never says "lost". With the lids down it reports
	# a gaze parked about 18 degrees below the head's level and holds it still; open eyes flick
	# by 2-8 degrees all the time and every blink is a spike of 25-40.
	var tr: XRPositionalTracker = XRServer.get_tracker("/user/eyes_ext")
	if tr == null:
		return
	var ps: XRPose = tr.get_pose("default")
	if ps == null or not ps.has_tracking_data:
		return
	eyes_seen_at = t_run
	eye_dir = (stage.global_transform.basis.inverse() * (origin.global_transform.basis * (-ps.transform.basis.z))).normalized()
	var g := (cam.transform.basis.inverse() * (-ps.transform.basis.z)).normalized()      # the gaze, in the head's own frame
	if prev_gaze != Vector3.ZERO and rad_to_deg(g.angle_to(prev_gaze)) > EYES_JUMP_DEG:
		eyes_still = 0.0
	else:
		eyes_still += dt
	prev_gaze = g
	eyes_low = rad_to_deg(asin(clampf(g.y, -1.0, 1.0))) < -8.0


func eyes_closed() -> bool:
	if flat_args.has("closed"):
		return true
	if t_run - eyes_seen_at > 0.5:
		return false
	# still and parked low for five seconds; or simply still for much longer, for eyes that park elsewhere
	return (eyes_still >= EYES_CLOSED_SECONDS and eyes_low) or eyes_still >= 12.0


func begin_watch() -> void:
	# the mix is chosen: it plays, and the sky stays for as long as the eyes are open
	chosen = sound_index(set_mix[0])
	var cf := ConfigFile.new()
	cf.set_value("last", "mix", set_mix)
	cf.set_value("last", "timer", set_timer)
	cf.save("user://settings.cfg")
	state = WATCH
	t_state = 0.0


func begin_wind_down() -> void:
	chosen = sound_index(set_mix[0])
	var cf := ConfigFile.new()
	cf.set_value("last", "mix", set_mix)
	cf.set_value("last", "timer", set_timer)
	cf.save("user://settings.cfg")
	var f := FileAccess.open("user://choice", FileAccess.WRITE)     # the launcher reads this: the sounds joined by +, then minutes
	if f:
		f.store_string("%s\n%d\n" % ["+".join(set_mix), set_timer])
		f.close()
	state = WIND_DOWN
	t_state = 0.0


func build_dot() -> void:
	var q := SphereMesh.new()
	q.radius = 0.012
	q.height = 0.024
	dot_mat = StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(0.9, 0.8, 0.68)
	dot_mat.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = dot_mat
	mi.position = Vector3(0, 0, -3.0)
	cam.add_child(mi)
	dot_node = mi


# ---------------------------------------------------------------- the run of it

func _process(dt: float) -> void:
	t_run += dt
	t_state += dt
	if xr_on:
		read_eyes(dt)

	if state == ORIENT:
		# The scene comes to you. A person starts the program and then lies down, so until the
		# head has come to rest the whole scene follows the face, upright to the eyes whichever
		# way they lie. The countdown does not begin until it has stopped following.
		looked = -1
		dwell = 0.0
		if not xr_on:
			stage.global_transform = Transform3D()
			state = EYETEST if eye_test else OPEN
			t_state = 0.0
			idle = 0.0
			match flat_args.get("state", ""):
				"sound":
					state = MENU_SOUND
				"timer":
					state = MENU_TIMER
				"watch":
					begin_watch()
				"wind":
					begin_watch()
					begin_wind_down()
			g_open = 1.0 if state == OPEN else 0.0
			g_sound = 1.0 if state == MENU_SOUND else 0.0
			g_timer = 1.0 if state == MENU_TIMER else 0.0
			g_watch = 1.0 if state == WATCH else 0.0
			if flat_args.has("t"):
				t_state = float(flat_args["t"])
				idle = t_state
			return
		# The world never moves while it can be seen: that is what makes people sick. So it is
		# black until the head has been at rest, then it is hung once, fixed, and fades in.
		var fwd := -cam.global_transform.basis.z
		var turning := rad_to_deg(fwd.angle_to(last_fwd)) / maxf(dt, 0.001) if last_fwd != Vector3.ZERO else 999.0
		last_fwd = fwd
		still_for = still_for + dt if turning < 10.0 else 0.0
		stage.visible = false
		appear = 0.0
		if (still_for > SETTLE_SECONDS and t_state > 1.0) or t_state > 20.0:
			stage.global_transform = Transform3D(cam.global_transform.basis.orthonormalized(), cam.global_transform.origin)
			stage.visible = true
			state = EYETEST if eye_test else OPEN
			t_state = 0.0
			idle = 0.0
			away_for = 0.0
		else:
			return

	var light := 1.0       # the sun, the planet, the air
	var others := 1.0      # the lights that were not chosen
	var pick := 1.0        # the chosen light
	var stars := 1.0

	# The scene is hung once and stays put: look anywhere, the galaxy's core is behind you.
	if leaving:
		appear = move_toward(appear, 0.0, dt / 1.0)
		if appear <= 0.0:
			get_tree().quit()      # no choice was written, so the launcher ends without going dark
	elif state != ORIENT:
		appear = move_toward(appear, 1.0, dt / 1.2)
	if not xr_on:
		appear = 1.0

	if (state == OPEN or state == MENU_SOUND or state == MENU_TIMER) and not leaving:
		var list: Array = open_items if state == OPEN else (sound_items if state == MENU_SOUND else timer_items)
		var raw := gaze_in(list) if (t_state > GRACE_SECONDS or flat_args.has("look")) else -1
		if raw == looked:
			look_miss = 0.0
		else:
			# a blink throws the gaze far away for an instant: only a third of a second off counts
			look_miss += dt
			if look_miss > 0.33 or looked < 0 or flat_args.has("look"):
				looked = raw
				dwell = 0.0
				look_miss = 0.0
		if looked >= 0:
			dwell += dt if not flat_args.has("dwell") else 0.0
			if flat_args.has("dwell"):
				dwell = float(flat_args["dwell"])
		else:
			dwell = 0.0
			# the countdown runs only while the head is at rest: looking around starts it over.
			# Measured over half a second, so the tracker's own tremble does not count as looking.
			idle += dt
			if eyes_live():
				idle = 0.0           # with the eyes tracked there is no countdown: closed eyes do that job
			ref_age += dt
			if ref_age >= 0.5:
				var fwd2 := -cam.global_transform.basis.z
				if xr_on and ref_fwd != Vector3.ZERO and rad_to_deg(fwd2.angle_to(ref_fwd)) > 4.0:
					idle = 0.0
				ref_fwd = fwd2
				ref_age = 0.0
		# The sound menu: a sound that was just put in or taken out cannot change again until the
		# eyes have left it; a fourth sound is quietly refused; and there is no going on with nothing.
		if mix_lock >= 0 and (looked != mix_lock or state != MENU_SOUND):
			mix_lock = -1
		if state == MENU_SOUND and looked >= 0 and not flat_args.has("dwell"):
			var is_sound := looked < bodies.size()
			if looked == mix_lock \
					or (is_sound and set_mix.size() >= MIX_MAX and not set_mix.has(bodies[looked].id)) \
					or (not is_sound and set_mix.is_empty()):
				dwell = 0.0
		var picked := -1
		if looked >= 0 and dwell >= DWELL_SECONDS and not flat_args.has("dwell"):
			picked = looked
		elif (xr_on and eyes_closed()) or (idle >= (CHOOSE_SECONDS if state == OPEN else CHOOSE_SECONDS * 2.0) and not flat_args.has("t")):
			# eyes closed for five seconds, or (with no eye tracker) left alone: "as before" at the
			# opening; in a menu, whatever is already set
			if state == OPEN:
				picked = 0
			elif state == MENU_SOUND:
				if set_mix.is_empty():
					set_mix = [bodies[0].id]
				picked = bodies.size()        # on to the timer with the mix as it stands
			else:
				picked = 3
				for i in timer_items.size():
					if timer_items[i].minutes == set_timer:
						picked = i
		if picked >= 0 and state == MENU_SOUND and picked < bodies.size():
			# a sound joins tonight's mix, or leaves it; the menu stays
			var pid: String = bodies[picked].id
			if set_mix.has(pid):
				set_mix.erase(pid)
			elif set_mix.size() < MIX_MAX:
				set_mix.append(pid)
			mix_lock = picked
			dwell = 0.0
			idle = 0.0
			picked = -1
			print("mix: ", "+".join(set_mix), "  at ", snappedf(t_state, 0.1), " s")
		if picked >= 0:
			var was := state
			dwell = 0.0
			idle = 0.0
			looked = -1
			t_state = 0.0
			if was == OPEN:
				if open_items[picked].id == "before":
					begin_watch()
				elif open_items[picked].id == "leave":
					leaving = true
				else:
					state = MENU_SOUND
			elif was == MENU_SOUND:
				state = MENU_TIMER
			else:
				set_timer = timer_items[picked].minutes
				begin_watch()
	elif state == WATCH:
		# the sky stays until the eyes close
		var blind := t_run - eyes_seen_at > 1.0
		if eyes_closed() or (blind and t_state > WATCH_FALLBACK and not flat_args.has("t")):
			begin_wind_down()
	elif state == WIND_DOWN:
		var k := clampf(t_state / WIND_DOWN_SECONDS, 0.0, 1.0)
		set_sun(clampf(k / 0.8, 0.0, 1.0))
		others = 1.0 - smoothstep(0.0, 0.25, k)
		light = 1.0 - smoothstep(0.35, 0.80, k)
		pick = 1.0 - smoothstep(0.55, 0.9, k)
		stars = 1.0 - smoothstep(0.8, 1.0, k)
		if k >= 1.0:
			state = DARK
			t_state = 0.0
	elif state == DARK:
		light = 0.0
		others = 0.0
		pick = 0.0
		stars = 0.0
		if OS.get_environment("SLEEPFRAME_LAUNCHER") == "1":
			if not said_dark:
				said_dark = true
				var df := FileAccess.open("user://dark", FileAccess.WRITE)      # the launcher turns the screens off on this
				if df:
					df.store_string("dark")
					df.close()
			if t_state > 1.6:
				get_tree().quit()      # the screens are off by now; the launcher carries the sound on

	if state == EYETEST:
		# walk through the steps by the clock; the words say what to do, the chimes mark the closed part
		var at := 0.0
		var step := TEST_STEPS.size()
		for i in TEST_STEPS.size():
			if t_state < at + TEST_STEPS[i][0]:
				step = i
				break
			at += TEST_STEPS[i][0]
		if step != test_step:
			test_step = step
			if step < TEST_STEPS.size():
				test_words.text = TEST_STEPS[step][1]
				for n in int(TEST_STEPS[step][3]):
					get_tree().create_timer(n * 0.95).timeout.connect(func(): test_chime.play())
		if step >= TEST_STEPS.size():
			leaving = true
		test_words.modulate = Color(WORDS_COLOUR.r, WORDS_COLOUR.g, WORDS_COLOUR.b, appear)
		for i in test_marks.size():
			test_marks[i].visible = step < TEST_STEPS.size() and TEST_STEPS[step][2] == i and appear > 0.5

	light *= appear
	others *= appear
	pick *= appear
	stars *= appear
	if state != WIND_DOWN:
		set_sun(0.0)
	planet_mat.set_shader_parameter("light", light)
	planet_mat.set_shader_parameter("drift", t_run * 0.00015)
	air_mat.set_shader_parameter("light", light)
	sun_mat.set_shader_parameter("light", light)
	if sun_lamp:
		sun_lamp.light_energy = 2.2 * light
	star_mat.set_shader_parameter("fade", stars)
	milky_mat.set_shader_parameter("fade", stars)
	# the dot marks where the HEAD points: hidden outright (not just darkened, which left a black
	# dot) while the eyes are choosing, and while you are only looking at the sky
	dot_node.visible = not (state == WATCH or eyes_live())
	dot_mat.albedo_color = Color(0.9, 0.8, 0.68) * (others if state >= WIND_DOWN else appear)      # no pointer dot while you are just looking at the sky

	# ---- which group is showing: each fades in and out, nothing pops
	g_open = move_toward(g_open, 1.0 if state == OPEN else 0.0, dt / 0.9)
	g_sound = move_toward(g_sound, 1.0 if state == MENU_SOUND else 0.0, dt / 0.9)
	g_timer = move_toward(g_timer, 1.0 if state == MENU_TIMER else 0.0, dt / 0.9)
	var breath := 0.5 + 0.5 * sin(t_run * TAU / 6.0)      # one slow breath every six seconds
	var count := clampf(idle / CHOOSE_SECONDS, 0.0, 1.0) if state == OPEN else 0.0

	for i in open_items.size():
		var o: Dictionary = open_items[i]
		var lift := 0.55
		if state == OPEN and i == looked:
			lift = 1.0
		elif state == OPEN and i == 0:
			lift = 0.55 + 0.35 * count + 0.05 * breath       # "as before" brightens as the count runs
		o.mat.set_shader_parameter("gain", o.base * lift * g_open * appear)
		var os: float = 1.0 + (SWELL * clampf(dwell / DWELL_SECONDS, 0.0, 1.0) if (state == OPEN and i == looked) else 0.0)
		o.node.scale = Vector3.ONE * lerpf(o.node.scale.x, os, clampf(dt * 5.0, 0.0, 1.0))
		var wc := WORDS_COLOUR * clampf(lift * 1.25, 0.0, 1.0)
		o.label.modulate = Color(wc.r, wc.g, wc.b, g_open * appear)
		if o.sub:
			o.sub.modulate = Color(wc.r * 0.75, wc.g * 0.75, wc.b * 0.75, g_open * appear)

	var trim: float = MIX_TRIM[clampi(set_mix.size(), 0, MIX_MAX)]
	var full := set_mix.size() >= MIX_MAX
	for i in bodies.size():
		var b: Dictionary = bodies[i]
		var in_mix: bool = set_mix.has(b.id)
		var glow := 0.62
		var want_db := -60.0
		if state == MENU_SOUND:
			if in_mix:
				glow = 0.95                                    # in tonight's mix: lit, and playing
				want_db = b.vol - 4.0 + trim
			elif full:
				glow = 0.28                                    # three are chosen: the rest stand back
			if i == looked and (in_mix or not full):
				glow = 1.0
				if not in_mix:
					want_db = b.vol - 4.0 + MIX_TRIM[set_mix.size() + 1]      # rest on it and you hear it with the others
		elif state == MENU_TIMER:
			if in_mix:
				want_db = b.vol - 4.0 + trim
		elif state == OPEN:
			if in_mix:
				if looked == 0:
					want_db = b.vol - 8.0 + trim               # look at "as before" and you hear it
				elif looked < 0:
					want_db = lerpf(-34.0, b.vol - 8.0 + trim, count)
		elif state == WATCH:
			if in_mix:
				want_db = b.vol + trim
		elif state >= WIND_DOWN:
			if in_mix:
				want_db = b.vol + trim
				if OS.get_environment("SLEEPFRAME_LAUNCHER") == "1":
					# hand the sound to the launcher: ours down over the last three seconds
					var k2 := clampf(t_state / WIND_DOWN_SECONDS, 0.0, 1.0) if state == WIND_DOWN else 1.0
					want_db = lerpf(b.vol + trim, -50.0, smoothstep(0.7, 1.0, k2))
		glow *= g_sound * appear
		var bs: float = 1.0 + (SWELL * clampf(dwell / DWELL_SECONDS, 0.0, 1.0) if (state == MENU_SOUND and i == looked) else 0.0) \
			+ (SWELL * 0.5 if (state == MENU_SOUND and in_mix) else 0.0)
		b.mesh.scale = Vector3.ONE * lerpf(b.mesh.scale.x, bs, clampf(dt * 5.0, 0.0, 1.0))
		b.mesh.visible = glow > 0.012
		b.mat.set_shader_parameter("gain", glow)
		var leaving_mix := state == MENU_SOUND and i == looked and in_mix
		b.held.visible = in_mix and g_sound * appear > 0.012
		b.held_mat.set_shader_parameter("progress", 1.0 - (clampf(dwell / DWELL_SECONDS, 0.0, 1.0) if leaving_mix else 0.0))
		b.held_mat.set_shader_parameter("gain", 0.55 * g_sound * appear)
		var bc := WORDS_COLOUR * clampf(glow * 1.5, 0.0, 1.0)
		b.label.modulate = Color(bc.r, bc.g, bc.b, g_sound * appear)
		if leaving:
			want_db = -60.0
		if b.has:
			b.player.volume_db = move_toward(b.player.volume_db, want_db, dt * 60.0)

	# the way on from the sound menu: a small warm star, faint until there is a mix to go on with
	var on_done := state == MENU_SOUND and looked == bodies.size()
	var dg := (1.0 if on_done else (0.25 if set_mix.is_empty() else 0.62)) * g_sound * appear
	var dsw: float = 1.0 + (SWELL * 2.0 * clampf(dwell / DWELL_SECONDS, 0.0, 1.0) if on_done else 0.0)
	done_item.mesh.scale = Vector3.ONE * lerpf(done_item.mesh.scale.x, dsw, clampf(dt * 5.0, 0.0, 1.0))
	done_item.mesh.visible = dg > 0.012
	done_item.mat.albedo_color = Color(STAR_COLOUR.r * dg, STAR_COLOUR.g * dg, STAR_COLOUR.b * dg)
	var dc := WORDS_COLOUR * clampf(dg * 1.5, 0.0, 1.0)
	done_item.label.modulate = Color(dc.r, dc.g, dc.b, g_sound * appear)
	mix_sub.modulate = Color(WORDS_COLOUR.r * 0.5, WORDS_COLOUR.g * 0.5, WORDS_COLOUR.b * 0.5, g_sound * appear)
	# once everything is chosen: say how the night begins. It comes up slowly and leaves with the wind-down.
	g_watch = move_toward(g_watch, 1.0 if (state == WATCH and t_state > 1.0) else 0.0, dt / 1.5)
	watch_words.modulate = Color(WORDS_COLOUR.r * 0.8, WORDS_COLOUR.g * 0.8, WORDS_COLOUR.b * 0.8, g_watch * appear)
	watch_sub.modulate = Color(WORDS_COLOUR.r * 0.66, WORDS_COLOUR.g * 0.66, WORDS_COLOUR.b * 0.66, g_watch * appear)

	for i in timer_items.size():
		var ti: Dictionary = timer_items[i]
		var tg := (1.0 if (state == MENU_TIMER and i == looked) else 0.62) * g_timer * appear
		var tsw: float = 1.0 + (SWELL * clampf(dwell / DWELL_SECONDS, 0.0, 1.0) if (state == MENU_TIMER and i == looked) else 0.0)
		ti.mesh.scale = Vector3.ONE * lerpf(ti.mesh.scale.x, tsw, clampf(dt * 5.0, 0.0, 1.0))
		ti.mesh.visible = tg > 0.012
		ti.mat.set_shader_parameter("gain", tg)
		var tc := WORDS_COLOUR * clampf(tg * 1.5, 0.0, 1.0)
		ti.label.modulate = Color(tc.r, tc.g, tc.b, g_timer * appear)
	headings[0].modulate = Color(WORDS_COLOUR.r * 0.7, WORDS_COLOUR.g * 0.7, WORDS_COLOUR.b * 0.7, g_sound * appear)
	headings[1].modulate = Color(WORDS_COLOUR.r * 0.7, WORDS_COLOUR.g * 0.7, WORDS_COLOUR.b * 0.7, g_timer * appear)

	# ---- the ring that draws round what you are resting on
	var showing: Array = open_items if state == OPEN else (sound_items if state == MENU_SOUND else (timer_items if state == MENU_TIMER else []))
	var on_held := state == MENU_SOUND and looked >= 0 and looked < bodies.size() and set_mix.has(bodies[looked].id)
	if looked >= 0 and looked < showing.size() and not on_held:
		var it: Dictionary = showing[looked]
		var rr: float = BODY_DIST * tan(deg_to_rad(it.ring_deg))
		var rd: Vector3 = it.get("ring_dir", it.dir)
		ring.transform = Transform3D(Basis.looking_at(rd, Vector3.UP) * Basis.from_scale(Vector3(rr, rr, 1.0)), rd * BODY_DIST)
		ring_mat.set_shader_parameter("progress", clampf(dwell / DWELL_SECONDS, 0.0, 1.0))
		ring_mat.set_shader_parameter("gain", 0.9 * appear)
		ring.visible = true
	else:
		ring.visible = false

	# ---- a record of what the eye tracker reports, ten times a second (testing: is "eyes closed" visible?)
	if xr_on and eye_test and t_run >= eye_next:
		eye_next = t_run + (0.0 if eye_test else 0.1)
		if eye_log == null:
			eye_log = FileAccess.open("user://eyes.log", FileAccess.WRITE)
			if eye_log:
				eye_log.store_line("# time  state  head_yaw head_pitch | eyes: found tracking conf valid_ang valid_lin gaze_yaw gaze_pitch (degrees, in the scene)  | supported=%s" % str(xr_iface.is_eye_gaze_interaction_supported() if xr_iface and xr_iface.has_method("is_eye_gaze_interaction_supported") else "?"))
		if eye_log:
			var inv := stage.global_transform.basis.inverse()
			var hf := inv * (-cam.global_transform.basis.z)
			var line := "%s %6.1f %d  %6.1f %6.1f |" % [Time.get_time_string_from_system(), t_run, state, rad_to_deg(atan2(hf.x, -hf.z)), rad_to_deg(asin(clampf(hf.y, -1.0, 1.0)))]
			var tr: XRPositionalTracker = XRServer.get_tracker("/user/eyes_ext")
			if tr == null:
				line += " none"
			else:
				var ps: XRPose = tr.get_pose("default")
				if ps == null:
					line += " tracker-but-no-pose"
				else:
					var gf := inv * (origin.global_transform.basis * (-ps.transform.basis.z))
					line += " yes %s %d  %6.1f %6.1f" % [str(ps.has_tracking_data), ps.tracking_confidence, rad_to_deg(atan2(gf.x, -gf.z)), rad_to_deg(asin(clampf(gf.y, -1.0, 1.0)))]
			eye_log.store_line(line + ("  step=%d" % test_step if eye_test else ""))
			eye_log.flush()

	if xr_on and t_run >= perf_next:
		perf_next += 5.0
		var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE if (perf_begun and FileAccess.file_exists("user://perf.log")) else FileAccess.WRITE)
		perf_begun = true
		if f:
			f.seek_end()
			f.store_line("%s  %5.1fs  %.0f fps  state %d  chosen %d" % [Time.get_datetime_string_from_system(), t_run, Engine.get_frames_per_second(), state, chosen])

	if flat_args.has("shot") and not shot_done and Engine.get_process_frames() > 12:
		shot_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(flat_args["shot"])
		get_tree().quit()


func _exit_tree() -> void:
	for th in threads:
		if th.is_started():
			th.wait_to_finish()
