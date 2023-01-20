//
//  USBController.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 15.01.23.
//

#import "USBController.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>

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
    IOUSBDeviceInterface** device;
}

- (id)initWithDelegate:(id)delegate error:(NSError**)error
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        device = [self detectKeyboardController:error];
        if (device == NULL) {
            return nil;
        }
        if ([self initKeyboardController:error] == NO) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    if (device != NULL) {
        (*device)->Release(device);
    }
}

static bool get_ioregistry_value_number (io_service_t service, CFStringRef property, CFNumberType type, void *p) {
  CFTypeRef cfNumber = IORegistryEntryCreateCFProperty (service, property, kCFAllocatorDefault, 0);
  Boolean success = 0;

  if (cfNumber) {
    if (CFGetTypeID(cfNumber) == CFNumberGetTypeID()) {
      success = CFNumberGetValue(cfNumber, type, p);
    }

    CFRelease (cfNumber);
  }

  return (success != 0);
}

- (IOReturn)interface:(uint8_t)ifc interface:(io_service_t*)usbInterfacep
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
        BOOL ret = get_ioregistry_value_number (*usbInterfacep,
                                                CFSTR("bInterfaceNumber"),
                                                kCFNumberSInt8Type,
                                                &bInterfaceNumber);
        if (ret && bInterfaceNumber == ifc) {
            break;
        }
        IOObjectRelease(*usbInterfacep);
    }
    IOObjectRelease(interface_iterator);
    return kIOReturnSuccess;
}

- (BOOL)initKeyboardController:(NSError**)error
{
    IOReturn ret = (*device)->USBDeviceOpenSeize(device);
    if (ret != kIOReturnSuccess) {
        return NO;
    }
    
    IOUSBConfigurationDescriptorPtr desc;
    uint8_t config_index = 1;
    
    ret = (*device)->GetConfigurationDescriptorPtr(device, config_index, &desc);
    if (ret != kIOReturnSuccess) {
        return NO;
    }
    
    io_service_t service;
    ret = [self interface:1 interface:&service];
    if (ret != kIOReturnSuccess) {
        return NO;
    }

    return YES;
}

- (IOUSBDeviceInterface**)detectKeyboardController:(NSError**)error
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

    io_registry_entry_t entry   = 0;
    io_iterator_t       iter    = 0;
    io_service_t        service = 0;
    kern_return_t       kret;

    entry = IORegistryGetRootEntry(kIOMasterPortDefault);
    if (entry == 0) {
        return nil;
    }

    kret = IORegistryEntryCreateIterator(entry, kIOUSBPlane, kIORegistryIterateRecursively, &iter);
    if (kret != KERN_SUCCESS || iter == 0) {
        return nil;
    }

    while ((service = IOIteratorNext(iter))) {
        IOCFPlugInInterface  **plug  = NULL;
        IOUSBDeviceInterface **dev   = NULL;
        io_string_t path;
        SInt32 score = 0;
        IOReturn ioret;

        kret = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plug, &score);
        IOObjectRelease(service);
        if (kret != KERN_SUCCESS || plug == NULL) {
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
        
        for (NSNumber* key in [supportedDevices allKeys]) {
            if (value != key.intValue) {
                continue;
            }
            _keyCount = [supportedDevices[key][@"keys"] intValue];
            _mk2Controller = [supportedDevices[key][@"mk2"] boolValue];
            _deviceName = [NSString stringWithFormat:@"Komplete Kontrol S%d MK%d", _keyCount, _mk2Controller ? 2 : 1];
            return dev;
        }
        (*dev)->Release(dev);
    }
    IOObjectRelease(iter);
    return nil;
}

@end
