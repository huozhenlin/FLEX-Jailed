#import "XHSBridgeLogger.h"

#import <UIKit/UIKit.h>

static BOOL gRemoteBackArmed;
static BOOL gPolling;

static BOOL XHSBridgeIsVideoType(NSString *type) {
    return [[type lowercaseString] isEqualToString:@"video"];
}

static void XHSBridgeOpenNote(NSString *noteID, NSString *noteType) {
    if (noteID.length == 0) return;

    NSString *suffix = XHSBridgeIsVideoType(noteType)
        ? @"?type=video"
        : @"";
    NSString *value = [NSString stringWithFormat:
        @"xhsdiscover://item/%@%@", noteID, suffix];
    NSURL *url = [NSURL URLWithString:value];
    if (!url) return;

    gRemoteBackArmed = YES;
    XHSBridgeLog(@"xhs_deeplink_opened", @{
        @"note_id": noteID,
        @"note_type": noteType ?: @"",
        @"url": value
    });
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:nil];
}

static UIViewController *XHSBridgeVisibleController(
    UIViewController *controller
) {
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return XHSBridgeVisibleController(
            ((UINavigationController *)controller).topViewController
        );
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return XHSBridgeVisibleController(
            ((UITabBarController *)controller).selectedViewController
        );
    }
    return controller;
}

static void XHSBridgeGoBack(void) {
    if (!gRemoteBackArmed) return;
    gRemoteBackArmed = NO;

    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
            if (window) break;
        }
    }
    if (!window) return;

    UIViewController *visible =
        XHSBridgeVisibleController(window.rootViewController);
    UINavigationController *navigation = visible.navigationController;
    if (visible.presentingViewController) {
        [visible dismissViewControllerAnimated:YES completion:nil];
        XHSBridgeLog(@"xhs_back_executed", @{
            @"mode": @"dismiss",
            @"controller": NSStringFromClass(visible.class) ?: @""
        });
    } else if (navigation.viewControllers.count > 1 &&
               navigation.topViewController == visible) {
        [navigation popViewControllerAnimated:YES];
        XHSBridgeLog(@"xhs_back_executed", @{
            @"mode": @"pop",
            @"controller": NSStringFromClass(visible.class) ?: @""
        });
    }
}

static void XHSBridgePoll(void) {
    if (gPolling) return;
    gPolling = YES;

    NSURL *base = XHSBridgeCollectorURL();
    NSURLComponents *components = [
        NSURLComponents componentsWithURL:base
        resolvingAgainstBaseURL:NO
    ];
    components.path = @"/commands/next";
    components.query = nil;

    NSMutableURLRequest *request = [
        NSMutableURLRequest requestWithURL:components.URL
    ];
    request.HTTPMethod = @"GET";
    [request setValue:@"1" forHTTPHeaderField:@"X-XHS-FLEX-Bridge"];

    NSString *token = XHSBridgeCollectorToken();
    if (token.length > 0) {
        [request setValue:[@"Bearer " stringByAppendingString:token]
       forHTTPHeaderField:@"Authorization"];
    }

    NSURLSessionDataTask *task = [
        NSURLSession.sharedSession
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, __unused NSURLResponse *response,
                            __unused NSError *error) {
            gPolling = NO;
            NSDictionary *json = data.length > 0
                ? [NSJSONSerialization JSONObjectWithData:data
                                                   options:0
                                                     error:nil]
                : nil;
            NSDictionary *command = json[@"command"];
            if ([command isKindOfClass:NSDictionary.class]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *name = command[@"command"];
                    if ([name isEqualToString:@"open_note"]) {
                        XHSBridgeOpenNote(
                            command[@"note_id"],
                            command[@"note_type"]
                        );
                    } else if ([name isEqualToString:@"go_back"]) {
                        XHSBridgeGoBack();
                    }
                });
            }
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                dispatch_get_main_queue(),
                ^{ XHSBridgePoll(); }
            );
        }
    ];
    [task resume];
}

void XHSBridgeInstallCommandPolling(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        XHSBridgePoll();
    });
}
