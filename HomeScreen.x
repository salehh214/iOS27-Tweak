#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "iOS27Prefs.h"

static CGFloat gGlassAlpha = 0.25;
static NSInteger gDockStyle = 0;
static BOOL gLargeIcons = YES;
static BOOL gPadModeActive = NO;
static NSInteger gIconStyle = 0;
static NSInteger gIconSubMode = 0;
static CGFloat gTintHue = 0.55;
static CGFloat gTintBri = 0.85;
static NSUInteger gIconStyleEpoch = 1;

static void ReloadHomeScreenCache(void) {
    gGlassAlpha    = iOS27FloatPref(@"kGlassAlpha", 0.25);
    gDockStyle     = iOS27IntPref(@"kDockStyle", 0);
    gLargeIcons    = iOS27BoolPref(@"kHSLargeIcons", YES);
    gPadModeActive = iOS27BoolPref(@"kEnablePadMode", NO);
    gIconStyle     = iOS27IntPref(@"kHSIconStyle", 0);
    gIconSubMode   = iOS27IntPref(@"kHSIconSubMode", 0);
    gTintHue       = iOS27FloatPref(@"kHSTintHue", 0.55);
    gTintBri       = iOS27FloatPref(@"kHSTintBrightness", 0.85);
    gIconStyleEpoch++;
}

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
- (BOOL)isEditing;
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
            (id)[UIColor colorWithWhite:1.0 alpha:0.26].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor
        ];
        sheen.locations = @[@0.0, @0.50, @1.0];
        sheen.startPoint = CGPointMake(0.5, 0.0);
        sheen.endPoint = CGPointMake(0.5, 1.0);
        [targetView.layer insertSublayer:sheen atIndex:0];
    }
    if (!CGRectEqualToRect(sheen.frame, targetView.bounds)) {
        sheen.frame = targetView.bounds;
        sheen.cornerRadius = cornerRadius;
    }
}

static const void *kIconEpochKey = &kIconEpochKey;

static void ApplyLiquidGlassToIcon(UIView *iconImgView) {
    if (!iconImgView) return;

    CGRect bounds = iconImgView.bounds;
    if (CGRectIsEmpty(bounds) || bounds.size.width < 28.0 || bounds.size.width > 95.0) return;
    if (fabs(bounds.size.width - bounds.size.height) > 4.0) return;

    static Class folderImgCls = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        folderImgCls = NSClassFromString(@"SBFolderIconImageView");
    });
    if (folderImgCls && [iconImgView isKindOfClass:folderImgCls]) return;

    UIView *glassShell = [iconImgView viewWithTag:27888];
    NSNumber *appliedEpoch = objc_getAssociatedObject(iconImgView, kIconEpochKey);
    if (glassShell && appliedEpoch && [appliedEpoch unsignedIntegerValue] == gIconStyleEpoch && CGRectEqualToRect(glassShell.bounds, bounds)) {
        return;
    }

    CGFloat radius = floor(bounds.size.width * 0.225);

    if (!glassShell) {
        glassShell = [[UIView alloc] initWithFrame:bounds];
        glassShell.tag = 27888;
        glassShell.userInteractionEnabled = NO;
        glassShell.clipsToBounds = YES;
        glassShell.layer.cornerCurve = kCACornerCurveContinuous;
        glassShell.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [iconImgView addSubview:glassShell];
    }

    glassShell.frame = bounds;
    glassShell.layer.cornerRadius = radius;
    glassShell.hidden = NO;

    CAGradientLayer *domeLayer = nil;
    for (CALayer *layer in glassShell.layer.sublayers) {
        if ([layer.name isEqualToString:@"iOS27IconDome"]) {
            domeLayer = (CAGradientLayer *)layer;
            break;
        }
    }
    if (!domeLayer) {
        domeLayer = [CAGradientLayer layer];
        domeLayer.name = @"iOS27IconDome";
        domeLayer.startPoint = CGPointMake(0.5, 0.0);
        domeLayer.endPoint = CGPointMake(0.5, 1.0);
        domeLayer.locations = @[@0.0, @0.32, @0.70, @1.0];
        [glassShell.layer insertSublayer:domeLayer atIndex:0];
    }
    domeLayer.frame = bounds;
    domeLayer.cornerRadius = radius;
    glassShell.layer.borderWidth = 1.15;

    if (gIconStyle == 0) {
        iconImgView.alpha = 1.0;
        glassShell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
        glassShell.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.62].CGColor;
        domeLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.32].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.03].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.02].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.16].CGColor
        ];
    } else if (gIconStyle == 1) {
        iconImgView.alpha = 0.96;
        CGFloat darkAlpha = (gIconSubMode == 0) ? 0.36 : 0.24;
        glassShell.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:darkAlpha];
        glassShell.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
        domeLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.22].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.02].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.10].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor
        ];
    } else if (gIconStyle == 2) {
        if (gIconSubMode == 1) {
            iconImgView.alpha = 0.68;
            glassShell.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:0.38];
            glassShell.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;
            domeLayer.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.34].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
                (id)[UIColor colorWithWhite:0.0 alpha:0.08].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.20].CGColor
            ];
        } else {
            iconImgView.alpha = 0.72;
            glassShell.backgroundColor = [UIColor colorWithWhite:0.96 alpha:0.24];
            glassShell.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
            domeLayer.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.48].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.08].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.28].CGColor
            ];
        }
    } else {
        iconImgView.alpha = (gIconSubMode == 1) ? 0.85 : 0.90;
        CGFloat tintAlpha = (gIconSubMode == 1) ? 0.56 : 0.44;
        glassShell.backgroundColor = [UIColor colorWithHue:gTintHue saturation:0.80 brightness:gTintBri alpha:tintAlpha];
        glassShell.layer.borderColor = [UIColor colorWithHue:gTintHue saturation:0.45 brightness:MIN(gTintBri + 0.20, 1.0) alpha:0.82].CGColor;
        domeLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.34].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.05].CGColor,
            (id)[UIColor colorWithHue:gTintHue saturation:0.50 brightness:1.0 alpha:0.20].CGColor
        ];
    }

    objc_setAssociatedObject(iconImgView, kIconEpochKey, @(gIconStyleEpoch), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ios27_syncHomeWallpaper)
                                                     name:kIOS27HSStyleChanged
                                                   object:nil];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIImageView *wpView = (UIImageView *)[self.view viewWithTag:27301];
    if (wpView && !CGRectEqualToRect(wpView.frame, self.view.bounds)) {
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
    ReloadHomeScreenCache();

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

    NSInteger hsMode = iOS27IntPref(@"kHSWallpaperMode", 0);
    NSInteger colorIdx = iOS27IntPref(@"kHSColorIndex", 0);
    NSInteger gradIdx = iOS27IntPref(@"kHSGradientIndex", 0);
    BOOL blurOn = iOS27BoolPref(@"kHSBlurEnabled", NO);
    BOOL dimOn = iOS27BoolPref(@"kHSDimWallpaper", NO);
    iOS27ApplyHomeWallpaperToView(wpView, hsMode, colorIdx, gradIdx, blurOn, dimOn, NO);
}

%end

%hook SBIconView

- (void)setLabelHidden:(BOOL)hidden {
    if (gPadModeActive) {
        %orig;
        return;
    }
    %orig(gLargeIcons ? YES : hidden);
}

- (void)layoutSubviews {
    %orig;

    if (!gPadModeActive) {
        @try {
            UIView *labelView = [self valueForKey:@"_labelView"];
            if ([labelView isKindOfClass:[UIView class]] && labelView.hidden != gLargeIcons) {
                labelView.hidden = gLargeIcons;
                labelView.alpha = gLargeIcons ? 0.0 : 1.0;
            }
        } @catch (NSException *e) {}
    }

    UIView *iconImgView = nil;
    @try {
        iconImgView = [self valueForKey:@"_iconImageView"];
    } @catch (NSException *e) {}

    if ([iconImgView isKindOfClass:[UIView class]]) {
        ApplyLiquidGlassToIcon(iconImgView);
    }
}

%end

%hook SBDockView
- (void)layoutSubviews {
    %orig;
    UIView *bgView = [self valueForKey:@"_backgroundView"];
    if (bgView && !bgView.hidden) {
        bgView.hidden = YES;
        bgView.alpha = 0.0;
    }

    UIView *glassDock = [self viewWithTag:27001];
    if (gDockStyle == 4) {
        if (glassDock) glassDock.hidden = YES;
        return;
    }

    if (!glassDock) {
        glassDock = [[UIView alloc] initWithFrame:CGRectZero];
        glassDock.tag = 27001;
        glassDock.userInteractionEnabled = NO;
        [self insertSubview:glassDock atIndex:0];
    }
    glassDock.hidden = NO;

    BOOL isVerticalSideDock = (self.bounds.size.height > self.bounds.size.width);

    CGRect targetFrame;
    CGFloat radius;
    CACornerMask mask = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;

    if (isVerticalSideDock) {
        targetFrame = CGRectInset(self.bounds, 5.0, 10.0);
        radius = 20.0;
    } else if (gDockStyle == 1) {
        targetFrame = self.bounds;
        radius = 22.0;
        mask = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else if (gDockStyle == 2) {
        targetFrame = CGRectInset(self.bounds, 18.0, 8.0);
        radius = 34.0;
    } else {
        targetFrame = CGRectInset(self.bounds, 10.0, 6.0);
        radius = 30.0;
    }

    if (!CGRectEqualToRect(glassDock.frame, targetFrame)) {
        glassDock.frame = targetFrame;
        ApplyFakeGlass(glassDock, radius, (gDockStyle == 3 ? MAX(gGlassAlpha, 0.52) : gGlassAlpha));
        if (gDockStyle == 3) {
            glassDock.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:0.58];
        }
        glassDock.layer.maskedCorners = mask;
    }
}
%end

%hook SBFloatyFolderView
- (void)layoutSubviews {
    %orig;
    UIView *bgView = [self valueForKey:@"_backgroundView"];
    if (bgView) {
        for (UIView *sub in bgView.subviews) {
            if (!sub.hidden) sub.hidden = YES;
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
            if (!sub.hidden) sub.hidden = YES;
        }
        ApplyFakeGlass(bgView, 16.0, gGlassAlpha);
    }
}
%end

%hook SBIconListPageControl

- (void)layoutSubviews {
    %orig;

    SBIconController *ic = [%c(SBIconController) sharedInstance];
    SBHIconManager *mgr = [ic respondsToSelector:@selector(iconManager)] ? [ic iconManager] : nil;
    BOOL isEditing = (mgr && [mgr respondsToSelector:@selector(isEditing)]) ? [mgr isEditing] : NO;

    UIButton *searchPill = (UIButton *)[self viewWithTag:27005];

    if (isEditing) {
        if (searchPill) searchPill.hidden = YES;
        for (UIView *sub in self.subviews) {
            if (sub.tag != 27005 && sub.hidden) {
                sub.hidden = NO;
                sub.alpha = 1.0;
            }
        }
        return;
    }

    for (UIView *sub in self.subviews) {
        if (sub.tag != 27005 && !sub.hidden) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }

    self.userInteractionEnabled = YES;

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

    searchPill.hidden = NO;
    CGFloat pillW = 86.0;
    CGFloat pillH = 26.0;
    CGRect target = CGRectMake((self.bounds.size.width - pillW) / 2.0, (self.bounds.size.height - pillH) / 2.0, pillW, pillH);
    if (!CGRectEqualToRect(searchPill.frame, target)) {
        searchPill.frame = target;
        ApplyFakeGlass(searchPill, pillH / 2.0, gGlassAlpha);
    }
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
        ReloadHomeScreenCache();
        %init(HomeScreenHooks);
    }
}
