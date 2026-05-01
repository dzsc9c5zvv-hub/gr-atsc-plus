# Proven RF capture recipe for ATSC decode

Empirically validated on a Windows 11 + SDRplay RSPdx + attic TV antenna
+ inline amplifier setup. Decoding through gr-dtv 3.10.9.2 + this fork's
gr-atscplus blocks gives **~60% RS-clean** on UHF channels with these
exact settings.

## Capture command (Windows PowerShell)

```powershell
& "C:\Program Files\PothosSDR\bin\rx_sdr.exe" `
  -d "driver=sdrplay" `
  -a "Antenna A" `
  -f 593000000 `
  -s 8000000 `
  -g "IFGR=59" `
  -t "rfgain_sel=5" `
  -F CS16 -n 480000000 `
  capture.cs16
```

The two non-obvious values are:

| Setting | Value | Why |
|---|---|---|
| `-g IFGR=59` | 59 dB | Maximum IF gain reduction so the post-AGC IQ doesn't clip on ATSC's high-crest-factor symbols |
| `-t rfgain_sel=5` | 5 | Disables 5 LNA stages, dropping median IQ from ~10000 to ~750 — gives the equalizer real ADC headroom |
| `-s 8000000` | 8 MS/s | SDRplay native rate (only 5/6/7/8/10 MS/s are native; 6.25 forces driver resampling and adds aliased noise) |

## Wrong values that look reasonable but produce 0% RS-clean

| Setting | Wrong value | Symptom |
|---|---|---|
| `-t rfgain_sel=3` | LNA mostly enabled | 100% TEI=1, signal saturates ADC |
| `-t rfgain_sel=0` | All LNAs on | 4 RS-clean packets (clipping) |
| `-g 30` | Aggregate gain 30 | Carrier locks but 70% of segments fail RS |
| `-s 6250000` | 6.25 MS/s | Driver internally resamples, introduces aliased noise |

## Decode pipeline

```
rx_sdr.exe → CS16 file → file_source(short)
  → interleaved_short_to_complex
  → rational_resampler_ccc(25/32)   # 8 MS/s → 6.25 MS/s
  → atsc_rx(6.25e6, sps=1.5)        # gr-dtv stock pipeline
  → ts_tei_scrub                    # rewrite TEI=1 packets to NULL
  → VLC                             # plays MPEG-TS
```

`run_combo.py` in this repo wraps the gr-dtv pipeline. After capture:

```bash
python3.12 run_combo.py capture.cs16 /tmp/out.ts stock
```

## Time-of-day note

Signal quality varies hour-to-hour. At 21:00–22:00 ET we've seen 60–66%
RS-clean on RF 34. After 23:00 it gets flaky — same recipe can drop to
0% within 30 seconds. Don't iterate on RF tests after 23:00 local; the
results aren't representative.
