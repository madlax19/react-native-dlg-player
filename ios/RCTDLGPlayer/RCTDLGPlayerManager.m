//
//  RCTDLGPlayerManager.m
//  RCTDLGPlayer
//
//  Created by Elena Chekhova on 11/29/17.
//  Copyright © 2017 len. All rights reserved.
//

#import "RCTDLGPlayerManager.h"
#import "RCTDLGPlayer.h"

@implementation RCTDLGPlayerManager

RCT_EXPORT_MODULE();

- (UIView *)view {
    return [[RCTDLGPlayer alloc] init];
}

RCT_EXPORT_VIEW_PROPERTY(source, NSDictionary);
RCT_EXPORT_VIEW_PROPERTY(paused, BOOL);
RCT_EXPORT_VIEW_PROPERTY(seek, float);
RCT_EXPORT_VIEW_PROPERTY(rate, float);
RCT_EXPORT_VIEW_PROPERTY(volume, float);
RCT_EXPORT_VIEW_PROPERTY(snapshotPath, NSString);
RCT_EXPORT_VIEW_PROPERTY(onPaused, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onStopped, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onBuffering, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onPlaying, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onEnded, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onError, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onProgress, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onVolumeChanged, RCTDirectEventBlock);

@end
