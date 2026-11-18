#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUIContentModuleContentContainerView : UIView
@end

@interface CCUIBaseSliderView : UIView
@end

@interface CCUIHeaderPocketView : UIView
@end

static void ApplyCCGlassStyle(UIView *view, CGFloat radius) {
    // Strip heavy Material/Blur subviews inside CC containers
    for (UIView *sub in view.subviews) {
        NSString *clsName = NSStringFromClass([sub class]);
        if ([clsName containsString:@"MTMaterialView"] || [clsName containsString:@"UIVisualEffectView"]) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }

    view.backgroundColor = [UIColor colorWithRed:0.10 green:0.14 blue:0.22 alpha:0.28];
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.1;
    view.layer.borderColor = [UIColor colorWithRed:0.75 green:0.90 blue:1.0 alpha:0.35].CGColor;
    view.clipsToBounds = YES;
}

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
    // Top Control Center status header ko clean aur lag-free rakhein
    for (UIView *sub in self.subviews) {
        if ([NSStringFromClass([sub class]) containsString:@"Material"]) {
            sub.hidden = YES;
        }
    }
}

%end
