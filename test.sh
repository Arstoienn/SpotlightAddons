#!/bin/sh
# Builds the solver with its tests and runs them.
set -e
cd "$(dirname "$0")"
mkdir -p build
swiftc -O -o build/solver-tests Sources/Solver.swift Sources/Latex.swift Sources/Math.swift Sources/Details.swift Sources/System.swift Sources/Comparison.swift Sources/Number.swift Sources/Hash.swift Sources/Simplify.swift Sources/Location.swift Sources/Convert.swift Sources/Inequality.swift Sources/Algebra.swift Sources/ComplexMath.swift Sources/MatrixMath.swift Sources/Domain.swift Sources/Given.swift Sources/Interval.swift Sources/BigInt.swift Sources/RationalEquation.swift Sources/TrigSimplify.swift Sources/Sequence.swift Tests/main.swift
./build/solver-tests
