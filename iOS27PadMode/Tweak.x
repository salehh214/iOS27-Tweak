#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#define kPadPrefsSuite @"com.elite.ios27"

static BOOL gPadCompactIcons = YES;

static BOOL PadBoolPref(NSString *key, BOOL defaultVal) {
    static NSUserDefaults *prefs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefs = [[NSUserDefaults alloc] initWithSuiteName:kPadPrefsSuite];
    });
    id val = [prefs objectForKey:key];
    return val ? [val boolValue] : defaultVal;
}

@interface SpringBoard : UIApplication
- (NSInteger)homeScreenRotationStyle;
- (BOOL)homeScreenSupportsRotation;
- (BOOL)homeScreenRotationStyleWantsUIKitRotation;
@end

@interface SBHomeScreenViewController : UIViewController
@end

@interface CCUIModularControlCenterOverlayViewController : UIViewController
@end

@interface SBIconView : UIView
- (void)setLabelHidden:(BOOL)hidden;
@end

// =========================================================================
// 1. iPhone SE (2016) Anti-Overlap Engine (No Labels + Smaller Spaced Icons)
// =========================================================================
static const void *kPadAppliedScaleKey = &kPadAppliedScaleKey;

%group PadSELayoutHooks

%hook SBIconView

- (void)setLabelHidden:(BOOL)hidden {
    %orig(YES);
}

- (void)layoutSubviews {
    %orig;

    @try {
        UIView *labelView = [self valueForKey:@"_labelView"];
        if ([labelView isKindOfClass:[UIView class]] && !labelView.hidden) {
            labelView.hidden = YES;
            labelView.alpha = 0.0;
        }
    } @catch (NSException *e) {}

    if (!gPadCompactIcons) return;

    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    BOOL isLandscape = (screenSize.width > screenSize.height);
    BOOL isWidget = (self.bounds.size.width > 95.0 || self.bounds.size.height > 95.0);

    CGFloat targetScale = 1.0;
    if (isWidget) {
        targetScale = isLandscape ? 0.80 : 0.92;
    } else {
        targetScale = isLandscape ? 0.74 : 0.84;
    }

    NSNumber *prevScale = objc_getAssociatedObject(self, kPadAppliedScaleKey);
    BOOL isOurTransform = (prevScale != nil) || CGAffineTransformIsIdentity(self.transform);

    if (isOurTransform && (!prevScale || fabs([prevScale doubleValue] - targetScale) > 0.005)) {
        self.transform = CGAffineTransformMakeScale(targetScale, targetScale);
        objc_setAssociatedObject(self, kPadAppliedScaleKey, @(targetScale), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

%end

// =========================================================================
// 2. GesturesXV-Compatible System Rotation (Style 2 + UIKit Rotation)
// =========================================================================
%group PadSystemRotationHooks

%hook SpringBoard

- (NSInteger)homeScreenRotationStyle {
    return 2; // UIKit bottom-dock rotation (Compatible with Gestures.x homeButtonType = 2)
}

- (BOOL)homeScreenSupportsRotation {
    return YES;
}

- (BOOL)homeScreenRotationStyleWantsUIKitRotation {
    return YES;
}

%end

%hook SBHomeScreenViewController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%hook CCUIModularControlCenterOverlayViewController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%end

// =========================================================================
// 3. Settings App (com.apple.Preferences) -> SE 2016 Mac/iPad Split View
// =========================================================================
%group PadSettingsAppHooks

%hook UIApplication

- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%hook UINavigationController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%hook UISplitViewController

- (void)viewDidLoad {
    %orig;
    if (@available(iOS 14.0, *)) {
        self.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    } else {
        self.preferredDisplayMode = UISplitViewControllerDisplayModeAllVisible;
    }
    self.preferredPrimaryColumnWidthFraction = 0.35;
    self.minimumPrimaryColumnWidth = 175.0;
    self.maximumPrimaryColumnWidth = 200.0;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (UITraitCollection *)traitCollection {
    UITraitCollection *orig = %orig;
    if (!orig) return orig;

    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    if (screenSize.width > screenSize.height) {
        UITraitCollection *regularW = [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassRegular];
        if (regularW) {
            return [UITraitCollection traitCollectionWithTraitsFromCollections:@[orig, regularW]];
        }
    }
    return orig;
}

%end

%end

// =========================================================================
// Constructor (Defaults to OFF on first install -> Guaranteed Clean Boot)
// =========================================================================
%ctor {
    if (!PadBoolPref(@"kEnabled", YES)) return;
    if (!PadBoolPref(@"kEnablePadMode", NO)) return;

    gPadCompactIcons = PadBoolPref(@"kPadCompactIcons", YES);

    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;

    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        %init(PadSELayoutHooks);
        if (PadBoolPref(@"kPadRotateSystem", YES)) {
            %init(PadSystemRotationHooks);
        }
    } else if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
        if (PadBoolPref(@"kPadSplitSettings", YES)) {
            %init(PadSettingsAppHooks);
        }
    }
}
