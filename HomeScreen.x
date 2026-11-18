#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "iOS27Prefs.h"

static CGFloat gGlassAlpha = 0.25;

@interface SBIconView : UIView
- (void)setLabelHidden:(BOOL)hidden;
@end

@interface SBDockView : UIView
@end

@interface SBFloatyFolderView : UIView
@end

@interface SBFolderIconImageView : UIView
@end

@interface SBHomeScreenViewController : UIViewController
@end

@interface SBFFluidBehaviorSettings : NSObject
- (void)setResponse:(double)response;
- (void)setDampingRatio:(double)damping;
@end

static void ApplyFakeGlass(UIView *targetView, CGFloat cornerRadius, CGFloat alpha) {
    targetView.backgroundColor = [UIColor colorWithRed:0.12 green:0.16 blue:0.24 alpha:alpha];
    targetView.layer.cornerRadius = cornerRadius;
    targetView.layer.cornerCurve = kCACornerCurveContinuous;
    targetView.layer.borderWidth = 1.0;
    targetView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.32].CGColor;
    targetView.clipsToBounds = YES;
}

%group HomeScreenHooks

%hook SBIconView
- (void)setLabelHidden:(BOOL)hidden {
    %orig(YES);
}
- (void)layoutSubviews {
    %orig;
    self.transform = CGAffineTransformMakeScale(0.94, 0.94);
}
%end

%hook SBDockView
- (void)layoutSubviews {
    %orig;
    UIView *bgView = [self valueForKey:@"_backgroundView"];
    if (bgView) {
        bgView.hidden = YES;
        bgView.alpha = 0.0;
    }
    UIView *glassDock = [self viewWithTag:27001];
    if (!glassDock) {
        glassDock = [[UIView alloc] initWithFrame:CGRectZero];
        glassDock.tag = 27001;
        glassDock.userInteractionEnabled = NO;
        ApplyFakeGlass(glassDock, 34.0, gGlassAlpha);
        [self insertSubview:glassDock atIndex:0];
    }
    glassDock.frame = CGRectInset(self.bounds, 10.0, 6.0);
}
%end

%hook SBFloatyFolderView
- (void)layoutSubviews {
    %orig;
    UIView *bgView = [self valueForKey:@"_backgroundView"];
    if (bgView) {
        for (UIView *sub in bgView.subviews) {
            sub.hidden = YES;
        }
        ApplyFakeGlass(bgView, 38.0, gGlassAlpha);
    }
}
%end

%hook SBFolderIconImageView
- (void)layoutSubviews {
    %orig;
    UIView *bgView = [self valueForKey:@"_backgroundView"];
    if (bgView) {
        for (UIView *sub in bgView.subviews) {
            sub.hidden = YES;
        }
        ApplyFakeGlass(bgView, 16.0, gGlassAlpha);
    }
}
%end

%hook SBHomeScreenViewController
- (void)viewDidLoad {
    %orig;
    if (![self.view viewWithTag:27002]) {
        UIButton *drawerPill = [UIButton buttonWithType:UIButtonTypeCustom];
        drawerPill.tag = 27002;
        drawerPill.frame = CGRectMake((self.view.bounds.size.width - 110.0) / 2.0, self.view.bounds.size.height - 118.0, 110.0, 26.0);
        drawerPill.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [drawerPill setTitle:@"⠿ Apps 27" forState:UIControlStateNormal];
        drawerPill.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
        [drawerPill setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.9] forState:UIControlStateNormal];
        ApplyFakeGlass(drawerPill, 13.0, gGlassAlpha);
        [drawerPill addTarget:self action:@selector(ios27_openAppDrawer) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:drawerPill];
    }
}

%new
- (void)ios27_openAppDrawer {
    UIAlertController *drawer = [UIAlertController alertControllerWithTitle:@"iOS 27 Quick Drawer"
                                                                    message:@"Select a quick action"
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    UIApplication *app = [UIApplication sharedApplication];
    [drawer addAction:[UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [app openURL:[NSURL URLWithString:@"App-Prefs:"] options:@{} completionHandler:nil];
    }]];
    [drawer addAction:[UIAlertAction actionWithTitle:@"Safari Browser" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [app openURL:[NSURL URLWithString:@"https://"] options:@{} completionHandler:nil];
    }]];
    [drawer addAction:[UIAlertAction actionWithTitle:@"Close Drawer" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:drawer animated:NO completion:nil];
}
%end

%hook SBFFluidBehaviorSettings
- (void)setResponse:(double)response {
    %orig(0.22);
}
- (void)setDampingRatio:(double)damping {
    %orig(1.0);
}
%end

%end

%ctor {
    if (iOS27BoolPref(@"kEnabled", YES) && iOS27BoolPref(@"kEnableHomeScreen", YES)) {
        gGlassAlpha = iOS27FloatPref(@"kGlassAlpha", 0.25);
        %init(HomeScreenHooks);
    }
}
