#!/bin/bash
# Plays thousands of random games (with random pauses and resets) and checks the model's invariants:
# the bot never misses a serve toward it, scores and paddle positions stay in range, matches end cleanly.
set -e
cd "$(dirname "$0")/.."
mkdir -p .build/fuzz
cp tools/fuzz.swift .build/fuzz/main.swift
swiftc -O Sources/Pong.swift .build/fuzz/main.swift -o .build/fuzz-run
./.build/fuzz-run
