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
    IOUSBInterfaceInterface800** interface;
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
        device = [self detectDevice:error];
        if (device == NULL) {
            return nil;
        }
        if ([self openDevice:error] == NO) {
            return nil;
        }
        NSImage* image = [NSImage imageNamed:@"test"];
        if ([self drawImage:image screen:0 x:0 y:0 error:error] == NO) {
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
    Boolean success = 0;
    CFTypeRef cfNumber = IORegistryEntryCreateCFProperty(service, property, kCFAllocatorDefault, 0);
    if (cfNumber) {
        if (CFGetTypeID(cfNumber) == CFNumberGetTypeID()) {
            success = CFNumberGetValue(cfNumber, type, p);
        }
        CFRelease (cfNumber);
    }
    return (success != 0);
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
    IOReturn kresult = (*device)->CreateInterfaceIterator(device, &request, &interface_iterator);
    if (kresult != kIOReturnSuccess) {
        return kresult;
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

- (IOUSBDeviceInterface**)detectDevice:(NSError**)error
{
    // FIXME: offset wont be used on this level - lets see what else we need here...
    NSDictionary* supportedDevices = @{
        @(kPID_S25MK1): @{ @"keys": @(25), @"mk2": @NO, @"offset": @(-21) },
        @(kPID_S49MK1): @{ @"keys": @(49), @"mk2": @NO, @"offset": @(-36) },
        @(kPID_S61MK1): @{ @"keys": @(61), @"mk2": @NO, @"offset": @(-36) },
        @(kPID_S88MK1): @{ @"keys": @(88), @"mk2": @NO, @"offset": @(-21) },

        @(kPID_S49MK2): @{ @"keys": @(49), @"mk2": @YES, @"offset": @(-36) },
        @(kPID_S61MK2): @{ @"keys": @(61), @"mk2": @YES, @"offset": @(-36) },
        @(kPID_S88MK2): @{ @"keys": @(88), @"mk2": @YES, @"offset": @(-21) },
    };

    io_registry_entry_t entry = 0;

    entry = IORegistryGetRootEntry(kIOMasterPortDefault);
    if (entry == 0) {
        return nil;
    }

    kern_return_t ret;
    io_iterator_t iter = 0;

    ret = IORegistryEntryCreateIterator(entry, kIOUSBPlane, kIORegistryIterateRecursively, &iter);
    if (ret != KERN_SUCCESS || iter == 0) {
        return nil;
    }

    io_service_t service = 0;

    while ((service = IOIteratorNext(iter))) {
        IOCFPlugInInterface  **plug = NULL;
        IOUSBDeviceInterface **dev = NULL;
        io_string_t path;
        SInt32 score = 0;
        IOReturn ioret;

        ret = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plug, &score);
        IOObjectRelease(service);
        if (ret != KERN_SUCCESS || plug == NULL) {
            continue;
        }

        ioret = (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (void *)&dev);
        (*plug)->Release(plug);
        if (ioret != kIOReturnSuccess || dev == NULL) {
            continue;
        }

        if (IORegistryEntryGetPath(service, kIOServicePlane, path) != KERN_SUCCESS) {
            (*dev)->Release(dev);
            continue;
        }

        u_int16_t value = 0;
        if ((*dev)->GetDeviceVendor(dev, &value) != kIOReturnSuccess) {
            (*dev)->Release(dev);
            continue;
        }

        if (value != kVendorID_NativeInstruments) {
            (*dev)->Release(dev);
            continue;
        }

        if ((*dev)->GetDeviceProduct(dev, &value) != kIOReturnSuccess) {
            (*dev)->Release(dev);
            continue;
        }

        if ([supportedDevices objectForKey:@(value)] != nil) {
            _keyCount = [supportedDevices[@(value)][@"keys"] intValue];
            _mk2Controller = [supportedDevices[@(value)][@"mk2"] boolValue];
            _deviceName = [NSString stringWithFormat:@"Komplete Kontrol S%d MK%d", _keyCount, _mk2Controller ? 2 : 1];
            IOObjectRelease(iter);
            return dev;
        }

        (*dev)->Release(dev);
    }
    IOObjectRelease(iter);
    return nil;
}

- (BOOL)openDevice:(NSError**)error
{
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

+ (NSImage*)KKImageFromNSImage:(NSImage*)image
{
    // Reduce the color information to an NSImage that is 16bitRBG (no alpha).
    // This isnt it though -- pretty sure we need RGB565.
    // FIXME: Kill this conversion and do it by hand as suggested in this commented code.
    /*
       // RGB888 to RGB565 in a quick and dirty way.
       uint16_t r,g,b;
       uint16_t ret = ((r & 0xf8) << 8) | ((g & 0xfc) << 3) | ((b & 0xf8) >> 3);
    */
    NSImageRep* rep = [[image representations] objectAtIndex:0];
    const float width = rep.pixelsWide;
    const float height = rep.pixelsHigh;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 5, width * 2, colorSpace, kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(colorSpace);

    CGInterpolationQuality quality = kCGInterpolationHigh;
    CGContextSetInterpolationQuality(context, quality);

    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)[image TIFFRepresentation], NULL);
    CGImageRef srcImage =  CGImageSourceCreateImageAtIndex(source, 0, NULL);

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), srcImage);
    CGImageRelease(srcImage);
    CGImageRef dst = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

   return [[NSImage alloc] initWithCGImage:dst size:NSMakeSize(width, height)];
}

- (BOOL)drawImage:(NSImage*)image screen:(uint8_t)screen x:(unsigned int)x y:(unsigned int)y error:(NSError**)error
{
    NSImage* bitmap = [USBController KKImageFromNSImage:image];

    NSImageRep* rep = [[image representations] objectAtIndex:0];
    const float width = rep.pixelsWide;
    const float height = rep.pixelsHigh;

    NSMutableData* stream = [NSMutableData data];

    const unsigned char commandBlob1[] = { 0x84, 0x00, screen, 0x60, 0x00, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob1 length:sizeof(commandBlob1)];

    const uint16_t rect[] = { x, y, width, height };
    [stream appendBytes:&rect length:sizeof(rect)];

    const unsigned char commandBlob2[] = { 0x02, 0x00, 0x00, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob2 length:sizeof(commandBlob2)];
    
    CFDataRef raw = CGDataProviderCopyData(CGImageGetDataProvider([bitmap CGImageForProposedRect:NULL context:NULL hints:NULL]));

    // Pretty sure that hardware expects 32bit boundary data.
    size_t imageSize = [(__bridge NSData*)raw length];
    uint16_t imageLongs = (imageSize >> 2);
    
    assert(imageLongs == (width * height)/2);
    // FIXME(tillt): This may explode - watch your image sizes used for the transfer!
    //assert((imageLongs << 2) == imageSize);
    [stream appendBytes:&imageLongs length:sizeof(imageLongs)];
    [stream appendData:(__bridge NSData*)raw];

    const unsigned char commandBlob3[] = { 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00 };
    [stream appendBytes:commandBlob3 length:sizeof(commandBlob3)];

    assert([stream writeToFile: @"tmp/test.data" atomically:NO]);

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

@end
