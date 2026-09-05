#include "SynthDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>

struct ABSynth {
    double sr, phase, subphase, shimmer, lfo, clock, fartphase, farttime;
    float gain, freq, bright, vib, drive, morph;
    _Atomic float targetFreq, targetGain, targetBright, targetVib, targetDrive;
    _Atomic int palette, fart;
    uint32_t noise;
};
ABSynth *ab_create(double sr) {
    ABSynth *s = calloc(1, sizeof(ABSynth));
    if (!s) return NULL;
    s->sr = sr; s->freq = 220; s->noise = 7419; s->farttime = 2;
    atomic_init(&s->targetFreq, 220); atomic_init(&s->targetGain, 0);
    atomic_init(&s->targetBright, 0.25); atomic_init(&s->targetVib, 0); atomic_init(&s->targetDrive, 0);
    atomic_init(&s->palette, 0); atomic_init(&s->fart, 0);
    return s;
}
void ab_destroy(ABSynth *s) { free(s); }
void ab_set(ABSynth *s, float f, float g, float b, float v, float d, int p) {
    atomic_store(&s->targetFreq, f); atomic_store(&s->targetGain, g);
    atomic_store(&s->targetBright, b); atomic_store(&s->targetVib, v);
    atomic_store(&s->targetDrive, d); atomic_store(&s->palette, p);
}
void ab_fart(ABSynth *s) { atomic_store(&s->fart, 1); }
static double wrap(double phase) { return phase - floor(phase); }
void ab_render(ABSynth *s, float *out, uint32_t frames) {
    const double tau = 6.283185307179586;
    float f = atomic_load(&s->targetFreq), g = atomic_load(&s->targetGain);
    float b = atomic_load(&s->targetBright), v = atomic_load(&s->targetVib);
    float d = atomic_load(&s->targetDrive);
    int palette = atomic_load(&s->palette);
    if (atomic_exchange(&s->fart, 0)) { s->farttime = 0; s->fartphase = 0; }
    const float smoothing = (float)(1 - exp(-1.0 / (s->sr * 0.018)));
    for (uint32_t i = 0; i < frames; i++) {
        s->freq += (f - s->freq) * smoothing;
        s->gain += (g - s->gain) * smoothing;
        s->bright += (b - s->bright) * smoothing;
        s->vib += (v - s->vib) * smoothing;
        s->drive += (d - s->drive) * smoothing;
        s->morph += ((float)palette - s->morph) * smoothing;
        s->lfo = wrap(s->lfo + 5.2 / s->sr);
        s->clock = wrap(s->clock + 3.2 / s->sr);
        double pitch = s->freq * (1 + 0.014 * s->vib * sin(tau * s->lfo));
        s->phase = wrap(s->phase + pitch / s->sr);
        s->subphase = wrap(s->subphase + pitch * 0.5008 / s->sr);
        s->shimmer = wrap(s->shimmer + pitch * 1.002 / s->sr);
        double ph = tau * s->phase;
        double prism = sin(ph + (0.18 + s->bright * 1.3) * sin(2 * ph)) * 0.7 + sin(tau * s->shimmer) * 0.16;
        double halo = sin(ph) * 0.40 + sin(tau * s->shimmer) * 0.27 + sin(tau * s->subphase) * 0.25 + sin(ph * 3) * s->bright * 0.08;
        double pulse = (sin(ph) * 0.65 + sin(2 * ph) * s->bright * 0.2 + sin(tau * s->subphase) * 0.15) * (0.3 + 0.7 * pow(0.5 + 0.5 * cos(tau * s->clock), 3));
        double a = fmin(1, s->morph), c = fmax(0, s->morph - 1);
        double tone = (prism * (1 - a) + halo * a) * (1 - c) + pulse * c;
        double driven = tanh(tone * (1 + s->drive * 4)) / (1 + s->drive * 0.65);
        double sample = (tone * (1-s->drive) + driven * s->drive) * s->gain * 0.48;
        if (s->farttime < 0.65) {
            double t = s->farttime;
            s->fartphase = wrap(s->fartphase + (48 + 100 * exp(-9*t) + 12*sin(80*t)) / s->sr);
            s->noise ^= s->noise << 13; s->noise ^= s->noise >> 17; s->noise ^= s->noise << 5;
            double noise = (double)s->noise / UINT32_MAX * 2 - 1;
            double env = fmin(1, t / 0.008) * pow(fmax(0, 1-t/0.65), 1.8);
            sample += (tanh(3.5 * sin(tau*s->fartphase + 0.8*sin(tau*s->fartphase*2))) * 0.8 + noise*0.2) * env * 0.5;
            s->farttime += 1 / s->sr;
        }
        out[i] = (float)tanh(sample);
    }
}
