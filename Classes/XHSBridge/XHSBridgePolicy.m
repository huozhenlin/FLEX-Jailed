#import "XHSBridgePolicy.h"

#import "XHSBridgeLogger.h"

static NSString *const XHSBridgeBlockingKey =
    @"XHSBridgeRequestBlockingEnabled";
static NSString *const XHSBridgePrefixesKey =
    @"XHSBridgeAllowedPathPrefixes";

BOOL XHSBridgeRequestBlockingEnabled(void) {
    return [NSUserDefaults.standardUserDefaults
        boolForKey:XHSBridgeBlockingKey];
}

NSString *XHSBridgeAllowedPathPrefixes(void) {
    return [NSUserDefaults.standardUserDefaults
        stringForKey:XHSBridgePrefixesKey] ?: @"";
}

void XHSBridgeSaveRequestPolicy(BOOL enabled, NSString *pathPrefixes) {
    [NSUserDefaults.standardUserDefaults setBool:enabled
                                           forKey:XHSBridgeBlockingKey];
    [NSUserDefaults.standardUserDefaults setObject:pathPrefixes ?: @""
                                            forKey:XHSBridgePrefixesKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

BOOL XHSBridgeShouldAllowRequest(NSURLRequest *request) {
    if (!request || XHSBridgeIsCollectorRequest(request)) return YES;
    if (!XHSBridgeRequestBlockingEnabled()) return YES;

    NSString *path = request.URL.path ?: @"";
    NSArray<NSString *> *prefixes =
        [XHSBridgeAllowedPathPrefixes() componentsSeparatedByString:@";"];
    BOOL hasPrefix = NO;
    for (NSString *rawPrefix in prefixes) {
        NSString *prefix = [rawPrefix
            stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (prefix.length == 0) continue;
        hasPrefix = YES;
        if ([path hasPrefix:prefix]) return YES;
    }

    // Enabled + no valid prefixes is intentionally fail-closed.
    return hasPrefix ? NO : NO;
}
