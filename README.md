# gr-atsc-plus

Open-source software ATSC 1.0 receiver, forked from GNU Radio's `gr-dtv`
with experimental extensions:

- `atsc_equalizer_long` — 256-tap DD-LMS equalizer (vs stock 64-tap)
- `atsc_viterbi_soft` — soft-decision Viterbi with L2-squared branch metrics
- `atsc_fs_checker_inst` — instrumented field-sync checker (PN511/PN63 histograms)
- `atsc_sync_tunable` — segment-sync block with parameterized lock thresholds + hysteresis
- `atsc_fpll_tight` — frequency PLL with tunable loop alpha and AFC time constant

Status: **algorithmic ceiling reached on real-RF discone capture (0.3% RS-clean,
0/199 HD frames)**. Empirical conclusion: signal SNR is below what the equalizer
can fix, regardless of FPLL/sync tuning. See `docs/findings.md`.

## Build

Requires Linux with `gnuradio` (3.10+), `gr-dtv`, `libvolk`, `pybind11`, `cmake`.

```bash
./bootstrap.sh
```

Installs prerequisites if missing, builds the OOT module under
`gr-atscplus/build/`, installs to `/usr/local`, and verifies the Python
binding by listing the registered blocks.

## Run

### Decode a single CS16 capture with a named combo

```bash
python3 run_combo.py input.cs16 output.ts full_stack
```

`combos.yaml` defines all available combos (16 by default). Each names which
forked blocks to use and their parameters. Add new combos by appending to the
list in `combos.yaml`; no Python edits needed.

### Synthetic benchmark sweep

```bash
python3 benchmark_synth.py
```

Generates AWGN + multipath ATSC IQ at multiple SNR levels, runs every combo
on every (channel, SNR) pair, and writes a Markdown scoreboard to
`results/<date>.md`.

A weekly remote agent runs this sweep on every push to `main` and commits
the results back. See `.github/workflows/synth_bench.yml` (TODO).

## Repo layout

```
gr-atscplus/        forked OOT module (the actual C++ blocks)
decoders/           v6-v9 demonstration decoder scripts (locked to specific combos)
scripts/            apply_*.sh — patch scripts that fork from upstream gr-dtv
combos.yaml         configuration matrix (combo name → which blocks)
run_combo.py        parameterized single-decode runner
benchmark_synth.py  synthetic IQ generator + combo sweep + scorecard writer
bootstrap.sh        Linux setup + build + install
results/            scoreboard output (gitignored except .gitkeep)
```

## License

GPL-3.0-or-later (inherited from gr-dtv).
