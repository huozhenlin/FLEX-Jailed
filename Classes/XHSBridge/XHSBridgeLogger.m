#import "XHSBridgeLogger.h"

#import <os/log.h>

static NSString *const XHSBridgeDefaultCollector =
    @"http://172.18.177.3:8901/events";
static NSString *const XHSBridgeMarker = @"X-XHS-FLEX-Bridge";
static NSString *const XHSBridgeEndpointKey = @"XRBCollectorEndpoint";
static NSString *const XHSBridgeTokenKey = @"XRBCollectorToken";
static NSUInteger const XHSBridgeMaxEventBytes = 512 * 1024;

static os_log_t XHSBridgeLogHandle(void) {
    static os_log_t handle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = os_log_create("com.xhs.flexbridge", "network");
    });
    return handle;
}

static BOOL XHSBridgeSensitiveKey(NSString *key) {
    NSString *normalized = [[key lowercaseString]
        stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    for (NSString *suffix in @[
        @"authorization", @"cookie", @"set_cookie", @"token",
        @"secret", @"password", @"session", @"sid", @"did",
        @"device_id", @"xsec_token", @"api_key"
    ]) {
        if ([normalized isEqualToString:suffix] ||
            [normalized hasSuffix:[@"_" stringByAppendingString:suffix]]) {
            return YES;
        }
    }
    return NO;
}

static id XHSBridgeSanitize(id value) {
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:
            ^(id key, id child, BOOL *stop) {
                (void)stop;
                NSString *name = [key description] ?: @"unknown";
                result[name] = XHSBridgeSensitiveKey(name)
                    ? @"<redacted>"
                    : XHSBridgeSanitize(child);
            }];
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id child in (NSArray *)value) {
            [result addObject:XHSBridgeSanitize(child) ?: [NSNull null]];
        }
        return result;
    }
    if ([value isKindOfClass:NSString.class] ||
        [value isKindOfClass:NSNumber.class] ||
        [value isKindOfClass:NSNull.class]) {
        return value;
    }
    if ([value isKindOfClass:NSURL.class]) {
        return [(NSURL *)value absoluteString] ?: @"";
    }
    NSString *description = [value description] ?: @"";
    return description.length > 1024
        ? [description substringToIndex:1024]
        : description;
}

static NSURL *XHSBridgeConfiguredURL(void) {
    NSString *value = [NSUserDefaults.standardUserDefaults
        stringForKey:XHSBridgeEndpointKey];
    if (value.length == 0) value = XHSBridgeDefaultCollector;
    if (![value containsString:@"://"]) {
        value = [@"http://" stringByAppendingString:value];
    }
    NSURL *url = [NSURL URLWithString:value];
    if (url.path.length == 0) {
        url = [NSURL URLWithString:
            [value stringByAppendingString:@"/events"]];
    }
    return url;
}

void XHSBridgeStart(void) {
    os_log_info(XHSBridgeLogHandle(), "XHS FLEX bridge started");
}

NSURL *XHSBridgeCollectorURL(void) {
    return XHSBridgeConfiguredURL();
}

NSString *XHSBridgeCollectorToken(void) {
    return [NSUserDefaults.standardUserDefaults
        stringForKey:XHSBridgeTokenKey] ?: @"";
}

BOOL XHSBridgeIsCollectorRequest(NSURLRequest *request) {
    return [[request valueForHTTPHeaderField:XHSBridgeMarker]
        isEqualToString:@"1"];
}

void XHSBridgeLog(NSString *event, NSDictionary<NSString *, id> *fields) {
    if (event.length == 0) return;

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"event"] = event;
    payload[@"time"] =
        @((long long)(NSDate.date.timeIntervalSince1970 * 1000.0));
    payload[@"pid"] = @(NSProcessInfo.processInfo.processIdentifier);
    payload[@"bundle_id"] =
        NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
    if (fields.count > 0) {
        [payload addEntriesFromDictionary:fields];
    }

    NSDictionary *safePayload = XHSBridgeSanitize(payload);
    NSError *serializationError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:safePayload
                                                    options:0
                                                      error:&serializationError];
    if (serializationError || body.length == 0 ||
        body.length > XHSBridgeMaxEventBytes) {
        return;
    }

    NSURL *endpoint = XHSBridgeCollectorURL();
    if (!endpoint) return;

    NSMutableURLRequest *request = [
        NSMutableURLRequest requestWithURL:endpoint
    ];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:@"application/json"
   forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"1" forHTTPHeaderField:XHSBridgeMarker];

    NSString *token = XHSBridgeCollectorToken();
    if (token.length > 0) {
        [request setValue:[@"Bearer " stringByAppendingString:token]
       forHTTPHeaderField:@"Authorization"];
    }

    NSURLSessionDataTask *task =
        [NSURLSession.sharedSession dataTaskWithRequest:request];
    [task resume];
}
