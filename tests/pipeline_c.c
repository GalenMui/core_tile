// Small C program with a visible store and load in the pipeline trace.
#include <stdint.h>

volatile uint64_t pipeline_word;

int main(void)
{
    pipeline_word = 0x11;
    return pipeline_word == 0x11 ? 0 : 1;
}
