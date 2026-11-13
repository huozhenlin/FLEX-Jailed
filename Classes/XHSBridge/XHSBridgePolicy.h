#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL XHSBridgeRequestBlockingEnabled(void);
void XHSBridgeSaveRequestPolicy(BOOL enabled, NSString *pathPrefixes);
NSString *XHSBridgeAllowedPathPrefixes(void);
BOOL XHSBridgeShouldAllowRequest(NSURLRequest *request);

NS_ASSUME_NONNULL_END
