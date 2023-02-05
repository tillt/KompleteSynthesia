//
//  ApplicationHelperFunction.h
//  KompleteSynthesia
//
//  Created by Till Toenshoff on 05.02.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ApplicationObserverDelegate <NSObject>
@end

@interface ApplicationObserver : NSObject
@property (nonatomic, weak) id<ApplicationObserverDelegate> delegate;

+ (BOOL)applicationIsRunning:(NSString*)name;
- (BOOL)terminateApplication:(NSString*)name completion:(void(^)(void))completion;
- (id)initWithDelegate:(id)delegate;
- (void)observeApplication:(NSString*)name;


@end

NS_ASSUME_NONNULL_END
