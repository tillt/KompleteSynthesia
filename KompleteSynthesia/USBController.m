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

#import <Accelerate/Accelerate.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>

#import <AppKit/AppKit.h>

/*
killall -9 NIHardwareAgent
killall -9 NIHostIntegrationAgent
killall -9 NTKDaemon
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

- (id)initWithDelegate:(id)delegate error:(NSError**)error
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        if ([self detectDevice:error] == NULL) {
            return nil;
        }
        if ([self openDevice:error] == NO) {
            return nil;
        }
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
    NSLog(@"bulk transfer complete");
    if (result != kIOReturnSuccess) {
        NSLog(@"async transfer failed");
    }
}

- (BOOL)endpoint:(uint8_t)ep pipeRef:(uint8_t*)pipep
{
    for (int8_t i = 0 ; i < endpointCount; i++) {
        if (endpointAddresses[i] == ep) {
            *pipep = i + 1;
            NSLog(@"pipe %d matches", *pipep);
            return YES;
        }
    }
    NSLog(@"no pipeRef found with endpoint address 0x%02x", ep);
    return NO;
}

- (IOReturn)bulkWriteData:(NSData*)data endpoint:(int)endpointNumber
{
    uint8_t pipeRef;
    if ([self endpoint:endpointNumber pipeRef:&pipeRef] == NO) {
        NSLog(@"endpoint doesnt exist");
        return kIOReturnIOError;
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
        return ret;
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
    }
    
    return ret;
}

- (IOUSBDeviceInterface942**)detectDevice:(NSError**)error
{
    // FIXME: offset wont be used on this level - lets see what else we need here...
    NSDictionary* supportedDevices = @{
        @(kPID_S25MK1): @{ @"keys": @(25), @"mk2": @NO },
        @(kPID_S49MK1): @{ @"keys": @(49), @"mk2": @NO },
        @(kPID_S61MK1): @{ @"keys": @(61), @"mk2": @NO },
        @(kPID_S88MK1): @{ @"keys": @(88), @"mk2": @NO },

        @(kPID_S49MK2): @{ @"keys": @(49), @"mk2": @YES, @"width": @(480), @"height": @(272) },
        @(kPID_S61MK2): @{ @"keys": @(61), @"mk2": @YES, @"width": @(480), @"height": @(272) },
        @(kPID_S88MK2): @{ @"keys": @(88), @"mk2": @YES, @"width": @(480), @"height": @(272) },
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
            if (_mk2Controller == YES) {
                _screenSize = CGSizeMake([supportedDevices[@(valueWord)][@"width"] intValue],
                                         [supportedDevices[@(valueWord)][@"height"] intValue]);
                _screenCount = 2;
            }
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
    assert(device);
    assert(*device);
    IOReturn ret = (*device)->USBDeviceOpen(device);
    if (ret != kIOReturnSuccess) {
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

    return YES;
}

typedef struct {
    unsigned short width;
    unsigned short height;
    unsigned short* data;
} NIImage;

+ (void)NIImageFromNSImage:(NSImage*)source destination:(NIImage*)destination
{
    vImage_CGImageFormat RGBA8888Format =
    {
        .bitsPerComponent = 8,
        .bitsPerPixel = 32,
        .bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast,
        .colorSpace = NULL,
    };
    vImage_CGImageFormat RGB565Format =
    {
        .bitsPerComponent = 5,
        .bitsPerPixel = 16,
        .bitmapInfo = kCGBitmapByteOrder16Big | kCGImageAlphaNone,
        .colorSpace = RGBA8888Format.colorSpace,
    };

    NSImageRep* rep = [[source representations] objectAtIndex:0];
    destination->width = rep.pixelsWide;
    destination->height = rep.pixelsHigh;
    destination->data = malloc(destination->width * 2 * destination->height);

    destination->width = rep.pixelsWide;
    destination->height = rep.pixelsHigh;
    destination->data = malloc(destination->width * 2 * destination->height);

    CFDataRef raw = CGDataProviderCopyData(CGImageGetDataProvider([source CGImageForProposedRect:NULL context:NULL hints:NULL]));

    vImage_Error err = kvImageNoError;
    vImageConverterRef converter = vImageConverter_CreateWithCGImageFormat(&RGBA8888Format,
                                                                           &RGB565Format,
                                                                           NULL,
                                                                           kvImageNoFlags,
                                                                           &err);
    
    vImage_Buffer sourceBuffer = { (void*)CFDataGetBytePtr(raw), destination->height, destination->width, destination->width * 4 };
    vImage_Buffer destinationBuffer = { destination->data, destination->height, destination->width, destination->width * 2 };

    vImageConvert_AnyToAny(converter,
                           &sourceBuffer,
                           &destinationBuffer,
                           NULL,
                           kvImageNoFlags);
}

- (BOOL)drawNIImage:(NIImage*)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error
{
    NSMutableData* stream = [NSMutableData data];

    const unsigned char commandBlob1[] = { 0x84, 0x00, screen, 0x60, 0x00, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob1 length:sizeof(commandBlob1)];

    const uint16_t rect[] = { ntohs(x), ntohs(y), ntohs(image->width), ntohs(image->height) };
    [stream appendBytes:&rect length:sizeof(rect)];

    const unsigned char commandBlob2[] = { 0x02, 0x00, 0x00, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob2 length:sizeof(commandBlob2)];
    
    // Pretty sure that hardware expects 32bit boundary data.
    size_t imageSize = image->width * image->height * 2;
    uint16_t imageLongs = (imageSize >> 2);
    
    assert(imageLongs == (image->width * image->height)/2);
    // FIXME: This may explode - watch your image sizes used for the transfer!
    assert((imageLongs << 2) == imageSize);
    uint16_t writtenLongs = ntohs(imageLongs);
    [stream appendBytes:&writtenLongs length:sizeof(writtenLongs)];

    [stream appendBytes:image->data length:imageSize];

    const unsigned char commandBlob3[] = { 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob3 length:sizeof(commandBlob3)];

    IOReturn ret = [self bulkWriteData:stream endpoint:3];
    if (ret == kIOReturnSuccess) {
        NSLog(@"transferred image");
        return YES;
    }

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

- (BOOL)drawImage:(NSImage*)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error
{
    NIImage convertedImage;
    [USBController NIImageFromNSImage:image destination:&convertedImage];
    BOOL ret =  [self drawNIImage:&convertedImage screen:screen x:x y:y error:error];
    free(convertedImage.data);
    return ret;
}

- (BOOL)clearScreen:(uint8_t)screen error:(NSError**)error
{
    NIImage image = {
        _screenSize.width,
        _screenSize.height,
        calloc(_screenSize.width * _screenSize.height, 2)
    };
    BOOL ret = [self drawNIImage:&image screen:screen x:0 y:0 error:error];
    free(image.data);
    return ret;
}

@end
