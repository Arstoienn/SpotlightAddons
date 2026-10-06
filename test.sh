#!/bin/sh
# Builds the solver with its tests and runs them.
set -e
cd "$(dirname "$0")"
mkdir -p build
swiftc -O -o build/solver-tests Sources/Solver.swift Sources/Latex.swift Sources/Math.swift Sources/Details.swift Sources/System.swift Sources/Comparison.swift Sources/Number.swift Sources/Hash.swift Tests/main.swift
./build/solver-tests
