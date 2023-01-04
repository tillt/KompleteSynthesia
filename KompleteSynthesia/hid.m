//
//  hid.m
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 29.12.22.
//
//  Original source is:
//  https://github.com/donniebreve/touchcursor-mac/blob/02f35660bbc6dd1e365f2485577cfb19a7b51fb0/src/hidInformation.c

#import <Foundation/Foundation.h>
#import "hid.h"

/**
 * Gets an int from the given HID reference.
 */
static int32_t getIntProperty(IOHIDDeviceRef device, CFStringRef property)
{
    CFTypeRef typeReference = IOHIDDeviceGetProperty(device, property);
    if (typeReference) {
        if (CFGetTypeID(typeReference) == CFNumberGetTypeID()) {
            int32_t value;
            CFNumberGetValue((CFNumberRef)typeReference, kCFNumberSInt32Type, &value);
            return value;
        }
    }
    return 0;
}

/**
 * Gets the Product ID from the given HID reference.
 */
int getProductID(IOHIDDeviceRef device)
{
    return getIntProperty(device, CFSTR(kIOHIDProductIDKey));
}

/**
 * Gets the Vendor ID from the given HID reference.
 */
int getVendorID(IOHIDDeviceRef device)
{
    return getIntProperty(device, CFSTR(kIOHIDVendorIDKey));
}

/**
 * Prints the return string.
 */
char* getIOReturnString(IOReturn ioReturn)
{
    switch (ioReturn)
    {
        case kIOReturnSuccess         : return "Success";
        case kIOReturnError           : return "General error";
        case kIOReturnNoMemory        : return "Can't allocate memory";
        case kIOReturnNoResources     : return "Resource shortage";
        case kIOReturnIPCError        : return "Error during IPC";
        case kIOReturnNoDevice        : return "No such device";
        case kIOReturnNotPrivileged   : return "Privilege violation";
        case kIOReturnBadArgument     : return "Invalid argument";
        case kIOReturnLockedRead      : return "Device read locked";
        case kIOReturnLockedWrite     : return "Device write locked";
        case kIOReturnExclusiveAccess : return "Exclusive access and device already open";
        case kIOReturnBadMessageID    : return "Sent/received messages had different msg_id";
        case kIOReturnUnsupported     : return "Unsupported function";
        case kIOReturnVMError         : return "Miscellaneous VM failure";
        case kIOReturnInternalError   : return "Internal error";
        case kIOReturnIOError         : return "General I/O error";
        case kIOReturnCannotLock      : return "Can't acquire lock";
        case kIOReturnNotOpen         : return "Device not open";
        case kIOReturnNotReadable     : return "Read not supported";
        case kIOReturnNotWritable     : return "Write not supported";
        case kIOReturnNotAligned      : return "Alignment error";
        case kIOReturnBadMedia        : return "Media Error";
        case kIOReturnStillOpen       : return "Device(s) still open";
        case kIOReturnRLDError        : return "RLD failure";
        case kIOReturnDMAError        : return "DMA failure";
        case kIOReturnBusy            : return "Device Busy";
        case kIOReturnTimeout         : return "I/O Timeout";
        case kIOReturnOffline         : return "Device offline";
        case kIOReturnNotReady        : return "Not ready";
        case kIOReturnNotAttached     : return "Device not attached";
        case kIOReturnNoChannels      : return "No DMA channels left";
        case kIOReturnNoSpace         : return "No space for data";
        case kIOReturnPortExists      : return "Port already exists";
        case kIOReturnCannotWire      : return "Can't wire down physical memory";
        case kIOReturnNoInterrupt     : return "No interrupt attached";
        case kIOReturnNoFrames        : return "No DMA frames enqueued";
        case kIOReturnMessageTooLarge : return "Oversized msg received on interrupt port";
        case kIOReturnNotPermitted    : return "Not permitted";
        case kIOReturnNoPower         : return "No power to device";
        case kIOReturnNoMedia         : return "Media not present";
        case kIOReturnUnformattedMedia: return "Media not formatted";
        case kIOReturnUnsupportedMode : return "No such mode";
        case kIOReturnUnderrun        : return "Data underrun";
        case kIOReturnOverrun         : return "Data overrun";
        case kIOReturnDeviceError     : return "The device is not working properly!";
        case kIOReturnNoCompletion    : return "A completion routine is required";
        case kIOReturnAborted         : return "Operation aborted";
        case kIOReturnNoBandwidth     : return "Bus bandwidth would be exceeded";
        case kIOReturnNotResponding   : return "Device not responding";
        case kIOReturnIsoTooOld       : return "Isochronous I/O request for distant past!";
        case kIOReturnIsoTooNew       : return "Isochronous I/O request for distant future";
        case kIOReturnNotFound        : return "Data was not found";
        case kIOReturnInvalid         : return "Should never be seen";
    }
    return "Unknown";
}
