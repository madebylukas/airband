#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/tests
swiftc AirBand/Core/Instrument.swift Tests/CoreTests.swift -o .build/tests/core-tests
.build/tests/core-tests
for sample in cowbell.wav kick.wav snare.wav crash.wav hat.wav rizz.wav; do
    test -s "AirBand/Audio/$sample"
done
echo "PASS supplied drum and mouth samples are present"
clang -std=c11 -Wall -Wextra -Werror -I AirBand/Audio AirBand/Audio/SynthDSP.c Tests/DSPTests.c -o .build/tests/dsp-tests
.build/tests/dsp-tests
