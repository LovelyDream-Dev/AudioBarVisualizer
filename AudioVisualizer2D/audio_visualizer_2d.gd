extends Node2D
class_name AudioVisualizer2D

## The shape that the audio visualizer will draw on.
@export var shape:Curve2D
@export_group("Audio Bus Effect")
var _audioBusIndex:int
## The index of the audio bus that contains an [member AudioSpectrumAnalyzer] effect.
@export var audioBusIndex:int = 0:
	set(value):
		manage_audio_bus_index_variable(value)
	get:
		return _audioBusIndex
var _spectrumEffectIndex:int
## The index of the [member AudioSpectrumAnalyzer] effect within its bus.
@export var spectrumEffectIndex:int = 0:
	set(value):
		manage_spectrum_effect_index_variable(value)
	get:
		return _spectrumEffectIndex
@export_group("Bars")
## How many pixels represent [code]1[/code] decibel of volume. Directly affects the height of the bars.
@export_range(1.0, 10000.0, 0.1) var pixelsPerDecibel:float = 1.0
## The amount of bars displayed by the visualizer. Less bars means less representation of each frequency band.
## More bars means more representation of each frequency band.
@export var barCount:int = 32
## The width of each bar.
@export var barWidth:float = 12.0
## The maximum height in pixels that the bars will be able to reach.
@export var maxBarHeight:float = 500.0
@export_category("Appearance")
@export_group("Color")
## The color of the bars.
@export var barColor:Color = Color.WHITE
@export_group("Smoothing")
@export_range(0.0, 1.0, 0.1) var smoothing:float = 0.5
@export_category("Frequency")
@export_group("Range")
var _minimumFrequency:float = 20.0
## The minimum frequency that the bars will react to. Note: A smaller range of frequencies will result in 
## less-accurate visualization of audio.
@export_range(20.0, 20000.0, 0.1) var minimumFrequency:float = 20.0:
	set(value):
		manage_minimum_frequency_variable(value)
	get:
		return _minimumFrequency
var _maximumFrequency:float = 20000.0
## The maximum frequency that the bars will react to. Note: A smaller range of frequencies will result in 
## less-accurate visualization of audio.
@export_range(20.0, 20000.0, 0.1) var maximumFrequency:float = 2500.0:
	set(value):
		manage_maximum_frequency_variable(value)
	get:
		return _maximumFrequency

var smoothedHeights:Array = []

func _ready() -> void:
	smoothedHeights.resize(barCount)
	for bar in range(barCount):
		smoothedHeights[bar] = 0.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	update_visualizer()

func manage_audio_bus_index_variable(value:int):
	_audioBusIndex = value
	if _audioBusIndex > AudioServer.bus_count:
		_audioBusIndex = 0

func manage_spectrum_effect_index_variable(value:int):
	_spectrumEffectIndex = value
	if _spectrumEffectIndex > AudioServer.get_bus_effect_count(_audioBusIndex):
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
	
	# clamp minimum and maximum frequencies to safe values
	var safeMin = max(minimumFrequency, 0.0001)
	var safeMax = max(maximumFrequency, safeMin + 1.0)  # ensure max > min

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
	var points:Array[Vector2]
	var length:float = shape.get_baked_length()
	
	for bar in range(barCount):
		var d = (bar / float(barCount - 1)) * length
		var p = shape.sample_baked(d)
		points.append(p)
	return points

func update_visualizer() -> void:
	if shape == null or shape.get_baked_length() <= 0:
		return

	var analyzer:AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(audioBusIndex, spectrumEffectIndex)
	if analyzer == null:
		return

	var bands:Array[Vector2] = get_frequency_bands()
	var points:Array[Vector2] = get_points_along_curve()

	for bar in range(barCount):
		var band = bands[bar]
		var p = points[bar]

		# get db
		var magnitude:Vector2 = analyzer.get_magnitude_for_frequency_range(band.x, band.y)
		var amplitude = max((magnitude.x + magnitude.y) / 2, 0.0000001)
		amplitude = max(amplitude, 0.000001)
		var db = linear_to_db(amplitude)
		db = clamp(db, -80, 0)
		var height = clamp((db + 80.0) * pixelsPerDecibel, 0, maxBarHeight)

		# boost lows
		var centerFrequency:float = (band.x + band.y) / 2
		var lowFreqFactor = clamp(1.0 + 1.0 - log(centerFrequency / maximumFrequency), 1.0, 1.5)
		height *= lowFreqFactor

		# smoothing
		var normFreq = (log(centerFrequency) - log(minimumFrequency)) / (log(maximumFrequency) - log(minimumFrequency))
		normFreq = clamp(normFreq, 0.0, 1.0)
		var freqSmoothFactor = lerp(0.6, 0.3, normFreq)
		smoothedHeights[bar] = lerp(smoothedHeights[bar], height, 1.0 - freqSmoothFactor)
		var peakPoint = Vector2(p.x, p.y - smoothedHeights[bar])

		# fx on low frequencies

		# draw bars
		draw_line(p, peakPoint, barColor, barWidth)
