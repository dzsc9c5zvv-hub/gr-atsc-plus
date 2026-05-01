# How software ATSC decoding actually works

This document explains the radio science behind every step of the
pipeline — what each signal-processing block does, why it's needed,
and what goes wrong when it's misconfigured. If you've ever wondered
how a stream of int16 samples from an SDR turns into watchable HD
television, this is for you.

## TL;DR

ATSC 1.0 is a 1990s-era digital TV standard that's still on the air
across North America. The signal is **8-VSB modulation** — eight-level
pulse amplitude modulation with vestigial sideband and a small pilot
tone. To decode it you need to:

1. Tune to the right frequency
2. Lock to the **carrier pilot** so the constellation stops rotating
3. Recover **symbol timing** so you sample at the right moment
4. Equalize away the **multipath echoes** picked up between the
   transmitter and your antenna
5. Run **trellis Viterbi decoding** to undo the convolutional code
6. Run **Reed-Solomon decoding** to fix the leftover errors
7. Slap a TS sync byte on every 188 bytes and hand it to a media player

Each step has a way to silently fail in a way that makes downstream
steps look broken. Most of this document is about diagnosing **which**
step is the actual culprit.

## 1. The signal

ATSC transmits at **6 MHz channel bandwidth** in the same VHF/UHF
slots that analog TV used to occupy. Channel 34, for example, spans
**590-596 MHz**. The data lives in a **5.38 MHz one-sided VSB
sideband**, with a tiny pilot tone at the lower edge (2.69 MHz below
center) that the receiver uses to lock the carrier.

8-VSB means data is encoded as one of 8 amplitude levels:
**±1, ±3, ±5, ±7**. The data segment sync at the start of every
832-symbol segment is always **+5, -5, -5, +5** so the receiver can
find segment boundaries. Every 313 segments there's a special **field
sync segment** containing a known PN511 pseudo-noise sequence, three
PN63 sequences, and reserved fields. The PN sequences are how the
receiver does *coarse* alignment and trains its equalizer.

## 2. Carrier recovery — the FPLL

The SDR captures complex IQ samples but doesn't know the phase of the
transmitter's carrier. If the transmitter and receiver are off by
even 100 Hz, the constellation rotates a full circle every 10 ms and
nothing else can work.

The **FPLL (Frequency PLL)** finds the pilot tone, locks an internal
NCO (numerically-controlled oscillator) to it, and de-rotates the IQ
stream. After the FPLL, the data lands as real-valued symbols on the
real axis, with the pilot at DC.

**Why it fails:** if the loop bandwidth is too tight, it can't track
phase noise or thermal drift and unlocks. Too loose and it wanders
during long quiet runs. Our `atsc_fpll_tight(alpha, afc_tau_us)`
exposes those parameters; **alpha=0.002, AFC tau=20µs** is the value
that empirically wins on real RF in our test setup.

## 3. Why VSB needs a Hilbert transform (or pre-shifted complex IQ)

Standard PLL math assumes you have a complex analytic signal —
**both** the in-phase and quadrature components, all positive
frequencies. ATSC's vestigial sideband chops most of one sideband off
in the transmitter to save bandwidth. If you fed the FPLL the raw
real-valued post-mixing stream, you'd get aliasing because the
negative-frequency image is missing.

The fix is the **Hilbert transform**: a 90°-phase-shift filter that
reconstructs the missing imaginary part from the real one. After
Hilbert, you have a proper analytic signal — only positive
frequencies — which the FPLL can lock cleanly.

(Mathematically: if `x(t)` is the real signal, the analytic signal is
`x(t) + jH{x(t)}`, where `H` is the Hilbert transform. The Fourier
transform of this has all energy in positive frequencies.)

## 4. Symbol timing recovery

Even with a perfectly locked carrier, you don't know exactly when in
each symbol period to sample. Sampling halfway between two symbols
gives 0 information; sampling at the right instant maximizes the
distance between adjacent constellation points.

The **Gardner timing-error detector** estimates the timing error from
three samples per symbol and feeds it to a loop that nudges the
sample clock. After timing recovery, you have one clean sample per
symbol.

**Why it fails:** if the input RMS isn't normalized, the loop
bandwidth is wrong by orders of magnitude. We learned this the hard
way — the original Gardner TED in the project assumed RMS=1 but the
SDR output was RMS=0.026, so the loop bandwidth was 600× too slow.

## 5. The equalizer — undoing multipath

Real RF doesn't go straight from the transmitter to your antenna. It
also bounces off buildings and arrives 1-10 µs later. Each delayed
copy is added to the direct signal at the receive antenna. This is
**multipath**, and it's why TV reception in cities used to look like
ghost images on analog sets.

The equalizer learns the inverse of the channel's impulse response,
so when it convolves the received signal with its taps, the multipath
echoes cancel out. ATSC equalizers train on the known PN511 sequence
during field syncs — for those known bits, they compute the error vs
the ideal and update taps via **LMS (Least Mean Squares)**. Between
field syncs, they switch to **DD-LMS** (decision-directed LMS): they
slice the equalizer output to the nearest 8-VSB level, treat that
guess as the ideal, and keep adapting.

**Why it fails:** if the input data SNR is too low, the slicer makes
wrong decisions, the LMS update goes the wrong way, and the
equalizer diverges to a useless solution. This is why bad gain
settings make the equalizer look broken — it's actually just being
fed too-noisy symbols.

## 6. Trellis-coded modulation + Viterbi decoding

ATSC encodes data with a **rate 2/3 trellis code** on each of 12
parallel symbol streams (interleaved across symbols). This adds
redundancy that lets the receiver recover from individual symbol
errors. The decoder runs the **Viterbi algorithm** — a dynamic
programming search through the trellis — to find the most likely
sequence of input bits given the noisy observed symbols.

**Hard-decision Viterbi** slices each symbol to its nearest level
first, then runs Viterbi on the resulting bits. **Soft-decision
Viterbi** (our `atsc_viterbi_soft`) skips the slicer and uses the
actual squared-distance to each candidate level as the branch metric.
Soft is theoretically ~3 dB better but gains less in practice
because most of the SNR margin is already eaten by other steps.

## 7. Reed-Solomon — the safety net

After Viterbi spits out bytes, the data goes through **Reed-Solomon
RS(207,187)**: 187 data bytes are protected by 20 parity bytes, so RS
can fix up to 10 byte errors per 207-byte block. If the upstream
chain is mostly working but has occasional residual errors, RS
silently corrects them and sets the **TEI (Transport Error Indicator)
flag** on packets that exceeded its correction capacity.

**A "60% RS-clean" result** means 60% of decoded packets passed RS
without errors. The other 40% had so many byte errors that RS gave up
and flagged them TEI=1. A media player like VLC can usually tolerate
30-40% TEI=1 on standard-def content (because MPEG-2 GOPs have lots
of redundancy) but HD primary streams need ≥60% RS-clean for smooth
playback.

## 8. Why gain settings matter so much

The single biggest variable in this whole pipeline turned out to be
**SDR analog gain configuration**. Get it wrong and 100% of packets
fail RS even though the carrier locks perfectly.

Two gain stages on the SDRplay RSPdx that matter:

- **`rfgain_sel`**: enables/disables stages of the RF Low-Noise
  Amplifier. Higher values = fewer LNA stages = less RF gain.
  Counterintuitively for distant signals you want **fewer LNA stages**
  if your signal is already strong; over-amplifying clips the ADC on
  ATSC's high crest-factor symbols.
- **`IFGR` (IF Gain Reduction)**: post-mixer attenuation. Set to
  ~59 dB for ATSC so the AGC has enough room to track without
  clipping symbol peaks.

Wrong: `rfgain_sel=3` (5 LNA stages enabled) → ADC saturates →
constellation flatlines → 100% TEI=1.

Right: `rfgain_sel=5` (only 2 LNA stages enabled) → median IQ ~750
out of int16 ±32767 → 14 bits of headroom for ATSC's ±7 levels →
clean decode.

If you ever see "carrier locks but data is garbage", check **clipping
on the raw IQ first**: `numpy.percentile(abs(iq), 99.9)` should be
**well below 32767** (around 8000-15000 is healthy).

## 9. Antenna polarization — the OTHER big variable

ATSC broadcast TV in North America is **horizontally polarized**.
Dipoles, log-periodics, and Yagis that come pre-aimed for TV are all
laid out horizontally. SDR-hobby antennas like discones and vertical
whips lose 10-15 dB on horizontally-polarized signals. That's enough
to push a "would have decoded" station below the FPLL lock threshold.

The fix is **physical**: orient your TV antenna horizontal. Even a
$10 indoor pair of rabbit-ears bent into a flat horizontal "V" works
for nearby UHF stations.

## 10. Putting it all together — what a healthy decode looks like

For a clean strong-station capture with the right gain:

```
[fpll_tight] rate=16143357 alpha=0.00200 beta=1.000e-06 afc_tau_us=20.0
[fs_checker_inst @50000 segs] pn511_hits=160 f1=80 f2=80
                              uncertain=0 min_pn511_e=0 min_pn63_e=0
[fs_checker_inst FINAL] segments=775951 pn511_hits=2479
                              field1=1239 field2=1240 uncertain=0
                              min_pn511_err=0 min_pn63_err=0
PN511 error histogram (binned by 16):
  pn511_err [  0- 16): 2479
  pn511_err [240-256): 325973
  pn511_err [256-272): 325716
```

The `pn511_err [0-16)` bin shows ~2480 hits — that's exactly
~41 fields/second × 60 seconds (the field sync rate). The bulk of
segments cluster around 240-272 errors out of 511 — that's pure
random data, which is what you expect from data segments (PN511
isn't supposed to be there). `min_pn511_err=0` and `min_pn63_err=0`
mean the field syncs we found are bit-perfect.

This is the signature of a healthy decode. If you see far fewer
PN511 hits OR `min_pn511_err > 30`, something upstream of
`atsc_fs_checker` is broken.

## Further reading

- ATSC A/53 Annex D — the actual modulation spec: https://www.atsc.org/atsc-documents/a53-atsc-digital-television-standard/
- Gnu Radio's `gr-dtv` source — best free reference implementation: https://github.com/gnuradio/gnuradio/tree/main/gr-dtv
- Wikipedia on **8VSB** (good high-level intro): https://en.wikipedia.org/wiki/8VSB
- *Digital Communications* by John Proakis — bible for everything in this document
