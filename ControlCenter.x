#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "iOS27Prefs.h"

static CGFloat gCCGlassAlpha = 0.28;

@interface CCUIContentModuleContentContainerView : UIView
@end

@interface CCUIBaseSliderView : UIView
@end

@interface CCUIHeaderPocketView : UIView
@end

static void ApplyCCGlassStyle(UIView *view, CGFloat radius) {
    for (UIView *sub in view.subviews) {
        NSString *clsName = NSStringFromClass([sub class]);
        if ([clsName containsString:@"MTMaterialView"] || [clsName containsString:@"UIVisualEffectView"]) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }
    view.backgroundColor = [UIColor colorWithRed:0.10 green:0.14 blue:0.22 alpha:gCCGlassAlpha];
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.1;
    view.layer.borderColor = [UIColor colorWithRed:0.75 green:0.90 blue:1.0 alpha:0.35].CGColor;
    view.clipsToBounds = YES;
}

%group ControlCenterHooks

%hook CCUIContentModuleContentContainerView
- (void)layoutSubviews {
    %orig;
    ApplyCCGlassStyle(self, 28.0);
}
%end

%hook CCUIBaseSliderView
- (void)layoutSubviews {
    %orig;
    ApplyCCGlassStyle(self, 28.0);
}
%end

%hook CCUIHeaderPocketView
- (void)layoutSubviews {
    %orig;
    for (UIView *sub in self.subviews) {
        if ([NSStringFromClass([sub class]) containsString:@"Material"]) {
            sub.hidden = YES;
        }
    }
}
%end

%end

%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (iOS27BoolPref(@"kEnabled", YES) && iOS27BoolPref(@"kEnableCC", YES)) {
        gCCGlassAlpha = iOS27FloatPref(@"kGlassAlpha", 0.28);
        %init(ControlCenterHooks);
    }
}
