#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void XHSBridgeStart(void);
void XHSBridgeLog(NSString *event, NSDictionary<NSString *, id> * _Nullable fields);
BOOL XHSBridgeIsCollectorRequest(NSURLRequest *request);
NSURL * _Nullable XHSBridgeCollectorURL(void);
NSString *XHSBridgeCollectorToken(void);

NS_ASSUME_NONNULL_END
