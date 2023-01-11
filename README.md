# Komplete Synthesia

Native Instruments Komplete Kontrol Light Guide support for Synthesia.

Routes Synthesia lighting information to your Native Instruments keyboard controller USB device. Auto-detects a Native Instruments S-series keyboard controller USB device. 

Listens on the "LoopBe" MIDI input interface port - a historic choice. Notes received are forwarded to the keyboard controller USB device as key lighting requests adhering to the Synthesia protocol.

Additionally supports jogwheel and play button for starting and stopping a session in Synthesia.

## Setup

You first need to configure your system and Synthesia to support our way of routing the lighting information to KompleteSynthesia. Please follow [SETUP.md](SETUP.md).

## Use

Simply run `KompleteSynthesia.app`. First thing you will have to permit a bunch of rather intrusive application capabilities.
- Allow for "Input Monitoring"
  - this is needed for receiving button events from the Komplete Kontrol controller
- Allow for "Accessibility"
  - this is needed for sending out virtual keyboard events to your system, recognized by Synthesia

It will detect your controller and show a little swoop on its lighting, signalling that it is up and running. The Play and Stop button should be illuminated now. You will also recognise a little MIDI cable icon on the top right of your screen.

For finding out about the detected controller, click on the icon which will show a menu which contains its name.

![Komplete Synthesia](site/images/KompleteSynthesia.png)

## Background and Motivation

The major parts of this approach and implementation is closely following a neat little Python project called [SynthesiaKontrol](https://github.com/ojacques/SynthesiaKontrol).

Kudos and many thanks to Olivier Jacques [@ojacques] for sharing!

The inspiration for re-implementing this as a native macOS appllication struck me when I had a bit of a hard time getting that original Python project to build on a recent system as it would not run on anything beyond Python 3.7 for me. Another driver here is that I always took great pleasure from controlling hardware via code. As a result no third party dependencies are made use of - pure, native macOS code that will compile without hassle in 10 years from now.
