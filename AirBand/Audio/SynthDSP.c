#include "SynthDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>

enum { EVENT_FART = 1, EVENT_DING = 2, EVENT_KICK = 4, EVENT_CYMBAL = 8 };

struct ABSynth {
    double sr, phase, subphase, shimmer, lfo, clock;
    double songPhase, bassPhase, stepPhase, kickPhase, dingPhase;
    double fartPhase, fartTime;
    float gain, freq, bright, vib, drive, muffle, root, tempo;
    float kickEnv, snareEnv, hatEnv, cymbalEnv, dingEnv, lowpass;
    float melodyFreq, bassFreq, morph;
    int step, currentMode;
    _Atomic float targetFreq, targetGain, targetBright, targetVib, targetDrive;
    _Atomic float targetMuffle, targetRoot, targetTempo;
    _Atomic int palette, mode, events;
    uint32_t noise;
};

static double wrap(double phase) { return phase - floor(phase); }
static double midi_ratio(int semitones) { return pow(2.0, (double)semitones / 12.0); }

ABSynth *ab_create(double sr) {
    ABSynth *s = calloc(1, sizeof(ABSynth));
    if (!s) return NULL;
    s->sr = sr; s->freq = 220; s->root = 220; s->tempo = 108;
    s->noise = 7419; s->fartTime = 2; s->step = 15; s->currentMode = -1;
    atomic_init(&s->targetFreq, 220); atomic_init(&s->targetGain, 0);
    atomic_init(&s->targetBright, 0.25); atomic_init(&s->targetVib, 0);
    atomic_init(&s->targetDrive, 0); atomic_init(&s->targetMuffle, 0);
    atomic_init(&s->targetRoot, 220); atomic_init(&s->targetTempo, 108);
    atomic_init(&s->palette, 0); atomic_init(&s->mode, 0); atomic_init(&s->events, 0);
    return s;
}

void ab_destroy(ABSynth *s) { free(s); }

void ab_set(ABSynth *s, float f, float g, float b, float v, float d, float m,
            float root, float tempo, int mode, int palette) {
    atomic_store(&s->targetFreq, f); atomic_store(&s->targetGain, g);
    atomic_store(&s->targetBright, b); atomic_store(&s->targetVib, v);
    atomic_store(&s->targetDrive, d); atomic_store(&s->targetMuffle, m);
    atomic_store(&s->targetRoot, root); atomic_store(&s->targetTempo, tempo);
    atomic_store(&s->mode, mode); atomic_store(&s->palette, palette);
}

void ab_fart(ABSynth *s) { atomic_fetch_or(&s->events, EVENT_FART); }
void ab_ding(ABSynth *s) { atomic_fetch_or(&s->events, EVENT_DING); }
void ab_kick(ABSynth *s) { atomic_fetch_or(&s->events, EVENT_KICK); }
void ab_cymbal(ABSynth *s) { atomic_fetch_or(&s->events, EVENT_CYMBAL); }

static double palette_tone(ABSynth *s, double phase, double subphase, double shimmer, int palette) {
    const double tau = 6.283185307179586;
    double ph = tau * phase;
    double prism = sin(ph + (0.18 + s->bright * 1.3) * sin(2 * ph)) * 0.7 + sin(tau * shimmer) * 0.16;
    double halo = sin(ph) * 0.40 + sin(tau * shimmer) * 0.27 + sin(tau * subphase) * 0.25 + sin(ph * 3) * s->bright * 0.08;
    double pulse = (sin(ph) * 0.65 + sin(2 * ph) * s->bright * 0.2 + sin(tau * subphase) * 0.15)
                 * (0.3 + 0.7 * pow(0.5 + 0.5 * cos(tau * s->clock), 3));
    double a = fmin(1, s->morph), c = fmax(0, s->morph - 1);
    (void)palette;
    return (prism * (1 - a) + halo * a) * (1 - c) + pulse * c;
}

static void trigger_step(ABSynth *s, int mode) {
    static const int melody[16] = {0, 3, 7, 10, 7, 5, 3, 7, 12, 10, 7, 5, 3, 5, 7, 10};
    static const int bass[4] = {0, 0, 7, 10};
    s->step = (s->step + 1) & 15;
    s->melodyFreq = s->root * (float)midi_ratio(melody[s->step]);
    s->bassFreq = s->root * 0.5f * (float)midi_ratio(bass[s->step / 4]);
    s->hatEnv = mode == 2 ? 0.28f : 0.10f;
    if ((s->step & 3) == 0) s->kickEnv = mode == 2 ? 1.0f : 0.65f;
    if (s->step == 4 || s->step == 12) s->snareEnv = mode == 2 ? 0.72f : 0.28f;
}

void ab_render(ABSynth *s, float *out, uint32_t frames) {
    const double tau = 6.283185307179586;
    float targetF = atomic_load(&s->targetFreq), targetG = atomic_load(&s->targetGain);
    float targetB = atomic_load(&s->targetBright), targetV = atomic_load(&s->targetVib);
    float targetD = atomic_load(&s->targetDrive), targetM = atomic_load(&s->targetMuffle);
    float targetRoot = atomic_load(&s->targetRoot), targetTempo = atomic_load(&s->targetTempo);
    int mode = atomic_load(&s->mode), palette = atomic_load(&s->palette);
    int events = atomic_exchange(&s->events, 0);
    if (events & EVENT_FART) { s->fartTime = 0; s->fartPhase = 0; }
    if (events & EVENT_DING) { s->dingEnv = 1; s->dingPhase = 0; }
    if (events & EVENT_KICK) { s->kickEnv = 1; s->kickPhase = 0; }
    if (events & EVENT_CYMBAL) s->cymbalEnv = 1;
    if (s->currentMode != mode) {
        s->currentMode = mode; s->step = 15; s->stepPhase = 0.999;
        s->kickEnv = s->snareEnv = s->hatEnv = 0;
    }
    const float smoothing = (float)(1 - exp(-1.0 / (s->sr * 0.018)));
    for (uint32_t i = 0; i < frames; i++) {
        s->freq += (targetF - s->freq) * smoothing;
        s->gain += (targetG - s->gain) * smoothing;
        s->bright += (targetB - s->bright) * smoothing;
        s->vib += (targetV - s->vib) * smoothing;
        s->drive += (targetD - s->drive) * smoothing;
        s->muffle += (targetM - s->muffle) * smoothing;
        s->root += (targetRoot - s->root) * smoothing;
        s->tempo += (targetTempo - s->tempo) * smoothing;
        s->morph += ((float)palette - s->morph) * smoothing;
        s->lfo = wrap(s->lfo + 5.2 / s->sr);
        s->clock = wrap(s->clock + 3.2 / s->sr);

        double musical = 0;
        if (mode == 0) {
            double pitch = s->freq * (1 + 0.014 * s->vib * sin(tau * s->lfo));
            s->phase = wrap(s->phase + pitch / s->sr);
            s->subphase = wrap(s->subphase + pitch * 0.5008 / s->sr);
            s->shimmer = wrap(s->shimmer + pitch * 1.002 / s->sr);
            musical = palette_tone(s, s->phase, s->subphase, s->shimmer, palette) * 0.48;
        } else {
            s->stepPhase += (s->tempo / 60.0) * 4.0 / s->sr;
            if (s->stepPhase >= 1) { s->stepPhase -= 1; trigger_step(s, mode); }
            if (mode == 1) {
                double melodyPitch = s->melodyFreq * (1 + 0.008 * s->vib * sin(tau * s->lfo));
                s->songPhase = wrap(s->songPhase + melodyPitch / s->sr);
                s->shimmer = wrap(s->shimmer + melodyPitch * 1.002 / s->sr);
                s->bassPhase = wrap(s->bassPhase + s->bassFreq / s->sr);
                double melodyEnv = 0.52 + 0.48 * exp(-s->stepPhase * 5.5);
                musical = palette_tone(s, s->songPhase, s->songPhase * 0.5, s->shimmer, palette) * 0.34 * melodyEnv;
                musical += tanh(sin(tau * s->bassPhase) * 1.8) * 0.22;
            }
        }

        s->kickPhase = wrap(s->kickPhase + (48 + 92 * s->kickEnv * s->kickEnv) / s->sr);
        double kick = sin(tau * s->kickPhase) * s->kickEnv * 0.78;
        s->noise ^= s->noise << 13; s->noise ^= s->noise >> 17; s->noise ^= s->noise << 5;
        double noise = (double)s->noise / UINT32_MAX * 2 - 1;
        double snare = noise * s->snareEnv * 0.34;
        double hat = noise * s->hatEnv * ((s->noise & 1) ? 1 : -1) * 0.18;
        double cymbal = noise * s->cymbalEnv * 0.42 + sin(tau * s->phase * 7.13) * s->cymbalEnv * 0.15;
        s->kickEnv *= 0.99970f; s->snareEnv *= 0.99962f; s->hatEnv *= 0.9972f; s->cymbalEnv *= 0.99972f;

        double driven = tanh(musical * (1 + s->drive * 5)) / (1 + s->drive * 0.75);
        double musicMix = musical * (1 - s->drive) + driven * s->drive;
        double percussion = mode == 0 ? 0 : kick + snare + hat;
        double sample = (musicMix + percussion) * s->gain;

        double cutoff = 260 + pow(1 - s->muffle, 2) * 15000;
        double filterAlpha = 1 - exp(-tau * cutoff / s->sr);
        s->lowpass += (float)(filterAlpha * (sample - s->lowpass));
        sample = sample * (1 - s->muffle) + s->lowpass * s->muffle;
        sample += cymbal * (mode == 2 ? 1 : 0.72);

        if (s->fartTime < 0.65) {
            double t = s->fartTime;
            s->fartPhase = wrap(s->fartPhase + (48 + 100 * exp(-9*t) + 12*sin(80*t)) / s->sr);
            double env = fmin(1, t / 0.008) * pow(fmax(0, 1-t/0.65), 1.8);
            sample += (tanh(3.5 * sin(tau*s->fartPhase + 0.8*sin(tau*s->fartPhase*2))) * 0.8 + noise*0.2) * env * 0.5;
            s->fartTime += 1 / s->sr;
        }
        s->dingPhase = wrap(s->dingPhase + 920.0 / s->sr);
        sample += (sin(tau*s->dingPhase) + 0.32*sin(tau*s->dingPhase*2.01)) * s->dingEnv * 0.28;
        s->dingEnv *= 0.99987f;
        out[i] = (float)tanh(sample);
    }
}
