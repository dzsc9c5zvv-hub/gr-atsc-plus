# gr-atsc-plus

Open-source software ATSC 1.0 receiver, forked from GNU Radio's `gr-dtv`
with experimental extensions and an empirically-tuned RF capture recipe.

> **2026-05-01 milestone:** software decode of WRC NBC HD (RF 34) at
> visual quality matching HDHomeRun on the same RF moment, using SDRplay
> RSPdx + Antenna A + the proven gain settings + the `fpll_a002_tau20`
> combo. **62.2% RS-clean, ~1100 HD frames + 1100 SD frames per 60 sec
> capture.** See [`docs/proven_capture_recipe.md`](docs/proven_capture_recipe.md)
> and [`results/2026-05-01-real-rf34-29combos.md`](results/2026-05-01-real-rf34-29combos.md).

## Quick start (the actual working recipe)

```powershell
# Capture (Windows, requires PothosSDR + SDRplay RSPdx + a horizontal TV antenna)
& "C:\Program Files\PothosSDR\bin\rx_sdr.exe" -d "driver=sdrplay" `
  -a "Antenna A" -f 593000000 -s 8000000 `
  -g "IFGR=59" -t "rfgain_sel=5" `
  -F CS16 -n 480000000 capture.cs16
```

```bash
# Decode (Linux/WSL, after ./bootstrap.sh)
python3 run_combo.py capture.cs16 out.ts fpll_a002_tau20
python3 ts_tei_scrub.py out.ts out_clean.ts
vlc out_clean.ts
```

The two non-obvious capture values (`rfgain_sel=5`, `IFGR=59`) make the
difference between 100% TEI=1 (ADC saturation, signal looks dead) and
60%+ RS-clean watchable TV.

## Forked blocks

| Block | Status | Notes |
|---|---|---|
| `atsc_fpll_tight` | ✓ working, +2pp wins | Parameterized alpha + AFC tau. Best params: alpha=0.002, tau=20µs |
| `atsc_viterbi_soft` | ✓ working, neutral-positive | Soft-decision Viterbi; small win on top of tight FPLL |
| `atsc_sync_tunable` | ✓ working, neutral | Lock thresholds + hysteresis; tied stock on the test capture |
| `atsc_fs_checker_inst` | ✓ working | Instrumented (PN511/PN63 histograms to stderr) |
| `atsc_equalizer_long` | ✗ **broken**, 0.3% RS-clean | 256-tap DD-LMS, regression of unknown cause; do not use |

`combos.yaml` defines 29 named combos (stock baseline + 28 forks). The
2026-05-01 sweep against a real RF 34 capture produced this leaderboard:

| Rank | HD frames | SD frames | Clean% | Combo |
|---|---|---|---|---|
| 1 | 1113 | 1094 | 62.2% | **fpll_a002_tau20** |
| 2 | 1112 | 1094 | 62.2% | fpll_soft_a003_tau10 |
| 3 | 1111 | 1094 | 62.1% | tight_fpll_soft_vit |
| ... | | | | |
| stock | 1083 | 1077 | 60.8% | gr-dtv baseline |

## Build

Requires Linux (Ubuntu 24.04 tested) with `gnuradio` (3.10.9+),
`gr-dtv`, `libvolk`, `pybind11`, `cmake`. Use Python 3.12.

```bash
./bootstrap.sh
```

Installs missing prerequisites, builds the OOT module under
`gr-atscplus/build/`, installs to `/usr/local`, verifies the Python
binding lists all 5 forked blocks.

## Regression sweep

After any C++ change to a forked block, run the local sweep against
your captured IQ to make sure stock didn't regress and check whether
your change actually helps:

```bash
bash scripts/run_local_sweep.sh /path/to/capture.cs16
```

Outputs RS-clean %, SD frames, HD frames per combo and a sorted
leaderboard. ~15 minutes for all 29 combos on a 60-sec capture.

## Repo layout

```
gr-atscplus/        forked OOT module (5 C++ blocks)
combos.yaml         29 named combo configurations
run_combo.py        parameterized single-decode runner
benchmark_synth.py  synthetic IQ generator + combo sweep (currently broken — synth IQ produces 0% on stock too; investigation pending)
scripts/run_local_sweep.sh  real-IQ regression sweep with SD/HD frame counts
docs/               capture recipe + findings
results/            scoreboard outputs by date
bootstrap.sh        Linux setup + build + install
```

## License

GPL-3.0-or-later (inherited from gr-dtv).
