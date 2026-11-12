#!/bin/bash
# Compiles the model with the simulator and prints win rates per difficulty.
set -e
cd "$(dirname "$0")/.."
mkdir -p .build
cp tools/simulate.swift .build/main.swift
swiftc -O Sources/Pong.swift .build/main.swift -o .build/simulate
./.build/simulate
