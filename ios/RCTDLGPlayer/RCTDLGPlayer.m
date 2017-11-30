//
//  RCTDLGPlayer.m
//  RCTDLGPlayer
//
//  Created by Elena Chekhova on 11/29/17.
//  Copyright © 2017 len. All rights reserved.
//

#import "RCTDLGPlayer.h"
#import "DLGPlayer.h"
#import "React/RCTConvert.h"
#import "React/RCTBridgeModule.h"
#import "React/RCTEventDispatcher.h"
#import "UIView+React.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

@interface MPVolumeView()

@property (nonatomic, readonly) UISlider *volumeSlider;

@end

@implementation MPVolumeView (private_volume)

- (UISlider*)volumeSlider {
    for(id view in self.subviews) {
        if ([view isKindOfClass:[UISlider class]]) {
            UISlider *slider = (UISlider*)view;
            slider.continuous = NO;
            slider.value = AVAudioSession.sharedInstance.outputVolume;
            return slider;
        }
    }
    return nil;
}

@end


@interface RCTDLGPlayer()

@property (nonatomic) UISlider *volumeSlider;
@property (nonatomic, strong) DLGPlayer *player;

@end


@implementation RCTDLGPlayer

@synthesize volume = _volume;

- (id)init {
    if (self = [super init]) {
        _volume = -1.0;
        self.volumeSlider = [[[MPVolumeView alloc] init] volumeSlider];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(volumeChanged:)
                                                     name:@"AVSystemController_SystemVolumeDidChangeNotification"
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onPlayerError:)
                                                     name:DLGPlayerNotificationError
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onPlayerEnded:)
                                                     name:DLGPlayerNotificationEOF
                                                   object:nil];
        
    }
    return self;
}


- (void)applicationWillResignActive:(NSNotification *)notification {
    if (!_paused) {
        [self setPaused:_paused];
    }
}


- (void)applicationWillEnterForeground:(NSNotification *)notification {
    if(!_paused) {
        [self setPaused:NO];
    }
}


- (void)setPaused:(BOOL)paused {
    if (self.player) {
        if (paused) {
            [self.player pause];
            if (self.onPaused) {
                self.onPaused(@{ @"target": self.reactTag });
            }
        } else {
            [self.player play];
            if (self.onPlaying) {
                self.onPlaying(@{ @"target": self.reactTag,
                                  @"duration":[NSNumber numberWithInt:self.player.duration] });
            }
        }
        _paused = paused;
    }
}


- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    self.player.playerView.frame = bounds;
}


- (DLGPlayer*)player {
    if (!_player) {
        _player = [[DLGPlayer alloc] init];
        _player.playerView.frame = self.bounds;
        __weak RCTDLGPlayer *weakSelf = self;
        [_player setOnBufferingChanged:^(BOOL buffering) {
            if (self.onBuffering && buffering) {
                weakSelf.onBuffering(@{ @"target": weakSelf.reactTag });
            }
        }];
        [_player setOnPositionChanged:^(double position) {
            [weakSelf updateVideoProgress];
        }];
        [self addSubview:_player.playerView];
    }
    return _player;
}


- (void)setVolume:(float)volume {
    if ((_volume != volume)) {
        _volume = volume;
        self.volumeSlider.value = volume;
    }
}


- (float)volume {
    return self.volumeSlider.value;
}


- (void)volumeChanged:(NSNotification *)notification {
    float volume = [[[notification userInfo] objectForKey:@"AVSystemController_AudioVolumeNotificationParameter"] floatValue];
    if (_volume != volume) {
        _volume = volume;
        if (self.onVolumeChanged) {
            self.onVolumeChanged(@{@"volume": [NSNumber numberWithFloat: volume]});
        }
    }
}


- (void)onPlayerError:(NSNotification *)notification {
    if (self.onError) {
        self.onError(@{ @"target": self.reactTag });
    }
    [self _release];
}


- (void)onPlayerEnded:(NSNotification *)notification {
    if (self.onEnded) {
        self.onEnded(@{ @"target": self.reactTag });
    }
    if (self.onStopped) {
        self.onStopped(@{ @"target": self.reactTag });
    }
}


- (void)setSource:(NSDictionary *)source {
    NSString *uri = [source objectForKey:@"uri"];
    BOOL autoplay = [RCTConvert BOOL:[source objectForKey:@"autoplay"]];
    
    [self.player open:uri];
    [self setPaused:!autoplay];
}


- (void)updateVideoProgress {
    double currentTime   = ceil(self.player.position);
    double remainingTime = ceil(self.player.duration) - currentTime;
    double duration      = ceil(self.player.duration);
    double position = round(self.player.position) / round(self.player.duration);
    
    if( currentTime >= 0 && currentTime < duration) {
        if (self.onProgress) {
            self.onProgress(@{ @"target": self.reactTag,
                               @"currentTime": [NSNumber numberWithInt:currentTime],
                               @"remainingTime": [NSNumber numberWithInt:remainingTime],
                               @"duration":[NSNumber numberWithInt:duration],
                               @"position":[NSNumber numberWithFloat:position] });
        }
    }
}


- (void)setSeek:(float)pos {
    if(self.player.opened) {
        if(pos >= 0 && pos <= 1.0) {
            double position = self.player.duration * pos;
            [self.player setPosition:position];
        }
    }
}


- (void)_release {
    [self.player pause];
    [self.player close];
    self.player = nil;
}


#pragma mark - Lifecycle
- (void)removeFromSuperview {
    [self _release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super removeFromSuperview];
}

@end
