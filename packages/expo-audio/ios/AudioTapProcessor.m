// Copyright 2016-present 650 Industries. All rights reserved.

#import "AudioTapProcessor.h"
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct AVAudioTapProcessorContext {
  Boolean isNonInterleaved;
  Boolean supportedTapProcessingFormat;
  void *self;
} AVAudioTapProcessorContext;


@implementation AudioTapProcessor

- (instancetype)initWithPlayer:(AVPlayer *)player {
  self = [super init];
  if (self) {
    _player = player;
  }
  return self;
}

- (bool)installTap {
  if (![_player currentItem]) {
    return false;
  }
  
  AVAssetTrack *track = _player.currentItem.tracks.firstObject.assetTrack;
  if (!track) {
    return false;
  }
  
  AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
  if (audioMix) {
    AVMutableAudioMixInputParameters *audioMixInputParameters = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
    if (audioMixInputParameters) {
      MTAudioProcessingTapCallbacks callbacks;
      callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
      callbacks.clientInfo = (__bridge void *)self;
      callbacks.init = tapInit;
      callbacks.finalize = tapFinalize;
      callbacks.prepare = tapPrepare;
      callbacks.unprepare = tapUnprepare;
      callbacks.process = tapProcess;
      
      MTAudioProcessingTapRef audioProcessingTap;
      OSStatus status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &audioProcessingTap);
      if (status == noErr) {
        audioMixInputParameters.audioTapProcessor = audioProcessingTap;
        audioMix.inputParameters = @[audioMixInputParameters];
        [_player.currentItem setAudioMix:audioMix];
        CFRelease(audioProcessingTap);
      } else {
        return false;
      }
    }
  }
  return true;
}

- (void)uninstallTap {
  [_player.currentItem setAudioMix:nil];
}

#pragma mark - Audio Sample Buffer Callbacks (MTAudioProcessingTapCallbacks)

void tapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
  AVAudioTapProcessorContext *context = calloc(1, sizeof(AVAudioTapProcessorContext));
  context->isNonInterleaved = false;
  context->self = clientInfo;
  *tapStorageOut = context;
}

void tapFinalize(MTAudioProcessingTapRef tap) {
  AVAudioTapProcessorContext *context = (AVAudioTapProcessorContext *)MTAudioProcessingTapGetStorage(tap);
  context->self = NULL;
  free(context);
}

void tapPrepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *processingFormat) {
  AVAudioTapProcessorContext *context = (AVAudioTapProcessorContext *)MTAudioProcessingTapGetStorage(tap);
  context->supportedTapProcessingFormat = true;
  
  if (processingFormat->mFormatID != kAudioFormatLinearPCM) {
    NSLog(@"Audio Format ID for audioProcessingTap: LinearPCM");
  }
  
  if (!(processingFormat->mFormatFlags & kAudioFormatFlagIsFloat)) {
    NSLog(@"Audio Format ID for audioProcessingTap: Float only");
  }
  
  if (processingFormat->mFormatFlags & kAudioFormatFlagIsNonInterleaved) {
    context->isNonInterleaved = true;
  }
}

void tapUnprepare(MTAudioProcessingTapRef tap) {
  AVAudioTapProcessorContext *context = (AVAudioTapProcessorContext *)MTAudioProcessingTapGetStorage(tap);
  context->self = NULL;
}

void tapProcess(MTAudioProcessingTapRef tap, CMItemCount numberFrames, MTAudioProcessingTapFlags flags, AudioBufferList *bufferListInOut, CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut) {
  AVAudioTapProcessorContext *context = (AVAudioTapProcessorContext *)MTAudioProcessingTapGetStorage(tap);
  if (!context || !context->self) {
    NSLog(@"Audio Processing Tap storage or context is invalid!");
    return;
  }
  
  AudioTapProcessor *_self = (__bridge AudioTapProcessor *)context->self;
  if (!_self.sampleBufferCallback) {
    return;
  }
  
  OSStatus status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, NULL, numberFramesOut);
  if (status != noErr) {
    NSLog(@"MTAudioProcessingTapGetSourceAudio: %d", (int)status);
    return;
  }
  
  double seconds = CMTimeGetSeconds([_self->_player.currentItem currentTime]);
  _self.sampleBufferCallback(&bufferListInOut->mBuffers[0], numberFrames, seconds);
}


@end

NS_ASSUME_NONNULL_END
