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
@end

@interface SBHomeScreenViewController : UIViewController
@end

@interface SBRootFolderController : UIViewController
@end

@interface SBMainSwitcherViewController : UIViewController
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
    %orig(YES); // Always hide app names so text never overlaps
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

    // Compact scaling for iPhone SE 2016 (320x568 / 568x320) -> clean spacing (waqfa) & zero overlap
    CGFloat targetScale = 1.0;
    if (isWidget) {
        targetScale = isLandscape ? 0.80 : 0.92;
    } else {
        targetScale = isLandscape ? 0.74 : 0.84;
    }

    NSNumber *prevScale = objc_getAssociatedObject(self, kPadAppliedScaleKey);
    BOOL isOurTransform = (prevScale != nil) || CGAffineTransformIsIdentity(self.transform);

    // Only apply when icon is not mid-drag or mid-app-launch zoom animation
    if (isOurTransform && (!prevScale || fabs([prevScale doubleValue] - targetScale) > 0.005)) {
        self.transform = CGAffineTransformMakeScale(targetScale, targetScale);
        objc_setAssociatedObject(self, kPadAppliedScaleKey, @(targetScale), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

%end

// =========================================================================
// 2. Crash-Free System Rotation (Home Screen, Control Center, App Switcher)
// =========================================================================
%group PadSystemRotationHooks

%hook SpringBoard

- (NSInteger)homeScreenRotationStyle {
    return 1; // Official iOS 15 Phone Landscape Rotation (Style 2 crashes without iPad FloatingDock)
}

- (BOOL)homeScreenSupportsRotation {
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

%hook SBRootFolderController

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

%hook SBMainSwitcherViewController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%end

// =========================================================================
// 3. Settings App (com.apple.Preferences) -> SE 2016 Landscape Split View
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
// Constructor (RAM-Cached, Zero Safe-Mode Crashes)
// =========================================================================
%ctor {
    if (!PadBoolPref(@"kEnabled", YES)) return;
    if (!PadBoolPref(@"kEnablePadMode", YES)) return;

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
