#ifndef SynthDSP_h
#define SynthDSP_h
#include <stdint.h>
typedef struct ABSynth ABSynth;
ABSynth *ab_create(double sampleRate);
void ab_destroy(ABSynth *s);
void ab_set(ABSynth *s, float frequency, float gain, float brightness, float vibrato,
            float distortion, float muffle, float rootFrequency, float tempo,
            int mode, int palette);
void ab_fart(ABSynth *s);
void ab_ding(ABSynth *s);
void ab_kick(ABSynth *s);
void ab_cymbal(ABSynth *s);
void ab_trigger_drum(ABSynth *s, int voice, float gain);
void ab_trigger_note(ABSynth *s, int note, float gain);
void ab_set_note_gates(ABSynth *s, uint32_t mask, float gain);
void ab_set_performance(ABSynth *s, float drumGain, float melodyGain, int metronomeEnabled);
void ab_render(ABSynth *s, float *out, uint32_t frames);
#endif
