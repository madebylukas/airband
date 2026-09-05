#include "SynthDSP.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static void check(int condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", message); exit(1); }
}

static double render_rms(ABSynth *s, float *buffer, int frames) {
    ab_render(s, buffer, (uint32_t)frames);
    double power = 0;
    for (int i = 0; i < frames; i++) {
        check(isfinite(buffer[i]) && fabs(buffer[i]) <= 1, "finite bounded output");
        power += buffer[i] * buffer[i];
    }
    return sqrt(power / frames);
}

int main(void) {
    float buffer[48000];
    ABSynth *s = ab_create(48000);
    check(s != NULL, "allocation");
    check(render_rms(s, buffer, 48000) == 0, "initial silence");

    for (int palette = 0; palette < 3; palette++) {
        ab_set(s, 293.6648f, 0.64f, 1, 1, 0.8f, 0.2f, 130.81f, 112, 0, palette);
        double rms = render_rms(s, buffer, 48000);
        check(rms > 0.001, "audible free palette");
        printf("PASS free palette %d RMS %.4f\n", palette, rms);
    }

    ab_set(s, 220, 0.60f, 0.5f, 0.2f, 0.3f, 0.1f, 130.81f, 124, 1, 0);
    check(render_rms(s, buffer, 48000) > 0.01, "song mode produces melody bass and beat");
    ab_set(s, 220, 0.60f, 0, 0, 0.4f, 0, 130.81f, 142, 2, 0);
    check(render_rms(s, buffer, 48000) > 0.01, "drum mode produces a beat");
    ab_kick(s); ab_cymbal(s);
    check(render_rms(s, buffer, 48000) > 0.01, "manual drum gestures are audible");

    ab_set(s, 220, 0, 0.5f, 0, 0.25f, 0, 146.83f, 116, 3, 0);
    ab_set_performance(s, 0.85f, 0.75f, 0);
    for (int voice = 0; voice < 5; voice++) ab_trigger_drum(s, voice, 0.85f);
    for (int note = 0; note < 5; note++) ab_trigger_note(s, note, 0.75f);
    check(render_rms(s, buffer, 48000) > 0.01, "finger jam drums and pentatonic notes are audible");

    ab_set(s, 220, 0, 0, 0, 0, 0, 146.83f, 120, 3, 0);
    ab_set_performance(s, 0, 0, 1);
    check(render_rms(s, buffer, 48000) > 0.001, "metronome is audible without either hand");

    ab_set(s, 220, 0, 0, 0, 0, 0, 220, 108, 0, 0);
    ab_set_performance(s, 0, 0, 0);
    render_rms(s, buffer, 48000);
    check(fabs(buffer[47999]) < 0.0001, "release reaches silence");
    ab_fart(s); check(render_rms(s, buffer, 48000) > 0.001, "fallback fart is audible");
    ab_ding(s); check(render_rms(s, buffer, 48000) > 0.001, "fallback ding is audible");
    ab_destroy(s);
    puts("PASS sequencer, effects, gestures, release and output bounds");
}
