//
//  DLGPlayer.m
//  DLGPlayer
//
//  Created by Liu Junqi on 09/12/2016.
//  Copyright © 2016 Liu Junqi. All rights reserved.
//

#import "DLGPlayer.h"
#import "DLGPlayerView.h"
#import "DLGPlayerDecoder.h"
#import "DLGPlayerDef.h"
#import "DLGPlayerAudioManager.h"
#import "DLGPlayerFrame.h"
#import "DLGPlayerVideoFrame.h"
#import "DLGPlayerAudioFrame.h"

@interface DLGPlayer ()

@property (nonatomic) DLGPlayerView *view;
@property (nonatomic) DLGPlayerDecoder *decoder;
@property (nonatomic) DLGPlayerAudioManager *audio;

@property (nonatomic) NSMutableArray *vframes;
@property (nonatomic) NSMutableArray *aframes;
@property (nonatomic) DLGPlayerAudioFrame *playingAudioFrame;
@property (nonatomic) NSUInteger playingAudioFrameDataPosition;
@property (nonatomic) double bufferedDuration;
@property (nonatomic) double mediaPosition;
@property (nonatomic) double mediaSyncTime;
@property (nonatomic) double mediaSyncPosition;

@property (nonatomic) NSThread *frameReaderThread;
@property (nonatomic) BOOL notifiedBufferStart;
@property (nonatomic) BOOL requestSeek;
@property (nonatomic) double requestSeekPosition;
@property (nonatomic) BOOL opening;

@property (nonatomic) dispatch_semaphore_t vFramesLock;
@property (nonatomic) dispatch_semaphore_t aFramesLock;

@end

@implementation DLGPlayer

- (id)init {
    self = [super init];
    if (self) {
        [self initAll];
    }
    return self;
}

- (void)dealloc {
    NSLog(@"DLGPlayer dealloc");
}

- (void)initAll {
    [self initVars];
    [self initAudio];
    [self initDecoder];
    [self initView];
}

- (void)initVars {
    self.minBufferDuration = DLGPlayerMinBufferDuration;
    self.maxBufferDuration = DLGPlayerMaxBufferDuration;
    self.bufferedDuration = 0;
    self.mediaPosition = 0;
    self.mediaSyncTime = 0;
    self.vframes = [NSMutableArray arrayWithCapacity:128];
    self.aframes = [NSMutableArray arrayWithCapacity:128];
    self.playingAudioFrame = nil;
    self.playingAudioFrameDataPosition = 0;
    self.opening = NO;
    self.buffering = NO;
    self.playing = NO;
    self.opened = NO;
    self.requestSeek = NO;
    self.requestSeekPosition = 0;
    self.frameReaderThread = nil;
    self.aFramesLock = dispatch_semaphore_create(1);
    self.vFramesLock = dispatch_semaphore_create(1);
}

- (void)initView {
    DLGPlayerView *v = [[DLGPlayerView alloc] init];
    self.view = v;
}

- (void)initDecoder {
    self.decoder = [[DLGPlayerDecoder alloc] init];
}

- (void)initAudio {
    self.audio = [[DLGPlayerAudioManager alloc] init];
}

- (void)clearVars {
    [self.vframes removeAllObjects];
    [self.aframes removeAllObjects];
    self.playingAudioFrame = nil;
    self.playingAudioFrameDataPosition = 0;
    self.opening = NO;
    self.buffering = NO;
    self.playing = NO;
    self.opened = NO;
    self.bufferedDuration = 0;
    self.mediaPosition = 0;
    self.mediaSyncTime = 0;
    [self.view clear];
}

- (void)open:(NSString *)url {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        _opening = YES;
        
        if ([_audio open:&error]) {
            _decoder.audioChannels = [_audio channels];
            _decoder.audioSampleRate = [_audio sampleRate];
        } else {
            [self handleError:error];
        }
        
        if (![_decoder open:url error:&error]) {
            _opening = NO;
            [self handleError:error];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            _view.isYUV = [_decoder isYUV];
            _view.keepLastFrame = [_decoder hasPicture] && ![_decoder hasVideo];
            _view.contentSize = CGSizeMake([_decoder videoWidth], [_decoder videoHeight]);
            _view.contentMode = UIViewContentModeScaleAspectFit;
            
            _duration = _decoder.duration;
            _metadata = _decoder.metadata;
            _opening = NO;
            self.buffering = NO;
            self.playing = NO;
            _bufferedDuration = 0;
            self.mediaPosition = 0;
            _mediaSyncTime = 0;
            
            __weak DLGPlayer *ws = self;
            _audio.frameReaderBlock = ^(float *data, UInt32 frames, UInt32 channels) {
                [ws readAudioFrame:data frames:frames channels:channels];
            };
            
            _opened = YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:DLGPlayerNotificationOpened object:self];
        });
    });
}

- (void)close {
    if (!_opened && !_opening) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DLGPlayerNotificationClosed object:self];
        return;
    }
    [self pause];
    [_decoder prepareClose];
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        if (_opening || self.buffering) return;
        [_decoder close];
        NSArray<NSError *> *errors = nil;
        if ([_audio close:&errors]) {
            [self clearVars];
            [[NSNotificationCenter defaultCenter] postNotificationName:DLGPlayerNotificationClosed object:self];
        } else {
            for (NSError *error in errors) {
                [self handleError:error];
            }
        }
        dispatch_cancel(timer);
    });
    dispatch_resume(timer);
}

- (void)play {
    if (!_opened || self.playing) return;
    
    self.playing = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self render];
        [self startFrameReaderThread];
    });
    NSError *error = nil;
    if (![_audio play:&error]) {
        [self handleError:error];
    }
}

- (void)pause {
    self.playing = NO;
    NSError *error = nil;
    if (![_audio pause:&error]) {
        [self handleError:error];
    }
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
}

- (void)startFrameReaderThread {
    if (_frameReaderThread == nil) {
        self.frameReaderThread = [[NSThread alloc] initWithTarget:self selector:@selector(runFrameReader) object:nil];
        [self.frameReaderThread start];
    }
}

- (void)runFrameReader {
    @autoreleasepool {
        while (self.playing) {
            [self readFrame];
            if (_requestSeek) {
                [self seekPositionInFrameReader];
            } else {
                [NSThread sleepForTimeInterval:1.5];
            }
        }
        self.frameReaderThread = nil;
    }
}

- (void)readFrame {
    self.buffering = YES;
    
    NSMutableArray *tempVFrames = [NSMutableArray arrayWithCapacity:8];
    NSMutableArray *tempAFrames = [NSMutableArray arrayWithCapacity:8];
    double tempDuration = 0;
    dispatch_time_t t = dispatch_time(DISPATCH_TIME_NOW, 0.02 * NSEC_PER_SEC);
    
    while (self.playing && !_decoder.isEOF && !_requestSeek
           && (_bufferedDuration + tempDuration) < _maxBufferDuration) {
        @autoreleasepool {
            NSArray *fs = [_decoder readFrames];
            if (fs == nil) { break; }
            if (fs.count == 0) { continue; }
            
            {
                for (DLGPlayerFrame *f in fs) {
                    if (f.type == kDLGPlayerFrameTypeVideo) {
                        [tempVFrames addObject:f];
                        tempDuration += f.duration;
                    }
                }
                
                long timeout = dispatch_semaphore_wait(_vFramesLock, t);
                if (timeout == 0) {
                    if (tempVFrames.count > 0) {
                        _bufferedDuration += tempDuration;
                        tempDuration = 0;
                        [_vframes addObjectsFromArray:tempVFrames];
                        [tempVFrames removeAllObjects];
                    }
                    dispatch_semaphore_signal(_vFramesLock);
                }
            }
            {
                for (DLGPlayerFrame *f in fs) {
                    if (f.type == kDLGPlayerFrameTypeAudio) {
                        [tempAFrames addObject:f];
                        if (!_decoder.hasVideo) tempDuration += f.duration;
                    }
                }
                
                long timeout = dispatch_semaphore_wait(_aFramesLock, t);
                if (timeout == 0) {
                    if (tempAFrames.count > 0) {
                        if (!_decoder.hasVideo) {
                            _bufferedDuration += tempDuration;
                            tempDuration = 0;
                        }
                        [_aframes addObjectsFromArray:tempAFrames];
                        [tempAFrames removeAllObjects];
                    }
                    dispatch_semaphore_signal(_aFramesLock);
                }
            }
        }
    }
    
    {
        // add the rest video frames
        while (tempVFrames.count > 0 || tempAFrames.count > 0) {
            if (tempVFrames.count > 0) {
                long timeout = dispatch_semaphore_wait(_vFramesLock, t);
                if (timeout == 0) {
                    _bufferedDuration += tempDuration;
                    tempDuration = 0;
                    [_vframes addObjectsFromArray:tempVFrames];
                    [tempVFrames removeAllObjects];
                    dispatch_semaphore_signal(_vFramesLock);
                }
            }
            if (tempAFrames.count > 0) {
                long timeout = dispatch_semaphore_wait(_aFramesLock, t);
                if (timeout == 0) {
                    if (!_decoder.hasVideo) {
                        _bufferedDuration += tempDuration;
                        tempDuration = 0;
                    }
                    [_aframes addObjectsFromArray:tempAFrames];
                    [tempAFrames removeAllObjects];
                    dispatch_semaphore_signal(_aFramesLock);
                }
            }
        }
    }
    
    self.buffering = NO;
}

- (void)seekPositionInFrameReader {
    [_decoder seek:_requestSeekPosition];
    {
        dispatch_semaphore_wait(_vFramesLock, DISPATCH_TIME_FOREVER);
        [_vframes removeAllObjects];
        dispatch_semaphore_signal(_vFramesLock);
    }
    {
        dispatch_semaphore_wait(_aFramesLock, DISPATCH_TIME_FOREVER);
        [_aframes removeAllObjects];
        dispatch_semaphore_signal(_aFramesLock);
    }
    _bufferedDuration = 0;
    _requestSeek = NO;
    _mediaSyncTime = 0;
    self.mediaPosition = _requestSeekPosition;
}

- (void)render {
    if (!self.playing) return;
    BOOL eof = _decoder.isEOF;
    BOOL noframes = ((_decoder.hasVideo && _vframes.count <= 0) ||
                     (_decoder.hasAudio && _aframes.count <= 0));
    
    // Check if reach the end and play all frames.
    if (noframes && eof) {
        [self pause];
        [_decoder seek:0.0];
        [[NSNotificationCenter defaultCenter] postNotificationName:DLGPlayerNotificationEOF object:self];
        return;
    }
    
    if (noframes && !_notifiedBufferStart) {
        _notifiedBufferStart = YES;
        NSDictionary *userInfo = @{ DLGPlayerNotificationBufferStateKey : @(_notifiedBufferStart) };
        [[NSNotificationCenter defaultCenter] postNotificationName:DLGPlayerNotificationBufferStateChanged object:self userInfo:userInfo];
    } else if (!noframes && _notifiedBufferStart) {
        _notifiedBufferStart = NO;
        NSDictionary *userInfo = @{ DLGPlayerNotificationBufferStateKey : @(_notifiedBufferStart) };
        [[NSNotificationCenter defaultCenter] postNotificationName:DLGPlayerNotificationBufferStateChanged object:self userInfo:userInfo];
    }
    
    // Render if has picture
    if (_decoder.hasPicture && _vframes.count > 0) {
        DLGPlayerVideoFrame *frame = _vframes[0];
        _view.contentSize = CGSizeMake(frame.width, frame.height);
        [_vframes removeObjectAtIndex:0];
        [_view render:frame];
    }
    
    // Check whether render is neccessary
    if (_vframes.count <= 0 || !_decoder.hasVideo) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self render];
        });
        return;
    }
    
    // Render video
    DLGPlayerVideoFrame *frame = nil;
    {
        long timeout = dispatch_semaphore_wait(_vFramesLock, DISPATCH_TIME_NOW);
        if (timeout == 0) {
            frame = _vframes[0];
            self.mediaPosition = frame.position;
            _bufferedDuration -= frame.duration;
            [_vframes removeObjectAtIndex:0];
            dispatch_semaphore_signal(_vFramesLock);
        }
    }
    [_view render:frame];
    
    // Sync audio with video
    double syncTime = [self syncTime];
    NSTimeInterval t = MAX(frame.duration + syncTime, 0.01);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self render];
    });
}

- (double)syncTime {
    const double now = [NSDate timeIntervalSinceReferenceDate];
    
    if (_mediaSyncTime == 0) {
        _mediaSyncTime = now;
        _mediaSyncPosition = self.mediaPosition;
        return 0;
    }
    
    double dp = self.mediaPosition - _mediaSyncPosition;
    double dt = now - _mediaSyncTime;
    double sync = dp - dt;
    
    if (sync > 1 || sync < -1) {
        sync = 0;
        _mediaSyncTime = 0;
    }
    
    return sync;
}

/*
 * For audioUnitRenderCallback, (DLGPlayerAudioManagerFrameReaderBlock)readFrameBlock
 */
- (void)readAudioFrame:(float *)data frames:(UInt32)frames channels:(UInt32)channels {
    if (!self.playing) return;
    while(frames > 0) {
        @autoreleasepool {
            if (_playingAudioFrame == nil) {
                {
                    if (_aframes.count <= 0) {
                        memset(data, 0, frames * channels * sizeof(float));
                        return;
                    }
                    
                    long timeout = dispatch_semaphore_wait(_aFramesLock, DISPATCH_TIME_NOW);
                    if (timeout == 0) {
                        DLGPlayerAudioFrame *frame = _aframes[0];
                        if (_decoder.hasVideo) {
                            const double dt = self.mediaPosition - frame.position;
                            if (dt < -0.1) { // audio is faster than video, silence
                                memset(data, 0, frames * channels * sizeof(float));
                                dispatch_semaphore_signal(_aFramesLock);
                                break;
                            } else if (dt > 0.1) { // audio is slower than video, skip
                                [_aframes removeObjectAtIndex:0];
                                dispatch_semaphore_signal(_aFramesLock);
                                continue;
                            } else {
                                self.playingAudioFrameDataPosition = 0;
                                self.playingAudioFrame = frame;
                                [_aframes removeObjectAtIndex:0];
                            }
                        } else {
                            self.playingAudioFrameDataPosition = 0;
                            self.playingAudioFrame = frame;
                            [_aframes removeObjectAtIndex:0];
                            self.mediaPosition = frame.position;
                            _bufferedDuration -= frame.duration;
                        }
                        dispatch_semaphore_signal(_aFramesLock);
                    } else return;
                }
            }
            
            NSData *frameData = _playingAudioFrame.data;
            NSUInteger pos = _playingAudioFrameDataPosition;
            if (frameData == nil) {
                memset(data, 0, frames * channels * sizeof(float));
                return;
            }
            
            const void *bytes = (Byte *)frameData.bytes + pos;
            const NSUInteger remainingBytes = frameData.length - pos;
            const NSUInteger channelSize = channels * sizeof(float);
            const NSUInteger bytesToCopy = MIN(frames * channelSize, remainingBytes);
            const NSUInteger framesToCopy = bytesToCopy / channelSize;
            
            memcpy(data, bytes, bytesToCopy);
            frames -= framesToCopy;
            data += framesToCopy * channels;
            
            if (bytesToCopy < remainingBytes) {
                _playingAudioFrameDataPosition += bytesToCopy;
            } else {
                self.playingAudioFrame = nil;
            }
        }
    }
}

- (UIView *)playerView {
    return _view;
}

- (void)setPosition:(double)position {
    _requestSeekPosition = position;
    _requestSeek = YES;
}

- (double)position {
    return _mediaPosition;
}

- (void)setMediaPosition:(double)mediaPosition {
    _mediaPosition = mediaPosition;
    if (self.onPositionChanged) {
        self.onPositionChanged(mediaPosition);
    }
}

#pragma mark - Handle Error
- (void)handleError:(NSError *)error {
    if (error == nil) return;
    NSDictionary *userInfo = @{ DLGPlayerNotificationErrorKey : error };
    [[NSNotificationCenter defaultCenter] postNotificationName:DLGPlayerNotificationError object:self userInfo:userInfo];
}


- (void)setBuffering:(BOOL)buffering {
    if (_buffering != buffering) {
        _buffering = buffering;
        if (self.onBufferingChanged) {
            self.onBufferingChanged(_buffering);
        }
    }
    
}

@end
