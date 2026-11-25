#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "iOS27Prefs.h"

static BOOL gEnableGestures = YES;
static BOOL gClassicKeyboard = YES;
static BOOL gHideHomeBar = NO;
static BOOL gRoundedSwitcher = YES;
static BOOL gLockQuickActions = YES;
static NSInteger gStatusBarStyle = 0;

@interface BSPlatform : NSObject
- (NSInteger)homeButtonType;
@end

@interface SBHomeGestureSettings : NSObject
- (BOOL)isHomeGestureEnabled;
@end

@interface MTLumaDodgePillView : UIView
@end

@interface UIStatusBar_Modern : UIView
+ (Class)_visualProviderClassForIdiom:(NSInteger)idiom hasNotch:(BOOL)hasNotch;
@end

@interface UIKeyboardImpl : UIView
+ (UIEdgeInsets)deviceSpecificPaddingForInterfaceOrientation:(NSInteger)orientation inputMode:(id)mode;
@end

@interface CSQuickActionsViewController : UIViewController
+ (BOOL)deviceSupportsButtons;
@end

@interface SBAppSwitcherPageView : UIView
@end

%group FluidGesturesHooks

%hook BSPlatform
- (NSInteger)homeButtonType {
    return 2;
}
%end

%hook SBHomeGestureSettings
- (BOOL)isHomeGestureEnabled {
    return YES;
}
%end

%end

%group ClassicKeyboardHooks

%hook UIKeyboardImpl
+ (UIEdgeInsets)deviceSpecificPaddingForInterfaceOrientation:(NSInteger)orientation inputMode:(id)mode {
    return UIEdgeInsetsZero;
}
%end

%end

%group HideHomeBarHooks

%hook MTLumaDodgePillView
- (void)setAlpha:(CGFloat)alpha {
    %orig(0.0);
}
- (void)setHidden:(BOOL)hidden {
    %orig(YES);
}
- (void)layoutSubviews {
    %orig;
    self.alpha = 0.0;
    self.hidden = YES;
}
%end

%end

%group StatusBarStyleHooks

%hook UIStatusBar_Modern
+ (Class)_visualProviderClassForIdiom:(NSInteger)idiom hasNotch:(BOOL)hasNotch {
    if (gStatusBarStyle == 0) {
        return %orig(idiom, NO);
    } else if (gStatusBarStyle == 1) {
        return %orig(idiom, YES);
    } else if (gStatusBarStyle == 2) {
        Class padProvider = NSClassFromString(@"_UIStatusBarVisualProvider_Pad_ForcedCellular");
        if (!padProvider) padProvider = NSClassFromString(@"_UIStatusBarVisualProvider_Pad");
        if (padProvider) return padProvider;
    }
    return %orig;
}
%end

%end

%group RoundedSwitcherHooks

%hook SBAppSwitcherPageView
- (void)layoutSubviews {
    %orig;
    self.layer.cornerRadius = 24.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
}
%end

%end

%group QuickActionsHooks

%hook CSQuickActionsViewController
+ (BOOL)deviceSupportsButtons {
    return gLockQuickActions;
}
%end

%end

%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (!iOS27BoolPref(@"kEnabled", YES)) return;

    gEnableGestures   = iOS27BoolPref(@"kEnableGestures", YES);
    gClassicKeyboard  = iOS27BoolPref(@"kClassicKeyboard", YES);
    gHideHomeBar      = iOS27BoolPref(@"kHideHomeBar", NO);
    gRoundedSwitcher  = iOS27BoolPref(@"kRoundedSwitcher", YES);
    gLockQuickActions = iOS27BoolPref(@"kLockQuickActions", YES);
    gStatusBarStyle   = iOS27IntPref(@"kStatusBarStyle", 0);

    if (gEnableGestures) {
        %init(FluidGesturesHooks);
        %init(StatusBarStyleHooks);
    }
    if (gClassicKeyboard) {
        %init(ClassicKeyboardHooks);
    }
    if (gHideHomeBar) {
        %init(HideHomeBarHooks);
    }
    if (gRoundedSwitcher) {
        %init(RoundedSwitcherHooks);
    }
    %init(QuickActionsHooks);
}
