#include "SynthDSP.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void check(int condition, const char *message) { if (!condition) { fprintf(stderr,"FAIL %s\n",message); exit(1); } }
int main(void) {
    float buffer[48000];
    ABSynth *s=ab_create(48000); check(s!=NULL,"allocation");
    ab_render(s,buffer,48000);
    for(int i=0;i<48000;i++) check(buffer[i]==0,"initial silence");
    for(int p=0;p<3;p++) {
        ab_set(s,293.6648,0.67,1,1,1,p); ab_render(s,buffer,48000);
        double power=0;
        for(int i=0;i<48000;i++) { check(isfinite(buffer[i]) && fabs(buffer[i])<=1,"finite bounded tone"); power+=buffer[i]*buffer[i]; }
        check(power/48000>0.001,"audible palette");
        printf("PASS palette %d RMS %.4f\n",p,sqrt(power/48000));
    }
    ab_set(s,220,0,0,0,0,0); ab_render(s,buffer,48000);
    check(fabs(buffer[47999])<0.000001,"release to silence");
    ab_fart(s); ab_render(s,buffer,48000);
    double power=0; for(int i=0;i<48000;i++){check(isfinite(buffer[i])&&fabs(buffer[i])<=1,"finite bounded fart");power+=buffer[i]*buffer[i];}
    check(power>1,"fart audible");check(fabs(buffer[47999])<0.000001,"fart ends");
    ab_destroy(s); puts("PASS silence, release, fart envelope and output bounds");
}
