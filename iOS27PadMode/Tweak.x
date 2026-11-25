#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

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

@interface CSCoverSheetViewController : UIViewController
@end

@interface CCUIModularControlCenterOverlayViewController : UIViewController
@end

@interface SBAppSwitcherSettings : NSObject
- (NSInteger)switcherStyle;
- (NSInteger)effectiveSwitcherStyle;
@end

@interface UIStatusBar_Modern : UIView
+ (Class)_visualProviderClassForIdiom:(NSInteger)idiom hasNotch:(BOOL)hasNotch;
@end

@interface SBIconView : UIView
- (void)setLabelHidden:(BOOL)hidden;
@end

// =========================================================================
// 1. iPhone SE (2016) Anti-Overlap Engine (No Labels + Smaller Spaced Icons)
// =========================================================================
%group PadSELayoutHooks

%hook SBIconView

- (void)setLabelHidden:(BOOL)hidden {
    %orig(YES); // Always remove app text labels to prevent overlap
}

- (void)layoutSubviews {
    %orig;

    // Force-hide icon text label view
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

    // Tuned specifically for iPhone SE 2016 (320x568 portrait / 568x320 landscape)
    // Smaller scale automatically adds crisp spacing (waqfa) between icons with zero overlap
    CGFloat targetScale = 1.0;
    if (isWidget) {
        targetScale = isLandscape ? 0.80 : 0.92;
    } else {
        targetScale = isLandscape ? 0.74 : 0.84;
    }

    CGAffineTransform desired = CGAffineTransformMakeScale(targetScale, targetScale);
    if (!CGAffineTransformEqualToTransform(self.transform, desired)) {
        self.transform = desired;
    }
}

%end

%end

// =========================================================================
// 2. Full System Rotation (Home Screen, Lock Screen, Control Center)
// =========================================================================
%group PadSystemRotationHooks

%hook SpringBoard

- (NSInteger)homeScreenRotationStyle {
    return 2; // Full iPad-style Home Screen rotation
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

%end

// =========================================================================
// 3. iPadOS / Mac Grid App Switcher
// =========================================================================
%group PadGridSwitcherHooks

%hook SBAppSwitcherSettings

- (NSInteger)switcherStyle {
    return 2;
}

- (NSInteger)effectiveSwitcherStyle {
    return 2;
}

%end

%end

// =========================================================================
// 4. iPad / Mac Status Bar
// =========================================================================
%group PadStatusBarHooks

%hook UIStatusBar_Modern

+ (Class)_visualProviderClassForIdiom:(NSInteger)idiom hasNotch:(BOOL)hasNotch {
    Class padProvider = NSClassFromString(@"_UIStatusBarVisualProvider_Pad_ForcedCellular");
    if (!padProvider) padProvider = NSClassFromString(@"_UIStatusBarVisualProvider_Pad");
    if (padProvider) return padProvider;
    return %orig;
}

%end

%end

// =========================================================================
// 5. Settings App (com.apple.Preferences) -> SE 2016 Tuned Split View
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
    // Proportioned for 568pt SE 2016 landscape width so sidebar & detail pane never squish
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
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    if (screenSize.width > screenSize.height) {
        UITraitCollection *regularW = [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassRegular];
        return [UITraitCollection traitCollectionWithTraitsFromCollections:@[orig, regularW]];
    }
    return orig;
}

%end

%end

// =========================================================================
// Constructor (RAM-Cached, Zero Overhead when OFF)
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
        if (PadBoolPref(@"kPadGridSwitcher", YES)) {
            %init(PadGridSwitcherHooks);
        }
        if (PadBoolPref(@"kPadStatusBar", YES)) {
            %init(PadStatusBarHooks);
        }
    } else if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
        if (PadBoolPref(@"kPadSplitSettings", YES)) {
            %init(PadSettingsAppHooks);
        }
    }
}
