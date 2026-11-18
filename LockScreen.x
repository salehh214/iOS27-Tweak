#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "iOS27Prefs.h"

static CGFloat gLSGlassAlpha = 0.25;

@interface SBFLockScreenDateView : UIView
@end

@interface CSQuickActionsButton : UIControl
@end

%group LockScreenHooks

%hook SBFLockScreenDateView
- (void)layoutSubviews {
    %orig;
    UILabel *timeLabel = [self valueForKey:@"_timeLabel"];
    if ([timeLabel isKindOfClass:[UILabel class]]) {
        UIFontDescriptor *desc = [[UIFont systemFontOfSize:78.0 weight:UIFontWeightHeavy].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (desc) {
            timeLabel.font = [UIFont fontWithDescriptor:desc size:78.0];
        }
        timeLabel.textColor = [UIColor colorWithRed:0.88 green:0.96 blue:1.0 alpha:0.95];
    }

    UIView *widgetPill = [self viewWithTag:27101];
    if (!widgetPill) {
        widgetPill = [[UIView alloc] initWithFrame:CGRectZero];
        widgetPill.tag = 27101;
        widgetPill.backgroundColor = [UIColor colorWithRed:0.10 green:0.15 blue:0.22 alpha:gLSGlassAlpha];
        widgetPill.layer.cornerRadius = 18.0;
        widgetPill.layer.cornerCurve = kCACornerCurveContinuous;
        widgetPill.layer.borderWidth = 1.0;
        widgetPill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
        widgetPill.userInteractionEnabled = NO;

        UILabel *hudLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        hudLabel.tag = 27102;
        hudLabel.textAlignment = NSTextAlignmentCenter;
        hudLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        hudLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
        [widgetPill addSubview:hudLabel];

        [self addSubview:widgetPill];
    }

    CGFloat pillWidth = 220.0;
    CGFloat pillHeight = 36.0;
    widgetPill.frame = CGRectMake((self.bounds.size.width - pillWidth) / 2.0, self.bounds.size.height + 8.0, pillWidth, pillHeight);

    UILabel *hudLabel = (UILabel *)[widgetPill viewWithTag:27102];
    if (hudLabel) {
        hudLabel.frame = widgetPill.bounds;
        UIDevice *device = [UIDevice currentDevice];
        device.batteryMonitoringEnabled = YES;
        int batteryPercent = (int)(device.batteryLevel * 100);
        if (batteryPercent < 0) batteryPercent = 100;
        hudLabel.text = [NSString stringWithFormat:@"⚡ iOS 27 • %d%% • Low-RAM Mode", batteryPercent];
    }
}
%end

%hook CSQuickActionsButton
- (void)layoutSubviews {
    %orig;
    for (UIView *sub in self.subviews) {
        if ([NSStringFromClass([sub class]) containsString:@"Material"] || [NSStringFromClass([sub class]) containsString:@"Effect"]) {
            sub.hidden = YES;
        }
    }
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:gLSGlassAlpha];
    self.layer.cornerRadius = self.bounds.size.width / 2.0;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    self.clipsToBounds = YES;
}
%end

%end

%ctor {
    if (iOS27BoolPref(@"kEnabled", YES) && iOS27BoolPref(@"kEnableLockScreen", YES)) {
        gLSGlassAlpha = iOS27FloatPref(@"kGlassAlpha", 0.25);
        %init(LockScreenHooks);
    }
}
