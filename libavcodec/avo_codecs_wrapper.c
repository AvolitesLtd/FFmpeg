#include <windows.h>
#include "avo_codecs_wrapper.h"
#include "libavutil/opt.h"
#include "libavutil/thread.h"
#include "codec_internal.h"
#include "encode.h"
#include "decode.h"

static HMODULE g_avo_codec_dll = NULL;
static AVOnce g_avo_once = AV_ONCE_INIT;

typedef int (*avo_init_func)(AVCodecContext*);
typedef int (*avo_decode_func)(AVCodecContext*, AVFrame*, int*, AVPacket*);
typedef int (*avo_encode_func)(AVCodecContext*, AVPacket*, const AVFrame*, int*);
typedef void (*avo_close_func)(AVCodecContext*);
typedef size_t (*avo_get_frame_size_func)(AVCodecContext*);

static avo_init_func g_avo_init = NULL;
static avo_decode_func g_avo_decode = NULL;
static avo_encode_func g_avo_encode = NULL;
static avo_close_func g_avo_close = NULL;
static avo_get_frame_size_func g_avo_get_frame_size = NULL;

static void load_avo_codec(void)
{
    g_avo_codec_dll = LoadLibraryA("AVO_codecs_d.dll");

    if (g_avo_codec_dll)
    {
        g_avo_init = (avo_init_func)GetProcAddress(g_avo_codec_dll, "avo_codec_init");
        g_avo_encode = (avo_encode_func)GetProcAddress(g_avo_codec_dll, "avo_codec_encode");
        g_avo_decode = (avo_decode_func)GetProcAddress(g_avo_codec_dll, "avo_codec_decode");
        g_avo_close = (avo_close_func)GetProcAddress(g_avo_codec_dll, "avo_codec_close");
        g_avo_get_frame_size = (avo_get_frame_size_func)GetProcAddress(g_avo_codec_dll, "avo_codec_get_frame_size");
    }

    if (!g_avo_init || !g_avo_encode || !g_avo_decode || !g_avo_close)
        FreeLibrary(g_avo_codec_dll);
}

static int avo_codec_global_init()
{
    ff_thread_once(&g_avo_once, load_avo_codec);

    if (!g_avo_codec_dll)
        return AVERROR_EXTERNAL;

    return 0;
}

static av_cold int avo_codec_init(AVCodecContext* avctx)
{
    avo_codec_global_init();

    if (!g_avo_init)
        return AVERROR_EXTERNAL;

    return g_avo_init(avctx);
}

static int avo_codec_decode(AVCodecContext* avctx, AVFrame* frame, int* got_frame, AVPacket* avpkt)
{
    if (ff_reget_buffer(avctx, frame, 0) < 0)
        return AVERROR(ENOMEM);

    int ret = 0;
    if (g_avo_decode)
        ret = g_avo_decode(avctx, frame, got_frame, avpkt);

    return ret < 0 ? ret : 0;
}

static int avo_codec_encode(AVCodecContext* avctx, AVPacket* pkt, const AVFrame* frame, int* got_packet)
{
    if (!g_avo_encode || !g_avo_get_frame_size)
        return -1;

    uint64_t frame_size = g_avo_get_frame_size(avctx);

    int ret = 0;
    ret = ff_alloc_packet(avctx, pkt, frame_size);
    if (ret < 0)
        return ret;

    ret = g_avo_encode(avctx, pkt, frame, got_packet);

    return ret < 0 ? ret : 0;
}

static av_cold int avo_codec_close(AVCodecContext* avctx)
{
    if (!g_avo_close)
        return -1;

    g_avo_close(avctx);

	return 0;
}

const FFCodec ff_avo_codec_encoder = {
	.p.name = "avo_codec",
	CODEC_LONG_NAME("Avolites Codec"),
	.p.type = AVMEDIA_TYPE_VIDEO,
	.p.id = AV_CODEC_ID_AVO_CODEC,
    .priv_data_size = sizeof(AVO_CodecContext),
	.init = avo_codec_init,
	FF_CODEC_ENCODE_CB(avo_codec_encode),
	.close = avo_codec_close,
	.p.wrapper_name = "avo_codecs_dll",
    CODEC_PIXFMTS(AV_PIX_FMT_ARGB),
    .caps_internal = FF_CODEC_CAP_INIT_CLEANUP,
};

const FFCodec ff_avo_codec_decoder = {
    .p.name = "avo_codec",
    CODEC_LONG_NAME("Avolites Codec"),
    .p.type = AVMEDIA_TYPE_VIDEO,
    .p.id = AV_CODEC_ID_AVO_CODEC,
    .priv_data_size = sizeof(AVO_CodecContext),
    .init = avo_codec_init,
    FF_CODEC_DECODE_CB(avo_codec_decode),
    .close = avo_codec_close,
    .p.wrapper_name = "avo_codecs_dll",
    .p.capabilities = AV_CODEC_CAP_DR1,
};