#include <jni.h>

#include <math.h>

#include <libavcodec/avcodec.h>
#include <libavfilter/avcodec.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/avfiltergraph.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/channel_layout.h>
#include <libavutil/common.h>
#include <libavutil/imgutils.h>
#include <libavutil/mathematics.h>
#include <libavutil/opt.h>
#include <libavutil/samplefmt.h>

#include <android/log.h>

#define MODULE "media-decoder"
/* uncomment the following line to enable native logging */
/* #define LOGGING */

#ifdef LOGGING
#define NDK_INFO(...) \
    __android_log_print(ANDROID_LOG_INFO, MODULE, __VA_ARGS__)
#else
#define NDK_INFO(...)
#endif
#define NDK_ERROR(...) \
    __android_log_print(ANDROID_LOG_ERROR, MODULE, __VA_ARGS__)

typedef struct {
    AVFilterContext *buffersink_ctx, *buffersrc_ctx;
    AVFilterGraph *filter_graph;
    AVCodec *codec;
    AVCodecContext *context;
} internal_data_t;

static const char *filter_descr = "aconvert=s16:stereo";
static jclass runtime_exception;
static jclass out_of_mem;
static jclass aac_info;
static jmethodID aac_info_constr;
static jclass decoding_info;
static jmethodID decoding_info_constr;
static jfieldID ptr_id;

static int
find_sync(jbyte *buffer, int length) {
    int i;
    for (i = 0; i < length - 1 &&
                ((buffer[i] & 0xff) != 0xff || (buffer[i + 1] & 0xf0) != 0xf0);
         i++)
        ;
    return i;
}

static int
init_filters(JNIEnv *env, const char *filters_descr,
             AVFilterGraph **filter_graph, AVCodecContext *dec_ctx,
             AVFilterContext **buffersink_ctx,
             AVFilterContext **buffersrc_ctx) {
    char args[512];
    int ret;
    AVFilter *abuffersrc   = avfilter_get_by_name("abuffer");
    AVFilter *abuffersink  = avfilter_get_by_name("ffabuffersink");
    AVFilterInOut *outputs = avfilter_inout_alloc();
    AVFilterInOut *inputs  = avfilter_inout_alloc();
    const enum AVSampleFormat sample_fmts[] = {AV_SAMPLE_FMT_S16, -1};
    AVABufferSinkParams *abuffersink_params;
    const AVFilterLink *outlink;
    *filter_graph = avfilter_graph_alloc();
    /* buffer audio source: the decoded frames from the decoder will be
     * inserted here. */
    if (!dec_ctx->channel_layout)
        dec_ctx->channel_layout =
            av_get_default_channel_layout(dec_ctx->channels);

    snprintf(args, sizeof(args),
             "sample_rate=%d:sample_fmt=%s:channel_layout=0x%" PRIx64,
             dec_ctx->sample_rate, av_get_sample_fmt_name(dec_ctx->sample_fmt),
             dec_ctx->channel_layout);

    ret = avfilter_graph_create_filter(buffersrc_ctx, abuffersrc, "in", args,
                                       NULL, *filter_graph);
    if (ret < 0) {
        (*env)->ThrowNew(env, runtime_exception,
                         "Cannot create audio buffer source");
        return ret;
    }
    /* buffer audio sink: to terminate the filter chain. */
    abuffersink_params              = av_abuffersink_params_alloc();
    abuffersink_params->sample_fmts = sample_fmts;
    ret =
        avfilter_graph_create_filter(buffersink_ctx, abuffersink, "out", NULL,
                                     abuffersink_params, *filter_graph);
    av_free(abuffersink_params);
    if (ret < 0) {
        (*env)->ThrowNew(env, runtime_exception,
                         "Cannot create audio buffer sink");
        return ret;
    }
    /* Endpoints for the filter graph. */
    outputs->name       = av_strdup("in");
    outputs->filter_ctx = *buffersrc_ctx;
    outputs->pad_idx    = 0;
    outputs->next       = NULL;
    inputs->name        = av_strdup("out");
    inputs->filter_ctx  = *buffersink_ctx;
    inputs->pad_idx     = 0;
    inputs->next        = NULL;
    if ((ret = avfilter_graph_parse(*filter_graph, filters_descr, &inputs,
                                    &outputs, NULL)) < 0) {
        (*env)->ThrowNew(env, runtime_exception,
                         "cannot parse filter description");
        return ret;
    }
    if ((ret = avfilter_graph_config(*filter_graph, NULL)) < 0) {
        (*env)->ThrowNew(env, runtime_exception, "cannot config filter");
        return ret;
    }
    /* Print summary of the sink buffer
     * Note: args buffer is reused to store channel layout string */
    outlink = (*buffersink_ctx)->inputs[0];
    av_get_channel_layout_string(args, sizeof(args), -1,
                                 outlink->channel_layout);
    av_log(NULL, AV_LOG_INFO, "Output: srate:%dHz fmt:%s chlayout:%s\n",
           (int)outlink->sample_rate,
           (char *)av_x_if_null(av_get_sample_fmt_name(outlink->format), "?"),
           args);
    return 0;
}

static void
ffmpeg_log(void *ptr, int level, const char *fmt, va_list vl) {
    char buffer[1024];
    int print_prefix = 1;
    av_log_format_line(ptr, level, fmt, vl, buffer, sizeof(buffer),
                       &print_prefix);
    NDK_INFO(buffer);
}

/*
 * Class:     com_github_jvshahid_mediaplayer_AACPlayer
 * Method:    staticInitNative
 * Signature: ()V
 */
JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM *vm, void *reserved) {
    /* register all the codecs */
    avcodec_register_all();
    avfilter_register_all();

    JNIEnv *env;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        return -1;
    }

    av_log_set_callback(ffmpeg_log);
    av_log_set_level(AV_LOG_DEBUG);

    runtime_exception = (*env)->FindClass(env, "java/lang/RuntimeException");
    runtime_exception = (*env)->NewGlobalRef(env, runtime_exception);
    out_of_mem        = (*env)->FindClass(env, "java/lang/OutOfMemoryError");
    out_of_mem        = (*env)->NewGlobalRef(env, out_of_mem);
    aac_info =
        (*env)->FindClass(env, "com/github/jvshahid/mediaplayer/AACInfo");
    aac_info = (*env)->NewGlobalRef(env, aac_info);
    decoding_info =
        (*env)->FindClass(env, "com/github/jvshahid/mediaplayer/DecodingInfo");
    decoding_info   = (*env)->NewGlobalRef(env, decoding_info);
    aac_info_constr = (*env)->GetMethodID(env, aac_info, "<init>", "(II)V");
    decoding_info_constr =
        (*env)->GetMethodID(env, decoding_info, "<init>", "(I[S)V");
    jclass klazz =
        (*env)->FindClass(env, "com/github/jvshahid/mediaplayer/AACPlayer");
    ptr_id = (*env)->GetFieldID(env, klazz, "ptr", "J");
    return JNI_VERSION_1_6;
}

/*
 * Class:     com_github_jvshahid_mediaplayer_AACPlayer
 * Method:    initNative
 * Signature: ([BI)Lcom/github/jvshahid/mediaplayer/AACInfo;
 */
JNIEXPORT jobject JNICALL
Java_com_github_jvshahid_mediaplayer_AACPlayer_initNative(JNIEnv *env,
                                                          jclass unused,
                                                          jobject thiz,
                                                          jbyteArray jbuffer,
                                                          jint length) {
    internal_data_t *data = calloc(1, sizeof(internal_data_t));

    // FIXME: make sure that the user doesn't call init twice
    (*env)->SetLongField(env, thiz, ptr_id, (jlong)data);

    jbyte *buffer = (*env)->GetByteArrayElements(env, jbuffer, NULL);

    /* find the mpeg audio decoder */
    data->codec = avcodec_find_decoder(AV_CODEC_ID_AAC);
    if (!data->codec) {
        (*env)->ThrowNew(env, runtime_exception, "Cannot create decoder");
        return NULL;
    }

    data->context = avcodec_alloc_context3(NULL);
    if (!data->context) {
        (*env)->ThrowNew(env, out_of_mem, "Cannot create context");
        return NULL;
    }

    /* open it */
    if (avcodec_open2(data->context, data->codec, NULL) < 0) {
        (*env)->ThrowNew(env, runtime_exception, "Could not open codec");
        return NULL;
    }

    int offset = find_sync(buffer, length);

    NDK_INFO("Found sync byte at %d in a buffer of length %d", offset, length);

    // do the initial decoding
    AVPacket avpkt;
    av_init_packet(&avpkt);
    avpkt.data = buffer + offset;
    avpkt.size = length - offset;
    int got_frame;
    AVFrame *decoded_frame = NULL;
    if (!(decoded_frame = avcodec_alloc_frame())) {
        (*env)->ThrowNew(env, runtime_exception,
                         "Could not allocate audio frame");
        return NULL;
    }

    int rc = avcodec_decode_audio4(data->context, decoded_frame, &got_frame,
                                   &avpkt);
    if (rc < 0) {
        (*env)->ThrowNew(env, runtime_exception, "Error while decoding");
        avcodec_free_frame(&decoded_frame);
        return NULL;
    }

    NDK_INFO(
        "decoded first chunk, sample rate: %d, channels: %d, consumed: %d",
        data->context->sample_rate, data->context->channels, rc);

    rc = init_filters(env, filter_descr, &data->filter_graph, data->context,
                      &data->buffersink_ctx, &data->buffersrc_ctx);
    if (rc < 0) {
        // init_filters will throw the appropriate exception
        // (*env)->ThrowNew(env, runtime_exception, "cannot initialize
        // filters\n");
        avcodec_free_frame(&decoded_frame);
        return NULL;
    }

    avcodec_free_frame(&decoded_frame);
    (*env)->ReleaseByteArrayElements(env, jbuffer, buffer, 0);

    return (*env)->NewObject(env, aac_info, aac_info_constr,
                             data->context->sample_rate,
                             data->context->channels);
}

/*
 * Class:     com_github_jvshahid_mediaplayer_AACPlayer
 * Method:    decodeNative
 * Signature: ([BI)Lcom/github/jvshahid/mediaplayer/DecodingInfo;
 */
JNIEXPORT jobject JNICALL
Java_com_github_jvshahid_mediaplayer_AACPlayer_decodeNative(JNIEnv *env,
                                                            jclass unused,
                                                            jobject thiz,
                                                            jbyteArray jbuffer,
                                                            jint length) {
    jobject result        = NULL;
    uint16_t *pcm_samples = NULL;
    int consumed = 0, generated = 0;
    uint16_t *pcm = NULL;

    internal_data_t *data =
        (internal_data_t *)(*env)->GetLongField(env, thiz, ptr_id);

    if (!data) {
        (*env)->ThrowNew(env, runtime_exception,
                         "How is the data pointer NULL");
        return NULL;
    }

    jbyte *buffer = (*env)->GetByteArrayElements(env, jbuffer, NULL);

    AVPacket avpkt;
    av_init_packet(&avpkt);
    avpkt.data             = buffer;
    avpkt.size             = length;
    AVFrame *decoded_frame = NULL;
    while (avpkt.size > 1024) {
        // find the sync packet
        int offset = find_sync(avpkt.data, avpkt.size);
        avpkt.size -= offset;
        avpkt.data += offset;

        if (offset > 0) {
            NDK_ERROR("Found sync at %d, %x, %x", offset, avpkt.data[0] & 0xff,
                      avpkt.data[1] & 0xff);
            consumed += offset;
        }

        if (!decoded_frame) {
            if (!(decoded_frame = avcodec_alloc_frame())) {
                (*env)->ThrowNew(env, runtime_exception,
                                 "Cannot allocate frame");
                return NULL;
            }
        } else {
            avcodec_get_frame_defaults(decoded_frame);
        }

        int got_frame;
        int len = avcodec_decode_audio4(data->context, decoded_frame,
                                        &got_frame, &avpkt);
        if (len < 0) {
            NDK_INFO("Error while decoding: %s", strerror(len));
            (*env)->ThrowNew(env, runtime_exception, "Error while decoding");
            goto end;
        }

        consumed += len;

        if (got_frame) {
            /* push the audio data from decoded frame into the filtergraph */
            if (av_buffersrc_add_frame(data->buffersrc_ctx, decoded_frame, 0) <
                0) {
                (*env)->ThrowNew(env, runtime_exception,
                                 "Error while feeding the audio filtergraph");
                goto end;
            }

            /* pull filtered audio from the filtergraph */
            while (1) {
                AVFilterBufferRef *samplesref;
                int ret = av_buffersink_get_buffer_ref(data->buffersink_ctx,
                                                       &samplesref, 0);
                if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) break;
                if (ret < 0) {
                    (*env)->ThrowNew(
                        env, runtime_exception,
                        "Error while feeding the audio filtergraph");
                    goto end;
                }
                if (samplesref) {
                    const AVFilterBufferRefAudioProps *props =
                        samplesref->audio;
                    const int n =
                        props->nb_samples * av_get_channel_layout_nb_channels(
                                                props->channel_layout);
                    const uint16_t *p     = (uint16_t *)samplesref->data[0];
                    const uint16_t *p_end = p + n;

                    int size    = p_end - p;
                    pcm_samples = realloc(
                        pcm_samples, sizeof(uint16_t) * (generated + size));
                    memcpy(pcm_samples + generated, p, size * 2);
                    generated += size;
                    avfilter_unref_bufferp(&samplesref);
                }
            }
        }

        avpkt.size -= len;
        avpkt.data += len;
        avpkt.dts = avpkt.pts = AV_NOPTS_VALUE;
    }

    jshortArray jpcm_samples = (*env)->NewShortArray(env, generated);
    (*env)->SetShortArrayRegion(env, jpcm_samples, 0, generated, pcm_samples);
    result = (*env)->NewObject(env, decoding_info, decoding_info_constr,
                               consumed, jpcm_samples);

end:
    (*env)->ReleaseByteArrayElements(env, jbuffer, buffer, 0);
    avcodec_free_frame(&decoded_frame);
    free(pcm_samples);

    return result;
}

/*
 * Class:     com_github_jvshahid_mediaplayer_AACPlayer
 * Method:    releaseNative
 * Signature: ()V
 */
JNIEXPORT void JNICALL
Java_com_github_jvshahid_mediaplayer_AACPlayer_releaseNative(JNIEnv *env,
                                                             jclass unused,
                                                             jobject thiz) {
    internal_data_t *data =
        (internal_data_t *)(*env)->GetLongField(env, thiz, ptr_id);
    (*env)->SetLongField(env, thiz, ptr_id,
                         NULL); /* set the pointer to NULL */

    if (!data) return; /* we probably closed before we even initialize */

    avcodec_close(data->context);
    av_free(data->context);
    avfilter_graph_free(&data->filter_graph);
}
