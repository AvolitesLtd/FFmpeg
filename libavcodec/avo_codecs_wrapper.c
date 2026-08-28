#include <windows.h>
#include "avo_codecs_wrapper.h"
#include "libavutil/imgutils.h"
#include "libavutil/macros.h"
#include "libavutil/thread.h"
#include "codec.h"
#include "codec_internal.h"
#include "encode.h"
#include "decode.h"

static HMODULE g_avo_codec_dll = NULL;
static AVOnce g_avo_once = AV_ONCE_INIT;

typedef int (*avo_init_func)(AVO_CodecContext *);
typedef int (*avo_decode_func)(AVO_CodecContext *, AVO_CodecBuffer *frame, int *got_frame, const AVO_CodecBuffer *pkt);
typedef int (*avo_encode_func)(AVO_CodecContext *, AVO_CodecBuffer *pkt, const AVO_CodecBuffer *frame, int *got_packet);
typedef void (*avo_close_func)(AVO_CodecContext *);
typedef size_t (*avo_get_frame_size_func)(const AVO_CodecContext *);

static avo_init_func g_avo_init = NULL;
static avo_decode_func g_avo_decode = NULL;
static avo_encode_func g_avo_encode = NULL;
static avo_close_func g_avo_close = NULL;
static avo_get_frame_size_func g_avo_get_frame_size = NULL;

static int bind_avo_codec_dll(HMODULE dll)
{
    g_avo_init = (avo_init_func)GetProcAddress(dll, "avo_codec_init");
    g_avo_encode = (avo_encode_func)GetProcAddress(dll, "avo_codec_encode");
    g_avo_decode = (avo_decode_func)GetProcAddress(dll, "avo_codec_decode");
    g_avo_close = (avo_close_func)GetProcAddress(dll, "avo_codec_close");
    g_avo_get_frame_size = (avo_get_frame_size_func)GetProcAddress(dll, "avo_codec_get_frame_size");

    return g_avo_init && g_avo_encode && g_avo_decode && g_avo_close && g_avo_get_frame_size;
}

static void load_avo_codec(void)
{
    static const char *const dll_names[] = {
        "AVO_codecs.dll",
        "AVO_codecs_d.dll",
    };

    g_avo_codec_dll = NULL;
    g_avo_init = NULL;
    g_avo_encode = NULL;
    g_avo_decode = NULL;
    g_avo_close = NULL;
    g_avo_get_frame_size = NULL;

    for (int i = 0; i < FF_ARRAY_ELEMS(dll_names); i++) {
        HMODULE dll = LoadLibraryA(dll_names[i]);
        if (!dll)
            continue;
        if (bind_avo_codec_dll(dll)) {
            g_avo_codec_dll = dll;
            return;
        }
        FreeLibrary(dll);
    }
}

static int avo_codec_global_init(void)
{
    ff_thread_once(&g_avo_once, load_avo_codec);

    if (!g_avo_codec_dll)
        return AVERROR_EXTERNAL;

    return 0;
}

static void copy_avo_config(AVCodecContext *avctx, AVO_CodecContext *ctx)
{
    if (avctx->opaque) {
        const AVO_CodecContext *cfg = avctx->opaque;
        ctx->codec = cfg->codec;
        ctx->sub_codec = cfg->sub_codec;
        ctx->use_cpu = cfg->use_cpu;
        ctx->preserve_alpha = cfg->preserve_alpha;
        ctx->is_encoder = cfg->is_encoder;
        if (cfg->width)
            ctx->width = cfg->width;
        if (cfg->height)
            ctx->height = cfg->height;
    }

    if (!ctx->width)
        ctx->width = avctx->width;
    if (!ctx->height)
        ctx->height = avctx->height;
    ctx->is_encoder = av_codec_is_encoder(avctx->codec);
}

static av_cold int avo_codec_init(AVCodecContext *avctx)
{
    AVO_CodecContext *ctx = avctx->priv_data;
    int ret;

    if (avo_codec_global_init() < 0 || !g_avo_init)
        return AVERROR_EXTERNAL;

    copy_avo_config(avctx, ctx);

    if (av_image_check_size(ctx->width, ctx->height, 0, avctx) < 0)
        return AVERROR(EINVAL);

    ret = g_avo_init(ctx);
    if (ret < 0)
        return ret;

    avctx->pix_fmt = AV_PIX_FMT_ARGB;
    avctx->bits_per_coded_sample = 32;
    avctx->width = ctx->width;
    avctx->height = ctx->height;
    return 0;
}

static int avo_codec_decode(AVCodecContext *avctx, AVFrame *frame, int *got_frame, AVPacket *avpkt)
{
    AVO_CodecContext *ctx = avctx->priv_data;
    AVO_CodecBuffer out;
    AVO_CodecBuffer in;
    int ret;

    if (!g_avo_decode)
        return AVERROR_EXTERNAL;

    if (ff_reget_buffer(avctx, frame, 0) < 0)
        return AVERROR(ENOMEM);

    out.data = frame->data[0];
    out.size = 0;
    out.linesize = frame->linesize[0];
    out.width = frame->width;
    out.height = frame->height;

    in.data = avpkt->data;
    in.size = avpkt->size;
    in.linesize = 0;
    in.width = 0;
    in.height = 0;

    ret = g_avo_decode(ctx, &out, got_frame, &in);
    if (ret < 0)
        return ret;

    if (*got_frame)
        frame->pict_type = AV_PICTURE_TYPE_I;

    return 0;
}

static int avo_codec_encode(AVCodecContext *avctx, AVPacket *pkt, const AVFrame *frame, int *got_packet)
{
    AVO_CodecContext *ctx = avctx->priv_data;
    AVO_CodecBuffer out;
    AVO_CodecBuffer in;
    size_t frame_size;
    int ret;

    if (!g_avo_encode || !g_avo_get_frame_size)
        return AVERROR_EXTERNAL;

    frame_size = g_avo_get_frame_size(ctx);
    ret = ff_alloc_packet(avctx, pkt, frame_size);
    if (ret < 0)
        return ret;

    out.data = pkt->data;
    out.size = pkt->size;
    out.linesize = 0;
    out.width = 0;
    out.height = 0;

    in.data = frame ? frame->data[0] : NULL;
    in.size = 0;
    in.linesize = frame ? frame->linesize[0] : 0;
    in.width = frame ? frame->width : 0;
    in.height = frame ? frame->height : 0;

    ret = g_avo_encode(ctx, &out, &in, got_packet);
    if (ret < 0)
        return ret;

    pkt->size = out.size;
    if (*got_packet)
        pkt->flags |= AV_PKT_FLAG_KEY;

    return 0;
}

static av_cold int avo_codec_close(AVCodecContext *avctx)
{
    AVO_CodecContext *ctx = avctx->priv_data;

    if (g_avo_close)
        g_avo_close(ctx);

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
    CODEC_PIXFMTS(AV_PIX_FMT_ARGB),
    .p.capabilities = AV_CODEC_CAP_DR1,
    .caps_internal = FF_CODEC_CAP_INIT_CLEANUP,
};
