# KompleteSynthesia
Native Instruments Komplete Kontrol Light Guide support for Synthesia

Detects a Native Instruments keyboard controller USB device. Listens on the "LoopBe" MIDI input interface port.
Notes received are forwarded to the keyboard controller USB device as key lighting requests adhering to the Synthesia
protocol.

The entire approach and implementation is closely following a neat little Python project called
https://github.com/ojacques/SynthesiaKontrol
Kudos to you Olivier Jacques for sharing!

The inspiration for re-implementing this as a native macOS appllication struck me when I had a bit of a hard time getting
that original Python project to build on a recent system as it would not run on anything beyond Python 3.7 for me.
