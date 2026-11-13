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
    NSURL *collector = XHSBridgeCollectorURL();
    if (collector.host.length > 0 &&
        [request.URL.host.lowercaseString
            isEqualToString:collector.host.lowercaseString] &&
        request.URL.port.integerValue == collector.port.integerValue) {
        // Keep both the FLEX bridge and the legacy NoteDetailMonitor command
        // poll alive. They use different marker headers but share the same
        // configured collector host.
        return YES;
    }
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
