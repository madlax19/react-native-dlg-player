//
//  RCTDLGPlayer.h
//  RCTDLGPlayer
//
//  Created by Elena Chekhova on 11/29/17.
//  Copyright © 2017 len. All rights reserved.
//

#import "React/RCTView.h"

@interface RCTDLGPlayer : UIView

@property (nonatomic) BOOL paused;
@property (nonatomic) float volume;

@property (nonatomic, copy) RCTDirectEventBlock onPaused;
@property (nonatomic, copy) RCTDirectEventBlock onStopped;
@property (nonatomic, copy) RCTDirectEventBlock onBuffering;
@property (nonatomic, copy) RCTDirectEventBlock onPlaying;
@property (nonatomic, copy) RCTDirectEventBlock onEnded;
@property (nonatomic, copy) RCTDirectEventBlock onError;
@property (nonatomic, copy) RCTDirectEventBlock onProgress;
@property (nonatomic, copy) RCTDirectEventBlock onVolumeChanged;

@end
