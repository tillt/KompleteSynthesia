//
//  CoreAudioTools.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 27.12.23.
//

#import "CoreAudioTools.h"

#import <AudioToolbox/AudioServices.h>

@implementation CoreAudioTools

+ (AudioDeviceID)defaultOutputDeviceID
{
    AudioDeviceID outputDeviceID = kAudioObjectUnknown;

    // Get default output device.
    UInt32 propertySize = 0;
    OSStatus status = noErr;
    AudioObjectPropertyAddress propertyAOPA;
    propertyAOPA.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    propertyAOPA.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAOPA.mElement = kAudioObjectPropertyElementMaster;

    if (!AudioHardwareServiceHasProperty(kAudioObjectSystemObject, &propertyAOPA)) {
        NSLog(@"Cannot find default output device!");
        return outputDeviceID;
    }

    propertySize = sizeof(AudioDeviceID);

    status = AudioHardwareServiceGetPropertyData(kAudioObjectSystemObject, &propertyAOPA, 0, NULL, &propertySize,
                                                 &outputDeviceID);

    if (status) {
        NSLog(@"Cannot find default output device!");
    }
    return outputDeviceID;
}

+ (float)volume
{
    Float32 outputVolume;

    UInt32 propertySize = 0;
    OSStatus status = noErr;
    AudioObjectPropertyAddress propertyAOPA;
    propertyAOPA.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
    propertyAOPA.mScope = kAudioDevicePropertyScopeOutput;
    propertyAOPA.mElement = kAudioObjectPropertyElementMaster;

    AudioDeviceID outputDeviceID = [[self class] defaultOutputDeviceID];

    if (outputDeviceID == kAudioObjectUnknown) {
        NSLog(@"Unknown device");
        return 0.0;
    }

    if (!AudioHardwareServiceHasProperty(outputDeviceID, &propertyAOPA)) {
        NSLog(@"No volume returned for device 0x%0x", outputDeviceID);
        return 0.0;
    }

    propertySize = sizeof(Float32);

    status = AudioHardwareServiceGetPropertyData(outputDeviceID, &propertyAOPA, 0, NULL, &propertySize, &outputVolume);

    if (status) {
        NSLog(@"No volume returned for device 0x%0x", outputDeviceID);
        return 0.0;
    }

    if (outputVolume < 0.0 || outputVolume > 1.0) {
        return 0.0;
    }

    return outputVolume;
}

@end
