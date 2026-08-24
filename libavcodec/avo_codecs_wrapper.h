#pragma once

#include <stdint.h>
#include <stddef.h>

/*
 * Internal ABI between libavcodec and AVO_codecs.dll.
 * This header is not part of the public FFmpeg API.
 */
#pragma pack(push, 1)
typedef struct AVO_CodecContext
{
    uint32_t codec;
    uint32_t sub_codec;
    uint32_t width;
    uint32_t height;
    size_t buffer_size;
    uint8_t *buffer;
    int use_cpu;
    int preserve_alpha;
    int is_encoder;
    void *reserved;
} AVO_CodecContext;

typedef struct AVO_CodecBuffer
{
    uint8_t *data;
    int size;
    int linesize;
    int width;
    int height;
} AVO_CodecBuffer;
#pragma pack(pop)
