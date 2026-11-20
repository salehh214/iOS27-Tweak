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

// Shared Fake-Glass Style for Dock, Folders & Search Pill
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

// =========================================================================
// Universal iOS 27 Liquid Glass Icon Engine (ALL System + 3rd Party Apps)
// Zero UIVisualEffectView — Pure GPU CoreAnimation for 2GB RAM 60fps Speed
// =========================================================================
static void ApplyLiquidGlassToIcon(UIView *iconImgView, NSInteger iconStyle, NSInteger subMode, CGFloat tintHue, CGFloat tintBri) {
    if (!iconImgView) return;

    CGRect bounds = iconImgView.bounds;
    // Apply strictly to square app icons (skips rectangular widgets & folder containers)
    if (CGRectIsEmpty(bounds) || bounds.size.width < 32.0 || bounds.size.width > 95.0) return;
    if (fabs(bounds.size.width - bounds.size.height) > 4.0) return;
    if ([iconImgView isKindOfClass:NSClassFromString(@"SBFolderIconImageView")]) return;

    CGFloat radius = floor(bounds.size.width * 0.225);

    UIView *glassShell = [iconImgView viewWithTag:27888];
    if (!glassShell) {
        glassShell = [[UIView alloc] initWithFrame:bounds];
        glassShell.tag = 27888;
        glassShell.userInteractionEnabled = NO;
        glassShell.clipsToBounds = YES;
        glassShell.layer.cornerCurve = kCACornerCurveContinuous;
        glassShell.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [iconImgView addSubview:glassShell];
    }

    BOOL sizeChanged = !CGRectEqualToRect(glassShell.bounds, bounds);
    if (sizeChanged) {
        glassShell.frame = bounds;
    }
    glassShell.layer.cornerRadius = radius;
    glassShell.hidden = NO;
    [iconImgView bringSubviewToFront:glassShell];

    // 1. Top/Bottom Centered Liquid Glass Dome Reflection Layer
    CAGradientLayer *domeLayer = nil;
    // 2. Crisp Specular Rim Border Gradient Layer (Masked to Squircle Stroke)
    CAGradientLayer *rimGrad = nil;

    for (CALayer *layer in glassShell.layer.sublayers) {
        if ([layer.name isEqualToString:@"iOS27IconDome"]) {
            domeLayer = (CAGradientLayer *)layer;
        } else if ([layer.name isEqualToString:@"iOS27IconSpecularRim"]) {
            rimGrad = (CAGradientLayer *)layer;
        }
    }

    if (!domeLayer) {
        domeLayer = [CAGradientLayer layer];
        domeLayer.name = @"iOS27IconDome";
        domeLayer.startPoint = CGPointMake(0.5, 0.0);
        domeLayer.endPoint = CGPointMake(0.5, 1.0);
        domeLayer.locations = @[@0.0, @0.32, @0.68, @1.0];
        [glassShell.layer insertSublayer:domeLayer atIndex:0];
    }

    if (!rimGrad) {
        rimGrad = [CAGradientLayer layer];
        rimGrad.name = @"iOS27IconSpecularRim";
        rimGrad.startPoint = CGPointMake(0.25, 0.0);
        rimGrad.endPoint = CGPointMake(0.75, 1.0);
        rimGrad.locations = @[@0.0, @0.45, @0.75, @1.0];

        CAShapeLayer *rimMask = [CAShapeLayer layer];
        rimMask.fillColor = [UIColor clearColor].CGColor;
        rimMask.strokeColor = [UIColor whiteColor].CGColor;
        rimMask.lineWidth = 2.6; // Clipped by glassShell -> razor-sharp ~1.3pt glass rim
        rimGrad.mask = rimMask;

        [glassShell.layer addSublayer:rimGrad];
    }

    if (sizeChanged || CGRectIsEmpty(domeLayer.frame)) {
        domeLayer.frame = bounds;
        domeLayer.cornerRadius = radius;
        rimGrad.frame = bounds;

        CAShapeLayer *rimMask = (CAShapeLayer *)rimGrad.mask;
        rimMask.frame = bounds;
        rimMask.path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius].CGPath;
    }

    // Apply Mode-Specific iOS 27 Liquid Glass Material
    if (iconStyle == 0) {
        // MODE 0: Default Vibrant Liquid Glass (Every app keeps its colors + crystal glass dome & rim)
        iconImgView.alpha = 1.0;
        glassShell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
        domeLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.34].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.03].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.18].CGColor
        ];
        rimGrad.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.88].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.18].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.65].CGColor
        ];
    } else if (iconStyle == 1) {
        // MODE 1: Dark Smoked Liquid Glass (Always / Auto)
        iconImgView.alpha = 0.96;
        CGFloat darkAlpha = (subMode == 0) ? 0.36 : 0.24;
        glassShell.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:darkAlpha];
        domeLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.24].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.02].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.12].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor
        ];
        rimGrad.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.68].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.45].CGColor
        ];
    } else if (iconStyle == 2) {
        // MODE 2: Clear Translucent Liquid Glass (Light / Dark / Auto)
        if (subMode == 1) {
            // Clear Dark Glass
            iconImgView.alpha = 0.68;
            glassShell.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:0.38];
            domeLayer.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.36].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor,
                (id)[UIColor colorWithWhite:0.0 alpha:0.10].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.22].CGColor
            ];
            rimGrad.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.85].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.22].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.18].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.68].CGColor
            ];
        } else {
            // Clear Light Crystal Glass
            iconImgView.alpha = 0.72;
            glassShell.backgroundColor = [UIColor colorWithWhite:0.96 alpha:0.24];
            domeLayer.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.52].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.30].CGColor
            ];
            rimGrad.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.98].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.34].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.28].CGColor,
                (id)[UIColor colorWithWhite:1.0 alpha:0.82].CGColor
            ];
        }
    } else {
        // MODE 3: Tinted Liquid Glass (Live Rainbow Hue + Brightness)
        iconImgView.alpha = (subMode == 1) ? 0.85 : 0.90;
        CGFloat tintAlpha = (subMode == 1) ? 0.56 : 0.44;
        UIColor *tintCol = [UIColor colorWithHue:tintHue saturation:0.80 brightness:tintBri alpha:tintAlpha];
        UIColor *rimBright = [UIColor colorWithHue:tintHue saturation:0.45 brightness:MIN(tintBri + 0.20, 1.0) alpha:0.95];
        UIColor *rimSoft = [UIColor colorWithHue:tintHue saturation:0.65 brightness:tintBri alpha:0.28];

        glassShell.backgroundColor = tintCol;
        domeLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.36].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.06].CGColor,
            (id)[UIColor colorWithHue:tintHue saturation:0.50 brightness:1.0 alpha:0.22].CGColor
        ];
        rimGrad.colors = @[
            (id)rimBright.CGColor,
            (id)rimSoft.CGColor,
            (id)rimSoft.CGColor,
            (id)rimBright.CGColor
        ];
    }
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
    BOOL largeIcons = iOS27BoolPref(@"kHSLargeIcons", YES);
    %orig(largeIcons ? YES : hidden);
}

- (void)layoutSubviews {
    %orig;

    BOOL largeIcons = iOS27BoolPref(@"kHSLargeIcons", YES);
    CGFloat scale = largeIcons ? 1.06 : 0.94;
    self.transform = CGAffineTransformMakeScale(scale, scale);

    @try {
        UIView *labelView = [self valueForKey:@"_labelView"];
        if ([labelView isKindOfClass:[UIView class]]) {
            labelView.hidden = largeIcons;
            labelView.alpha = largeIcons ? 0.0 : 1.0;
        }
    } @catch (NSException *e) {}

    NSInteger iconStyle = iOS27IntPref(@"kHSIconStyle", 0);
    NSInteger subMode = iOS27IntPref(@"kHSIconSubMode", 0);
    CGFloat tintHue = iOS27FloatPref(@"kHSTintHue", 0.55);
    CGFloat tintBri = iOS27FloatPref(@"kHSTintBrightness", 0.85);

    UIView *iconImgView = nil;
    @try {
        iconImgView = [self valueForKey:@"_iconImageView"];
    } @catch (NSException *e) {}

    if ([iconImgView isKindOfClass:[UIView class]]) {
        ApplyLiquidGlassToIcon(iconImgView, iconStyle, subMode, tintHue, tintBri);
    }
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

    SBIconController *ic = [%c(SBIconController) sharedInstance];
    SBHIconManager *mgr = [ic respondsToSelector:@selector(iconManager)] ? [ic iconManager] : nil;
    BOOL isEditing = (mgr && [mgr respondsToSelector:@selector(isEditing)]) ? [mgr isEditing] : NO;

    UIButton *searchPill = (UIButton *)[self viewWithTag:27005];

    if (isEditing) {
        if (searchPill) searchPill.hidden = YES;
        for (UIView *sub in self.subviews) {
            if (sub.tag != 27005) {
                sub.hidden = NO;
                sub.alpha = 1.0;
            }
        }
        return;
    }

    for (UIView *sub in self.subviews) {
        if (sub.tag != 27005) {
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
