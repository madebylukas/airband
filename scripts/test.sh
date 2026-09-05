#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/tests
swiftc AirBand/Core/Instrument.swift Tests/CoreTests.swift -o .build/tests/core-tests
.build/tests/core-tests
clang -std=c11 -Wall -Wextra -Werror -I AirBand/Audio AirBand/Audio/SynthDSP.c Tests/DSPTests.c -o .build/tests/dsp-tests
.build/tests/dsp-tests
