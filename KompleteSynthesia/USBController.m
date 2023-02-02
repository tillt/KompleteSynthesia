//
//  USBController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 15.01.23.
//

#import "USBController.h"

#import <Foundation/Foundation.h>

#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
/*
killall -9 NIHardwareAgent

killall -9 NIHostIntegrationAgent

killall -9 NTKDaemon

 
/Library/Application Support/Native Instruments/Hardware/NIHostIntegrationAgent.app/Contents/MacOS/NIHostIntegrationAgent
/Library/Application Support/Native Instruments/Hardware/NIHardwareAgent.app/Contents/MacOS/NIHardwareAgent
 
 */

const uint32_t kVendorID_NativeInstruments = 0x17CC;

// MK1 controllers.
const uint32_t kPID_S25MK1 = 0x1340;
const uint32_t kPID_S49MK1 = 0x1350;
const uint32_t kPID_S61MK1 = 0x1360;
const uint32_t kPID_S88MK1 = 0x1410;

// MK2 controllers.
const uint32_t kPID_S49MK2 = 0x1610;
const uint32_t kPID_S61MK2 = 0x1620;
const uint32_t kPID_S88MK2 = 0x1630;

@implementation USBController {
    IOUSBDeviceInterface942** device;
    IOUSBInterfaceInterface942** interface;
    uint8_t endpointCount;
    uint8_t endpointAddresses[32];
}

+ (NSString*)descriptionWithIOReturn:(IOReturn)err
{
    return [NSString stringWithCString:mach_error_string(err)
                              encoding:NSStringEncodingConversionAllowLossy];
}

- (id)initWithError:(NSError**)error
{
    self = [super init];
    if (self) {
        _connected = NO;
        if ([self detectDevice:error] == NULL) {
            return nil;
        }
        NSLog(@"detected %@ USB device", _deviceName);
        if ([self openDevice:error] == NO) {
            return nil;
        }
        NSLog(@"USB controller fully connected - up and running");
    }
    return self;
}

- (void)dealloc
{
    if (interface != NULL) {
        (*interface)->USBInterfaceClose(interface);
        (*interface)->Release(interface);
    }
    if (device != NULL) {
        (*device)->USBDeviceClose(device);
        (*device)->Release(device);
    }
}

- (NSString*)status
{
    return ((device != NULL) & (interface != NULL)) ? _deviceName : @"disconnected";
}

+ (BOOL)ioRegistryValueNumber:(io_service_t)service name:(CFStringRef)property type:(CFNumberType)type target:(void*)p
{
    BOOL success = NO;
    CFTypeRef cfNumber = IORegistryEntryCreateCFProperty(service, property, kCFAllocatorDefault, 0);
    if (cfNumber) {
        if (CFGetTypeID(cfNumber) == CFNumberGetTypeID()) {
            success = CFNumberGetValue(cfNumber, type, p) != 0;
        }
        CFRelease (cfNumber);
    }
    return success;
}

- (IOReturn)interface:(io_service_t*)usbInterfacep atIndex:(uint8_t)number
{
    *usbInterfacep = IO_OBJECT_NULL;

    IOUSBFindInterfaceRequest request;
    request.bInterfaceClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceSubClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
    request.bAlternateSetting = kIOUSBFindInterfaceDontCare;

    io_iterator_t interface_iterator;
    IOReturn ret = (*device)->CreateInterfaceIterator(device, &request, &interface_iterator);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    while ((*usbInterfacep = IOIteratorNext(interface_iterator))) {
        UInt8 bInterfaceNumber;
        BOOL ret = [USBController ioRegistryValueNumber:*usbInterfacep
                                                   name:CFSTR("bInterfaceNumber")
                                                   type:kCFNumberSInt8Type
                                                 target:&bInterfaceNumber];
        if (ret && bInterfaceNumber == number) {
            break;
        }
        IOObjectRelease(*usbInterfacep);
    }
    IOObjectRelease(interface_iterator);

    return kIOReturnSuccess;
}

- (IOReturn)endpoints
{
    IOReturn ret = (*interface)->GetNumEndpoints(interface, &endpointCount);
    if (ret != kIOReturnSuccess) {
        NSLog(@"GetNumEndpoints failed");
        return ret;
    }
    assert(endpointCount <= 32);

    for (int i = 1 ; i <= endpointCount ; i++) {
        UInt8 direction;
        UInt8 number;
        UInt8 dont_care1, dont_care3;
        UInt16 dont_care2;
        ret = (*interface)->GetPipeProperties(interface,
                                              i,
                                              &direction,
                                              &number,
                                              &dont_care1,
                                              &dont_care2,
                                              &dont_care3);
        if (ret != kIOReturnSuccess) {
            NSLog(@"GetPipeProperties failed");
            return ret;
        }
        endpointAddresses[i - 1] = (((kUSBIn == direction) << kUSBRqDirnShift) | (number & 0x0f));
        NSLog(@"pipe: %d, direction: %d, number: %d", i, endpointAddresses[i - 1] >> kUSBRqDirnShift, endpointAddresses[i - 1] & 0x0F);
    }
    return kIOReturnSuccess;
}

- (IOReturn)openDeviceInterface:(int)number
{
    io_service_t usbInterface = IO_OBJECT_NULL;

    IOReturn ret = [self interface:&usbInterface atIndex:number];
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    SInt32 score;
    IOCFPlugInInterface **pluginInterface = NULL;
    ret = IOCreatePlugInInterfaceForService(usbInterface,
                                            kIOUSBInterfaceUserClientTypeID,
                                            kIOCFPlugInInterfaceID,
                                            &pluginInterface,
                                            &score);
    IOObjectRelease(usbInterface);
    if (ret != kIOReturnSuccess) {
        NSLog(@"IOCreatePlugInInterfaceForService failed");
        return ret;
    }
    if (!pluginInterface) {
        NSLog(@"plugin interface not found");
        return kIOReturnIOError;
    }

    ret = (*pluginInterface)->QueryInterface(pluginInterface,
                                             CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                                             (LPVOID)&interface);
    (*pluginInterface)->Release(pluginInterface);
    if (ret != kIOReturnSuccess) {
        NSLog(@"pluginInterface->QueryInterface failed");
        return ret;
    }
    if (!interface) {
        NSLog(@"device interface not found");
        return kIOReturnIOError;
    }

    ret = (*interface)->USBInterfaceOpen(interface);
    if (ret != kIOReturnSuccess) {
        NSLog(@"USBInterfaceOpen failed");
        return ret;
    }

    CFRunLoopSourceRef compl_event_source;
    ret = (*interface)->CreateInterfaceAsyncEventSource(interface, &compl_event_source);
    if (ret != kIOReturnSuccess) {
        NSLog(@"CreateInterfaceAsyncEventSource failed");
        return ret;
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), compl_event_source, kCFRunLoopDefaultMode);

    NSLog(@"interface opened and async port setup");

    return ret;
}

static void asyncCallback (void *refcon, IOReturn result, void *arg0)
{
    //USBController* caller = (__bridge USBController*)refcon;
    //NSLog(@"bulk transfer complete");
    if (result != kIOReturnSuccess) {
        NSLog(@"async transfer failed");
    }
}

- (BOOL)endpoint:(uint8_t)ep pipeRef:(uint8_t*)pipep
{
    for (int8_t i = 0 ; i < endpointCount; i++) {
        if (endpointAddresses[i] == ep) {
            *pipep = i + 1;
            return YES;
        }
    }
    NSLog(@"no pipeRef found with endpoint address 0x%02x", ep);
    return NO;
}

- (BOOL)bulkWriteData:(NSData*)data endpoint:(int)endpointNumber error:(NSError**)error
{
    uint8_t pipeRef;
    if ([self endpoint:endpointNumber pipeRef:&pipeRef] == NO) {
        NSLog(@"endpoint doesnt exist");
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: @"USB Error: endpoint does not exist",
                NSLocalizedRecoverySuggestionErrorKey: @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:1 userInfo:userInfo];
        }
        return NO;
    }
    
    uint8_t transferType, direction, number, interval;
    uint16_t maxPacketSize;
    IOReturn ret = (*interface)->GetPipeProperties(interface,
                                                   pipeRef,
                                                   &direction,
                                                   &number,
                                                   &transferType,
                                                   &maxPacketSize,
                                                   &interval);
    if (ret != kIOReturnSuccess) {
        NSLog(@"GetPipeProperties failed");
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB Error: %@",
                                             [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }

    assert(transferType == kUSBBulk);
    assert(data.length % maxPacketSize);
    
    ret = (*interface)->WritePipeAsyncTO(interface,
                                         pipeRef,
                                         (void *)data.bytes,
                                         (UInt32)data.length,
                                         0,
                                         0,
                                         asyncCallback,
                                         (__bridge void *)self);
    if (ret != kIOReturnSuccess) {
        NSLog(@"(*interface)->WritePipeAsync failed");
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB Error: %@",
                                             [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }
    
    return YES;
}

- (IOUSBDeviceInterface942**)detectDevice:(NSError**)error
{
    // FIXME: offset wont be used on this level - lets see what else we need here...
    NSDictionary* supportedDevices = @{
        @(kPID_S25MK1): @{ @"keys": @(25), @"mk2": @NO },
        @(kPID_S49MK1): @{ @"keys": @(49), @"mk2": @NO },
        @(kPID_S61MK1): @{ @"keys": @(61), @"mk2": @NO },
        @(kPID_S88MK1): @{ @"keys": @(88), @"mk2": @NO },

        @(kPID_S49MK2): @{ @"keys": @(49), @"mk2": @YES },
        @(kPID_S61MK2): @{ @"keys": @(61), @"mk2": @YES },
        @(kPID_S88MK2): @{ @"keys": @(88), @"mk2": @YES },
    };

    io_registry_entry_t entry = 0;

    entry = IORegistryGetRootEntry(kIOMasterPortDefault);
    if (entry == 0) {
        return nil;
    }

    IOReturn ret;
    io_iterator_t iter = 0;

    ret = IORegistryEntryCreateIterator(entry, kIOUSBPlane, kIORegistryIterateRecursively, &iter);
    if (ret != KERN_SUCCESS || iter == 0) {
        return nil;
    }

    io_service_t service = 0;

    while ((service = IOIteratorNext(iter))) {
        IOCFPlugInInterface** plug = NULL;
        SInt32 score = 0;
        // Note that the `IOReturn` type is an alias for `kern_return_t` - we can use them
        // interchangeably for convenience reasons - may not be the best style though.
        //
        // This would fail if the user did not allow for this application to access
        // USB devices as requested via our entitlements.
        ret = IOCreatePlugInInterfaceForService(service,
                                                kIOUSBDeviceUserClientTypeID,
                                                kIOCFPlugInInterfaceID,
                                                &plug,
                                                &score);
        IOObjectRelease(service);
        
        if (ret != KERN_SUCCESS || plug == NULL) {
            NSLog(@"IOCreatePlugInInterfaceForService failed");
            if (error) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB Error: %@",
                                                 [USBController descriptionWithIOReturn:ret]],
                    NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
                };
                *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
            }
            continue;
        }

        IOUSBDeviceInterface942** dev = NULL;
        
        ret = (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942), (void *)&dev);
        (*plug)->Release(plug);
        if (ret != kIOReturnSuccess || dev == NULL) {
            NSLog(@"QueryInterface failed");
            continue;
        }

        unsigned short valueWord = 0;
        if ((*dev)->GetDeviceVendor(dev, &valueWord) != kIOReturnSuccess) {
            NSLog(@"GetDeviceVendor failed");
            (*dev)->Release(dev);
            continue;
        }

        if (valueWord != kVendorID_NativeInstruments) {
            (*dev)->Release(dev);
            continue;
        }

        if ((*dev)->GetDeviceProduct(dev, &valueWord) != kIOReturnSuccess) {
            NSLog(@"GetDeviceProduct failed");
            (*dev)->Release(dev);
            continue;
        }

        if ([supportedDevices objectForKey:@(valueWord)] != nil) {
            _keyCount = [supportedDevices[@(valueWord)][@"keys"] intValue];
            _mk2Controller = [supportedDevices[@(valueWord)][@"mk2"] boolValue];
            _deviceName = [NSString stringWithFormat:@"Komplete Kontrol S%d MK%d", _keyCount, _mk2Controller ? 2 : 1];
            IOObjectRelease(iter);
            device = dev;
            return dev;
        }
        (*dev)->Release(dev);
    }
    IOObjectRelease(iter);
    return nil;
}

- (BOOL)openDevice:(NSError**)error
{
    _connected = NO;

    assert(device);
    assert(*device);
    IOReturn ret = (*device)->USBDeviceOpen(device);
    if (ret != kIOReturnSuccess && ret != kIOReturnExclusiveAccess) {
        NSLog(@"USBDeviceOpen failed");
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB Error: %@",
                                             [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }
    
    IOUSBConfigurationDescriptorPtr desc = NULL;
    uint8_t config_index = 0;
    
    ret = (*device)->GetConfigurationDescriptorPtr(device, config_index, &desc);
    if (ret != kIOReturnSuccess) {
        NSLog(@"GetConfigurationDescriptorPtr failed");
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB Error: %@",
                                             [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }
    
    ret = [self openDeviceInterface:3];
    if (ret != kIOReturnSuccess) {
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB Error: %@",
                                             [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }

    ret = [self endpoints];
    if (ret != kIOReturnSuccess) {
        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB Error: %@",
                                             [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:ret userInfo:userInfo];
        }
        return NO;
    }
    
    _connected = YES;

    return YES;
}

@end
