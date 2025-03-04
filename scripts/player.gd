extends CharacterBody3D
#تعريف القور للhealth bar 
const HEALTH_BAR_1 = preload("res://photos/health bar 1.png")
const HEALTH_BAR_2 = preload("res://photos/health bar 2.png")
const HEALTH_BAR_3 = preload("res://photos/health bar 3.png")
const HEALTH_BAR_4 = preload("res://photos/health bar 4.png")
const HEALTH_BAR_5 = preload("res://photos/health bar 5.png")
const HEALTH_BAR_6 = preload("res://photos/heealth bar 6.png")

# خصائص الحركة والفيزياء
@export var max_speed: float = 10.0        # السرعة القصوى للثقب الأسود
@export var acceleration: float = 500.0    # معدل تسارع الثقب الأسود
@export var friction: float = 300.0        # معدل تباطؤ الثقب الأسود

# خصائص الجاذبية الديناميكية
@export var speed_gravity_factor: float = 0.5  # معامل تأثير السرعة على الجاذبية
@export var min_gravity: float = 3.5           # الحد الأدنى للجاذبية
@export var max_gravity: float = 80.0          # الحد الأقصى للجاذبية
@export var gravity_smoothness: float = 5.0    # معامل نعومة تغيير الجاذبية

# خصائص الثقب الأسود
@export var player_size: float = 1.0  # حجم الثقب الأسود الأساسي
@export var absorption_multiplier: float = 1.0  # مضاعف سرعة الامتصاص
@export var can_absorb: bool = true  # هل يمكن للاعب الامتصاص حالياً

# متغيرات لتأثيرات الأدوات
var shield_active: bool = false  # هل الدرع مفعل

# مراجع للعقد الفرعية
@onready var mesh_instance = $MeshInstance3D  # نموذج الثقب الأسود
@onready var collision_shape = $CollisionShape3D  # شكل التصادم
@onready var material = $MeshInstance3D.get_surface_override_material(0) as ShaderMaterial  # مادة الشادر
@onready var sprite_material = $MeshInstance3D.get_surface_override_material(0) as ShaderMaterial  # مادة الشادر (نفس المرجع)
@onready var camera = $Camera3D  # الكاميرا
@onready var hud_label = $CanvasLayer/Label  # نص واجهة المستخدم
@onready var absorption_area = $AbsorptionArea  # منطقة الامتصاص
@onready var health_bar = $HealthBar  # شريط الصحة
@onready var camera_3d = $Camera3D


# نظام الإشارات
signal size_changed(new_size)
signal player_damaged(amount)
signal shield_toggled(is_active)

# متغيرات داخلية
var current_gravity: float = 0.0  # قيمة الجاذبية الحالية
var health: float = 100.0  # صحة اللاعب
var energy: float = 100.0  # طاقة اللاعب
var shrink_timer: float = 0.0  # مؤقت لتأثير التقلص
var original_size: float = 1.0  # الحجم الأصلي قبل التأثيرات

# متغيرات لمخزون المواد في سكريبت اللاعب
var materials_inventory = {
	"iron": 0.0,
	"copper": 0.0,
	"silicon": 0.0
}

# الدالة التي تستقبل المواد الممتصة
func add_absorbed_material(material_type: String, amount: float):
	# التحقق من نوع المادة وإضافتها إلى المخزون
	if materials_inventory.has(material_type):
		materials_inventory[material_type] += amount
		print("تم امتصاص " + str(amount) + " من " + material_type)
		print("المخزون الحالي: " + str(materials_inventory))
		
		# يمكن إضافة تأثيرات إضافية هنا (صوت، تأثير بصري، إلخ)
		
		# تحديث واجهة المستخدم لعرض المخزون الجديد
		update_materials_display()
	else:
		print("نوع مادة غير معروف: " + material_type)

# تحديث عرض المخزون في واجهة المستخدم
func update_materials_display():
	# إذا كانت لديك واجهة مستخدم لعرض المخزون، قم بتحديثها هنا
	if has_node("CanvasLayer/MaterialsDisplay"):
		$CanvasLayer/MaterialsDisplay.update_display(materials_inventory)

func _ready():
	# تهيئة المظهر البصري للثقب الأسود
	original_size = player_size
	update_visual_size()
	
	# تهيئة مادة الشادر
	if material:
		material.set_shader_parameter("color", Color(0.0, 0.0, 0.0, 1.0))  # أسود
	
	if sprite_material:
		sprite_material.set_shader_parameter("time", 0.0)  # تعيين قيمة ابتدائية للوقت
	
	# تهيئة منطقة الامتصاص
	if absorption_area:
		absorption_area.scale = Vector3.ONE * (player_size + 2.0)  # منطقة الامتصاص أكبر من الثقب نفسه
	
	# تهيئة شريط الصحة
	update_health_bar()
	
	# الاتصال بإشارة تلقي الضرر لتحديث شريط الصحة
	connect("player_damaged", update_health_bar_on_damage)

func _process(delta):
	# تحديث قيمة الوقت في الشادر
	if sprite_material:
		var current_time = sprite_material.get_shader_parameter("time") if sprite_material.get_shader_parameter("time") != null else 0.0
		sprite_material.set_shader_parameter("time", current_time + delta)
	
	# تحديث مؤقت التقلص إذا كان نشطاً
	if shrink_timer > 0:
		shrink_timer -= delta
		if shrink_timer <= 0:
			# استعادة الحجم الأصلي
			player_size = original_size
			update_visual_size()
			emit_signal("size_changed", player_size)
	
	# تحديث نص واجهة المستخدم
	update_hud()
	
	# التحقق من إدخال استخدام الأدوات
	check_tool_input()

func _physics_process(delta):
	# تنفيذ حركة اللاعب
	var direction = Vector3.ZERO
	
	# التقاط إدخال اللاعب لحركة سلسة على المحورين X و Z
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1  # التحرك لليسار (X-)
	if Input.is_action_pressed("ui_right"):
		direction.x += 1  # التحرك لليمين (X+)
	if Input.is_action_pressed("ui_up"):
		direction.y += 1  # التحرك للأمام (Z-)
	if Input.is_action_pressed("ui_down"):
		direction.y -= 1  # التحرك للخلف (Z+)
	
	if Input.is_action_pressed("middel_mouse"):
		if camera_3d.position.z <= 10 :
			camera_3d.position.z += 0.4  # التحرك للخلف (Z+)
	else :
		if camera_3d.position.z >= 3.5:
			camera_3d.position.z -= 1
		pass
	
	# إذا كان هناك إدخال حركة
	if direction != Vector3.ZERO:
		direction = direction.normalized()
		velocity = velocity.move_toward(direction * max_speed, acceleration * delta)  # تسريع سلس
		
		# حساب الجاذبية بناءً على سرعة اللاعب الأفقية
		var speed_ratio = velocity.length() / max_speed  # نسبة السرعة الحالية إلى السرعة القصوى
		var target_gravity = lerp(min_gravity, max_gravity, speed_ratio * speed_gravity_factor)
		
		# تنعيم تغيير الجاذبية للحصول على انتقال سلس
		current_gravity = lerp(current_gravity, target_gravity, delta * gravity_smoothness)
		
		# استهلاك الطاقة أثناء الحركة
		consume_energy(0.1 * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, friction * delta)  # تباطؤ تدريجي عند التوقف
		
		# تقليل الجاذبية عند التوقف
		current_gravity = lerp(current_gravity, 0.0, delta * gravity_smoothness)
		
		# استعادة الطاقة عند الثبات
		restore_energy(0.05 * delta)
	
	# تطبيق الجاذبية الحالية إذا لم يكن اللاعب على الأرض
	if not is_on_floor():
		velocity.y -= current_gravity * delta  # تطبيق الجاذبية الديناميكية
	
	move_and_slide()  # تنفيذ الحركة بناءً على السرعة والاتجاه

# تغيير حجم الثقب الأسود
func change_size(size_factor: float):
	player_size *= size_factor
	update_visual_size()
	emit_signal("size_changed", player_size)

# تحديث المظهر المرئي للثقب الأسود بناءً على حجمه
func update_visual_size():
	mesh_instance.scale = Vector3.ONE * player_size
	collision_shape.scale = Vector3.ONE * player_size
	if absorption_area:
		absorption_area.scale = Vector3.ONE * (player_size + 2.0)

# تصغير الثقب الأسود مؤقتًا (تأثير أنظمة الأمان)
func shrink_temporarily(factor: float, duration: float):
	original_size = player_size
	player_size *= factor
	update_visual_size()
	emit_signal("size_changed", player_size)
	shrink_timer = duration

# تطبيق قوة خارجية على اللاعب (مثل أجهزة ضغط الجاذبية)
func apply_external_force(force: Vector3):
	# تقليل القوة إذا كان الدرع مفعلًا
	if shield_active:
		force *= 0.3  # تقليل بنسبة 70%
	velocity += force

# تلقي ضرر (من أنظمة الأمان)
func take_damage(amount: float):
	# تقليل الضرر إذا كان الدرع مفعلًا
	if shield_active:
		amount *= 0.2  # تقليل بنسبة 80%
	
	health -= amount
	emit_signal("player_damaged", amount)
	
	# تحديث شريط الصحة مباشرةً
	update_health_bar()
	
	# التحقق من نفاد الصحة
	if health <= 0:
		die()

# استعادة الصحة
func heal(amount: float):
	health = min(health + amount, 100.0)
	# تحديث شريط الصحة عند استعادة الصحة
	update_health_bar()

# استهلاك الطاقة
func consume_energy(amount: float):
	energy = max(0.0, energy - amount)
	
	# تعطيل القدرة على الامتصاص عند نفاد الطاقة
	if energy <= 0 and can_absorb:
		can_absorb = false

# استعادة الطاقة
func restore_energy(amount: float):
	energy = min(energy + amount, 100.0)
	
	# إعادة تفعيل القدرة على الامتصاص عند استعادة الطاقة الكافية
	if energy > 10.0 and !can_absorb:
		can_absorb = true

# تفعيل/تعطيل الدرع
func toggle_shield(is_active: bool):
	shield_active = is_active
	
	# تأثير بصري لتفعيل الدرع
	if shield_active:
		if material:
			material.set_shader_parameter("shield_active", true)
	else:
		if material:
			material.set_shader_parameter("shield_active", false)
	
	emit_signal("shield_toggled", shield_active)

# تحديث نص واجهة المستخدم
func update_hud():
	if hud_label:
		hud_label.text = "الصحه: %d%%     
	
	
	
	
	
	الطاقه: %d%%" % [int(health), int(energy)]

# تحديث شريط الصحة بناء على قيمة الصحة الحالية
func update_health_bar():
	if health_bar:
		# تحديد الصورة المناسبة حسب نسبة الصحة
		if health > 83:  # 100-84% (صحة كاملة)
			health_bar.texture = HEALTH_BAR_1
		elif health > 66:  # 83-67%
			health_bar.texture = HEALTH_BAR_2
		elif health > 50:  # 66-51%
			health_bar.texture = HEALTH_BAR_3
		elif health > 33:  # 50-34%
			health_bar.texture = HEALTH_BAR_4
		elif health > 16:  # 33-17% 
			health_bar.texture = HEALTH_BAR_5
		else:  # 16-0% (صحة منخفضة)
			health_bar.texture = HEALTH_BAR_6

# دالة تُستدعى عند تلقي الضرر
func update_health_bar_on_damage(amount):
	update_health_bar()

# التحقق من إدخال استخدام الأدوات
func check_tool_input():
	# إذا ضغط اللاعب على مفتاح الامتصاص
	if Input.is_action_just_pressed("absorb") and energy > 0:
		# يمكن إضافة إشارة هنا لتفعيل الامتصاص
		pass
	
	# استخدام الدرع
	if Input.is_action_just_pressed("shield") and energy > 20:
		toggle_shield(true)
		consume_energy(20)  # استهلاك الطاقة عند تفعيل الدرع
	
	# إلغاء تفعيل الدرع عند ترك الزر
	if Input.is_action_just_released("shield") and shield_active:
		toggle_shield(false)

# عند نفاد الصحة
func die():
	# إيقاف حركة اللاعب
	velocity = Vector3.ZERO
	
	# تشغيل تأثير الموت (اختفاء تدريجي)
	if material:
		material.set_shader_parameter("death_effect", true)
	
	# تعطيل التحكم
	set_physics_process(false)
	set_process_input(false)
	
	# تحديث شريط الصحة ليكون فارغًا
	if health_bar:
		health_bar.texture = HEALTH_BAR_1
	
	# يمكن إضافة إشارة هنا لإعلام مدير اللعبة بموت اللاعب
	# emit_signal("player_died")
	
	# الانتقال إلى شاشة الموت بعد فترة
	await get_tree().create_timer(2.0).timeout
	# get_tree().change_scene_to_file("res://ui/game_over.tscn")
