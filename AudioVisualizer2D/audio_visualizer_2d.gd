extends Node2D
class_name AudioVisualizer2D

## The amount of bars displayed by the visualizer. Less bars means less representation of each frequency band.
## More bars means more representation of each frequency band.
@export var barCount:int = 32
## The maximum height in pixels that the bars will be able to reach.
@export var maxBarHeight:float = 200.0
@export_category("Appearance")
@export_group("Color")
## The color of the bars.
@export var barColor:Color = Color.WHITE
@export_category("Frequency")
@export_group("Range")
var _minimumFrequency:float 
## The minimum frequency that the bars will react to. Note: A smaller range of frequencies will result in 
## less-accurate visualization of audio.
@export_range(22.0, 22000.0, 0.1) var minimumFrequency:float = 22.0:
	set(value):
		manage_minimum_frequency_export_variable(value)
	get:
		return _minimumFrequency
var _maximumFrequency:float
## The maximum frequency that the bars will react to. Note: A smaller range of frequencies will result in 
## less-accurate visualization of audio.
@export_range(22.0, 22000.0, 0.1) var maximumFrequency:float = 22000.0:
	set(value):
		manage_maximum_frequency_export_variable(value)
	get:
		return _maximumFrequency

func manage_minimum_frequency_export_variable(value:float):
	_minimumFrequency = value
	if _minimumFrequency > maximumFrequency:
		_minimumFrequency = 22.0

func manage_maximum_frequency_export_variable(value:float):
	_maximumFrequency = value
	if _maximumFrequency < minimumFrequency:
		_maximumFrequency = 22000.0
