//
//  DLGPlayerDecoder.m
//  DLGPlayer
//
//  Created by Liu Junqi on 05/12/2016.
//  Copyright © 2016 Liu Junqi. All rights reserved.
//

#import "DLGPlayerDecoder.h"
#import "DLGPlayerDef.h"
#import "DLGPlayerUtils.h"
#import "DLGPlayerVideoFrame.h"
#import "DLGPlayerAudioFrame.h"
#import "DLGPlayerVideoRGBFrame.h"
#import "DLGPlayerVideoYUVFrame.h"
#import <libavformat/avformat.h>
#import <libavutil/imgutils.h>
#import <libswscale/swscale.h>
#import <libswresample/swresample.h>
#import <Accelerate/Accelerate.h>

#define DLGPlayerIOTimeout 30

static NSTimeInterval g_dIOStartTime = 0;
static bool g_bPrepareClose = FALSE;

static int interruptCallback(void *context) {
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval dt = t - g_dIOStartTime;
    if (g_bPrepareClose || dt > DLGPlayerIOTimeout) return 1;
    return 0;
}

@interface DLGPlayerDecoder () {
    AVFormatContext *m_pFormatContext;
    
    // Video
    int m_nVideoStream;
    AVFrame *m_pVideoFrame;
    AVFrame *m_pVideoSwsFrame;
    AVCodecContext *m_pVideoCodecContext;
    struct SwsContext *m_pVideoSwsContext;
    int m_nPictureStream;
    
    // Audio
    int m_nAudioStream;
    AVFrame *m_pAudioFrame;
    AVCodecContext *m_pAudioCodecContext;
    SwrContext *m_pAudioSwrContext;
    void *m_pAudioSwrBuffer;
    int m_nAudioSwrBufferSize;
}

@end

@implementation DLGPlayerDecoder

- (id)init {
    self = [super init];
    if (self) {
        av_register_all();
    }
    return self;
}

- (void)dealloc {
    NSLog(@"DLGPlayerDecoder dealloc");
}

- (BOOL)open:(NSString *)url error:(NSError **)error {
    if (url == nil || url.length == 0) {
        [DLGPlayerUtils createError:error
                         withDomain:DLGPlayerErrorDomainDecoder
                            andCode:DLGPlayerErrorCodeInvalidURL
                         andMessage:DLG_PLAYER_STRINGS_INVALID_URL];
        return NO;
    }
    
    // 1. Init
    avformat_network_init();
    
    // 2. Open Input
    AVFormatContext *fmtctx = NULL;
    int ret = avformat_open_input(&fmtctx, [url UTF8String], NULL, NULL);
    if (ret != 0) {
        if (fmtctx != NULL) avformat_free_context(fmtctx);
        [DLGPlayerUtils createError:error
                         withDomain:DLGPlayerErrorDomainDecoder
                            andCode:DLGPlayerErrorCodeCannotOpenInput
                         andMessage:DLG_PLAYER_STRINGS_CANNOT_OPEN_INPUT];
        return NO;
    }
    
#ifdef DEBUG
    av_dump_format(fmtctx, 0, [url UTF8String], 0);
#endif
    
    // 3. Analyze Stream Info
    ret = avformat_find_stream_info(fmtctx, NULL);
    if (ret < 0) {
        avformat_close_input(&fmtctx);
        [DLGPlayerUtils createError:error
                         withDomain:DLGPlayerErrorDomainDecoder
                            andCode:DLGPlayerErrorCodeCannotFindStreamInfo
                         andMessage:DLG_PLAYER_STRINGS_CANNOT_FIND_STREAM_INFO];
        return NO;
    }
    
    // 4. Find Video Stream
    AVFrame *vframe = NULL;
    AVFrame *vswsframe = NULL;
    AVCodecContext *vcodectx = NULL;
    struct SwsContext *swsctx = NULL;
    BOOL isYUV = NO;
    int picstream = -1;
    int vstream = [self findVideoStream:fmtctx context:&vcodectx pictureStream:&picstream];
    if (vstream >= 0 && vcodectx != NULL) {
        if (vcodectx->pix_fmt != AV_PIX_FMT_NONE) {
            vframe = av_frame_alloc();
            isYUV = (vcodectx->pix_fmt == AV_PIX_FMT_YUV420P || vcodectx->pix_fmt == AV_PIX_FMT_YUVJ420P);
            if (!isYUV) {
                vswsframe = av_frame_alloc();
                ret = av_image_alloc(vswsframe->data, vswsframe->linesize, vcodectx->width, vcodectx->height, AV_PIX_FMT_RGB24, 1);
                swsctx = sws_getContext(vcodectx->width, vcodectx->height, vcodectx->pix_fmt,
                                        vcodectx->width, vcodectx->height, AV_PIX_FMT_RGB24,
                                        SWS_BILINEAR, NULL, NULL, NULL);
            }
            [DLGPlayerDecoder stream:fmtctx->streams[vstream] fps:&_videoFPS timebase:&_videoTimebase default:0.04];
        }
        
        BOOL swsError = isYUV ? NO : (swsctx == NULL || vswsframe == NULL);
        if (vframe == NULL || swsError || ret < 0) {
            vstream = -1;
            if (vcodectx != NULL) avcodec_free_context(&vcodectx);
            if (vframe != NULL) av_frame_free(&vframe);
            if (vswsframe != NULL) av_frame_free(&vswsframe);
            if (swsctx != NULL) { sws_freeContext(swsctx); swsctx = NULL; }
        }
    }
    
    // 5. Find Audio Stream
    AVFrame *aframe = NULL;
    AVCodecContext *acodectx = NULL;
    SwrContext *aswrctx = NULL;
    int astream = [self findAudioStream:fmtctx context:&acodectx];
    if (astream >= 0 && acodectx != NULL) {
        aframe = av_frame_alloc();
        [DLGPlayerDecoder stream:fmtctx->streams[astream] fps:NULL timebase:&_audioTimebase default:0.025];
        
        if (aframe == NULL) {
            astream = -1;
            if (acodectx != NULL) avcodec_free_context(&acodectx);
        }
        aswrctx = swr_alloc_set_opts(NULL,
                                     av_get_default_channel_layout(_audioChannels),
                                     AV_SAMPLE_FMT_S16,
                                     _audioSampleRate,
                                     av_get_default_channel_layout(acodectx->channels),
                                     acodectx->sample_fmt,
                                     acodectx->sample_rate,
                                     0,
                                     NULL);
        if (aswrctx == NULL) {
            astream = -1;
            if (acodectx != NULL) avcodec_free_context(&acodectx);
            if (aframe != NULL) av_frame_free(&aframe);
        }
        
        ret = swr_init(aswrctx);
        if (ret < 0) {
            astream = -1;
            if (aswrctx != NULL) swr_free(&aswrctx);
            if (acodectx != NULL) avcodec_free_context(&acodectx);
            if (aframe != NULL) av_frame_free(&aframe);
        }
    }
    
    // 6. Finish Init
    if (vstream < 0 && astream < 0) {
        avformat_close_input(&fmtctx);
        [DLGPlayerUtils createError:error
                         withDomain:DLGPlayerErrorDomainDecoder
                            andCode:DLGPlayerErrorCodeNoVideoAndAudioStream
                         andMessage:DLG_PLAYER_STRINGS_NO_VIDEO_AND_AUDIO_STREAM];
        return NO;
    }
    
    m_pFormatContext = fmtctx;
    m_nVideoStream = vstream;
    m_pVideoFrame = vframe;
    m_pVideoSwsFrame = vswsframe;
    m_pVideoCodecContext = vcodectx;
    m_pVideoSwsContext = swsctx;
    m_nPictureStream = picstream;
    m_nAudioStream = astream;
    m_pAudioFrame = aframe;
    m_pAudioCodecContext = acodectx;
    m_pAudioSwrContext = aswrctx;
    
    self.isYUV = isYUV;
    self.hasVideo = vstream >= 0;
    self.hasAudio = astream >= 0;
    self.hasPicture = picstream >= 0;
    self.isEOF = NO;
    
    int64_t duration = fmtctx->duration;
    self.duration = (duration == AV_NOPTS_VALUE ? -1 : ((double)duration / AV_TIME_BASE));
    self.metadata = [self findMetadata:fmtctx];
    
    g_bPrepareClose = FALSE;
    AVIOInterruptCB icb = {interruptCallback, NULL};
    fmtctx->interrupt_callback = icb;
    
    return YES;
}

- (NSDictionary *)findMetadata:(AVFormatContext *)fmtctx {
    if (fmtctx == NULL || fmtctx->metadata == NULL) return nil;
    
    NSMutableDictionary *md = [NSMutableDictionary dictionary];
    AVDictionary *metadata = fmtctx->metadata;
    AVDictionaryEntry *entry = av_dict_get(metadata, "", NULL, AV_DICT_IGNORE_SUFFIX);
    while (entry != NULL) {
        NSString *key = [NSString stringWithCString:entry->key encoding:NSUTF8StringEncoding];
        NSString *value = [NSString stringWithCString:entry->value encoding:NSUTF8StringEncoding];
        if (key != nil && value != nil) md[key] = value;
        entry = av_dict_get(metadata, "", entry, AV_DICT_IGNORE_SUFFIX);
    }
    
    return md;
}

#pragma mark - Video Stream & Codec
- (int)findVideoStream:(AVFormatContext *)fmtctx context:(AVCodecContext **)context pictureStream:(int *)pictureStream {
    int stream = -1;
    for (int i = 0; i < fmtctx->nb_streams; ++i) {
        if (fmtctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            int disposition = fmtctx->streams[i]->disposition;
            if ((disposition & AV_DISPOSITION_ATTACHED_PIC) == 0) { // Not attached picture
                AVCodecContext *codectx = [self openVideoCodec:fmtctx stream:i];
                if (codectx != NULL) {
                    if (context != NULL) *context = codectx;
                    stream = i;
                    break;
                }
            } else {
                if (pictureStream != NULL) *pictureStream = i;
            }
        }
    }
    return stream;
}

- (AVCodecContext *)openVideoCodec:(AVFormatContext *)fmtctx stream:(int)stream {
    AVCodecParameters *params = fmtctx->streams[stream]->codecpar;
    AVCodec *codec = avcodec_find_decoder(params->codec_id);
    if (codec == NULL) return NULL;
    
    AVCodecContext *context = avcodec_alloc_context3(codec);
    if (context == NULL) return NULL;
    
    int ret = avcodec_parameters_to_context(context, params);
    if (ret < 0) {
        avcodec_free_context(&context);
        return NULL;
    }
    
    ret = avcodec_open2(context, codec, NULL);
    if (ret < 0) {
        avcodec_free_context(&context);
        return NULL;
    }
    
    return context;
}

#pragma mark - Audio Stream & Codec
- (int)findAudioStream:(AVFormatContext *)fmtctx context:(AVCodecContext **)context {
    int stream = -1;
    for (int i = 0; i < fmtctx->nb_streams; ++i) {
        if (fmtctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            AVCodecContext *codectx = [self openAudioCodec:fmtctx stream:i];
            if (codectx != NULL) {
                if (context != NULL) *context = codectx;
                stream = i;
                break;
            }
        }
    }
    return stream;
}

- (AVCodecContext *)openAudioCodec:(AVFormatContext *)fmtctx stream:(int)stream {
    AVCodecParameters *params = fmtctx->streams[stream]->codecpar;
    AVCodec *codec = avcodec_find_decoder(params->codec_id);
    if (codec == NULL) return NULL;
    
    AVCodecContext *context = avcodec_alloc_context3(codec);
    if (context == NULL) return NULL;
    
    int ret = avcodec_parameters_to_context(context, params);
    if (ret < 0) {
        avcodec_free_context(&context);
        return NULL;
    }
    
    ret = avcodec_open2(context, codec, NULL);
    if (ret < 0) {
        avcodec_free_context(&context);
        return NULL;
    }
    
    return context;
}

#pragma mark - Close
- (void)prepareClose {
    g_bPrepareClose = TRUE;
}

- (void)close {
    [self flush:m_pVideoCodecContext frame:m_pVideoFrame];
    [self flush:m_pAudioCodecContext frame:m_pAudioFrame];
    [self closeVideoStream];
    [self closeAudioStream];
    [self closePictureStream];
    if (m_pFormatContext != NULL) avformat_close_input(&m_pFormatContext);
    avformat_network_deinit();
    self.isYUV = NO;
    self.hasVideo = NO;
    self.hasAudio = NO;
    self.hasPicture = NO;
    self.isEOF = NO;
}

- (void)closeVideoStream {
    m_nVideoStream = -1;
    if (m_pVideoFrame != NULL) av_frame_free(&m_pVideoFrame);
    if (m_pVideoCodecContext != NULL) avcodec_free_context(&m_pVideoCodecContext);
    if (m_pVideoSwsContext != NULL) { sws_freeContext(m_pVideoSwsContext); m_pVideoSwsContext = NULL; }
}

- (void)closeAudioStream {
    m_nAudioStream = -1;
    if (m_pAudioFrame != NULL) av_frame_free(&m_pAudioFrame);
    if (m_pAudioCodecContext != NULL) avcodec_free_context(&m_pAudioCodecContext);
    if (m_pAudioSwrContext != NULL) swr_free(&m_pAudioSwrContext);
}

- (void)closePictureStream {
    m_nPictureStream = -1;
}

- (void)flush:(AVCodecContext *)codectx frame:(AVFrame *)frame {
    if (codectx == NULL) return;
    int ret = avcodec_send_packet(codectx, NULL);
    do {
        ret = avcodec_receive_frame(codectx, frame);
    } while (ret != AVERROR_EOF);
}

#pragma mark - Handle Frames
- (NSArray *)readFrames {
    if ((m_nVideoStream < 0 && m_nAudioStream < 0) || _isEOF) return nil;
    
    AVFormatContext *fmtctx = m_pFormatContext;
    const int vstream = m_nVideoStream;
    AVFrame *vframe = m_pVideoFrame;
    AVFrame *vswsframe = m_pVideoSwsFrame;
    AVCodecContext *vcodectx = m_pVideoCodecContext;
    struct SwsContext *swsctx = m_pVideoSwsContext;
    const int picstream = m_nPictureStream;
    const int astream = m_nAudioStream;
    AVFrame *aframe = m_pAudioFrame;
    AVCodecContext *acodectx = m_pAudioCodecContext;
    SwrContext *swrctx = m_pAudioSwrContext;
    void **swrbuf = &m_pAudioSwrBuffer;
    int *swrbufsize = &m_nAudioSwrBufferSize;
    
    AVPacket packet;
    
    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:15];
    BOOL reading = YES;
    while (reading) {
        g_dIOStartTime = [NSDate timeIntervalSinceReferenceDate];
        int ret = av_read_frame(fmtctx, &packet);
        if (ret < 0) {
            if (ret == AVERROR_EOF) self.isEOF = YES;
            char *e = av_err2str(ret);
            NSLog(@"read frame error: %s", e);
            break;
        }
        
        /*
         * https://ffmpeg.org/doxygen/3.1/group__lavc__encdec.html
         */
        NSArray<DLGPlayerFrame *> *fs = nil;
        if (packet.stream_index == vstream) {
            fs = [self handleVideoPacket:&packet byContext:vcodectx andFrame:vframe andSwsContext:swsctx andSwsFrame:vswsframe];
            reading = NO;
        } else if (packet.stream_index == astream) {
            fs = [self handleAudioPacket:&packet byContext:acodectx andFrame:aframe andSwrContext:swrctx andSwrBuffer:swrbuf andSwrBufferSize:swrbufsize];
            if (!_hasVideo) reading = NO;
        } else if (packet.stream_index == picstream) {
            fs = [self handlePicturePacket:&packet];
            if (!_hasVideo && !_hasAudio) reading = NO;
        }
        if (fs != nil && fs.count > 0) [frames addObjectsFromArray:fs];
        
        av_packet_unref(&packet);
    }
    
    return frames;
}

- (NSArray<DLGPlayerVideoFrame *> *)handlePicturePacket:(AVPacket *)packet {
    NSData *data = [NSData dataWithBytes:packet->data length:packet->size];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    if (provider == NULL) return nil;
    CGImageRef image = CGImageCreateWithJPEGDataProvider(provider, NULL, YES, kCGRenderingIntentDefault);
    if (image == NULL) image = CGImageCreateWithPNGDataProvider(provider, NULL, YES, kCGRenderingIntentDefault);
    if (image == NULL) { CGDataProviderRelease(provider); return nil; }
    
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    NSUInteger length = width * height * 4;
    GLubyte *imageData = malloc(length);
    CGContextRef context = CGBitmapContextCreate(imageData,
                                                 width,
                                                 height,
                                                 8,
                                                 width * 4,
                                                 CGColorSpaceCreateDeviceRGB(),
                                                 kCGImageAlphaPremultipliedLast);
    if (context == NULL) {
        CGImageRelease(image);
        CGDataProviderRelease(provider);
        free(imageData);
        return nil;
    }
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGImageRelease(image);
    CGDataProviderRelease(provider);
    
    NSMutableArray<DLGPlayerVideoFrame *> *frames = [NSMutableArray array];
    DLGPlayerVideoRGBFrame *frame = [[DLGPlayerVideoRGBFrame alloc] init];
    frame.data = [NSData dataWithBytes:imageData length:length];
    frame.width = (int)width;
    frame.height = (int)height;
    frame.hasAlpha = YES;
    [frames addObject:frame];
    
    free(imageData);
    
    return frames;
}

- (NSArray<DLGPlayerVideoFrame *> *)handleVideoPacket:(AVPacket *)packet byContext:(AVCodecContext *)context andFrame:(AVFrame *)frame andSwsContext:(struct SwsContext *)swsctx andSwsFrame:(AVFrame *)swsframe {
    int ret = avcodec_send_packet(context, packet);
    if (ret != 0) { NSLog(@"avcodec_send_packet: %d", ret); return nil; }
    
    NSMutableArray<DLGPlayerVideoFrame *> *frames = [NSMutableArray array];
    do {
        ret = avcodec_receive_frame(context, frame);
        if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)) { break; }
        else if (ret < 0) { NSLog(@"avcodec_receive_frame: %d", ret); break; }
        
        DLGPlayerVideoFrame *f = nil;
        const int width = context->width;
        const int height = context->height;
        if (_isYUV) {
            DLGPlayerVideoYUVFrame *yuv = [[DLGPlayerVideoYUVFrame alloc] init];
            yuv.Y = [DLGPlayerDecoder dataFromVideoFrame:frame->data[0]
                                                linesize:frame->linesize[0]
                                                   width:width
                                                  height:height];
            yuv.Cb = [DLGPlayerDecoder dataFromVideoFrame:frame->data[1]
                                                 linesize:frame->linesize[1]
                                                    width:width / 2
                                                   height:height / 2];
            yuv.Cr = [DLGPlayerDecoder dataFromVideoFrame:frame->data[2]
                                                 linesize:frame->linesize[2]
                                                    width:width / 2
                                                   height:height / 2];
            f = yuv;
        } else {
            sws_scale(swsctx,
                      (uint8_t const **)frame->data,
                      frame->linesize,
                      0,
                      context->height,
                      swsframe->data,
                      swsframe->linesize);
            
            DLGPlayerVideoRGBFrame *rgb = [[DLGPlayerVideoRGBFrame alloc] init];
            rgb.linesize = swsframe->linesize[0];
            rgb.data = [NSData dataWithBytes:swsframe->data[0] length:rgb.linesize * height];
            f = rgb;
        }
        
        f.width = width;
        f.height = height;
        f.position = av_frame_get_best_effort_timestamp(frame) * _videoTimebase;
        double duration = av_frame_get_pkt_duration(frame);
        if (duration > 0) {
            f.duration = duration * _videoTimebase;
            f.duration += frame->repeat_pict * _videoTimebase * 0.5;
        } else {
            f.duration = 1 / _videoFPS;
        }
        
        [frames addObject:f];
    } while(ret == 0);
    
    return frames;
}

- (NSArray<DLGPlayerAudioFrame *> *)handleAudioPacket:(AVPacket *)packet byContext:(AVCodecContext *)context andFrame:(AVFrame *)frame andSwrContext:(SwrContext *)swrctx andSwrBuffer:(void **)swrbuf andSwrBufferSize:(int *)swrbufsize {
    int ret = avcodec_send_packet(context, packet);
    if (ret != 0) { NSLog(@"avcodec_send_packet: %d", ret); return nil; }
    
    NSMutableArray<DLGPlayerAudioFrame *> *frames = [NSMutableArray array];
    do {
        ret = avcodec_receive_frame(context, frame);
        if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)) { break; }
        else if (ret < 0) { NSLog(@"avcodec_receive_frame: %d", ret); break; }
        if (frame->data[0] == NULL) continue;
        
        const float sampleRate = _audioSampleRate;
        const UInt32 channels = _audioChannels;
        
        void *data = NULL;
        NSInteger samplesPerChannel = 0;
        if (swrctx != NULL) {
            float sampleRatio = sampleRate / context->sample_rate;
            float channelRatio = channels / context->channels;
            float ratio = MAX(1, sampleRatio) * MAX(1, channelRatio) * 2;
            int samples = frame->nb_samples * ratio;
            int bufsize = av_samples_get_buffer_size(NULL,
                                                     channels,
                                                     samples,
                                                     AV_SAMPLE_FMT_S16,
                                                     1);
            if (swrbuf == NULL || *swrbufsize < bufsize) {
                *swrbufsize = bufsize;
                *swrbuf = realloc(*swrbuf, bufsize);
            }
            
            Byte *o[2] = { *swrbuf, 0 };
            samplesPerChannel = swr_convert(swrctx, o, samples, (const uint8_t **)frame->data, frame->nb_samples);
            if (samplesPerChannel < 0) {
                NSLog(@"failed to resample audio");
                return nil;
            }
            
            data = *swrbuf;
        } else {
            if (context->sample_fmt != AV_SAMPLE_FMT_S16) {
                NSLog(@"invalid audio format");
                return nil;
            }
            
            data = frame->data[0];
            samplesPerChannel = frame->nb_samples;
        }
        
        NSUInteger elements = samplesPerChannel * channels;
        NSUInteger dataLength = elements * sizeof(float);
        NSMutableData *mdata = [NSMutableData dataWithLength:dataLength];
        
        float scalar = 1.0f / INT16_MAX;
        vDSP_vflt16(data, 1, mdata.mutableBytes, 1, elements);
        vDSP_vsmul(mdata.mutableBytes, 1, &scalar, mdata.mutableBytes, 1, elements);
        
        DLGPlayerAudioFrame *f = [[DLGPlayerAudioFrame alloc] init];
        f.data = mdata;
        f.position = av_frame_get_best_effort_timestamp(frame) * _audioTimebase;
        f.duration = av_frame_get_pkt_duration(frame) * _audioTimebase;
        
        if (f.duration == 0)
            f.duration = f.data.length / (sizeof(float) * channels * sampleRate);
        
        [frames addObject:f];
    } while(ret == 0);
    
    return frames;
}

#pragma mark - Seek
- (void)seek:(double)position {
    _isEOF = NO;
    if (_hasVideo) {
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        int64_t ts = (int64_t)(position / _videoTimebase);
        avformat_seek_file(m_pFormatContext, m_nVideoStream, ts, ts, ts, AVSEEK_FLAG_FRAME);
        avcodec_flush_buffers(m_pVideoCodecContext);
        NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval dt = end - start;
        NSLog(@"seek video: %.4f, start: %.4f, end: %.4f", dt, start, end);
    } else if (_hasAudio) {
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        int64_t ts = (int64_t)(position / _audioTimebase);
        avformat_seek_file(m_pFormatContext, m_nAudioStream, ts, ts, ts, AVSEEK_FLAG_FRAME);
        avcodec_flush_buffers(m_pAudioCodecContext);
        NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval dt = end - start;
        NSLog(@"seek audio: %.4f, start: %.4f, end: %.4f", dt, start, end);
    }
}

#pragma mark - Getter
- (int)videoWidth {
    if (m_pVideoCodecContext == NULL) return 0;
    int width = m_pVideoCodecContext->width;
    AVRational sar = m_pVideoCodecContext->sample_aspect_ratio;
    if (sar.num != 0 && sar.den != 0) {
        width = width * sar.num / sar.den;
    }
    return width;
}

- (int)videoHeight {
    if (m_pVideoCodecContext == NULL) return 0;
    return m_pVideoCodecContext->height;
}

#pragma mark - Utils
+ (NSData *)dataFromVideoFrame:(UInt8 *)data linesize:(int)linesize width:(int)width height:(int)height {
    width = MIN(linesize, width);
    NSMutableData *md = [NSMutableData dataWithLength:width * height];
    Byte *mdata = md.mutableBytes;
    for (int i = 0; i < height; ++i) {
        memcpy(mdata, data, width);
        mdata += width;
        data += linesize;
    }
    return md;
}

+ (void)stream:(AVStream *)stream fps:(double *)fps timebase:(double *)timebase default:(double)defaultTimebase {
    double f = 0, t = 0;
    if (stream->time_base.den > 0 && stream->time_base.num > 0) {
        t = av_q2d(stream->time_base);
    } else {
        t = defaultTimebase;
    }
    
    if (stream->avg_frame_rate.den > 0 && stream->avg_frame_rate.num) {
        f = av_q2d(stream->avg_frame_rate);
    } else if (stream->r_frame_rate.den > 0 && stream->r_frame_rate.num > 0) {
        f = av_q2d(stream->r_frame_rate);
    } else {
        f = 1 / t;
    }
    
    if (fps != NULL) *fps = f;
    if (timebase != NULL) *timebase = t;
}

@end
