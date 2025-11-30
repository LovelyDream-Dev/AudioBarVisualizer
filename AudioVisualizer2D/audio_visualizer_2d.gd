extends Node2D
class_name AudioVisualizer2D

# Shape that the audio visualizer will draw on.
@export var shape:Curve2D

@export_group("Audio Bus Effect")
var _audioBusIndex:int
@export var audioBusIndex:int = 0:
	set(value):
		manage_audio_bus_index_variable(value)
	get:
		return _audioBusIndex

var _spectrumEffectIndex:int
@export var spectrumEffectIndex:int = 0:
	set(value):
		manage_spectrum_effect_index_variable(value)
	get:
		return _spectrumEffectIndex

@export_group("Bars")
@export_range(1.0, 10000.0, 0.1) var pixelsPerDecibel:float = 1.0
@export var barCount:int = 32
@export var barWidth:float = 12.0
@export var maxBarHeight:float = 500.0
@export var spatialSmoothing:int = 2  # number of neighboring bars to average for spatial smoothing

@export_category("Appearance")
@export_group("Color")
@export var barColor:Color = Color.WHITE

@export_group("Smoothing")
@export_range(0.0, 1.0, 0.01) var smoothing:float = 0.5 # legacy; kept for compatibility

# New envelope parameters (attack/release are in per-second rates used in exp smoothing)
@export var globalAttackSpeed:float = 40.0
@export var globalReleaseSpeed:float = 6.0

@export_group("Bass / Dynamics")
@export_range(0.0, 3.0, 0.01) var bassBoost:float = 0.6
@export_range(0.0, 1.0, 0.01) var bassEmphasisCurve:float = 0.7 # used for static low-frequency shaping

@export_group("Dynamic Bass (peaks)")
@export_range(1, 8) var lowBandCount:int = 3 # how many lowest visual bands are used to detect low-end peaks
@export var lowBaselineRate:float = 1.0 # per-second smoothing for baseline (higher = faster)
@export_range(0.0, 8.0, 0.01) var transientGain:float = 2.0
@export_range(0.1, 4.0, 0.01) var transientPower:float = 1.2
@export_range(0.0, 1.0, 0.01) var dynamicBassMix:float = 1.0 # how much dynamic peak boosting mixes in (0..1)

@export_group("Bell Shape")
@export_range(0.01, 0.5, 0.01) var bellWidth:float = 0.08 # standard deviation in normalized freq units (0..1)
@export_range(0.0, 8.0, 0.01) var bellMaxMultiplier:float = 3.0 # maximum multiplier at the center for dynamic bell

@export_group("Peaks")
@export_range(0.0, 5.0, 0.01) var peakHoldTime:float = 0.25
@export_range(0.0, 10.0, 0.01) var peakFallSpeed:float = 100.0

@export_category("Frequency")
var _minimumFrequency:float = 20.0
@export_range(20.0, 20000.0, 0.1) var minimumFrequency:float = 20.0:
	set(value):
		manage_minimum_frequency_variable(value)
	get:
		return _minimumFrequency

var _maximumFrequency:float = 20000.0
@export_range(20.0, 20000.0, 0.1) var maximumFrequency:float = 2500.0:
	set(value):
		manage_maximum_frequency_variable(value)
	get:
		return _maximumFrequency

# internal arrays
var smoothedHeights:PackedFloat32Array = PackedFloat32Array()
var envelopeStates:PackedFloat32Array = PackedFloat32Array() # lowpass/envelope per band
var peakHeights:PackedFloat32Array = PackedFloat32Array()
var peakTimers:PackedFloat32Array = PackedFloat32Array()

# dynamic-bass baseline
var lowBaseline:float = 0.0

# Cache natural log(10) so we can compute log10 using natural log
const LN10:float = log(10.0)

func _ready() -> void:
	smoothedHeights.resize(barCount)
	envelopeStates.resize(barCount)
	peakHeights.resize(barCount)
	peakTimers.resize(barCount)
	for i in range(barCount):
		smoothedHeights[i] = 0.0
		envelopeStates[i] = 0.0
		peakHeights[i] = 0.0
		peakTimers[i] = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	# compute visual values every frame (need delta for time-based smoothing)
	update_visualizer(delta)
	queue_redraw()

func _draw() -> void:
	if shape == null or shape.get_baked_length() <= 0:
		return

	var points:Array[Vector2] = get_points_along_curve()
	for i in range(barCount):
		var p = points[i]
		var h = smoothedHeights[i]
		var top = Vector2(p.x, p.y - h)
		draw_line(p, top, barColor, barWidth)

		# draw peak marker as a thin line on top
		var peak = peakHeights[i]
		if peak > 0.01:
			var peak_pos = Vector2(p.x, p.y - peak)
			draw_line(peak_pos - Vector2(4,0), peak_pos + Vector2(4,0), barColor, 2)

func manage_audio_bus_index_variable(value:int):
	_audioBusIndex = value
	if _audioBusIndex >= AudioServer.bus_count:
		_audioBusIndex = 0

func manage_spectrum_effect_index_variable(value:int):
	_spectrumEffectIndex = value
	if _spectrumEffectIndex >= AudioServer.get_bus_effect_count(_audioBusIndex):
		_spectrumEffectIndex = 0

func manage_minimum_frequency_variable(value:float):
	_minimumFrequency = value
	if _minimumFrequency > maximumFrequency:
		_minimumFrequency = 22.0

func manage_maximum_frequency_variable(value:float):
	_maximumFrequency = value
	if _maximumFrequency < minimumFrequency:
		_maximumFrequency = 22000.0

func get_frequency_bands() -> Array:
	var result:Array[Vector2] = []
	var safeMin = max(minimumFrequency, 0.0001)
	var safeMax = max(maximumFrequency, safeMin + 1.0)
	var logMinFrequency:float = log(safeMin)
	var logMaxFrequency:float = log(safeMax)
	for bar in range(barCount):
		var sliceBegin = float(bar) / barCount
		var sliceEnd = float(bar + 1) / barCount
		var frequency1 = exp(sliceBegin * (logMaxFrequency - logMinFrequency) + logMinFrequency)
		var frequency2 = exp(sliceEnd * (logMaxFrequency - logMinFrequency) + logMinFrequency)
		result.append(Vector2(frequency1, frequency2))
	return result

func get_points_along_curve() -> Array[Vector2]:
	var points:Array[Vector2] = []
	var length:float = shape.get_baked_length()
	for bar in range(barCount):
		var d = (bar / float(barCount - 1)) * length
		var p = shape.sample_baked(d)
		points.append(p)
	return points

# Helper: convert linear magnitude to decibels using natural log
func linear_to_db(v:float) -> float:
	return 20.0 * (log(max(v, 1e-10)) / LN10)

func update_visualizer(delta:float) -> void:
	if shape == null or shape.get_baked_length() <= 0:
		return

	var analyzer:AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(audioBusIndex, spectrumEffectIndex)
	if analyzer == null:
		return

	var bands:Array[Vector2] = get_frequency_bands()

	# get raw heights (pixel units)
	var rawHeights:PackedFloat32Array = PackedFloat32Array()
	rawHeights.resize(barCount)
	for i in range(barCount):
		var band = bands[i]
		# get magnitude (two channels returned as Vector2)
		var magnitude:Vector2 = analyzer.get_magnitude_for_frequency_range(band.x, band.y)
		var amplitude = max((magnitude.x + magnitude.y) * 0.5, 1e-7)
		var db = clamp(linear_to_db(amplitude), -80, 0)
		var height = clamp((db + 80.0) * pixelsPerDecibel, 0, maxBarHeight)

		# base static bass weighting (frequency-dependent)
		var centerFrequency:float = (band.x + band.y) * 0.5
		var normFreq = 0.0
		if maximumFrequency > minimumFrequency:
			normFreq = clamp((log(centerFrequency) - log(minimumFrequency)) / (log(maximumFrequency) - log(minimumFrequency)), 0.0, 1.0)
		var bassFactor = 1.0 + bassBoost * pow(1.0 - normFreq, 1.0 + bassEmphasisCurve * 3.0)
		height *= bassFactor

		rawHeights[i] = height

	# optional spatial smoothing (moving average across neighbors)
	if spatialSmoothing > 0:
		var smoothedRaw:PackedFloat32Array = PackedFloat32Array()
		smoothedRaw.resize(barCount)
		for i in range(barCount):
			var sum = 0.0
			var count = 0
			for k in range(-spatialSmoothing, spatialSmoothing+1):
				var idx = i + k
				if idx >= 0 and idx < barCount:
					sum += rawHeights[idx]
					count += 1
			smoothedRaw[i] = sum / max(count, 1)
		rawHeights = smoothedRaw

	# --- Dynamic low-end peak detection (make bass boost respond to actual low-frequency peaks) ---
	# compute lowEnergy from lowest visual bands (keep a running baseline)
	var lowCount = clamp(lowBandCount, 1, barCount)
	var lowSum = 0.0
	for i in range(lowCount):
		lowSum += rawHeights[i]
	var lowEnergy = lowSum / float(lowCount)

	# update baseline (slow-moving average)
	var baselineAlpha = 1.0 - exp(-lowBaselineRate * delta)
	lowBaseline = lowBaseline + baselineAlpha * (lowEnergy - lowBaseline)

	# transient (how much current lowEnergy sits above baseline)
	var lowTransient = max(0.0, lowEnergy - lowBaseline)
	var normalizedTransient = lowTransient / (lowBaseline + 1e-6)
	var boost = 1.0 + transientGain * pow(normalizedTransient, transientPower)
	# clamp to avoid runaway
	boost = clamp(boost, 1.0, 1.0 + max(0.0, transientGain) * 8.0)

	# find which low-band has the largest transient compared to baseline: that becomes the bell center
	var peakIdx:int = 0
	var peakVal:float = -1.0
	for i in range(lowCount):
		var t = max(0.0, rawHeights[i] - lowBaseline)
		if t > peakVal:
			peakVal = t
			peakIdx = i

	# compute center normalized frequency for the peak band
	var centerNorm:float = 0.0
	if peakIdx >= 0 and peakIdx < barCount:
		var centerFreq = (bands[peakIdx].x + bands[peakIdx].y) * 0.5
		if maximumFrequency > minimumFrequency:
			centerNorm = clamp((log(centerFreq) - log(minimumFrequency)) / (log(maximumFrequency) - log(minimumFrequency)), 0.0, 1.0)

	# safety for bell width (cannot be zero)
	var sigma = max(0.0001, bellWidth)

	# apply per-band envelope (attack / release) and optional 1-pole lowpass on envelope
	for i in range(barCount):
		var band = bands[i]
		var centerFrequency:float = (band.x + band.y) * 0.5
		var normFreq = 0.0
		if maximumFrequency > minimumFrequency:
			normFreq = clamp((log(centerFrequency) - log(minimumFrequency)) / (log(maximumFrequency) - log(minimumFrequency)), 0.0, 1.0)

		# adapt speeds by frequency: highs react faster, lows release slower
		var attackSpeed = lerp(globalAttackSpeed * 0.7, globalAttackSpeed * 1.2, normFreq)
		var releaseSpeed = lerp(globalReleaseSpeed * 1.5, max(globalReleaseSpeed * 0.6, 0.001), normFreq)
		# convert to alpha per-frame using simple expo: alpha = 1 - exp(-rate * dt)
		var aAttack = 1.0 - exp(-attackSpeed * delta)
		var aRelease = 1.0 - exp(-releaseSpeed * delta)

		var target = rawHeights[i]

		# compute bell curve weight around centerNorm
		var dNorm = (normFreq - centerNorm) / sigma
		var gauss = exp(-0.5 * dNorm * dNorm) # 1.0 at centerNorm, falls off away from it

		# scale boost amount at center by bellMaxMultiplier and by detected boost
		# boost is >= 1.0, so (boost-1.0) is the dynamic amount
		var dynamicMultiplier = 1.0 + (boost - 1.0) * gauss * dynamicBassMix
		# also clamp so dynamicMultiplier doesn't exceed bellMaxMultiplier
		dynamicMultiplier = min(dynamicMultiplier, bellMaxMultiplier)

		# apply the dynamic bell-shaped multiplier (on top of static bassFactor already applied)
		target *= dynamicMultiplier

		# envelope / smoothing logic (fast attack, slower release)
		var cur = smoothedHeights[i]
		if target > cur:
			cur = lerp(cur, target, aAttack)
		else:
			cur = lerp(cur, target, aRelease)

		# small additional 1-pole smoothing to make visuals less noisy
		var lpAlpha = clamp(0.08 + (1.0 - normFreq) * 0.12, 0.02, 0.6)
		envelopeStates[i] = envelopeStates[i] + lpAlpha * (cur - envelopeStates[i])
		smoothedHeights[i] = envelopeStates[i]

		# peak handling
		if smoothedHeights[i] > peakHeights[i]:
			peakHeights[i] = smoothedHeights[i]
			peakTimers[i] = peakHoldTime
		else:
			peakTimers[i] = max(0.0, peakTimers[i] - delta)
			if peakTimers[i] <= 0.0:
				# while not held, decay peak with fall speed
				peakHeights[i] = lerp(peakHeights[i], smoothedHeights[i], 1.0 - exp(-peakFallSpeed * delta))
