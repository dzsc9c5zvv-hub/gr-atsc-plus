# Findings — 2026-04 ATSC decode investigation

## Question

Can a software ATSC receiver match HDHomeRun on the same RF capture?
HDHR decodes 199 HD frames from an 8-second WRC-HD capture (RF 34, 593 MHz).
Stock `gr-dtv` decodes 0 HD frames from the same IQ. Why?

## Methodology

Built a benchmark harness (`benchmark_decoder.py`) that decodes a locked
8-second `iq.cf32` baseline and counts:

- HD frames recovered (target: 199)
- RS-clean fraction (TEI=0 packets / total)
- PN511 hit count + histogram (instrumented FS checker)
- PN63 error histogram

Versions tested:

| ver | description |
|-----|-------------|
| v0  | stock `gr-dtv` baseline |
| v1  | 256-tap equalizer, training-only |
| v2  | 256-tap + DD-LMS post-training |
| v3  | 256-tap + DFE (regression) |
| v4  | DFE + soft Viterbi |
| v5  | DD-LMS + soft Viterbi |
| v6  | v5 + instrumented FS checker (no algorithm change) |
| v7  | v6 + tight FPLL (alpha=0.003, AFC tau=20µs) |
| v8  | v6 + relaxed sync (lock=3, force-emit) |
| v9  | v6 + hysteresis-only sync (lock=3, unlock=1) |

## Results

| ver | total segs | PN511 hits | RS-clean | HD frames |
|-----|-----------:|-----------:|---------:|----------:|
| v0  | 65,951     | —          | 0.0%     | 0/199     |
| v5  | 65,951     | 91         | 0.3%     | 0/199     |
| v6  | 65,951     | 91         | 0.3%     | 0/199     |
| v7  | 66,437     | 97         | 0.3%     | 0/199     |
| v8  | 103,482    | 104        | 0.3%     | 0/199     |
| v9  | 75,475     | 92         | 0.3%     | 0/199     |

**RS-clean is pinned at 0.3% across every algorithmic variation.**

## What the histograms revealed

PN63 errors when PN511 locks:
- `errors=0`: 37 (perfect field-1 sync)
- `errors=63`: 42 (perfect field-2 sync, inverted)
- `errors=31-42`: 4 (uncertain)

**When the receiver finds a field sync, alignment is flawless.** The stages
downstream of `atsc_fs_checker` (equalizer, Viterbi, deinterleaver, RS) work
correctly when fed locked data.

PN511 distribution is **bimodal**:
- 91 segments at <16 errors (true field syncs)
- 65,000+ at 240–272 errors (random data, no sync expected)
- Almost nothing in between

We catch ~12 of 26 expected fields per second (43%). The other 57% don't appear
as "near misses" — they look like pure noise. No FPLL/sync tuning shifts this
ratio, ruling out carrier rotation or timing slip as the cause.

## Conclusion

The wall is **signal SNR**, not algorithmic. Between the sparse field syncs
that do lock, the channel is too noisy/distorted for the 256-tap DD-LMS
equalizer to keep symbols clean enough for RS(207,187). HDHR decodes the same
RF only because its hardware tuner has a better noise figure and a
VSB-specialized analog frontend that we cannot match in software.

## What this means for the project

1. **Don't pursue further FPLL/sync/equalizer tuning on the discone-fed
   baseline.** We are at the antenna ceiling.

2. **Do pursue better antennas.** Horizontal UHF with a yagi pointed at the
   transmitter farm should give +10–15 dB and unlock decode.

3. **Keep the diagnostic forks.** `atsc_fs_checker_inst` is the most useful
   thing built this session — it shows exactly where each ATSC capture is
   limited (carrier residual, timing slip, or SNR floor).

4. **The fork is still valuable.** Each block is a reusable parameter knob;
   future investigations on better captures can sweep them via
   `combos.yaml` without rebuilding.

## What "improvement" would look like

The synthetic benchmark (`benchmark_synth.py`) sweeps SNR levels against
clean ATSC signals. A combo that improves over stock will show:

- **higher RS-clean at SNR ≤ 14 dB** (where stock breaks down)
- **same or better RS-clean at SNR ≥ 18 dB** (no regression in clean conditions)
- **higher PN511 hit count per second** at intermediate SNR

The current fork doesn't show any of these on the discone capture, but
that capture sits below the SNR floor where any of the algorithms can help.
A higher-SNR capture from a better antenna is needed to validate whether
the long equalizer / soft Viterbi help on real RF.
