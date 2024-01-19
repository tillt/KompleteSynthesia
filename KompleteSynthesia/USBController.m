//
//  USBController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 15.01.23.
//
#include <stdatomic.h>

#import "USBController.h"

#import <Foundation/Foundation.h>

#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>

#import "LogViewController.h"

/// Detects a Komplete Kontrol S-series USB controller. Supports USB bulk write for transmitting large amounts of data
/// as needed for graphics data transfer to the LCD screens.

const uint32_t kVendorID_NativeInstruments = 0x17CC;

// Bulk transfer interface specifications.
const uint32_t kUSBDeviceInterfaceMK2 = 0x03;
const uint32_t kUSBDeviceInterfaceEndpointMK2 = 0x03;

// FIXME: While this appears to be the interface and endpoint KompleteKontrol is using when
// FIXME: communicating with the controller, it also does nothing in my attempts so far.
const uint32_t kUSBDeviceInterfaceMK3 = 0x04;
const uint32_t kUSBDeviceInterfaceEndpointMK3 = 0x04;

@implementation USBController {
    IOUSBDeviceInterface942** device;
    IOUSBInterfaceInterface942** interface;
    uint8_t endpointCount;
    uint8_t endpointAddresses[32];
    dispatch_semaphore_t transfers;
    LogViewController* log;
}

+ (NSString*)descriptionWithIOReturn:(IOReturn)err
{
    return [NSString stringWithCString:mach_error_string(err) encoding:NSStringEncodingConversionAllowLossy];
}

- (id)initWithLogViewController:(LogViewController*)lc
{
    self = [super init];
    if (self) {
        _connected = NO;
        log = lc;
        transfers = dispatch_semaphore_create(0);
    }
    return self;
}

- (BOOL)setupWithError:(NSError**)error
{
    _connected = NO;
    if ([self detectDevice:error] == NULL) {
        return NO;
    }
    [log logLine:[NSString stringWithFormat:@"detected %@ USB device", _deviceName]];

    if ([self openDevice:error] == NO) {
        return NO;
    }
    NSLog(@"USB controller fully connected - up and running");
    return YES;
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

- (void)teardown
{
    // When our runloop is killed which happens on application termination, the async
    // callbacks wont get called anymore and thus the timeout may kick in here - make it
    // a safe value for being sure we can rely on the device status.
    [self waitForBulkTransfer:0.1];
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
        CFRelease(cfNumber);
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

- (IOReturn)gatherEndpoints
{
    IOReturn ret = (*interface)->GetNumEndpoints(interface, &endpointCount);
    if (ret != kIOReturnSuccess) {
        NSLog(@"GetNumEndpoints failed");
        return ret;
    }
    assert(endpointCount <= 32);

    for (int i = 1; i <= endpointCount; i++) {
        UInt8 direction;
        UInt8 number;
        UInt8 dont_care1, dont_care3;
        UInt16 dont_care2;
        ret = (*interface)->GetPipeProperties(interface, i, &direction, &number, &dont_care1, &dont_care2, &dont_care3);
        if (ret != kIOReturnSuccess) {
            NSLog(@"GetPipeProperties failed");
            return ret;
        }
        endpointAddresses[i - 1] = (((kUSBIn == direction) << kUSBRqDirnShift) | (number & 0x0f));
        NSLog(@"pipe: %d, direction: %d, number: %d", i, endpointAddresses[i - 1] >> kUSBRqDirnShift,
              endpointAddresses[i - 1] & 0x0F);
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
    IOCFPlugInInterface** pluginInterface = NULL;
    ret = IOCreatePlugInInterfaceForService(usbInterface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID,
                                            &pluginInterface, &score);
    IOObjectRelease(usbInterface);
    if (ret != kIOReturnSuccess) {
        NSLog(@"IOCreatePlugInInterfaceForService failed");
        return ret;
    }
    if (!pluginInterface) {
        NSLog(@"plugin interface not found");
        return kIOReturnIOError;
    }

    ret = (*pluginInterface)
              ->QueryInterface(pluginInterface, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID)&interface);
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

    CFRunLoopSourceRef eventSource;
    ret = (*interface)->CreateInterfaceAsyncEventSource(interface, &eventSource);
    if (ret != kIOReturnSuccess) {
        NSLog(@"CreateInterfaceAsyncEventSource failed");
        return ret;
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource, kCFRunLoopCommonModes);

    NSLog(@"interface opened and async port setup");

    return ret;
}

- (BOOL)endpoint:(uint8_t)ep pipeRef:(uint8_t*)pipep
{
    for (int8_t i = 0; i < endpointCount; i++) {
        if (endpointAddresses[i] == ep) {
            *pipep = i + 1;
            return YES;
        }
    }
    NSLog(@"no pipeRef found with endpoint address 0x%02x", ep);
    return NO;
}

static void asyncCallback(void* refcon, IOReturn result, void* arg0)
{
    dispatch_semaphore_t transfers = (__bridge dispatch_semaphore_t)refcon;
    dispatch_semaphore_signal(transfers);
    if (result != kIOReturnSuccess) {
        NSLog(@"async transfer failed");
    }
}

- (BOOL)bulkWriteData:(NSData*)data error:(NSError**)error
{
    assert(data.length > 0);

    // Get a pipe reference for the endpoint chosen.
    uint8_t pipeRef;
    if ([self endpoint:_deviceInterfaceEndpoint pipeRef:&pipeRef] == NO) {
        NSLog(@"endpoint doesnt exist");
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey : @"USB error: endpoint does not exist",
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:1
                                     userInfo:userInfo];
        }
        return NO;
    }

    // For additional footgun safety, get the properties of the pipe making sure it actually
    // does support bulk transfer and that the data to send fits into the max packet size.
    uint8_t transferType, direction, number, interval;
    uint16_t maxPacketSize;
    IOReturn ret =
        (*interface)
            ->GetPipeProperties(interface, pipeRef, &direction, &number, &transferType, &maxPacketSize, &interval);
    if (ret != kIOReturnSuccess) {
        NSLog(@"GetPipeProperties failed");
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB error when querying interface pipe: %@",
                                                                       [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:ret
                                     userInfo:userInfo];
        }
        return NO;
    }

    assert(transferType == kUSBBulk);
    assert(data.length % maxPacketSize);

    // Now send that data.
    ret = (*interface)
              ->WritePipeAsyncTO(interface, pipeRef, (void*)data.bytes, (UInt32)data.length, 0, 0, asyncCallback,
                                 (__bridge void*)transfers);
    if (ret != kIOReturnSuccess) {
        NSLog(@"(*interface)->WritePipeAsync failed");
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB error when writing to interface pipe: %@",
                                                                       [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:ret
                                     userInfo:userInfo];
        }
        return NO;
    }

    return YES;
}

- (IOUSBDeviceInterface942**)detectDevice:(NSError**)error
{
    NSDictionary* supportedDevices = @{
        @(kPID_S25MK1) : @{@"keys" : @(25), @"mk" : @(1)},
        @(kPID_S49MK1) : @{@"keys" : @(49), @"mk" : @(1)},
        @(kPID_S61MK1) : @{@"keys" : @(61), @"mk" : @(1)},
        @(kPID_S88MK1) : @{@"keys" : @(88), @"mk" : @(1)},

        @(kPID_S49MK2) : @{@"keys" : @(49), @"mk" : @(2)},
        @(kPID_S61MK2) : @{@"keys" : @(61), @"mk" : @(2)},
        @(kPID_S88MK2) : @{@"keys" : @(88), @"mk" : @(2)},

        @(kPID_S49MK3) : @{@"keys" : @(49), @"mk" : @(3)},
        @(kPID_S61MK3) : @{@"keys" : @(61), @"mk" : @(3)},
        @(kPID_S88MK3) : @{@"keys" : @(88), @"mk" : @(3)},
    };

    io_registry_entry_t entry = 0;

    // NOTE: macOS 10.15 (Catalina) does not know about `kIOMainPortDefault`. Doesnt really
    // make a difference as it is an alias to zero anyway.
    entry = IORegistryGetRootEntry(0);
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
        ret = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plug,
                                                &score);
        IOObjectRelease(service);

        if (ret != KERN_SUCCESS || plug == NULL) {
            NSLog(@"IOCreatePlugInInterfaceForService failed");
            continue;
        }

        IOUSBDeviceInterface942** dev = NULL;

        ret = (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942), (void*)&dev);
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
            _mk = [supportedDevices[@(valueWord)][@"mk"] intValue];
            _deviceName = [NSString stringWithFormat:@"Komplete Kontrol S%d MK%d", _keyCount, _mk];
            IOObjectRelease(iter);
            device = dev;
            return dev;
        }
        (*dev)->Release(dev);
    }
    IOObjectRelease(iter);

    NSLog(@"No Native Instruments keyboard controller USB device detected");
    if (error != nil) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey : @"No Native Instruments USB controller detected",
            NSLocalizedRecoverySuggestionErrorKey : @"Make sure the keyboard is connected and powered on."
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                     code:-1
                                 userInfo:userInfo];
    }

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
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"USB error when trying to open the device: %@",
                                                                       [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:ret
                                     userInfo:userInfo];
        }
        return NO;
    }

    _deviceInterfaceEndpoint = _mk == 2 ? kUSBDeviceInterfaceEndpointMK2 : kUSBDeviceInterfaceEndpointMK3;

    ret = [self openDeviceInterface:_mk == 2 ? kUSBDeviceInterfaceMK2 : kUSBDeviceInterfaceMK3];
    if (ret != kIOReturnSuccess) {
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey :
                    [NSString stringWithFormat:@"USB error when trying to open the device interface: %@",
                                               [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:ret
                                     userInfo:userInfo];
        }
        return NO;
    }

    ret = [self gatherEndpoints];
    if (ret != kIOReturnSuccess) {
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey :
                    [NSString stringWithFormat:@"USB error: %@", [USBController descriptionWithIOReturn:ret]],
                NSLocalizedRecoverySuggestionErrorKey : @"This is entirely unexpected - how did you get here?"
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:ret
                                     userInfo:userInfo];
        }
        return NO;
    }

    _connected = YES;

    return YES;
}

- (BOOL)waitForBulkTransfer:(NSTimeInterval)timeout
{
    return dispatch_semaphore_wait(transfers, dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC)) == 0;
}

@end
