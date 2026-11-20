#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
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
- (void)ios27_syncHomeWallpaper;
@end

@interface SBIconListPageControl : UIView
- (void)ios27_openSpotlightSearch:(UIButton *)sender;
@end

@interface SBSearchGesture : NSObject
+ (instancetype)sharedInstance;
- (void)revealAnimated:(BOOL)animated;
@end

@interface SBSearchPresenter : NSObject
- (void)presentSearchAnimated:(BOOL)animated;
@end

@interface SBRootFolderController : UIViewController
- (void)presentSpotlightAnimated:(BOOL)animated;
- (SBSearchGesture *)searchGesture;
@end

@interface SBHIconManager : NSObject
- (SBRootFolderController *)rootFolderController;
- (SBSearchPresenter *)searchPresenter;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
- (SBSearchGesture *)searchGesture;
- (SBSearchPresenter *)searchPresenter;
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

%hook SBHomeScreenViewController

- (void)viewDidLoad {
    %orig;
    [self ios27_syncHomeWallpaper];

    static const void *kHSWpObsKey = &kHSWpObsKey;
    if (!objc_getAssociatedObject(self, kHSWpObsKey)) {
        objc_setAssociatedObject(self, kHSWpObsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ios27_syncHomeWallpaper)
                                                     name:kIOS27WallpaperChanged
                                                   object:nil];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIImageView *wpView = (UIImageView *)[self.view viewWithTag:27301];
    if (wpView) {
        wpView.frame = self.view.bounds;
        for (CALayer *sub in wpView.layer.sublayers) {
            if ([sub.name isEqualToString:@"iOS27PresetGradient"]) {
                sub.frame = wpView.bounds;
            }
        }
    }
}

%new
- (void)ios27_syncHomeWallpaper {
    UIImageView *wpView = (UIImageView *)[self.view viewWithTag:27301];
    if (!wpView) {
        wpView = [[UIImageView alloc] initWithFrame:self.view.bounds];
        wpView.tag = 27301;
        wpView.contentMode = UIViewContentModeScaleAspectFill;
        wpView.clipsToBounds = YES;
        wpView.userInteractionEnabled = NO;
        wpView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view insertSubview:wpView atIndex:0];
    }
    iOS27ApplyWallpaperToView(wpView);
}

%end

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

%hook SBIconListPageControl

- (void)layoutSubviews {
    %orig;

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
        [searchPill addTarget:self action:@selector(ios27_openSpotlightSearch:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:searchPill];
    }

    CGFloat pillW = 86.0;
    CGFloat pillH = 26.0;
    searchPill.frame = CGRectMake((self.bounds.size.width - pillW) / 2.0, (self.bounds.size.height - pillH) / 2.0, pillW, pillH);
    ApplyFakeGlass(searchPill, pillH / 2.0, gGlassAlpha);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *searchPill = [self viewWithTag:27005];
    if (searchPill && !searchPill.hidden && CGRectContainsPoint(CGRectInset(searchPill.frame, -12.0, -10.0), point)) {
        return searchPill;
    }
    return %orig;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *searchPill = [self viewWithTag:27005];
    if (searchPill && !searchPill.hidden && CGRectContainsPoint(CGRectInset(searchPill.frame, -12.0, -10.0), point)) {
        return YES;
    }
    return %orig;
}

%new
- (void)ios27_openSpotlightSearch:(UIButton *)sender {
    [UIView animateWithDuration:0.08 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.12 animations:^{
            sender.transform = CGAffineTransformIdentity;
        }];
    }];

    SBIconController *ic = [%c(SBIconController) sharedInstance];

    if ([ic respondsToSelector:@selector(searchPresenter)]) {
        SBSearchPresenter *sp = [ic searchPresenter];
        if (sp && [sp respondsToSelector:@selector(presentSearchAnimated:)]) {
            [sp presentSearchAnimated:YES];
            return;
        }
    }

    SBHIconManager *manager = [ic respondsToSelector:@selector(iconManager)] ? [ic iconManager] : nil;
    if (manager) {
        if ([manager respondsToSelector:@selector(searchPresenter)]) {
            SBSearchPresenter *sp = [manager searchPresenter];
            if (sp && [sp respondsToSelector:@selector(presentSearchAnimated:)]) {
                [sp presentSearchAnimated:YES];
                return;
            }
        }
        SBRootFolderController *rfc = [manager respondsToSelector:@selector(rootFolderController)] ? [manager rootFolderController] : nil;
        if (rfc) {
            if ([rfc respondsToSelector:@selector(presentSpotlightAnimated:)]) {
                [rfc presentSpotlightAnimated:YES];
                return;
            }
            @try {
                SBSearchGesture *gesture = [rfc valueForKey:@"_searchGesture"];
                if (gesture && [gesture respondsToSelector:@selector(revealAnimated:)]) {
                    [gesture revealAnimated:YES];
                    return;
                }
            } @catch (NSException *e) {}
        }
    }

    @try {
        id sp = [ic valueForKey:@"_searchPresenter"];
        if (sp && [sp respondsToSelector:@selector(presentSearchAnimated:)]) {
            [sp presentSearchAnimated:YES];
            return;
        }
    } @catch (NSException *e) {}

    @try {
        id gesture = [ic valueForKey:@"_searchGesture"];
        if (gesture && [gesture respondsToSelector:@selector(revealAnimated:)]) {
            [gesture revealAnimated:YES];
            return;
        }
    } @catch (NSException *e) {}

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
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (iOS27BoolPref(@"kEnabled", YES) && iOS27BoolPref(@"kEnableHomeScreen", YES)) {
        gGlassAlpha = iOS27FloatPref(@"kGlassAlpha", 0.25);
        %init(HomeScreenHooks);
    }
}
