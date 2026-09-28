class_name ClickTrack
## Procedural metronome for practice rounds and calibration: a click on every
## beat, higher on each bar's downbeat. Not looped -- the Conductor clock must
## never jump backwards, so callers restart it on song_finished instead.


static func make(bpm: float, beats: int, beats_per_measure: int = 4, first_beat_offset: float = 0.0) -> AudioStreamWAV:
	var rate := 44100
	var spb := 60.0 / bpm
	var n := int(rate * (first_beat_offset + spb * beats + 0.5))
	var data := PackedByteArray()
	data.resize(n * 2)   # zero-filled = silence
	var click_n := int(rate * 0.04)
	for b in beats:
		var freq := 1600.0 if b % beats_per_measure == 0 else 1000.0
		var start := int(rate * (first_beat_offset + b * spb))
		for i in click_n:
			var t := float(i) / rate
			var env := pow(1.0 - float(i) / click_n, 3.0)
			data.encode_s16((start + i) * 2, int(sin(TAU * freq * t) * env * 0.6 * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
