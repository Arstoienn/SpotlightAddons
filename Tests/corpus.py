#!/usr/bin/env python3
# Writes Tests/corpus.txt: every input the snapshot is taken of. They are every string in the
# tests (the answers among them do no harm as inputs), every example in the README, and terms of
# binomial expansions and choices made by a fixed seed, so that the corpus is the same each time.
import random, re, sys
from fractions import Fraction as F
from math import factorial
from pathlib import Path

here = Path(__file__).resolve().parent
inputs = []

def swift_strings(text):
    out = []
    i = 0
    while i < len(text):
        if text.startswith('#"', i):
            j = text.find('"#', i + 2)
            if j < 0: break
            out.append(text[i + 2:j]); i = j + 2; continue
        if text[i] == '"' and not text.startswith('"""', i):
            j, s = i + 1, []
            while j < len(text) and text[j] != '"' and text[j] != '\n':
                if text[j] == '\\' and j + 1 < len(text):
                    s.append({'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'"}.get(text[j + 1], '\\' + text[j + 1])); j += 2
                else:
                    s.append(text[j]); j += 1
            if j < len(text) and text[j] == '"': out.append(''.join(s))
            i = j + 1; continue
        if text.startswith('//', i):
            i = text.find('\n', i); i = len(text) if i < 0 else i; continue
        i += 1
    return out

inputs += swift_strings((here / 'main.swift').read_text())
for line in (here.parent / 'README.md').read_text().splitlines():
    inputs += re.findall(r'`([^`]+)`', line)

random.seed(20261109)
for _ in range(400):
    k = random.randint(1, 4)
    p, q = random.choice([1, -1, 2, -2, 3, -3, 5]), random.choice([1, 2, 3, 4])
    a = random.choice(['1', '-1', '2', '-2', '3', '-3', '(1/2)'])
    falling = 'n' + ''.join(f'(n-{i})' for i in range(1, k))
    term = random.choice([f'({a}x)^{k}', f'{a}*x^{k}'])
    inputs.append(f"({falling})/{random.choice([f'{k}!', str(factorial(k))])}*{term}, n={p}/{q}" if q > 1 else f'({falling})/{k}!*{term}, n={p}')
for n in range(0, 31):
    for r in range(0, n + 1, 3):
        inputs += [f'nCr({n},{r})', f'nPr({n},{r})']

seen, kept = set(), []
for s in inputs:
    s = s.strip()
    # Pieces of a string with \( … ) written into it are no input.
    if not s or '\n' in s or '\t' in s or s in seen or len(s) > 200 or '\\(' in s or s.startswith(')'): continue
    seen.add(s); kept.append(s)
(here / 'corpus.txt').write_text('\n'.join(kept) + '\n')
print(f'{len(kept)} inputs', file=sys.stderr)
