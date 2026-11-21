extends SceneTree
## Mixture fuzzer: random adds, heats, pours, vents and thermal steps across a
## few containers. Fails on NaN/Inf, out-of-range temperature, or any drift
## in the mass or energy books.
## Usage: godot --headless --path . --script res://tools/fuzz_reactions_3d.gd

const ITERATIONS: int = 40000
const CONTAINER_COUNT: int = 3
const SEED: int = 0xA1C4E31


func _initialize() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var species: int = SubstanceRegistry.count()
	var boxes: Array[MixtureContainer] = []
	for _i: int in CONTAINER_COUNT:
		boxes.append(MixtureContainer.new())

	var mass_in_kg: float = 0.0
	var mass_out_kg: float = 0.0
	var energy_in_j: float = 0.0
	var energy_out_j: float = 0.0
	var failures: int = 0

	for step: int in ITERATIONS:
		var box: MixtureContainer = boxes[rng.randi_range(0, CONTAINER_COUNT - 1)]
		var other: MixtureContainer = boxes[rng.randi_range(0, CONTAINER_COUNT - 1)]
		var op: int = rng.randi_range(0, 6)
		match op:
			0:
				var idx: int = rng.randi_range(0, species - 1)
				var n: float = rng.randf_range(0.0, 3.0)
				var t: float = rng.randf_range(1.0, 2000.0)
				var h_before: float = box.enthalpy_joules
				var m_before: float = box.get_total_mass_kg()
				var c_before: float = box.clamp_correction_joules
				box.add_substance(idx, n, t)
				mass_in_kg += box.get_total_mass_kg() - m_before
				# Exclude any clamp correction; it is booked separately below.
				energy_in_j += (box.enthalpy_joules - h_before) - (box.clamp_correction_joules - c_before)
			1:
				energy_in_j += box.add_heat(rng.randf_range(-2e5, 5e5))
			2:
				if box != other:
					box.transfer_liquid_volume_to(other, rng.randf_range(0.0, 2e-4))
			3:
				mass_out_kg += box.transfer_liquid_volume_to(null, rng.randf_range(0.0, 1e-4))
				energy_out_j += box.last_transfer_enthalpy_joules
			4:
				mass_out_kg += box.vent_gas(rng.randf())
				energy_out_j += box.last_transfer_enthalpy_joules
			6:
				energy_in_j += box.step_reactions(SimConstants.TICK_SECONDS, rng.randf_range(0.0, 2.0))
			5:
				energy_in_j += box.step_thermal(SimConstants.TICK_SECONDS, rng.randf_range(100.0, 900.0), rng.randf_range(0.0, 50.0))

		var mass_now: float = 0.0
		var energy_now: float = 0.0
		var corrections: float = 0.0
		for b: MixtureContainer in boxes:
			mass_now += b.get_total_mass_kg()
			energy_now += b.enthalpy_joules
			corrections += b.clamp_correction_joules
			var t_k: float = b.temperature_kelvin
			if is_nan(t_k) or is_inf(t_k) or t_k < SimConstants.MIN_TEMP_KELVIN or t_k > SimConstants.MAX_TEMP_KELVIN:
				printerr("step %d: bad temperature %s" % [step, str(t_k)])
				failures += 1
			if is_nan(b.enthalpy_joules) or is_inf(b.enthalpy_joules):
				printerr("step %d: bad enthalpy" % step)
				failures += 1
		var mass_drift: float = mass_now - (mass_in_kg - mass_out_kg)
		var energy_expected: float = energy_in_j - energy_out_j + corrections
		var energy_drift: float = energy_now - energy_expected
		if absf(mass_drift) > 1e-9 * maxf(1.0, mass_in_kg):
			printerr("step %d: mass drift %s kg" % [step, str(mass_drift)])
			failures += 1
		if absf(energy_drift) > 1e-8 * maxf(1.0, absf(energy_in_j) + absf(energy_out_j)):
			printerr("step %d op %d: energy drift %s J" % [step, op, str(energy_drift)])
			failures += 1
		if failures > 10:
			break

	if failures == 0:
		print("FUZZ PASS: %d steps, %.3f kg in, %.3f kg out" % [ITERATIONS, mass_in_kg, mass_out_kg])
		quit(0)
	else:
		printerr("FUZZ FAIL: %d problems" % failures)
		quit(1)
