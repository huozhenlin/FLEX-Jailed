#import "XHSBridgeLogger.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

void XHSBridgeInstallCommandPolling(void);
void XHSBridgeInstallNetworkObservation(void);

__attribute__((constructor))
static void XHSBridgeInitialize(void) {
    @autoreleasepool {
        XHSBridgeStart();
        dispatch_async(dispatch_get_main_queue(), ^{
            XHSBridgeInstallCommandPolling();
            XHSBridgeInstallNetworkObservation();
        });
    }
}
