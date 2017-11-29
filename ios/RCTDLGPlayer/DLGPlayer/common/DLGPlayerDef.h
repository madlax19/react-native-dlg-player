//
//  DLGPlayerDef.h
//  DLGPlayer
//
//  Created by Liu Junqi on 05/12/2016.
//  Copyright © 2016 Liu Junqi. All rights reserved.
//

#ifndef DLGPlayerDef_h
#define DLGPlayerDef_h

#define DLGPlayerLocalizedStringTable   @"DLGPlayerStrings"

#define DLGPlayerMinBufferDuration  2
#define DLGPlayerMaxBufferDuration  5

#define DLGPlayerErrorDomainDecoder         @"DLGPlayerDecoder"
#define DLGPlayerErrorDomainAudioManager    @"DLGPlayerAudioManager"

#define DLGPlayerErrorCodeInvalidURL                        -1
#define DLGPlayerErrorCodeCannotOpenInput                   -2
#define DLGPlayerErrorCodeCannotFindStreamInfo              -3
#define DLGPlayerErrorCodeNoVideoAndAudioStream             -4

#define DLGPlayerErrorCodeNoAudioOuput                      -5
#define DLGPlayerErrorCodeNoAudioChannel                    -6
#define DLGPlayerErrorCodeNoAudioSampleRate                 -7
#define DLGPlayerErrorCodeNoAudioVolume                     -8
#define DLGPlayerErrorCodeCannotSetAudioCategory            -9
#define DLGPlayerErrorCodeCannotSetAudioActive              -10
#define DLGPlayerErrorCodeCannotInitAudioUnit               -11
#define DLGPlayerErrorCodeCannotCreateAudioComponent        -12
#define DLGPlayerErrorCodeCannotGetAudioStreamDescription   -13
#define DLGPlayerErrorCodeCannotSetAudioRenderCallback      -14
#define DLGPlayerErrorCodeCannotUninitAudioUnit             -15
#define DLGPlayerErrorCodeCannotDisposeAudioUnit            -16
#define DLGPlayerErrorCodeCannotDeactivateAudio             -17
#define DLGPlayerErrorCodeCannotStartAudioUnit              -18
#define DLGPlayerErrorCodeCannotStopAudioUnit               -19

#pragma mark - Notification
#define DLGPlayerNotificationOpened                 @"DLGPlayerNotificationOpened"
#define DLGPlayerNotificationClosed                 @"DLGPlayerNotificationClosed"
#define DLGPlayerNotificationEOF                    @"DLGPlayerNotificationEOF"
#define DLGPlayerNotificationBufferStateChanged     @"DLGPlayerNotificationBufferStateChanged"
#define DLGPlayerNotificationError                  @"DLGPlayerNotificationError"

#pragma mark - Notification Key
#define DLGPlayerNotificationBufferStateKey         @"DLGPlayerNotificationBufferStateKey"
#define DLGPlayerNotificationSeekStateKey           @"DLGPlayerNotificationSeekStateKey"
#define DLGPlayerNotificationErrorKey               @"DLGPlayerNotificationErrorKey"
#define DLGPlayerNotificationRawErrorKey            @"DLGPlayerNotificationRawErrorKey"


//strings
#define DLG_PLAYER_STRINGS_INVALID_URL @"Invalid URL"
#define DLG_PLAYER_STRINGS_CANNOT_OPEN_INPUT @"Cannot open input"
#define DLG_PLAYER_STRINGS_CANNOT_FIND_STREAM_INFO @"Cannot find stream info"
#define DLG_PLAYER_STRINGS_NO_VIDEO_AND_AUDIO_STREAM @"No video and audio streams"

#define DLG_PLAYER_STRINGS_NO_AUDIO_OUTPUT @"No audio output"
#define DLG_PLAYER_STRINGS_NO_AUDIO_CHANNEL @"No audio channel"
#define DLG_PLAYER_STRINGS_NO_AUDIO_SAMPLE_RATE @"No audio sample rate"
#define DLG_PLAYER_STRINGS_NO_AUDIO_VOLUME @"No audio volume"
#define DLG_PLAYER_STRINGS_CANNOT_SET_AUDIO_CATEGORY @"Cannot set audio category"
#define DLG_PLAYER_STRINGS_CANNOT_SET_AUDIO_ACTIVE @"Cannot set audio active"
#define DLG_PLAYER_STRINGS_CANNOT_INIT_AUDIO_UNIT @"Cannot initialize audio unit"
#define DLG_PLAYER_STRINGS_CANNOT_CREATE_AUDIO_UNIT @"Cannot create audio unit"
#define DLG_PLAYER_STRINGS_CANNOT_GET_AUDIO_STREAM_DESCRIPTION @"Cannot get audio stream description"
#define DLG_PLAYER_STRINGS_CANNOT_SET_AUDIO_RENDER_CALLBACK @"Cannot set audio render callback"
#define DLG_PLAYER_STRINGS_CANNOT_UNINIT_AUDIO_UNIT @"Cannot uninitialize audio unit"
#define DLG_PLAYER_STRINGS_CANNOT_DISPOSE_AUDIO_UNIT @"Cannot dispose audio unit"
#define DLG_PLAYER_STRINGS_CANNOT_DEACTIVATE_AUDIO @"Cannot deactivate audio"
#define DLG_PLAYER_STRINGS_CANNOT_START_AUDIO_UNIT @"Cannot start audio unit"
#define DLG_PLAYER_STRINGS_CANNOT_STOP_AUDIO_UNIT @"Cannot stop audio unit"

#endif /* DLGPlayerDef_h */
