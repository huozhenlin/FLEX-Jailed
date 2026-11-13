#import "XHSBridgeLogger.h"

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL (*gOriginalHandleURL)(
    id, SEL, id, id, BOOL
);
static BOOL (*gOriginalHandleRouteURL)(
    id, SEL, id, id, BOOL
);
static BOOL (*gOriginalHandleActivity)(id, SEL, id);
static void (*gOriginalCheckLogin)(id, SEL, id);

static NSDictionary *XHSRouteURLSummary(id value) {
    NSURL *url = nil;
    if ([value isKindOfClass:NSURL.class]) {
        url = value;
    } else if ([value isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:value];
    }
    if (!url) {
        return @{
            @"argument_class": value
                ? NSStringFromClass(object_getClass(value)) ?: @""
                : @"<nil>"
        };
    }

    NSURLComponents *components = [
        NSURLComponents componentsWithURL:url
        resolvingAgainstBaseURL:NO
    ];
    NSMutableArray<NSString *> *queryNames = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if (item.name.length > 0 && ![queryNames containsObject:item.name]) {
            [queryNames addObject:item.name];
        }
    }
    return @{
        @"scheme": url.scheme ?: @"",
        @"host": url.host ?: @"",
        @"path": url.path ?: @"",
        @"query_names": queryNames
    };
}

static void XHSRouteEntry(
    NSString *selector,
    id url,
    id source,
    BOOL isCold
) {
    XHSBridgeLog(@"deeplink_route_entry", @{
        @"selector": selector ?: @"",
        @"url": XHSRouteURLSummary(url),
        @"source_class": source
            ? NSStringFromClass(object_getClass(source)) ?: @""
            : @"<nil>",
        @"is_cold": @(isCold)
    });
}

static BOOL XHSRouteHandleURL(
    id self,
    SEL selector,
    id url,
    id source,
    BOOL isCold
) {
    XHSRouteEntry(@"handleUrl:andSource:isCold:", url, source, isCold);
    BOOL result = gOriginalHandleURL
        ? gOriginalHandleURL(self, selector, url, source, isCold)
        : NO;
    XHSBridgeLog(@"deeplink_route_result", @{
        @"selector": @"handleUrl:andSource:isCold:",
        @"result": @(result)
    });
    return result;
}

static BOOL XHSRouteHandleRouteURL(
    id self,
    SEL selector,
    id url,
    id source,
    BOOL isCold
) {
    XHSRouteEntry(
        @"handleRouteURLIfNeeded:source:isCold:",
        url,
        source,
        isCold
    );
    BOOL result = gOriginalHandleRouteURL
        ? gOriginalHandleRouteURL(self, selector, url, source, isCold)
        : NO;
    XHSBridgeLog(@"deeplink_route_result", @{
        @"selector": @"handleRouteURLIfNeeded:source:isCold:",
        @"result": @(result)
    });
    return result;
}

static BOOL XHSRouteHandleActivity(id self, SEL selector, id activity) {
    XHSBridgeLog(@"deeplink_route_entry", @{
        @"selector": @"handleURLRouteWithActivity:",
        @"activity_class": activity
            ? NSStringFromClass(object_getClass(activity)) ?: @""
            : @"<nil>"
    });
    BOOL result = gOriginalHandleActivity
        ? gOriginalHandleActivity(self, selector, activity)
        : NO;
    XHSBridgeLog(@"deeplink_route_result", @{
        @"selector": @"handleURLRouteWithActivity:",
        @"result": @(result)
    });
    return result;
}

static void XHSRouteCheckLogin(id self, SEL selector, id value) {
    XHSBridgeLog(@"deeplink_login_check", @{
        @"selector": @"checkingLoginStatusToRouteUrlWith:",
        @"argument": XHSRouteURLSummary(value)
    });
    if (gOriginalCheckLogin) {
        gOriginalCheckLogin(self, selector, value);
    }
}

void XHSBridgeInstallRouteObservation(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"XYAppDelegateURLRouteHandler");
        if (!cls) {
            XHSBridgeLog(@"deeplink_route_hook_unavailable", @{
                @"reason": @"class_not_found"
            });
            return;
        }

        Method urlMethod = class_getInstanceMethod(
            cls, @selector(handleUrl:andSource:isCold:)
        );
        Method routeMethod = class_getInstanceMethod(
            cls, @selector(handleRouteURLIfNeeded:source:isCold:)
        );
        Method activityMethod = class_getInstanceMethod(
            cls, @selector(handleURLRouteWithActivity:)
        );
        Method loginMethod = class_getInstanceMethod(
            cls, @selector(checkingLoginStatusToRouteUrlWith:)
        );

        if (urlMethod) {
            gOriginalHandleURL = (BOOL (*)(id, SEL, id, id, BOOL))
                method_setImplementation(urlMethod, (IMP)XHSRouteHandleURL);
        }
        if (routeMethod) {
            gOriginalHandleRouteURL = (BOOL (*)(id, SEL, id, id, BOOL))
                method_setImplementation(
                    routeMethod,
                    (IMP)XHSRouteHandleRouteURL
                );
        }
        if (activityMethod) {
            gOriginalHandleActivity = (BOOL (*)(id, SEL, id))
                method_setImplementation(
                    activityMethod,
                    (IMP)XHSRouteHandleActivity
                );
        }
        if (loginMethod) {
            gOriginalCheckLogin = (void (*)(id, SEL, id))
                method_setImplementation(
                    loginMethod,
                    (IMP)XHSRouteCheckLogin
                );
        }

        XHSBridgeLog(@"deeplink_route_hook_installed", @{
            @"class": NSStringFromClass(cls) ?: @"",
            @"handle_url": @(urlMethod != NULL),
            @"handle_route_url": @(routeMethod != NULL),
            @"handle_activity": @(activityMethod != NULL),
            @"login_check": @(loginMethod != NULL)
        });
    });
}
