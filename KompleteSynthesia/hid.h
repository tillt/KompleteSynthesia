//
//  hid.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 29.12.22.
//

#ifndef hid_h
#define hid_h

#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/IOKitLib.h>

int getProductID(IOHIDDeviceRef device);
int getVendorID(IOHIDDeviceRef device);
char* getIOReturnString(IOReturn ioReturn);

#endif /* hid_h */
