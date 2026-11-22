#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <spawn.h>
#import "iOS27Prefs.h"

extern char **environ;

#define kIOS27CCEditChanged @"iOS27CCEditModeDidChange"
#define kIOS27CCStyleChanged @"iOS27CCStyleDidChange"

static BOOL gCCEditMode = NO;
static CGFloat gCCGlassAlpha = 0.28;
static NSSet<NSString *> *gCCHiddenSet = nil;
static NSDictionary<NSString *, NSNumber *> *gCCScalesDict = nil;

static void ReloadCCCache(void) {
    gCCGlassAlpha = iOS27FloatPref(@"kCCGlassIntensity", iOS27FloatPref(@"kGlassAlpha", 0.28));
    NSArray *arr = [iOS27SharedPrefs() arrayForKey:@"kCCHiddenModules"];
    gCCHiddenSet = [arr isKindOfClass:[NSArray class]] ? [NSSet setWithArray:arr] : [NSSet set];
    NSDictionary *dict = [iOS27SharedPrefs() dictionaryForKey:@"kCCModuleScales"];
    gCCScalesDict = [dict isKindOfClass:[NSDictionary class]] ? dict : @{};
}

static NSMutableArray<NSString *> *iOS27CCHiddenModules(void) {
    NSArray *arr = [iOS27SharedPrefs() arrayForKey:@"kCCHiddenModules"];
    return [arr isKindOfClass:[NSArray class]] ? [arr mutableCopy] : [NSMutableArray array];
}

static void iOS27CCSaveHiddenModules(NSArray<NSString *> *arr) {
    NSUserDefaults *prefs = iOS27SharedPrefs();
    [prefs setObject:(arr ?: @[]) forKey:@"kCCHiddenModules"];
    [prefs synchronize];
    ReloadCCCache();
}

static NSMutableDictionary<NSString *, NSNumber *> *iOS27CCModuleScales(void) {
    NSDictionary *dict = [iOS27SharedPrefs() dictionaryForKey:@"kCCModuleScales"];
    return [dict isKindOfClass:[NSDictionary class]] ? [dict mutableCopy] : [NSMutableDictionary dictionary];
}

static void iOS27CCSaveModuleScales(NSDictionary *dict) {
    NSUserDefaults *prefs = iOS27SharedPrefs();
    [prefs setObject:(dict ?: @{}) forKey:@"kCCModuleScales"];
    [prefs synchronize];
    ReloadCCCache();
}

@interface CCUIContentModuleContentContainerView : UIView
@end

@interface CCUIBaseSliderView : UIView
@end

@interface CCUIHeaderPocketView : UIView
@end

@interface CCUIContentModuleContainerViewController : UIViewController
- (NSString *)moduleIdentifier;
- (void)ios27_refreshEditBadges;
- (void)ios27_removeModuleTapped;
- (void)ios27_resizeHandleTapped;
@end

@interface CCUIModularControlCenterOverlayViewController : UIViewController
@end

@interface CCUIModularControlCenterOverlayViewController (iOS27CCEditor) <UIGestureRecognizerDelegate>
- (void)ios27_setupCCChrome;
- (void)ios27_handleDoubleTap:(UITapGestureRecognizer *)tap;
- (void)ios27_toggleEditMode;
- (void)ios27_openPowerMenu;
- (void)ios27_openAddControlGallery;
- (void)ios27_switchToPage:(UIButton *)sender;
- (void)ios27_dismissOverlays;
- (void)ios27_updateEditUI;
@end

// Zero-Lag Hardware Liquid Glass (No CAShapeLayer Mask!)
static void ApplyCCLiquidGlass(UIView *view, CGFloat radius, CGFloat alpha) {
    if (!view || CGRectIsEmpty(view.bounds)) return;

    view.backgroundColor = [UIColor colorWithRed:0.10 green:0.13 blue:0.20 alpha:alpha];
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.1;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.48].CGColor;
    view.clipsToBounds = YES;

    CAGradientLayer *sheen = nil;
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"iOS27CCSheen"]) {
            sheen = (CAGradientLayer *)layer;
            break;
        }
    }
    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.name = @"iOS27CCSheen";
        sheen.startPoint = CGPointMake(0.5, 0.0);
        sheen.endPoint = CGPointMake(0.5, 1.0);
        sheen.locations = @[@0.0, @0.42, @1.0];
        sheen.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.24].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.03].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor
        ];
        [view.layer insertSublayer:sheen atIndex:0];
    }
    if (!CGRectEqualToRect(sheen.frame, view.bounds)) {
        sheen.frame = view.bounds;
        sheen.cornerRadius = radius;
    }
}

static void StripHeavyBlurViews(UIView *view) {
    for (UIView *sub in view.subviews) {
        if (sub.hidden) continue;
        NSString *clsName = NSStringFromClass([sub class]);
        if ([clsName containsString:@"MTMaterialView"] || [clsName containsString:@"UIVisualEffectView"]) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }
}

static void iOS27SendMediaCommand(unsigned int cmd) {
    static void (*sendCmd)(unsigned int, NSDictionary *) = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (handle) {
            sendCmd = (void (*)(unsigned int, NSDictionary *))dlsym(handle, "MRMediaRemoteSendCommand");
        }
    });
    if (sendCmd) sendCmd(cmd, nil);
}

static void iOS27RunRootlessBinary(const char *path, char *const args[]) {
    pid_t pid;
    posix_spawn(&pid, path, NULL, NULL, args, environ);
}

@interface IOS27CCPowerSheet : UIView
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation IOS27CCPowerSheet

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        ApplyCCLiquidGlass(self, 26.0, 0.88);
        CGFloat w = frame.size.width;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, w - 32, 24)];
        title.text = @"iOS 27 Power Menu";
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        NSArray *actions = @[
            @{@"title": @"Respring SpringBoard", @"icon": @"arrow.clockwise", @"color": [UIColor systemBlueColor],   @"sel": @"doRespring"},
            @{@"title": @"Userspace Reboot",     @"icon": @"power",           @"color": [UIColor systemOrangeColor], @"sel": @"doUserspace"},
            @{@"title": @"Open Settings",        @"icon": @"gear",            @"color": [UIColor colorWithWhite:0.35 alpha:1.0], @"sel": @"doSettings"},
            @{@"title": @"Cancel",               @"icon": @"xmark",           @"color": [UIColor colorWithWhite:0.22 alpha:1.0], @"sel": @"doCancel"}
        ];

        for (NSInteger i = 0; i < (NSInteger)actions.count; i++) {
            NSDictionary *item = actions[i];
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(14.0, 46.0 + i * 48.0, w - 28.0, 40.0);
            btn.layer.cornerRadius = 14.0;
            btn.layer.cornerCurve = kCACornerCurveContinuous;
            btn.backgroundColor = item[@"color"];
            [btn setTitle:[NSString stringWithFormat:@"  %@", item[@"title"]] forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightSemibold];
                [btn setImage:[UIImage systemImageNamed:item[@"icon"] withConfiguration:cfg] forState:UIControlStateNormal];
                btn.tintColor = [UIColor whiteColor];
            }

            [btn addTarget:self action:NSSelectorFromString(item[@"sel"]) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:btn];
        }
    }
    return self;
}

- (void)doRespring {
    char *const args[] = { "sbreload", NULL };
    pid_t pid;
    if (posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, args, environ) != 0) {
        char *const killArgs[] = { "killall", "-9", "SpringBoard", NULL };
        iOS27RunRootlessBinary("/var/jb/usr/bin/killall", killArgs);
    }
}
- (void)doUserspace {
    char *const args[] = { "launchctl", "reboot", "userspace", NULL };
    iOS27RunRootlessBinary("/var/jb/usr/bin/launchctl", args);
}
- (void)doSettings {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:"] options:@{} completionHandler:nil];
    if (self.onClose) self.onClose();
}
- (void)doCancel {
    if (self.onClose) self.onClose();
}
@end

@interface IOS27CCGallerySheet : UIView
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UISlider *glassSlider;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation IOS27CCGallerySheet

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        ApplyCCLiquidGlass(self, 26.0, 0.92);
        CGFloat w = frame.size.width;
        CGFloat h = frame.size.height;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, w - 76, 26)];
        title.text = @"Controls Gallery";
        title.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightBold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(w - 44, 10, 32, 32);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
            [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
            closeBtn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.8];
        }
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 46, w, h - 46)];
        [self addSubview:self.scrollView];
        [self rebuildContent];
    }
    return self;
}

- (void)rebuildContent {
    for (UIView *sub in self.scrollView.subviews) [sub removeFromSuperview];

    CGFloat w = self.bounds.size.width;
    CGFloat y = 6.0;

    UILabel *sec1 = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 20)];
    sec1.text = @"LIQUID GLASS INTENSITY";
    sec1.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    sec1.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    [self.scrollView addSubview:sec1];
    y += 24.0;

    UIView *sliderCard = [[UIView alloc] initWithFrame:CGRectMake(14, y, w - 28, 46)];
    ApplyCCLiquidGlass(sliderCard, 16.0, 0.45);
    self.glassSlider = [[UISlider alloc] initWithFrame:CGRectMake(14, 8, sliderCard.bounds.size.width - 28, 30)];
    self.glassSlider.minimumValue = 0.14;
    self.glassSlider.maximumValue = 0.58;
    self.glassSlider.value = gCCGlassAlpha;
    self.glassSlider.minimumTrackTintColor = [UIColor whiteColor];
    [self.glassSlider addTarget:self action:@selector(glassSliderChanged) forControlEvents:UIControlEventValueChanged];
    [sliderCard addSubview:self.glassSlider];
    [self.scrollView addSubview:sliderCard];
    y += 58.0;

    NSMutableArray<NSString *> *hidden = iOS27CCHiddenModules();
    UILabel *sec2 = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 20)];
    sec2.text = hidden.count > 0 ? @"REMOVED CONTROLS (TAP TO ADD BACK)" : @"ALL CONTROLS ACTIVE";
    sec2.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    sec2.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    [self.scrollView addSubview:sec2];
    y += 24.0;

    if (hidden.count > 0) {
        for (NSInteger i = 0; i < (NSInteger)hidden.count; i++) {
            NSString *modID = hidden[i];
            NSString *shortName = [[modID componentsSeparatedByString:@"."] lastObject] ?: modID;
            shortName = [shortName stringByReplacingOccurrencesOfString:@"Module" withString:@""];

            UIButton *restoreBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            restoreBtn.tag = i;
            restoreBtn.frame = CGRectMake(14, y, w - 28, 40);
            ApplyCCLiquidGlass(restoreBtn, 14.0, 0.40);
            [restoreBtn setTitle:[NSString stringWithFormat:@"  +  Restore %@", shortName] forState:UIControlStateNormal];
            restoreBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            restoreBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
            [restoreBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [restoreBtn addTarget:self action:@selector(restoreModuleTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.scrollView addSubview:restoreBtn];
            y += 46.0;
        }
    }

    y += 6.0;
    UIButton *resetAllBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    resetAllBtn.frame = CGRectMake(14, y, w - 28, 42);
    resetAllBtn.layer.cornerRadius = 15.0;
    resetAllBtn.backgroundColor = [UIColor systemBlueColor];
    [resetAllBtn setTitle:@"Restore All Controls & Sizes" forState:UIControlStateNormal];
    resetAllBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    [resetAllBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [resetAllBtn addTarget:self action:@selector(resetAllTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:resetAllBtn];
    y += 52.0;

    UIButton *ccPrefsBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    ccPrefsBtn.frame = CGRectMake(14, y, w - 28, 42);
    ApplyCCLiquidGlass(ccPrefsBtn, 15.0, 0.45);
    [ccPrefsBtn setTitle:@"Add / Reorder in iOS Settings" forState:UIControlStateNormal];
    ccPrefsBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    [ccPrefsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [ccPrefsBtn addTarget:self action:@selector(openCCSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:ccPrefsBtn];
    y += 58.0;

    self.scrollView.contentSize = CGSizeMake(w, y);
}

- (void)glassSliderChanged {
    iOS27SetFloatPref(@"kCCGlassIntensity", self.glassSlider.value);
    ReloadCCCache();
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27CCStyleChanged object:nil];
}

- (void)restoreModuleTapped:(UIButton *)sender {
    NSMutableArray *hidden = iOS27CCHiddenModules();
    if (sender.tag >= 0 && sender.tag < (NSInteger)hidden.count) {
        [hidden removeObjectAtIndex:sender.tag];
        iOS27CCSaveHiddenModules(hidden);
        [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27CCEditChanged object:nil];
        [self rebuildContent];
    }
}

- (void)resetAllTapped {
    iOS27CCSaveHiddenModules(@[]);
    iOS27CCSaveModuleScales(@{});
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27CCEditChanged object:nil];
    [self rebuildContent];
}

- (void)openCCSettings {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=ControlCenter"] options:@{} completionHandler:nil];
    if (self.onClose) self.onClose();
}
- (void)closeTapped {
    if (self.onClose) self.onClose();
}
@end

@interface IOS27CCExtraPageView : UIView
@property (nonatomic, assign) NSInteger pageType;
@end

@implementation IOS27CCExtraPageView

- (instancetype)initWithFrame:(CGRect)frame pageType:(NSInteger)pageType {
    self = [super initWithFrame:frame];
    if (self) {
        self.pageType = pageType;
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.10 alpha:0.86];

        CGFloat w = frame.size.width;
        CGFloat h = frame.size.height;
        CGFloat contentW = w - 52.0;

        if (pageType == 1) {
            UIView *card = [[UIView alloc] initWithFrame:CGRectMake(18.0, floor((h - 240.0) / 2.0), contentW - 18.0, 240.0)];
            ApplyCCLiquidGlass(card, 30.0, 0.36);
            [self addSubview:card];

            UIImageView *art = [[UIImageView alloc] initWithFrame:CGRectMake(20, 22, 62, 62)];
            art.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
            art.layer.cornerRadius = 16.0;
            art.contentMode = UIViewContentModeCenter;
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightMedium];
                art.image = [UIImage systemImageNamed:@"music.note" withConfiguration:cfg];
                art.tintColor = [UIColor whiteColor];
            }
            [card addSubview:art];

            UILabel *nowLbl = [[UILabel alloc] initWithFrame:CGRectMake(94, 28, card.bounds.size.width - 108, 24)];
            nowLbl.text = @"Now Playing";
            nowLbl.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
            nowLbl.textColor = [UIColor whiteColor];
            [card addSubview:nowLbl];

            UILabel *subLbl = [[UILabel alloc] initWithFrame:CGRectMake(94, 54, card.bounds.size.width - 108, 20)];
            subLbl.text = @"iOS 27 Media Controls";
            subLbl.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
            subLbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
            [card addSubview:subLbl];

            UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(24, 118, card.bounds.size.width - 48, 56)];
            stack.axis = UILayoutConstraintAxisHorizontal;
            stack.distribution = UIStackViewDistributionFillEqually;
            stack.spacing = 12;

            [stack addArrangedSubview:[self mediaBtn:@"backward.fill" sel:@selector(mediaPrev)]];
            [stack addArrangedSubview:[self mediaBtn:@"playpause.fill" sel:@selector(mediaToggle)]];
            [stack addArrangedSubview:[self mediaBtn:@"forward.fill" sel:@selector(mediaNext)]];
            [card addSubview:stack];

            UISlider *bri = [[UISlider alloc] initWithFrame:CGRectMake(22, 190, card.bounds.size.width - 44, 30)];
            bri.minimumValue = 0.05;
            bri.maximumValue = 1.0;
            bri.value = [UIScreen mainScreen].brightness;
            bri.minimumTrackTintColor = [UIColor whiteColor];
            [bri addTarget:self action:@selector(briChanged:) forControlEvents:UIControlEventValueChanged];
            [card addSubview:bri];
        } else {
            NSArray *items = @[
                @{@"title": @"Wi-Fi",            @"icon": @"wifi",                              @"url": @"App-Prefs:root=WIFI"},
                @{@"title": @"Bluetooth",        @"icon": @"dot.radiowaves.left.and.right",     @"url": @"App-Prefs:root=Bluetooth"},
                @{@"title": @"Cellular Data",    @"icon": @"antenna.radiowaves.left.and.right", @"url": @"App-Prefs:root=MOBILE_DATA_SETTINGS_ID"},
                @{@"title": @"Personal Hotspot", @"icon": @"personalhotspot",                   @"url": @"App-Prefs:root=INTERNET_TETHERING"},
                @{@"title": @"AirDrop",          @"icon": @"airdrop",                           @"url": @"App-Prefs:root=General&path=AIRDROP"},
                @{@"title": @"Battery",          @"icon": @"battery.100",                       @"url": @"App-Prefs:root=BATTERY_USAGE"}
            ];

            CGFloat startY = (h > 600.0) ? 100.0 : 62.0;
            CGFloat rowH = 54.0;
            for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
                NSDictionary *it = items[i];
                UIButton *pill = [UIButton buttonWithType:UIButtonTypeCustom];
                pill.tag = i;
                pill.frame = CGRectMake(18.0, startY + i * (rowH + 10.0), contentW - 18.0, rowH);
                ApplyCCLiquidGlass(pill, rowH / 2.0, 0.38);
                pill.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
                pill.contentEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 18);
                pill.titleEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
                [pill setTitle:it[@"title"] forState:UIControlStateNormal];
                pill.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
                [pill setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

                if (@available(iOS 13.0, *)) {
                    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
                    UIImage *img = [UIImage systemImageNamed:it[@"icon"] withConfiguration:cfg];
                    [pill setImage:img forState:UIControlStateNormal];
                    pill.tintColor = [UIColor colorWithRed:0.45 green:0.82 blue:1.0 alpha:1.0];
                }

                objc_setAssociatedObject(pill, "prefURL", it[@"url"], OBJC_ASSOCIATION_COPY_NONATOMIC);
                [pill addTarget:self action:@selector(openConnURL:) forControlEvents:UIControlEventTouchUpInside];
                [self addSubview:pill];
            }
        }
    }
    return self;
}

- (UIButton *)mediaBtn:(NSString *)symbol sel:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    ApplyCCLiquidGlass(b, 20.0, 0.35);
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold];
        [b setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
        b.tintColor = [UIColor whiteColor];
    }
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)mediaPrev { iOS27SendMediaCommand(5); }
- (void)mediaToggle { iOS27SendMediaCommand(2); }
- (void)mediaNext { iOS27SendMediaCommand(4); }
- (void)briChanged:(UISlider *)s { [UIScreen mainScreen].brightness = s.value; }

- (void)openConnURL:(UIButton *)sender {
    NSString *urlStr = objc_getAssociatedObject(sender, "prefURL");
    if (urlStr) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlStr] options:@{} completionHandler:nil];
    }
}
@end

static const void *kCCChromeSetupKey = &kCCChromeSetupKey;
static const void *kCCPlusBtnKey = &kCCPlusBtnKey;
static const void *kCCPowerBtnKey = &kCCPowerBtnKey;
static const void *kCCAddControlBtnKey = &kCCAddControlBtnKey;
static const void *kCCRailViewKey = &kCCRailViewKey;
static const void *kCCExtraPageKey = &kCCExtraPageKey;
static const void *kCCModalOverlayKey = &kCCModalOverlayKey;

%group ControlCenterHooks

%hook CCUIContentModuleContentContainerView
- (void)layoutSubviews {
    %orig;
    StripHeavyBlurViews(self);
    CGFloat minSide = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat radius = (minSide > 0 && minSide <= 82.0) ? (minSide / 2.0) : 30.0;
    ApplyCCLiquidGlass(self, radius, gCCGlassAlpha);
}
%end

%hook CCUIBaseSliderView
- (void)layoutSubviews {
    %orig;
    StripHeavyBlurViews(self);
    CGFloat minSide = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat radius = (minSide > 0) ? MIN(minSide / 2.0, 32.0) : 28.0;
    ApplyCCLiquidGlass(self, radius, gCCGlassAlpha);
}
%end

%hook CCUIHeaderPocketView
- (void)layoutSubviews {
    %orig;
    StripHeavyBlurViews(self);
}
%end

%hook CCUIContentModuleContainerViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ios27_refreshEditBadges) name:kIOS27CCEditChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ios27_refreshEditBadges) name:kIOS27CCStyleChanged object:nil];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [self ios27_refreshEditBadges];
}

%new
- (void)ios27_refreshEditBadges {
    UIView *v = self.view;
    if (!v) return;

    NSString *modID = [self respondsToSelector:@selector(moduleIdentifier)] ? [self moduleIdentifier] : @"";
    BOOL isHidden = (modID.length > 0 && [gCCHiddenSet containsObject:modID]);

    if (v.hidden != isHidden) {
        v.hidden = isHidden;
        v.alpha = isHidden ? 0.0 : 1.0;
    }

    NSInteger scaleMode = (modID.length > 0) ? [gCCScalesDict[modID] integerValue] : 0;
    CGFloat scaleVal = (scaleMode == 1) ? 0.88 : ((scaleMode == 2) ? 1.06 : 1.0);
    CGAffineTransform targetT = CGAffineTransformMakeScale(scaleVal, scaleVal);
    if (!CGAffineTransformEqualToTransform(v.transform, targetT)) {
        v.transform = targetT;
    }

    UIButton *minusBtn = (UIButton *)[v viewWithTag:27611];
    UIButton *resizeBtn = (UIButton *)[v viewWithTag:27612];

    if (!gCCEditMode || isHidden) {
        if (minusBtn && !minusBtn.hidden) minusBtn.hidden = YES;
        if (resizeBtn && !resizeBtn.hidden) resizeBtn.hidden = YES;
        if ([v.layer animationForKey:@"iOS27Jiggle"]) [v.layer removeAnimationForKey:@"iOS27Jiggle"];
        return;
    }

    v.clipsToBounds = NO;

    if (!minusBtn) {
        minusBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        minusBtn.tag = 27611;
        minusBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.92];
        minusBtn.layer.cornerRadius = 11.0;
        minusBtn.layer.borderWidth = 1.0;
        minusBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:10.5 weight:UIImageSymbolWeightBold];
            [minusBtn setImage:[UIImage systemImageNamed:@"minus" withConfiguration:cfg] forState:UIControlStateNormal];
            minusBtn.tintColor = [UIColor whiteColor];
        }
        [minusBtn addTarget:self action:@selector(ios27_removeModuleTapped) forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:minusBtn];
    }
    minusBtn.frame = CGRectMake(-4.0, -4.0, 22.0, 22.0);
    minusBtn.hidden = NO;
    [v bringSubviewToFront:minusBtn];

    if (!resizeBtn) {
        resizeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        resizeBtn.tag = 27612;
        resizeBtn.backgroundColor = [UIColor clearColor];

        CAShapeLayer *arc = [CAShapeLayer layer];
        arc.fillColor = [UIColor clearColor].CGColor;
        arc.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
        arc.lineWidth = 4.0;
        arc.lineCap = kCALineCapRound;
        UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:CGPointMake(6.0, 6.0)
                                                         radius:14.0
                                                     startAngle:0.08
                                                       endAngle:M_PI_2 - 0.08
                                                      clockwise:YES];
        arc.path = p.CGPath;
        [resizeBtn.layer addSublayer:arc];
        [resizeBtn addTarget:self action:@selector(ios27_resizeHandleTapped) forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:resizeBtn];
    }
    resizeBtn.frame = CGRectMake(v.bounds.size.width - 22.0, v.bounds.size.height - 22.0, 24.0, 24.0);
    resizeBtn.hidden = NO;
    [v bringSubviewToFront:resizeBtn];

    if (![v.layer animationForKey:@"iOS27Jiggle"]) {
        CAKeyframeAnimation *jiggle = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation"];
        jiggle.values = @[@(-0.018), @(0.018), @(-0.018)];
        jiggle.duration = 0.28;
        jiggle.repeatCount = HUGE_VALF;
        [v.layer addAnimation:jiggle forKey:@"iOS27Jiggle"];
    }
}

%new
- (void)ios27_removeModuleTapped {
    NSString *modID = [self respondsToSelector:@selector(moduleIdentifier)] ? [self moduleIdentifier] : @"";
    if (modID.length == 0) return;

    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [h impactOccurred];

    NSMutableArray *hidden = iOS27CCHiddenModules();
    if (![hidden containsObject:modID]) {
        [hidden addObject:modID];
        iOS27CCSaveHiddenModules(hidden);
    }
    [self ios27_refreshEditBadges];
}

%new
- (void)ios27_resizeHandleTapped {
    NSString *modID = [self respondsToSelector:@selector(moduleIdentifier)] ? [self moduleIdentifier] : @"";
    if (modID.length == 0) return;

    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [h impactOccurred];

    NSMutableDictionary *scales = iOS27CCModuleScales();
    NSInteger cur = [scales[modID] integerValue];
    scales[modID] = @((cur + 1) % 3);
    iOS27CCSaveModuleScales(scales);

    [UIView animateWithDuration:0.20 animations:^{
        [self ios27_refreshEditBadges];
    }];
}

%end

%hook CCUIModularControlCenterOverlayViewController

- (void)viewDidLoad {
    %orig;
    [self ios27_setupCCChrome];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self ios27_setupCCChrome];
    [self ios27_updateEditUI];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (gCCEditMode) {
        gCCEditMode = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27CCEditChanged object:nil];
    }
    [self ios27_dismissOverlays];
}

- (void)viewDidLayoutSubviews {
    %orig;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat topY = (h > 600.0) ? 44.0 : 12.0;

    UIButton *plusBtn = objc_getAssociatedObject(self, kCCPlusBtnKey);
    UIButton *powerBtn = objc_getAssociatedObject(self, kCCPowerBtnKey);
    UIButton *addCtrlBtn = objc_getAssociatedObject(self, kCCAddControlBtnKey);
    UIView *rail = objc_getAssociatedObject(self, kCCRailViewKey);

    if (plusBtn) {
        plusBtn.frame = CGRectMake(14.0, topY, 34.0, 34.0);
        [self.view bringSubviewToFront:plusBtn];
    }
    if (powerBtn) {
        powerBtn.frame = CGRectMake(w - 48.0, topY, 34.0, 34.0);
        [self.view bringSubviewToFront:powerBtn];
    }
    if (addCtrlBtn) {
        addCtrlBtn.frame = CGRectMake((w - 166.0) / 2.0, h - 52.0, 166.0, 36.0);
        [self.view bringSubviewToFront:addCtrlBtn];
    }
    if (rail) {
        CGFloat railH = 148.0;
        rail.frame = CGRectMake(w - 26.0, floor((h - railH) / 2.0), 24.0, railH);
        [self.view bringSubviewToFront:rail];
    }
}

%new
- (void)ios27_setupCCChrome {
    if (objc_getAssociatedObject(self, kCCChromeSetupKey)) return;
    objc_setAssociatedObject(self, kCCChromeSetupKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITapGestureRecognizer *dblTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ios27_handleDoubleTap:)];
    dblTap.numberOfTapsRequired = 2;
    dblTap.cancelsTouchesInView = NO;
    dblTap.delegate = self;
    [self.view addGestureRecognizer:dblTap];

    UIButton *plusBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    plusBtn.frame = CGRectMake(14.0, 12.0, 34.0, 34.0);
    ApplyCCLiquidGlass(plusBtn, 17.0, 0.45);
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightBold];
        [plusBtn setImage:[UIImage systemImageNamed:@"plus" withConfiguration:cfg] forState:UIControlStateNormal];
        plusBtn.tintColor = [UIColor whiteColor];
    }
    [plusBtn addTarget:self action:@selector(ios27_toggleEditMode) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:plusBtn];
    objc_setAssociatedObject(self, kCCPlusBtnKey, plusBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *powerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    powerBtn.frame = CGRectMake(self.view.bounds.size.width - 48.0, 12.0, 34.0, 34.0);
    ApplyCCLiquidGlass(powerBtn, 17.0, 0.45);
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightBold];
        [powerBtn setImage:[UIImage systemImageNamed:@"power" withConfiguration:cfg] forState:UIControlStateNormal];
        powerBtn.tintColor = [UIColor whiteColor];
    }
    [powerBtn addTarget:self action:@selector(ios27_openPowerMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:powerBtn];
    objc_setAssociatedObject(self, kCCPowerBtnKey, powerBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *addCtrlBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    addCtrlBtn.frame = CGRectMake((self.view.bounds.size.width - 166.0) / 2.0, self.view.bounds.size.height - 52.0, 166.0, 36.0);
    ApplyCCLiquidGlass(addCtrlBtn, 18.0, 0.65);
    [addCtrlBtn setTitle:@" Add a Control" forState:UIControlStateNormal];
    addCtrlBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    [addCtrlBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13.5 weight:UIImageSymbolWeightBold];
        [addCtrlBtn setImage:[UIImage systemImageNamed:@"plus.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
        addCtrlBtn.tintColor = [UIColor whiteColor];
    }
    addCtrlBtn.hidden = YES;
    [addCtrlBtn addTarget:self action:@selector(ios27_openAddControlGallery) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:addCtrlBtn];
    objc_setAssociatedObject(self, kCCAddControlBtnKey, addCtrlBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *rail = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 26.0, 200.0, 24.0, 148.0)];
    rail.backgroundColor = [UIColor clearColor];

    NSArray *railIcons = @[@"heart.fill", @"music.note", @"antenna.radiowaves.left.and.right", @"circle"];
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *rb = [UIButton buttonWithType:UIButtonTypeCustom];
        rb.tag = 27650 + i;
        rb.frame = CGRectMake(0, i * 36.0, 24.0, 30.0);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightBold];
            [rb setImage:[UIImage systemImageNamed:railIcons[i] withConfiguration:cfg] forState:UIControlStateNormal];
            rb.tintColor = (i == 0) ? [UIColor whiteColor] : [UIColor colorWithWhite:1.0 alpha:0.45];
        }
        if (i == 3) rb.hidden = YES;
        [rb addTarget:self action:@selector(ios27_switchToPage:) forControlEvents:UIControlEventTouchUpInside];
        [rail addSubview:rb];
    }
    [self.view addSubview:rail];
    objc_setAssociatedObject(self, kCCRailViewKey, rail, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *v = touch.view;
    while (v && v != self.view) {
        if ([v isKindOfClass:[UIControl class]]) return NO;
        v = v.superview;
    }
    return YES;
}

%new
- (void)ios27_handleDoubleTap:(UITapGestureRecognizer *)tap {
    [self ios27_toggleEditMode];
}

%new
- (void)ios27_toggleEditMode {
    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [h impactOccurred];

    gCCEditMode = !gCCEditMode;
    [self ios27_updateEditUI];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27CCEditChanged object:nil];
}

%new
- (void)ios27_updateEditUI {
    UIButton *plusBtn = objc_getAssociatedObject(self, kCCPlusBtnKey);
    UIButton *addCtrlBtn = objc_getAssociatedObject(self, kCCAddControlBtnKey);
    UIView *rail = objc_getAssociatedObject(self, kCCRailViewKey);
    UIView *circleBtn = [rail viewWithTag:27653];

    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightBold];
        NSString *sym = gCCEditMode ? @"checkmark" : @"plus";
        [plusBtn setImage:[UIImage systemImageNamed:sym withConfiguration:cfg] forState:UIControlStateNormal];
    }
    addCtrlBtn.hidden = !gCCEditMode;
    circleBtn.hidden = !gCCEditMode;
}

%new
- (void)ios27_switchToPage:(UIButton *)sender {
    NSInteger pageIdx = sender.tag - 27650;
    if (pageIdx == 3) {
        [self ios27_openAddControlGallery];
        return;
    }

    UIView *rail = objc_getAssociatedObject(self, kCCRailViewKey);
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *rb = (UIButton *)[rail viewWithTag:27650 + i];
        rb.tintColor = (i == pageIdx) ? [UIColor whiteColor] : [UIColor colorWithWhite:1.0 alpha:0.45];
    }

    UIView *oldExtra = objc_getAssociatedObject(self, kCCExtraPageKey);
    if (oldExtra) {
        [oldExtra removeFromSuperview];
        objc_setAssociatedObject(self, kCCExtraPageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (pageIdx == 0) return;

    IOS27CCExtraPageView *extra = [[IOS27CCExtraPageView alloc] initWithFrame:self.view.bounds pageType:pageIdx];
    extra.alpha = 0.0;
    [self.view addSubview:extra];
    objc_setAssociatedObject(self, kCCExtraPageKey, extra, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *plusBtn = objc_getAssociatedObject(self, kCCPlusBtnKey);
    UIView *powerBtn = objc_getAssociatedObject(self, kCCPowerBtnKey);
    if (plusBtn) [self.view bringSubviewToFront:plusBtn];
    if (powerBtn) [self.view bringSubviewToFront:powerBtn];
    if (rail) [self.view bringSubviewToFront:rail];

    [UIView animateWithDuration:0.22 animations:^{
        extra.alpha = 1.0;
    }];
}

%new
- (void)ios27_openPowerMenu {
    [self ios27_dismissOverlays];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat sheetW = MIN(w - 32.0, 280.0);
    CGFloat sheetH = 248.0;

    UIView *backdrop = [[UIView alloc] initWithFrame:self.view.bounds];
    backdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    [self.view addSubview:backdrop];
    objc_setAssociatedObject(self, kCCModalOverlayKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    IOS27CCPowerSheet *sheet = [[IOS27CCPowerSheet alloc] initWithFrame:CGRectMake((w - sheetW) / 2.0, (h - sheetH) / 2.0, sheetW, sheetH)];
    sheet.transform = CGAffineTransformMakeScale(0.88, 0.88);
    sheet.alpha = 0.0;
    [backdrop addSubview:sheet];

    __weak typeof(self) weakSelf = self;
    sheet.onClose = ^{
        [weakSelf ios27_dismissOverlays];
    };

    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
        sheet.transform = CGAffineTransformIdentity;
        sheet.alpha = 1.0;
    } completion:nil];
}

%new
- (void)ios27_openAddControlGallery {
    [self ios27_dismissOverlays];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat sheetH = h * 0.64;

    UIView *backdrop = [[UIView alloc] initWithFrame:self.view.bounds];
    backdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.42];
    [self.view addSubview:backdrop];
    objc_setAssociatedObject(self, kCCModalOverlayKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    IOS27CCGallerySheet *sheet = [[IOS27CCGallerySheet alloc] initWithFrame:CGRectMake(10.0, h, w - 20.0, sheetH)];
    [backdrop addSubview:sheet];

    __weak typeof(self) weakSelf = self;
    sheet.onClose = ^{
        [weakSelf ios27_dismissOverlays];
    };

    [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        sheet.frame = CGRectMake(10.0, h - sheetH - 12.0, w - 20.0, sheetH);
    } completion:nil];
}

%new
- (void)ios27_dismissOverlays {
    UIView *modal = objc_getAssociatedObject(self, kCCModalOverlayKey);
    if (modal) {
        [modal removeFromSuperview];
        objc_setAssociatedObject(self, kCCModalOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *extra = objc_getAssociatedObject(self, kCCExtraPageKey);
    if (extra) {
        [extra removeFromSuperview];
        objc_setAssociatedObject(self, kCCExtraPageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

%end

%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (iOS27BoolPref(@"kEnabled", YES) && iOS27BoolPref(@"kEnableCC", YES)) {
        ReloadCCCache();
        %init(ControlCenterHooks);
    }
}
