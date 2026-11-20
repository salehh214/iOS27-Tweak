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

@interface SBIconListPageControl : UIView
- (void)ios27_openSpotlightSearch;
@end

@interface SBSearchGesture : NSObject
- (void)revealAnimated:(BOOL)animated;
@end

@interface SBRootFolderController : UIViewController
- (void)presentSpotlightAnimated:(BOOL)animated;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
- (SBSearchGesture *)searchGesture;
- (SBRootFolderController *)_rootFolderController;
@end

@interface SBMainWorkspace : NSObject
+ (instancetype)sharedInstance;
- (void)presentSpotlightFromSource:(NSUInteger)source animated:(BOOL)animated;
@end

@interface SBFFluidBehaviorSettings : NSObject
- (void)setResponse:(double)response;
- (void)setDampingRatio:(double)damping;
@end

static void ApplyFakeGlass(UIView *targetView, CGFloat cornerRadius, CGFloat alpha) {
    targetView.backgroundColor = [UIColor colorWithRed:0.12 green:0.16 blue:0.24 alpha:alpha];
    targetView.layer.cornerRadius = cornerRadius;
    targetView.layer.cornerCurve = kCACornerCurveContinuous;
    targetView.layer.borderWidth = 1.1;
    targetView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
    targetView.clipsToBounds = YES;

    // Lightweight Glassy Sheen (Zero Blur / Zero Lag)
    CAGradientLayer *sheen = nil;
    for (CALayer *layer in targetView.layer.sublayers) {
        if ([layer.name isEqualToString:@"iOS27GlassSheen"]) {
            sheen = (CAGradientLayer *)layer;
            break;
        }
    }
    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.name = @"iOS27GlassSheen";
        sheen.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.28].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor
        ];
        sheen.locations = @[@0.0, @0.50, @1.0];
        sheen.startPoint = CGPointMake(0.5, 0.0);
        sheen.endPoint = CGPointMake(0.5, 1.0);
        [targetView.layer insertSublayer:sheen atIndex:0];
    }
    sheen.frame = targetView.bounds;
    sheen.cornerRadius = cornerRadius;
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
        [self insertSubview:glassDock atIndex:0];
    }
    glassDock.frame = CGRectInset(self.bounds, 10.0, 6.0);
    ApplyFakeGlass(glassDock, 30.0, gGlassAlpha);
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

// Replace Page Dots directly with iOS 16/27 Glass Search Pill (Zero Overlap)
%hook SBIconListPageControl

- (void)layoutSubviews {
    %orig;

    // Default page dots hide karein
    for (UIView *sub in self.subviews) {
        if (sub.tag != 27005) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }

    self.userInteractionEnabled = YES;

    UIButton *searchPill = (UIButton *)[self viewWithTag:27005];
    if (!searchPill) {
        searchPill = [UIButton buttonWithType:UIButtonTypeCustom];
        searchPill.tag = 27005;

        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:10.5 weight:UIImageSymbolWeightSemibold];
            UIImage *magIcon = [UIImage systemImageNamed:@"magnifyingglass" withConfiguration:cfg];
            [searchPill setImage:magIcon forState:UIControlStateNormal];
            searchPill.tintColor = [UIColor colorWithWhite:1.0 alpha:0.95];
        }

        [searchPill setTitle:@" Search" forState:UIControlStateNormal];
        searchPill.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
        [searchPill setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.95] forState:UIControlStateNormal];
        [searchPill addTarget:self action:@selector(ios27_openSpotlightSearch) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:searchPill];
    }

    CGFloat pillW = 84.0;
    CGFloat pillH = 26.0;
    searchPill.frame = CGRectMake((self.bounds.size.width - pillW) / 2.0, (self.bounds.size.height - pillH) / 2.0, pillW, pillH);
    ApplyFakeGlass(searchPill, pillH / 2.0, gGlassAlpha);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *searchPill = [self viewWithTag:27005];
    if (searchPill && CGRectContainsPoint(CGRectInset(searchPill.frame, -8.0, -8.0), point)) {
        return YES;
    }
    return %orig;
}

%new
- (void)ios27_openSpotlightSearch {
    SBIconController *iconController = [%c(SBIconController) sharedInstance];

    // Method 1: SpringBoard native Search Gesture (iOS 15 primary)
    if ([iconController respondsToSelector:@selector(searchGesture)]) {
        SBSearchGesture *gesture = [iconController searchGesture];
        if (gesture && [gesture respondsToSelector:@selector(revealAnimated:)]) {
            [gesture revealAnimated:YES];
            return;
        }
    }

    // Method 2: Root Folder Controller Spotlight presenter
    if ([iconController respondsToSelector:@selector(_rootFolderController)]) {
        SBRootFolderController *rfc = [iconController _rootFolderController];
        if (rfc && [rfc respondsToSelector:@selector(presentSpotlightAnimated:)]) {
            [rfc presentSpotlightAnimated:YES];
            return;
        }
    }

    // Method 3: MainWorkspace fallback
    SBMainWorkspace *workspace = [%c(SBMainWorkspace) sharedInstance];
    if ([workspace respondsToSelector:@selector(presentSpotlightFromSource:animated:)]) {
        [workspace presentSpotlightFromSource:1 animated:YES];
    }
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
