#import "XHSBridgeLogger.h"

#import "FLEXNetworkObserver.h"
#import "FLEXNetworkRecorder.h"
#import "FLEXNetworkTransaction.h"
#import "XHSBridgePolicy.h"

#import <objc/runtime.h>

static BOOL XHSBridgeIsInterestingURL(NSURL *URL) {
    NSString *path = URL.path.lowercaseString ?: @"";
    if (![path containsString:@"/api/"]) return NO;
    for (NSString *term in @[
        @"note", @"feed", @"detail", @"image", @"video", @"widgets"
    ]) {
        if ([path containsString:term]) return YES;
    }
    return NO;
}

static id XHSBridgeJSONProjection(NSData *data) {
    if (data.length == 0) return nil;
    id JSON = [NSJSONSerialization JSONObjectWithData:data
                                               options:0
                                                 error:nil];
    if (!JSON) return nil;
    if ([JSON isKindOfClass:NSDictionary.class]) {
        NSArray *keys = [[(NSDictionary *)JSON allKeys]
            sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
                return [[left description] compare:[right description]];
            }];
        return @{
            @"type": @"dictionary",
            @"top_level_keys": keys
        };
    }
    if ([JSON isKindOfClass:NSArray.class]) {
        return @{
            @"type": @"array",
            @"count": @([(NSArray *)JSON count])
        };
    }
    return @{@"type": @"non_json"};
}

static void XHSBridgeForwardTransaction(
    FLEXHTTPTransaction *transaction,
    BOOL finished
) {
    NSURLRequest *request = transaction.request;
    if (!request || !XHSBridgeIsInterestingURL(request.URL)) return;

    NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithDictionary:@{
        @"request_id": transaction.requestID ?: @"",
        @"method": request.HTTPMethod ?: @"",
        @"url_scheme": request.URL.scheme ?: @"",
        @"url_host": request.URL.host ?: @"",
        @"url_path": request.URL.path ?: @"",
        @"request_body_length": @(transaction.cachedRequestBody.length),
        @"response_body_length": @(transaction.receivedDataLength),
        @"state": @(transaction.state),
        @"finished": @(finished),
        @"mechanism": transaction.requestMechanism ?: @"flex_network_recorder"
    }];

    id requestProjection =
        XHSBridgeJSONProjection(transaction.cachedRequestBody);
    if (requestProjection) fields[@"request_json"] = requestProjection;

    NSData *responseBody =
        [FLEXNetworkRecorder.defaultRecorder
            cachedResponseBodyForTransaction:transaction];
    id responseProjection = XHSBridgeJSONProjection(responseBody);
    if (responseProjection) fields[@"response_json"] = responseProjection;

    if ([transaction.response isKindOfClass:NSHTTPURLResponse.class]) {
        fields[@"http_code"] =
            @([(NSHTTPURLResponse *)transaction.response statusCode]);
    }
    if (transaction.error) {
        fields[@"error_domain"] = transaction.error.domain ?: @"";
        fields[@"error_code"] = @(transaction.error.code);
    }

    XHSBridgeLog(
        finished ? @"xhs_request_response" : @"xhs_request_started",
        fields
    );
}

void XHSBridgeInstallNetworkObservation(void) {
    // FLEX owns the URLSession/NSURLConnection observer. We only subscribe
    // to its recorder and forward filtered request/response summaries.
    FLEXNetworkObserver.enabled = YES;

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:
        kFLEXNetworkRecorderNewTransactionNotification
        object:FLEXNetworkRecorder.defaultRecorder
        queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            FLEXHTTPTransaction *transaction =
                notification.userInfo[
                    kFLEXNetworkRecorderUserInfoTransactionKey
                ];
            if ([transaction isKindOfClass:FLEXHTTPTransaction.class]) {
                XHSBridgeForwardTransaction(transaction, NO);
            }
        }];

    [center addObserverForName:
        kFLEXNetworkRecorderTransactionUpdatedNotification
        object:FLEXNetworkRecorder.defaultRecorder
        queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            FLEXHTTPTransaction *transaction =
                notification.userInfo[
                    kFLEXNetworkRecorderUserInfoTransactionKey
                ];
            if (![transaction isKindOfClass:FLEXHTTPTransaction.class]) {
                return;
            }
            BOOL finished =
                transaction.state == FLEXNetworkTransactionStateFinished ||
                transaction.state == FLEXNetworkTransactionStateFailed;
            if (finished) {
                XHSBridgeForwardTransaction(transaction, YES);
            }
        }];

    SEL resumeSelector = @selector(resume);
    SEL bridgeResumeSelector = @selector(xhsbridge_resume);
    Method resumeMethod =
        class_getInstanceMethod(NSURLSessionTask.class, resumeSelector);
    Method bridgeResumeMethod =
        class_getInstanceMethod(NSURLSessionTask.class, bridgeResumeSelector);
    if (resumeMethod && bridgeResumeMethod) {
        method_exchangeImplementations(resumeMethod, bridgeResumeMethod);
    }
}

@interface NSURLSessionTask (XHSBridgePolicy)
- (void)xhsbridge_resume;
@end

@implementation NSURLSessionTask (XHSBridgePolicy)

- (void)xhsbridge_resume {
    NSURLRequest *request = self.currentRequest ?: self.originalRequest;
    if (!XHSBridgeShouldAllowRequest(request)) {
        XHSBridgeLog(@"xhs_request_blocked", @{
            @"method": request.HTTPMethod ?: @"",
            @"url_scheme": request.URL.scheme ?: @"",
            @"url_host": request.URL.host ?: @"",
            @"url_path": request.URL.path ?: @"",
            @"reason": @"path_not_allowed"
        });
        [self cancel];
        return;
    }
    [self xhsbridge_resume];
}

@end
