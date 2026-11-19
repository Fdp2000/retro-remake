@tool
class_name ContainerShovePhysics
extends RefCounted

## Physics-like shove/throw velocity tracking, friction damping, and interior wall bounce
## for objects dragged inside SearchableContainer Drawers and Briefcases.
## Operates strictly in normalized [0..1] X/Y interior space so vertical layer separation is preserved.

const SAMPLE_WINDOW_SEC: float = 0.085
const PAUSE_CUTOFF_SEC: float = 0.090
const MAX_SAMPLE_AGE_SEC: float = 0.140

const DEFAULT_MOMENTUM_SCALE: float = 1.00
const DEFAULT_FRICTION: float = 6.5
const DEFAULT_WALL_BOUNCE: float = 0.42
const DEFAULT_MAX_SPEED: float = 4.5
const DEFAULT_STOP_SPEED: float = 0.04


## Safely reads drag/slide tunables from GameConfig with fallback defaults.
static func get_config_dict() -> Dictionary:
	var cfg: Dictionary = {
		"momentum_scale": DEFAULT_MOMENTUM_SCALE,
		"friction": DEFAULT_FRICTION,
		"bounce": DEFAULT_WALL_BOUNCE,
		"max_speed": DEFAULT_MAX_SPEED,
		"stop_speed": DEFAULT_STOP_SPEED
	}
	if GameConfig != null:
		var v: Variant = GameConfig.get("container_drag_momentum_scale")
		if v is float or v is int:
			cfg["momentum_scale"] = float(v)
		v = GameConfig.get("container_drag_friction")
		if v is float or v is int:
			cfg["friction"] = float(v)
		v = GameConfig.get("container_drag_wall_bounce")
		if v is float or v is int:
			cfg["bounce"] = float(v)
		v = GameConfig.get("container_drag_max_speed")
		if v is float or v is int:
			cfg["max_speed"] = float(v)
		v = GameConfig.get("container_drag_stop_speed")
		if v is float or v is int:
			cfg["stop_speed"] = float(v)
	return cfg


## Appends a timestamped normalized cursor sample and prunes stale history beyond MAX_SAMPLE_AGE_SEC.
static func record_sample(samples: Array, norm_pos: Vector2, now_sec: float) -> void:
	samples.append({"t": now_sec, "p": norm_pos})
	var min_time: float = now_sec - MAX_SAMPLE_AGE_SEC
	while samples.size() > 1 and float((samples[0] as Dictionary).get("t", now_sec)) < min_time:
		samples.remove_at(0)
	while samples.size() > 16:
		samples.remove_at(0)


## Computes release shove velocity in normalized units/second from recent cursor motion.
## Returns Vector2.ZERO if the cursor paused longer than PAUSE_CUTOFF_SEC before release.
static func compute_release_velocity(
	samples: Array,
	release_norm_pos: Vector2,
	now_sec: float,
	cfg: Dictionary = {}
) -> Vector2:
	if samples.is_empty():
		return Vector2.ZERO
	var resolved: Dictionary = get_config_dict() if cfg.is_empty() else cfg
	var momentum_scale: float = float(resolved.get("momentum_scale", DEFAULT_MOMENTUM_SCALE))
	var max_speed: float = float(resolved.get("max_speed", DEFAULT_MAX_SPEED))
	var stop_speed: float = float(resolved.get("stop_speed", DEFAULT_STOP_SPEED))

	var last: Dictionary = samples[samples.size() - 1] as Dictionary
	if now_sec - float(last.get("t", now_sec)) > PAUSE_CUTOFF_SEC:
		return Vector2.ZERO

	var window_start: float = now_sec - SAMPLE_WINDOW_SEC
	var oldest_idx: int = 0
	for i in range(samples.size()):
		var s: Dictionary = samples[i] as Dictionary
		if float(s.get("t", now_sec)) >= window_start:
			oldest_idx = i
			break

	var oldest: Dictionary = samples[oldest_idx] as Dictionary
	var dt: float = now_sec - float(oldest.get("t", now_sec))
	if dt < 0.004 and oldest_idx > 0:
		oldest_idx -= 1
		oldest = samples[oldest_idx] as Dictionary
		dt = now_sec - float(oldest.get("t", now_sec))
	if dt < 0.004:
		return Vector2.ZERO

	var vel: Vector2 = ((release_norm_pos - (oldest.get("p", release_norm_pos) as Vector2)) / dt) * momentum_scale
	if vel.length() < stop_speed * 2.5:
		return Vector2.ZERO
	return vel.limit_length(max_speed)


## Advances one sliding object for delta seconds with exponential damping and damped wall bounces.
static func step_slide(
	pos: Vector2,
	vel: Vector2,
	delta: float,
	bounds_min: float,
	bounds_max: float,
	cfg: Dictionary = {}
) -> Dictionary:
	var resolved: Dictionary = get_config_dict() if cfg.is_empty() else cfg
	var friction: float = maxf(float(resolved.get("friction", DEFAULT_FRICTION)), 0.0)
	var bounce: float = clampf(float(resolved.get("bounce", DEFAULT_WALL_BOUNCE)), 0.0, 1.0)
	var stop_speed: float = maxf(float(resolved.get("stop_speed", DEFAULT_STOP_SPEED)), 0.001)

	var clamped_delta: float = maxf(delta, 0.0)
	var substeps: int = clampi(int(ceilf(clamped_delta / 0.016)), 1, 8)
	var dt: float = clamped_delta / float(substeps)
	var cur_pos: Vector2 = Vector2(
		clampf(pos.x, bounds_min, bounds_max),
		clampf(pos.y, bounds_min, bounds_max)
	)
	var cur_vel: Vector2 = vel
	var bounced: bool = false
	var max_impact_speed: float = 0.0

	if clamped_delta > 0.0:
		for _s in range(substeps):
			cur_pos += cur_vel * dt
			if cur_pos.x < bounds_min:
				cur_pos.x = bounds_min
				max_impact_speed = maxf(max_impact_speed, absf(cur_vel.x))
				cur_vel.x = absf(cur_vel.x) * bounce
				if absf(cur_vel.x) < stop_speed * 0.5:
					cur_vel.x = 0.0
				bounced = true
			elif cur_pos.x > bounds_max:
				cur_pos.x = bounds_max
				max_impact_speed = maxf(max_impact_speed, absf(cur_vel.x))
				cur_vel.x = -absf(cur_vel.x) * bounce
				if absf(cur_vel.x) < stop_speed * 0.5:
					cur_vel.x = 0.0
				bounced = true

			if cur_pos.y < bounds_min:
				cur_pos.y = bounds_min
				max_impact_speed = maxf(max_impact_speed, absf(cur_vel.y))
				cur_vel.y = absf(cur_vel.y) * bounce
				if absf(cur_vel.y) < stop_speed * 0.5:
					cur_vel.y = 0.0
				bounced = true
			elif cur_pos.y > bounds_max:
				cur_pos.y = bounds_max
				max_impact_speed = maxf(max_impact_speed, absf(cur_vel.y))
				cur_vel.y = -absf(cur_vel.y) * bounce
				if absf(cur_vel.y) < stop_speed * 0.5:
					cur_vel.y = 0.0
				bounced = true

			cur_vel *= exp(-friction * dt)

	cur_pos = Vector2(
		clampf(cur_pos.x, bounds_min, bounds_max),
		clampf(cur_pos.y, bounds_min, bounds_max)
	)
	var settled: bool = (cur_vel.length() <= stop_speed)
	if settled:
		cur_vel = Vector2.ZERO

	return {
		"pos": cur_pos,
		"vel": cur_vel,
		"bounced": bounced,
		"impact_speed": max_impact_speed,
		"settled": settled
	}


## Fast-forwards a slide to its deterministic resting coordinates within interior bounds.
static func simulate_to_rest(
	pos: Vector2,
	vel: Vector2,
	bounds_min: float,
	bounds_max: float,
	cfg: Dictionary = {},
	max_steps: int = 180
) -> Vector2:
	var cur_pos: Vector2 = Vector2(
		clampf(pos.x, bounds_min, bounds_max),
		clampf(pos.y, bounds_min, bounds_max)
	)
	var cur_vel: Vector2 = vel
	for _i in range(maxi(max_steps, 1)):
		var step_res: Dictionary = step_slide(cur_pos, cur_vel, 1.0 / 60.0, bounds_min, bounds_max, cfg)
		cur_pos = step_res["pos"] as Vector2
		cur_vel = step_res["vel"] as Vector2
		if bool(step_res["settled"]):
			break
	return cur_pos
