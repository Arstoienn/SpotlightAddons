#!/bin/sh
# Builds the solver with its tests and runs them.
#   ./test.sh                  runs the tests
#   ./test.sh --snapshot       writes what every input of the corpus gives to build/snapshot.txt
#   ./test.sh --baseline       does the same, and keeps it as build/snapshot-baseline.txt
#   ./test.sh --booklets       puts every question of Tests/booklets.json (the IB maths and physics
#                              booklets) to the solver and checks each answer
# After a snapshot, the differences from the baseline are listed in build/snapshot.diff.
set -e
cd "$(dirname "$0")"
mkdir -p build
./setup-astronomy.sh
build/astronomy-runtime/bin/python3 -I Tests/AstronomyEngineTests.py
sources="Sources/Solver.swift Sources/Latex.swift Sources/Math.swift Sources/Details.swift Sources/System.swift Sources/Comparison.swift Sources/Number.swift Sources/Hash.swift Sources/Simplify.swift Sources/Location.swift Sources/Convert.swift Sources/Inequality.swift Sources/Algebra.swift Sources/ComplexMath.swift Sources/MatrixMath.swift Sources/Domain.swift Sources/Given.swift Sources/Grouped.swift Sources/Insufficient.swift Sources/Interval.swift Sources/BigInt.swift Sources/RationalEquation.swift Sources/TrigSimplify.swift Sources/Sequence.swift Sources/Currency.swift Sources/Exact.swift Sources/Pipeline.swift Sources/Series.swift Sources/Integration.swift Sources/Differential.swift Sources/Letters.swift Sources/Intent.swift Sources/Roles.swift Sources/Notes.swift Sources/Command.swift Sources/TrigProof.swift Sources/Euler.swift Sources/AngleIdentity.swift Sources/Colour.swift Sources/Circuit.swift Sources/Working.swift Sources/Completion.swift Sources/Relation.swift Sources/Conditioned.swift Sources/Proof.swift Sources/Astronomy.swift Sources/AstronomyEngine.swift Sources/AstronomyFormula.swift Sources/AstronomySubstitution.swift Sources/AstronomyText.swift"

case "$1" in
--snapshot|--baseline)
    python3 -I Tests/corpus.py
    swiftc -O -o build/snapshot $sources Tests/Snapshot/main.swift
    ./build/snapshot Tests/corpus.txt build/snapshot.txt
    if [ "$1" = "--baseline" ]; then
        cp build/snapshot.txt build/snapshot-baseline.txt
        echo "Baseline kept in build/snapshot-baseline.txt"
    elif [ -f build/snapshot-baseline.txt ]; then
        diff build/snapshot-baseline.txt build/snapshot.txt > build/snapshot.diff || true
        echo "$(grep -c '^>' build/snapshot.diff || true) inputs differ from the baseline; see build/snapshot.diff"
    fi
    ;;
--booklets)
    swiftc -O -o build/booklets $sources Tests/Booklets/main.swift
    ./build/booklets Tests/booklets.json
    ;;
*)
    swiftc -O -o build/solver-tests $sources Tests/main.swift Tests/AstronomyTests.swift Tests/RelationTests.swift Tests/RatesTests.swift Tests/SubstitutionTests.swift Tests/UnitTests.swift
    ./build/solver-tests
    ;;
esac

if [ "${1:-}" = "--visual" ]; then
    python3 - <<'PYTHON'
from pathlib import Path
import subprocess
sources = [str(p) for p in sorted(Path('Sources').glob('*.swift')) if p.name != 'main.swift']
subprocess.run(['swiftc', '-o', 'build/astronomy-visual', *sources, 'Tests/AstronomyVisual/main.swift'], check=True)
subprocess.run(['./build/astronomy-visual'], check=True)
PYTHON
fi
