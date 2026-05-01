/* -*- c++ -*- */
/*
 * Copyright 2014 Free Software Foundation, Inc.
 *
 * This file is part of GNU Radio
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 */

#ifndef INCLUDED_ATSCPLUS_ATSC_EQUALIZER_LONG_IMPL_H
#define INCLUDED_ATSCPLUS_ATSC_EQUALIZER_LONG_IMPL_H

#include "atsc_syminfo_impl.h"
#include <gnuradio/dtv/atsc_consts.h>
#include <gnuradio/atscplus/atsc_equalizer_long.h>

namespace gr {
namespace atscplus {

class atsc_equalizer_long_impl : public atsc_equalizer_long
{
private:
    static constexpr int NTAPS = 256;
    // BUG: this block produces 0.3% RS-clean on real RF regardless of
    // NPRETAPS choice (tested 0.2 and 0.8 — both broken on the 2026-05-01
    // RF 34 capture vs stock's 60.8%). The bug is elsewhere in the impl;
    // suspect candidates: LMS gradient sign, tap-buffer slide indexing,
    // or DFE state mishandling. Until fixed, do NOT use any combo routing
    // through this block. Recommended combo: tight_fpll_soft_vit (62.1%).
    static constexpr int NPRETAPS = (int)(NTAPS * 0.8);

    // DFE (decision-feedback) settings — ported from atsc_decoder.py
    static constexpr int NDFE = 64;
    float d_dfe_taps[NDFE];
    float d_dec_hist[NDFE];
    bool d_dfe_initialized = false;

    // the length of the field sync pattern that we know unequivocally
    static constexpr int KNOWN_FIELD_SYNC_LENGTH = 4 + 511 + 3 * 63;

    float training_sequence1[KNOWN_FIELD_SYNC_LENGTH];
    float training_sequence2[KNOWN_FIELD_SYNC_LENGTH];

    void filterN(const float* input_samples, float* output_samples, int nsamples);
    void adaptN(const float* input_samples,
                const float* training_pattern,
                float* output_samples,
                int nsamples);
void adaptN_dd(const float* input_samples, float* output_samples, int nsamples);
void adaptN_dfe(const float* input_samples, float* output_samples, int nsamples);

    std::vector<float> d_taps;

    float data_mem[gr::dtv::ATSC_DATA_SEGMENT_LENGTH + NTAPS]; // Buffer for previous data packet
    float data_mem2[gr::dtv::ATSC_DATA_SEGMENT_LENGTH];
    unsigned short d_flags;
    short d_segno;

    bool d_buff_not_filled = true;

public:
    atsc_equalizer_long_impl();
    ~atsc_equalizer_long_impl() override;

    void setup_rpc() override;

    std::vector<float> taps() const override;
    std::vector<float> data() const override;

    int general_work(int noutput_items,
                     gr_vector_int& ninput_items,
                     gr_vector_const_void_star& input_items,
                     gr_vector_void_star& output_items) override;
};

} /* namespace atscplus */
} /* namespace gr */

#endif /* INCLUDED_ATSCPLUS_ATSC_EQUALIZER_LONG_IMPL_H */
