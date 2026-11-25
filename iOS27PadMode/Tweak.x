#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#define kPadPrefsSuite @"com.elite.ios27"
#define kPadBootGuardKey @"kPadBootInProgress"

static BOOL gPadCompactIcons = YES;

static NSUserDefaults *PadPrefs(void) {
    static NSUserDefaults *prefs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefs = [[NSUserDefaults alloc] initWithSuiteName:kPadPrefsSuite];
    });
    return prefs;
}

static BOOL PadBoolPref(NSString *key, BOOL defaultVal) {
    id val = [PadPrefs() objectForKey:key];
    return val ? [val boolValue] : defaultVal;
}

@interface SpringBoard : UIApplication
- (BOOL)homeScreenSupportsRotation;
@end

@interface SBHomeScreenViewController : UIViewController
@end

@interface SBRootFolderController : UIViewController
@end

@interface SBIconController : UIViewController
@end

@interface CSCoverSheetViewController : UIViewController
@end

@interface CCUIModularControlCenterOverlayViewController : UIViewController
@end

@interface SBMainSwitcherViewController : UIViewController
@end

@interface SBIconView : UIView
- (void)setLabelHidden:(BOOL)hidden;
@end

// =========================================================================
// 1. iPhone SE (2016) Anti-Overlap Engine (No Labels + Exact Landscape Fit)
// =========================================================================
static const void *kPadAppliedScaleKey = &kPadAppliedScaleKey;

%group PadSELayoutHooks

%hook SBIconView

- (void)setLabelHidden:(BOOL)hidden {
    %orig(YES); // Always hide app names so text never overlaps
}

- (void)layoutSubviews {
    %orig;

    if (class_getInstanceVariable([self class], "_labelView") != NULL) {
        UIView *labelView = [self valueForKey:@"_labelView"];
        if ([labelView isKindOfClass:[UIView class]] && !labelView.hidden) {
            labelView.hidden = YES;
            labelView.alpha = 0.0;
        }
    }

    if (!gPadCompactIcons) return;

    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    BOOL isLandscape = (screenSize.width > screenSize.height);
    BOOL isWidget = (self.bounds.size.width > 95.0 || self.bounds.size.height > 95.0);
    BOOL isInDock = [NSStringFromClass([self.superview class]) containsString:@"Dock"];

    // Exact scale math for iPhone SE 2016 (320x568 Portrait / 568x320 Landscape):
    // In landscape, 5 rows fit inside ~200pt height -> 0.56 scale keeps clean spacing (waqfa) & 0% overlap
    CGFloat targetScale = 1.0;
    if (isWidget) {
        targetScale = isLandscape ? 0.62 : 0.92;
    } else if (isInDock) {
        targetScale = isLandscape ? 0.64 : 0.84;
    } else {
        targetScale = isLandscape ? 0.56 : 0.84;
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
// 2. Crash-Free UIKit Window & ViewController Rotation (No homeScreenRotationStyle Crash)
// =========================================================================
%group PadSystemRotationHooks

%hook SpringBoard

- (BOOL)homeScreenSupportsRotation {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%hook SBIconController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
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

%hook CSCoverSheetViewController

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
// 3. Settings App (com.apple.Preferences) -> Crash-Free 2-Pane Split View
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

- (void)viewWillLayoutSubviews {
    %orig;
    BOOL isLandscape = (self.view.bounds.size.width > self.view.bounds.size.height);
    UITraitCollection *overrideTrait = isLandscape
        ? [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassRegular]
        : nil;

    for (UIViewController *child in self.childViewControllers) {
        [self setOverrideTraitCollection:overrideTrait forChildViewController:child];
    }
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%end

// =========================================================================
// Constructor with Automatic Safe-Mode Boot Guard
// =========================================================================
%ctor {
    if (!PadBoolPref(@"kEnabled", YES)) return;
    if (!PadBoolPref(@"kEnablePadMode", NO)) {
        [PadPrefs() setBool:NO forKey:kPadBootGuardKey];
        return;
    }

    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;

    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        BOOL rotateOn = PadBoolPref(@"kPadRotateSystem", YES);

        if (rotateOn && PadBoolPref(kPadBootGuardKey, NO)) {
            [PadPrefs() setBool:NO forKey:@"kPadRotateSystem"];
            [PadPrefs() setBool:NO forKey:kPadBootGuardKey];
            [PadPrefs() synchronize];
            rotateOn = NO;
        }

        if (rotateOn) {
            [PadPrefs() setBool:YES forKey:kPadBootGuardKey];
            [PadPrefs() synchronize];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [PadPrefs() setBool:NO forKey:kPadBootGuardKey];
                [PadPrefs() synchronize];
            });
        }

        gPadCompactIcons = PadBoolPref(@"kPadCompactIcons", YES);
        %init(PadSELayoutHooks);

        if (rotateOn) {
            %init(PadSystemRotationHooks);
        }
    } else if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
        if (PadBoolPref(@"kPadSplitSettings", YES)) {
            %init(PadSettingsAppHooks);
        }
    }
}
