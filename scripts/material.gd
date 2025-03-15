extends CharacterBody3D

# إعدادات نطاق التفاعل
@export var detection_range: float = 5.0  # المسافة التي يبدأ عندها اكتشاف اللاعب
@export var attraction_range: float = 4.0  # المسافة التي يبدأ عندها الانجذاب
@export var absorption_threshold: float = 1.5  # المسافة التي يمكن عندها امتصاص الكائن

# إعدادات الحركة
@export var min_attraction_speed: float = 1.0  # أقل سرعة انجذاب
@export var max_attraction_speed: float = 8.0  # أقصى سرعة انجذاب
@export var acceleration: float = 10.0  # تسارع الانجذاب

# إعدادات الدوران
@export var orbit_speed: float = 2.0  # سرعة الدوران حول اللاعب
@export var orbit_radius_shrink_rate: float = 0.8  # معدل تقلص نصف قطر المدار
@export var orbit_height_variation: float = 0.5  # تنوع في ارتفاع المدار
@export var spiral_factor: float = 0.7  # عامل الحركة الحلزونية (1.0 = حلزون قوي، 0.0 = دوران منتظم)

# إعدادات التأثيرات
@export var enable_rotation: bool = true  # تمكين دوران الكائن حول نفسه
@export var rotation_speed: float = 5.0  # سرعة دوران الكائن حول نفسه
@export var material_type: String = "iron"  # نوع المادة
@export var material_amount: float = 1.0  # كمية المادة

# إعدادات الجاذبية والحركة الفضائية
@export var space_gravity: bool = true  # تفعيل حركة الجاذبية الفضائية
@export var gravity_strength: float = 0.2  # قوة الجاذبية
@export var max_float_speed: float = 0.8  # أقصى سرعة للتحرك العشوائي
@export var damping: float = 0.98  # معامل تخميد الحركة (أقل من 1.0 يعني تباطؤ تدريجي)
@export var random_movement: bool = true  # تفعيل الحركة العشوائية البطيئة

# مرجع للاعب
var player = null

# متغيرات الحالة
var is_being_attracted: bool = false  # هل الكائن تحت تأثير الجذب
var current_rotation: Vector3 = Vector3.ZERO  # الدوران الحالي للكائن
var current_rotation_speed: float = 0.0  # سرعة الدوران الحالية
var orbit_angle: float = 0.0  # زاوية الدوران حول اللاعب
var current_orbit_radius: float = 0.0  # نصف قطر المدار الحالي
var initial_distance: float = 0.0  # المسافة الأولية من اللاعب
var orbit_y_offset: float = 0.0  # تنوع في الارتفاع للمدار
var activation_timer: float = 0.5  # تأخير قبل تفعيل السلوك
var random_direction: Vector3 = Vector3.ZERO  # اتجاه التحرك العشوائي
var time_to_next_direction: float = 0.0  # الوقت المتبقي قبل تغيير الاتجاه

# متغيرات للتأثيرات البصرية
@onready var mesh_instance = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var particles = $GPUParticles3D if has_node("GPUParticles3D") else null
@onready var original_scale = scale  # الحجم الأصلي للكائن

func _ready():
	# البحث عن اللاعب
	player = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
		if not player:
			player = get_node_or_null("/root/Player")
	
	# التأكد من أن مسافة الانجذاب أقل من أو تساوي مسافة الاكتشاف
	attraction_range = min(attraction_range, detection_range)
	
	# توليد زاوية دوران عشوائية أولية
	orbit_angle = randf() * 2.0 * PI
	
	# توليد تنوع عشوائي في الارتفاع
	orbit_y_offset = (randf() * 2.0 - 1.0) * orbit_height_variation
	
	# تهيئة الاتجاه العشوائي الأولي للحركة الفضائية
	generate_random_direction()
	
	# تكوين التأثيرات الأولية
	if particles:
		particles.emitting = false  # إيقاف الجسيمات حتى يبدأ الانجذاب
	
	# بدء الدوران البطيء كجزء من الحركة الفضائية
	if enable_rotation:
		current_rotation_speed = randf_range(0.1, 0.3)  # دوران بطيء عشوائي

func _physics_process(delta):
	# تأخير تفعيل السلوك
	if activation_timer > 0:
		activation_timer -= delta
		return
	
	if player:
		# حساب المسافة بين الكائن واللاعب
		var distance_to_player = global_position.distance_to(player.global_position)
		
		# التحقق إذا كان اللاعب في نطاق الاكتشاف (قريباً بما يكفي)
		if distance_to_player < detection_range:
			# التحقق إذا كان اللاعب قريباً بما يكفي للانجذاب
			if distance_to_player < attraction_range:
				handle_attraction(distance_to_player, delta)
			else:
				# في نطاق الاكتشاف لكن ليس قريباً بما يكفي للانجذاب
				look_at_player(delta)
				
				# توقف الانجذاب إذا كان نشطاً
				if is_being_attracted:
					stop_attraction()
					
				# تطبيق الحركة الفضائية عندما لا يكون في حالة انجذاب
				apply_space_motion(delta)
		else:
			# اللاعب بعيد جداً، إلغاء أي تفاعل
			if is_being_attracted:
				stop_attraction()
			
			# تطبيق الحركة الفضائية عندما لا يكون اللاعب قريباً
			apply_space_motion(delta)
	else:
		# في حالة عدم وجود اللاعب، تطبيق الحركة الفضائية فقط
		apply_space_motion(delta)
	
	# تنفيذ الحركة
	move_and_slide()

# التعامل مع حالة الانجذاب نحو اللاعب
func handle_attraction(distance_to_player, delta):
	# إذا لم يكن في حالة انجذاب بعد، تعيين المسافة الأولية
	if not is_being_attracted:
		is_being_attracted = true
		initial_distance = distance_to_player
		current_orbit_radius = distance_to_player * 0.9  # بدء المدار على مسافة قريبة من المسافة الأولية
		
		# تفعيل الجسيمات إذا كانت موجودة
		if particles and not particles.emitting:
			particles.emitting = true
	
	# تحديث نصف قطر المدار (يتقلص تدريجياً مع الوقت)
	current_orbit_radius = lerp(current_orbit_radius, absorption_threshold, delta * orbit_radius_shrink_rate)
	
	# احسب النسبة من المسافة الأولية
	var distance_ratio = current_orbit_radius / initial_distance
	
	# تحديث زاوية الدوران
	orbit_angle += delta * orbit_speed * (1.0 / max(distance_ratio, 0.1))  # أسرع عندما يكون أقرب
	
	# حساب الموقع الجديد على المدار مع إضافة تنوع في الارتفاع
	var offset = Vector3(
		cos(orbit_angle) * current_orbit_radius,
		orbit_y_offset * current_orbit_radius,
		sin(orbit_angle) * current_orbit_radius
	)
	
	var target_position = player.global_position + offset
	
	# حساب اتجاه الحركة نحو المدار المحدد
	var direction_to_orbit = (target_position - global_position).normalized()
	
	# إضافة عنصر حلزوني (حركة نحو اللاعب)
	var direction_to_player = (player.global_position - global_position).normalized()
	var blended_direction = direction_to_orbit.lerp(direction_to_player, spiral_factor * (1.0 - distance_ratio))
	
	# احسب سرعة الانجذاب بناءً على المسافة
	var orbit_attraction_speed = lerp(min_attraction_speed, max_attraction_speed, 1.0 - distance_ratio)
	
	# تحديث السرعة تدريجياً
	velocity = velocity.move_toward(blended_direction * orbit_attraction_speed, acceleration * delta)
	
	# تطبيق الدوران الذاتي إذا كان مفعلاً
	apply_self_rotation(delta, true)  # دوران سريع أثناء الانجذاب
	
	# تقليل حجم الكائن تدريجياً مع اقترابه من اللاعب
	var scale_factor = distance_to_player / attraction_range
	scale = original_scale * max(0.5, scale_factor)
	
	# التحقق إذا كان الكائن قريباً بما يكفي للامتصاص
	if distance_to_player < absorption_threshold:
		on_absorbed()

# تطبيق الحركة الفضائية عندما لا يكون في حالة انجذاب
func apply_space_motion(delta):
	if space_gravity:
		# تحديث المؤقت للاتجاه العشوائي
		time_to_next_direction -= delta
		if time_to_next_direction <= 0:
			generate_random_direction()
		
		# تطبيق الحركة العشوائية البطيئة
		if random_movement:
			velocity += random_direction * gravity_strength * delta
			
			# تحديد السرعة القصوى للحركة العشوائية
			if velocity.length() > max_float_speed:
				velocity = velocity.normalized() * max_float_speed
		
		# تطبيق التخميد (تباطؤ تدريجي)
		velocity *= damping
		
		# دوران بطيء للكائن
		apply_self_rotation(delta, false)  # دوران بطيء أثناء الحركة الفضائية

# توليد اتجاه عشوائي جديد للحركة الفضائية
func generate_random_direction():
	random_direction = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-0.5, 0.5),  # حركة أقل على المحور Y
		randf_range(-1.0, 1.0)
	).normalized() * 0.5  # تقليل القوة للحصول على حركة أبطأ
	
	# تعيين مدة عشوائية قبل تغيير الاتجاه التالي (5-10 ثوانٍ)
	time_to_next_direction = randf_range(5.0, 10.0)

# تطبيق الدوران الذاتي للكائن (حول نفسه)
func apply_self_rotation(delta, fast_rotation):
	if enable_rotation:
		if fast_rotation:
			# دوران سريع أثناء الانجذاب
			current_rotation_speed = min(current_rotation_speed + delta * 2.0, rotation_speed)
		else:
			# دوران بطيء أثناء الحركة الفضائية
			current_rotation_speed = min(current_rotation_speed, 0.5)
		
		# تحديث الدوران
		current_rotation.x += current_rotation_speed * delta
		current_rotation.y += current_rotation_speed * delta * 0.7
		current_rotation.z += current_rotation_speed * delta * 0.5
		
		# تطبيق الدوران
		rotation_degrees = current_rotation

# النظر نحو اللاعب بدون انجذاب
func look_at_player(delta):
	if player:
		# حساب الاتجاه نحو اللاعب
		var direction_to_player = player.global_position - global_position
		
		# فقط دوران بطيء نحو اللاعب
		if direction_to_player.length() > 0.5:
			var target_rotation = Vector3(0, atan2(-direction_to_player.x, -direction_to_player.z), 0)
			rotation.y = lerp_angle(rotation.y, target_rotation.y, delta * 2.0)

# توقف الانجذاب وإعادة الحالة الطبيعية
func stop_attraction():
	is_being_attracted = false
	
	# إيقاف الجسيمات
	if particles:
		particles.emitting = false
	
	# تقليل سرعة الدوران تدريجياً
	current_rotation_speed = max(current_rotation_speed - 0.1, 0.0)
	
	# استعادة الحجم الأصلي تدريجياً
	scale = scale.lerp(original_scale, 0.1)
	
	# تقليل السرعة تدريجياً (لكن ليس بشكل كامل للحفاظ على الحركة الفضائية)
	velocity = velocity.move_toward(Vector3.ZERO, 0.3)

# الدالة التي تُستدعى عند امتصاص الكائن
func on_absorbed():
	# تعطيل التصادم لمنع التفاعلات الإضافية
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	# تفعيل تأثير نهائي للامتصاص
	if particles:
		particles.amount = 20  # زيادة عدد الجسيمات
		particles.one_shot = true  # جعلها انبعاث لمرة واحدة
		particles.emitting = true
	
	# تقليل حجم الكائن تدريجياً
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
	
	# محاولة إرسال المادة إلى اللاعب
	if player.has_method("add_absorbed_material"):
		player.add_absorbed_material(material_type, material_amount)
	elif player:
		print("أضف دالة add_absorbed_material إلى اللاعب لتلقي المواد")
	
	# حذف الكائن بعد انتهاء التأثير
	tween.tween_callback(queue_free)
	
	# تعطيل معالجة الفيزياء لمنع الحركة الإضافية
	set_physics_process(false)
