#pragma once

#include <stdint.h>
#include <stddef.h>

#pragma pack(push, 1) 
typedef struct AVO_CodecContext
{
    uint32_t codec;
    uint32_t sub_codec;
    uint32_t width;
    uint32_t height;
    size_t buffer_size;
    uint8_t *buffer;
    int use_cpu;        // 0 or 1
    int preserve_alpha; // 0 or 1
    int is_encoder;     // 0 or 1
} AVO_CodecContext;
#pragma pack(pop) 