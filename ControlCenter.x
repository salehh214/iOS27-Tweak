#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <spawn.h>
#import "iOS27Prefs.h"

extern char **environ;

static CGFloat gCCGlassAlpha = 0.28;

@interface CCUIModularControlCenterOverlayViewController : UIViewController
@end

// =========================================================================
// 1. Safe System Hardware & Toggle Controllers (Zero Private Framework Linking)
// =========================================================================
static void iOS27RunRootlessBin(const char *path, char *const args[]) {
    pid_t pid;
    posix_spawn(&pid, path, NULL, NULL, args, environ);
}

static void iOS27SendMediaCmd(unsigned int cmd) {
    static void (*sendCmd)(unsigned int, NSDictionary *) = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (h) sendCmd = (void (*)(unsigned int, NSDictionary *))dlsym(h, "MRMediaRemoteSendCommand");
    });
    if (sendCmd) sendCmd(cmd, nil);
}

static BOOL iOS27IsWiFiOn(void) {
    Class cls = NSClassFromString(@"SBWiFiManager");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        id mgr = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        SEL sel = NSSelectorFromString(@"wiFiEnabled");
        if (mgr && [mgr respondsToSelector:sel]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(mgr, sel);
        }
    }
    return YES;
}

static void iOS27ToggleWiFi(void) {
    Class cls = NSClassFromString(@"SBWiFiManager");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        id mgr = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        SEL setSel = NSSelectorFromString(@"setWiFiEnabled:");
        if (mgr && [mgr respondsToSelector:setSel]) {
            BOOL cur = iOS27IsWiFiOn();
            ((void (*)(id, SEL, BOOL))objc_msgSend)(mgr, setSel, !cur);
            return;
        }
    }
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=WIFI"] options:@{} completionHandler:nil];
}

static id iOS27BTManager(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
    });
    Class cls = NSClassFromString(@"BluetoothManager");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        return ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
    }
    return nil;
}

static BOOL iOS27IsBluetoothOn(void) {
    id mgr = iOS27BTManager();
    SEL sel = NSSelectorFromString(@"powered");
    if (mgr && [mgr respondsToSelector:sel]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(mgr, sel);
    }
    return NO;
}

static void iOS27ToggleBluetooth(void) {
    id mgr = iOS27BTManager();
    if (mgr) {
        BOOL next = !iOS27IsBluetoothOn();
        SEL setPow = NSSelectorFromString(@"setPowered:");
        SEL setEn = NSSelectorFromString(@"setEnabled:");
        if ([mgr respondsToSelector:setPow]) ((void (*)(id, SEL, BOOL))objc_msgSend)(mgr, setPow, next);
        if ([mgr respondsToSelector:setEn]) ((void (*)(id, SEL, BOOL))objc_msgSend)(mgr, setEn, next);
        return;
    }
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=Bluetooth"] options:@{} completionHandler:nil];
}

static BOOL iOS27IsAirplaneOn(void) {
    Class cls = NSClassFromString(@"SBAirplaneModeController");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        id mgr = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        SEL sel = NSSelectorFromString(@"isInAirplaneMode");
        if (mgr && [mgr respondsToSelector:sel]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(mgr, sel);
        }
    }
    return NO;
}

static void iOS27ToggleAirplane(void) {
    Class cls = NSClassFromString(@"SBAirplaneModeController");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        id mgr = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        SEL setSel = NSSelectorFromString(@"setInAirplaneMode:");
        if (mgr && [mgr respondsToSelector:setSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(mgr, setSel, !iOS27IsAirplaneOn());
            return;
        }
    }
}

static BOOL iOS27IsTorchOn(void) {
    AVCaptureDevice *dev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (dev && [dev hasTorch]) {
        return dev.torchMode == AVCaptureTorchModeOn;
    }
    return NO;
}

static void iOS27ToggleTorch(void) {
    AVCaptureDevice *dev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (dev && [dev hasTorch]) {
        if ([dev lockForConfiguration:nil]) {
            dev.torchMode = (dev.torchMode == AVCaptureTorchModeOn) ? AVCaptureTorchModeOff : AVCaptureTorchModeOn;
            [dev unlockForConfiguration];
        }
    }
}

static BOOL iOS27IsOrientationLocked(void) {
    Class cls = NSClassFromString(@"SBOrientationLockManager");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        id mgr = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        SEL sel = NSSelectorFromString(@"isUserLocked");
        if (mgr && [mgr respondsToSelector:sel]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(mgr, sel);
        }
    }
    return NO;
}

static void iOS27ToggleOrientationLock(void) {
    Class cls = NSClassFromString(@"SBOrientationLockManager");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        id mgr = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
        if (mgr) {
            BOOL locked = iOS27IsOrientationLocked();
            SEL sel = NSSelectorFromString(locked ? @"unlock" : @"lock");
            if ([mgr respondsToSelector:sel]) {
                ((void (*)(id, SEL))objc_msgSend)(mgr, sel);
            }
        }
    }
}

static BOOL iOS27IsDarkModeOn(void) {
    if (@available(iOS 13.0, *)) {
        return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return YES;
}

static void iOS27ToggleDarkMode(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/UIKitServices.framework/UIKitServices", RTLD_LAZY);
    });
    Class cls = NSClassFromString(@"UISUserInterfaceStyleMode");
    if (cls) {
        id mode = [[cls alloc] init];
        SEL setSel = NSSelectorFromString(@"setModeValue:");
        if (mode && [mode respondsToSelector:setSel]) {
            long long nextVal = iOS27IsDarkModeOn() ? 1 : 2; // 1 = Light, 2 = Dark
            ((void (*)(id, SEL, long long))objc_msgSend)(mode, setSel, nextVal);
            return;
        }
    }
}

static BOOL iOS27IsLowPowerOn(void) {
    return [NSProcessInfo processInfo].lowPowerModeEnabled;
}

static void iOS27ToggleLowPower(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/CoreDuet.framework/CoreDuet", RTLD_LAZY);
    });
    Class cls = NSClassFromString(@"_CDBatterySaver");
    if (cls && [cls respondsToSelector:@selector(batterySaver)]) {
        id saver = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(batterySaver));
        SEL setSel = NSSelectorFromString(@"setPowerMode:error:");
        if (saver && [saver respondsToSelector:setSel]) {
            long long nextMode = iOS27IsLowPowerOn() ? 0 : 1;
            NSError *err = nil;
            ((BOOL (*)(id, SEL, long long, NSError **))objc_msgSend)(saver, setSel, nextMode, &err);
        }
    }
}

static float iOS27GetSystemVolume(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience", RTLD_LAZY);
    });
    Class cls = NSClassFromString(@"AVSystemController");
    if (cls && [cls respondsToSelector:@selector(sharedAVSystemController)]) {
        id ctrl = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedAVSystemController));
        SEL getSel = NSSelectorFromString(@"getVolume:forCategory:");
        if (ctrl && [ctrl respondsToSelector:getSel]) {
            float vol = 0.5f;
            ((BOOL (*)(id, SEL, float *, NSString *))objc_msgSend)(ctrl, getSel, &vol, @"Audio/Video");
            return vol;
        }
    }
    return [AVAudioSession sharedInstance].outputVolume;
}

static void iOS27SetSystemVolume(float vol) {
    Class cls = NSClassFromString(@"AVSystemController");
    if (cls && [cls respondsToSelector:@selector(sharedAVSystemController)]) {
        id ctrl = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedAVSystemController));
        SEL setSel = NSSelectorFromString(@"setVolumeTo:forCategory:");
        if (ctrl && [ctrl respondsToSelector:setSel]) {
            ((BOOL (*)(id, SEL, float, NSString *))objc_msgSend)(ctrl, setSel, vol, @"Audio/Video");
        }
    }
}

static void iOS27LaunchAppOrURL(NSString *bundleID, NSString *fallbackURL) {
    Class appCtrl = NSClassFromString(@"SBApplicationController");
    Class wsCls = NSClassFromString(@"SBMainWorkspace");
    if (bundleID.length > 0 && appCtrl && wsCls) {
        SEL sharedSel = @selector(sharedInstance);
        if ([appCtrl respondsToSelector:sharedSel]) {
            id ac = ((id (*)(id, SEL))objc_msgSend)(appCtrl, sharedSel);
            SEL appSel = NSSelectorFromString(@"applicationWithBundleIdentifier:");
            if (ac && [ac respondsToSelector:appSel]) {
                id app = ((id (*)(id, SEL, NSString *))objc_msgSend)(ac, appSel, bundleID);
                if (app) {
                    Class uiAppCls = [UIApplication class];
                    SEL launchSel = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
                    if ([[uiAppCls sharedApplication] respondsToSelector:launchSel]) {
                        ((BOOL (*)(id, SEL, NSString *, BOOL))objc_msgSend)([uiAppCls sharedApplication], launchSel, bundleID, NO);
                        return;
                    }
                }
            }
        }
    }
    if (fallbackURL.length > 0) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:fallbackURL] options:@{} completionHandler:nil];
    }
}

// =========================================================================
// 2. Liquid Glass Renderer (Zero UIVisualEffectView, 2GB RAM 60fps)
// =========================================================================
static CGFloat iOS27CCGlassVal(void) {
    return iOS27FloatPref(@"kCCGlassIntensity", gCCGlassAlpha);
}

static void ApplyCCGlass(UIView *view, CGFloat radius, CGFloat alpha, BOOL isActiveWhite) {
    if (!view || CGRectIsEmpty(view.bounds)) return;

    if (isActiveWhite) {
        view.backgroundColor = [UIColor colorWithWhite:0.96 alpha:0.92];
    } else {
        view.backgroundColor = [UIColor colorWithRed:0.11 green:0.13 blue:0.18 alpha:alpha];
    }
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;

    CAGradientLayer *sheen = nil;
    CAGradientLayer *rimGrad = nil;

    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"iOS27CCSheen"]) sheen = (CAGradientLayer *)layer;
        else if ([layer.name isEqualToString:@"iOS27CCRim"]) rimGrad = (CAGradientLayer *)layer;
    }

    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.name = @"iOS27CCSheen";
        sheen.startPoint = CGPointMake(0.5, 0.0);
        sheen.endPoint = CGPointMake(0.5, 1.0);
        sheen.locations = @[@0.0, @0.42, @1.0];
        [view.layer insertSublayer:sheen atIndex:0];
    }

    if (!rimGrad) {
        rimGrad = [CAGradientLayer layer];
        rimGrad.name = @"iOS27CCRim";
        rimGrad.startPoint = CGPointMake(0.2, 0.0);
        rimGrad.endPoint = CGPointMake(0.8, 1.0);
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.fillColor = [UIColor clearColor].CGColor;
        mask.strokeColor = [UIColor whiteColor].CGColor;
        mask.lineWidth = 2.0;
        rimGrad.mask = mask;
        [view.layer addSublayer:rimGrad];
    }

    sheen.colors = isActiveWhite ? @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.45].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor,
        (id)[UIColor colorWithWhite:0.9 alpha:0.15].CGColor
    ] : @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.26].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.03].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.13].CGColor
    ];

    rimGrad.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:(isActiveWhite ? 0.95 : 0.72)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.16].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(isActiveWhite ? 0.70 : 0.50)].CGColor
    ];

    sheen.frame = view.bounds;
    sheen.cornerRadius = radius;
    rimGrad.frame = view.bounds;

    CAShapeLayer *mask = (CAShapeLayer *)rimGrad.mask;
    mask.frame = view.bounds;
    mask.path = [UIBezierPath bezierPathWithRoundedRect:view.bounds cornerRadius:radius].CGPath;
}

// =========================================================================
// 3. Control Catalog & Saved Layout Persistence (Reorderable + Resizable)
// =========================================================================
static NSArray<NSDictionary *> *iOS27AllControlDefinitions(void) {
    return @[
        @{@"id": @"wifi",        @"title": @"Wi-Fi",         @"icon": @"wifi",                              @"span": @(2), @"accent": @"blue"},
        @{@"id": @"bluetooth",   @"title": @"Bluetooth",     @"icon": @"dot.radiowaves.left.and.right",     @"span": @(2), @"accent": @"blue"},
        @{@"id": @"airdrop",     @"title": @"AirDrop",       @"icon": @"airdrop",                           @"span": @(2), @"accent": @"blue"},
        @{@"id": @"flashlight",  @"title": @"Flashlight",    @"icon": @"flashlight.off.fill",               @"span": @(2), @"accent": @"blue"},
        @{@"id": @"brightness",  @"title": @"Brightness",    @"icon": @"sun.max.fill",                      @"span": @(2), @"accent": @"yellow"},
        @{@"id": @"volume",      @"title": @"Volume",        @"icon": @"speaker.wave.2.fill",               @"span": @(2), @"accent": @"blue"},
        @{@"id": @"lowpower",    @"title": @"Low Power",     @"icon": @"battery.25",                        @"span": @(1), @"accent": @"orange"},
        @{@"id": @"calculator",  @"title": @"Calculator",    @"icon": @"plus.forwardslash.minus",           @"span": @(1), @"accent": @"white"},
        @{@"id": @"camera",      @"title": @"Camera",        @"icon": @"camera.fill",                       @"span": @(1), @"accent": @"white"},
        @{@"id": @"airplane",    @"title": @"Airplane",      @"icon": @"airplane",                          @"span": @(1), @"accent": @"orange"},
        @{@"id": @"orientation", @"title": @"Orientation",   @"icon": @"lock.rotation",                     @"span": @(2), @"accent": @"pink"},
        @{@"id": @"darkmode",    @"title": @"Dark Mode",     @"icon": @"circle.lefthalf.filled",            @"span": @(2), @"accent": @"black"},
        @{@"id": @"cellular",    @"title": @"Cellular Data", @"icon": @"antenna.radiowaves.left.and.right", @"span": @(2), @"accent": @"green"},
        @{@"id": @"settings",    @"title": @"Settings",      @"icon": @"gear",                              @"span": @(1), @"accent": @"white"},
        @{@"id": @"timer",       @"title": @"Clock",         @"icon": @"timer",                             @"span": @(1), @"accent": @"orange"},
        @{@"id": @"notes",       @"title": @"Notes",         @"icon": @"note.text",                         @"span": @(1), @"accent": @"yellow"},
        @{@"id": @"respring",    @"title": @"Respring",      @"icon": @"arrow.clockwise",                   @"span": @(1), @"accent": @"blue"}
    ];
}

static NSDictionary *iOS27ControlDefByID(NSString *cid) {
    for (NSDictionary *d in iOS27AllControlDefinitions()) {
        if ([d[@"id"] isEqualToString:cid]) return d;
    }
    return nil;
}

static NSMutableArray<NSDictionary *> *iOS27LoadCCLayout(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
    NSArray *saved = [prefs arrayForKey:@"kCustomCCLayout"];
    if ([saved isKindOfClass:[NSArray class]] && saved.count > 0) {
        return [saved mutableCopy];
    }
    // Default layout matching video (Wi-Fi, BT, AirDrop, Flashlight, Brightness, Volume, 4 circles, Orientation, Dark Mode, Cellular)
    NSArray *defIDs = @[@"wifi", @"bluetooth", @"airdrop", @"flashlight", @"brightness", @"volume", @"lowpower", @"calculator", @"camera", @"airplane", @"orientation", @"darkmode", @"cellular", @"settings", @"respring"];
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *cid in defIDs) {
        NSDictionary *def = iOS27ControlDefByID(cid);
        if (def) [list addObject:@{@"id": cid, @"span": def[@"span"]}];
    }
    [prefs setObject:list forKey:@"kCustomCCLayout"];
    [prefs synchronize];
    return list;
}

static void iOS27SaveCCLayout(NSArray<NSDictionary *> *layout) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
    [prefs setObject:layout forKey:@"kCustomCCLayout"];
    [prefs synchronize];
}

static UIColor *iOS27AccentColor(NSString *name) {
    if ([name isEqualToString:@"blue"])   return [UIColor systemBlueColor];
    if ([name isEqualToString:@"orange"]) return [UIColor systemOrangeColor];
    if ([name isEqualToString:@"pink"])   return [UIColor systemPinkColor];
    if ([name isEqualToString:@"green"])  return [UIColor systemGreenColor];
    if ([name isEqualToString:@"yellow"]) return [UIColor systemYellowColor];
    if ([name isEqualToString:@"black"])  return [UIColor blackColor];
    return [UIColor whiteColor];
}

// =========================================================================
// 4. Custom Interactive Liquid Glass Slider Pill (Brightness / Volume)
// =========================================================================
@interface IOS27GlassSliderPill : UIControl
@property (nonatomic, assign) CGFloat value;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLbl;
@property (nonatomic, copy) void (^onValueChanged)(CGFloat val);
- (void)configureWithIcon:(NSString *)symbol title:(NSString *)title tint:(UIColor *)tint initialValue:(CGFloat)val;
@end

@implementation IOS27GlassSliderPill

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.fillView = [[UIView alloc] initWithFrame:CGRectZero];
        self.fillView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.88];
        self.fillView.userInteractionEnabled = NO;
        [self addSubview:self.fillView];

        self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        self.iconView.userInteractionEnabled = NO;
        [self addSubview:self.iconView];

        self.titleLbl = [[UILabel alloc] initWithFrame:CGRectZero];
        self.titleLbl.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
        self.titleLbl.textColor = [UIColor colorWithWhite:0.15 alpha:0.9];
        self.titleLbl.userInteractionEnabled = NO;
        [self addSubview:self.titleLbl];
    }
    return self;
}

- (void)configureWithIcon:(NSString *)symbol title:(NSString *)title tint:(UIColor *)tint initialValue:(CGFloat)val {
    self.value = MAX(0.02, MIN(1.0, val));
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold];
        self.iconView.image = [UIImage systemImageNamed:symbol withConfiguration:cfg];
        self.iconView.tintColor = tint;
    }
    self.titleLbl.text = title;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    ApplyCCGlass(self, h / 2.0, iOS27CCGlassVal(), NO);
    self.fillView.frame = CGRectMake(0, 0, w * self.value, h);
    [self bringSubviewToFront:self.iconView];
    [self bringSubviewToFront:self.titleLbl];
    self.iconView.frame = CGRectMake(14.0, (h - 22.0) / 2.0, 22.0, 22.0);
    self.titleLbl.frame = CGRectMake(42.0, (h - 18.0) / 2.0, w - 52.0, 18.0);
    self.titleLbl.textColor = (self.value > 0.45) ? [UIColor colorWithWhite:0.12 alpha:0.95] : [UIColor colorWithWhite:1.0 alpha:0.92];
}

- (void)updateForTouch:(UITouch *)touch {
    CGPoint pt = [touch locationInView:self];
    CGFloat newVal = MAX(0.02, MIN(1.0, pt.x / MAX(self.bounds.size.width, 1.0)));
    self.value = newVal;
    [self setNeedsLayout];
    if (self.onValueChanged) self.onValueChanged(newVal);
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self updateForTouch:touch];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self updateForTouch:touch];
    return YES;
}

@end

// =========================================================================
// 5. Power Menu & Controls Gallery Sheets
// =========================================================================
@interface IOS27CustomPowerSheet : UIView
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation IOS27CustomPowerSheet
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        ApplyCCGlass(self, 26.0, 0.90, NO);
        CGFloat w = frame.size.width;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, w - 32, 24)];
        title.text = @"iOS 27 Power";
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        NSArray *acts = @[
            @{@"t": @"Respring SpringBoard", @"i": @"arrow.clockwise", @"c": [UIColor systemBlueColor], @"s": @"doRespring"},
            @{@"t": @"Userspace Reboot",     @"i": @"power",           @"c": [UIColor systemOrangeColor], @"s": @"doUserspace"},
            @{@"t": @"Cancel",               @"i": @"xmark",           @"c": [UIColor colorWithWhite:0.25 alpha:1.0], @"s": @"doCancel"}
        ];
        for (NSInteger i = 0; i < (NSInteger)acts.count; i++) {
            NSDictionary *a = acts[i];
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(14, 46 + i * 48, w - 28, 40);
            b.layer.cornerRadius = 14.0;
            b.backgroundColor = a[@"c"];
            [b setTitle:[NSString stringWithFormat:@"  %@", a[@"t"]] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
                [b setImage:[UIImage systemImageNamed:a[@"i"] withConfiguration:cfg] forState:UIControlStateNormal];
                b.tintColor = [UIColor whiteColor];
            }
            [b addTarget:self action:NSSelectorFromString(a[@"s"]) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:b];
        }
    }
    return self;
}
- (void)doRespring {
    char *const args[] = { "sbreload", NULL };
    pid_t pid;
    if (posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, args, environ) != 0) {
        char *const killArgs[] = { "killall", "-9", "SpringBoard", NULL };
        iOS27RunRootlessBin("/var/jb/usr/bin/killall", killArgs);
    }
}
- (void)doUserspace {
    char *const args[] = { "launchctl", "reboot", "userspace", NULL };
    iOS27RunRootlessBin("/var/jb/usr/bin/launchctl", args);
}
- (void)doCancel { if (self.onClose) self.onClose(); }
@end

@interface IOS27CustomGallerySheet : UIView
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UISlider *glassSlider;
@property (nonatomic, copy) void (^onAddControl)(NSString *cid);
@property (nonatomic, copy) void (^onResetLayout)(void);
@property (nonatomic, copy) void (^onGlassChanged)(void);
@property (nonatomic, copy) void (^onClose)(void);
- (void)reloadAvailableWithActiveIDs:(NSSet<NSString *> *)activeIDs;
@end

@implementation IOS27CustomGallerySheet
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        ApplyCCGlass(self, 26.0, 0.94, NO);
        CGFloat w = frame.size.width;
        CGFloat h = frame.size.height;

        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, w - 70, 26)];
        t.text = @"Add a Control";
        t.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightBold];
        t.textColor = [UIColor whiteColor];
        [self addSubview:t];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(w - 42, 10, 30, 30);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
            [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
            closeBtn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.8];
        }
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 44, w, h - 44)];
        [self addSubview:self.scroll];
    }
    return self;
}

- (void)reloadAvailableWithActiveIDs:(NSSet<NSString *> *)activeIDs {
    for (UIView *sub in self.scroll.subviews) [sub removeFromSuperview];
    CGFloat w = self.bounds.size.width;
    CGFloat y = 6.0;

    UILabel *s1 = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 18)];
    s1.text = @"LIQUID GLASS TRANSPARENCY";
    s1.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    s1.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    [self.scroll addSubview:s1];
    y += 22.0;

    UIView *slBox = [[UIView alloc] initWithFrame:CGRectMake(14, y, w - 28, 42)];
    ApplyCCGlass(slBox, 14.0, 0.45, NO);
    self.glassSlider = [[UISlider alloc] initWithFrame:CGRectMake(12, 6, slBox.bounds.size.width - 24, 30)];
    self.glassSlider.minimumValue = 0.14;
    self.glassSlider.maximumValue = 0.56;
    self.glassSlider.value = iOS27CCGlassVal();
    self.glassSlider.minimumTrackTintColor = [UIColor whiteColor];
    [self.glassSlider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [slBox addSubview:self.glassSlider];
    [self.scroll addSubview:slBox];
    y += 52.0;

    UILabel *s2 = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 18)];
    s2.text = @"AVAILABLE CONTROLS (TAP TO ADD)";
    s2.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    s2.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    [self.scroll addSubview:s2];
    y += 24.0;

    NSArray<NSDictionary *> *allDefs = iOS27AllControlDefinitions();
    BOOL addedAny = NO;
    for (NSDictionary *def in allDefs) {
        if ([activeIDs containsObject:def[@"id"]]) continue;
        addedAny = YES;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(14, y, w - 28, 42);
        ApplyCCGlass(btn, 14.0, 0.40, NO);
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        btn.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        btn.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
        [btn setTitle:[NSString stringWithFormat:@"+  %@", def[@"title"]] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
            [btn setImage:[UIImage systemImageNamed:def[@"icon"] withConfiguration:cfg] forState:UIControlStateNormal];
            btn.tintColor = iOS27AccentColor(def[@"accent"]);
        }

        objc_setAssociatedObject(btn, "cid", def[@"id"], OBJC_ASSOCIATION_COPY_NONATOMIC);
        [btn addTarget:self action:@selector(addBtnTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:btn];
        y += 48.0;
    }

    if (!addedAny) {
        UILabel *none = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 30)];
        none.text = @"All controls are already on your Control Center.";
        none.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        none.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
        [self.scroll addSubview:none];
        y += 38.0;
    }

    y += 8.0;
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    resetBtn.frame = CGRectMake(14, y, w - 28, 40);
    resetBtn.layer.cornerRadius = 14.0;
    resetBtn.backgroundColor = [UIColor systemBlueColor];
    [resetBtn setTitle:@"Reset Default Layout" forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [resetBtn addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:resetBtn];
    y += 56.0;

    self.scroll.contentSize = CGSizeMake(w, y);
}

- (void)sliderChanged {
    iOS27SetFloatPref(@"kCCGlassIntensity", self.glassSlider.value);
    if (self.onGlassChanged) self.onGlassChanged();
}
- (void)addBtnTapped:(UIButton *)sender {
    NSString *cid = objc_getAssociatedObject(sender, "cid");
    if (cid && self.onAddControl) self.onAddControl(cid);
}
- (void)resetTapped { if (self.onResetLayout) self.onResetLayout(); }
- (void)closeTapped { if (self.onClose) self.onClose(); }
@end

// =========================================================================
// 6. Complete Custom iOS 27 Control Center View (3 Vertical Pages + Drag/Drop)
// =========================================================================
@interface IOS27CustomControlCenterView : UIView <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *controls;
@property (nonatomic, assign) BOOL isEditMode;
@property (nonatomic, strong) UIScrollView *pagerScroll;
@property (nonatomic, strong) UICollectionView *gridView;
@property (nonatomic, strong) UIButton *plusBtn;
@property (nonatomic, strong) UIButton *powerBtn;
@property (nonatomic, strong) UIButton *addControlBtn;
@property (nonatomic, strong) UIView *railView;
@property (nonatomic, strong) UIView *modalBackdrop;
@property (nonatomic, strong) UIView *connPageView;
@property (nonatomic, assign) CGFloat unitSize;
@property (nonatomic, assign) CGFloat gridGap;
- (void)refreshLiveStates;
- (void)exitEditAndModals;
@end

@implementation IOS27CustomControlCenterView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.tag = 27700;
        self.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:0.74];
        self.controls = iOS27LoadCCLayout();

        CGFloat w = frame.size.width;
        CGFloat h = frame.size.height;
        CGFloat topY = (h > 600.0) ? 44.0 : 14.0;

        // Vertical Paging ScrollView (3 Full-Screen Pages matching Video 1)
        self.pagerScroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        self.pagerScroll.pagingEnabled = YES;
        self.pagerScroll.showsVerticalScrollIndicator = NO;
        self.pagerScroll.alwaysBounceVertical = YES;
        self.pagerScroll.delegate = self;
        self.pagerScroll.contentSize = CGSizeMake(w, h * 3.0);
        [self addSubview:self.pagerScroll];

        // Double-Tap anywhere on Page 1 background to toggle Edit Mode
        UITapGestureRecognizer *dblTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleEditMode)];
        dblTap.numberOfTapsRequired = 2;
        dblTap.cancelsTouchesInView = NO;
        dblTap.delegate = self;
        [self.pagerScroll addGestureRecognizer:dblTap];

        // ---------------- PAGE 1 (y = 0): Reorderable Controls Grid ----------------
        CGFloat leftPad = 14.0;
        CGFloat rightRailSpace = 34.0;
        CGFloat gridW = w - leftPad - rightRailSpace;
        self.gridGap = (w <= 330.0) ? 8.0 : 12.0;
        self.unitSize = floor((gridW - self.gridGap * 3.0) / 4.0);

        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.minimumInteritemSpacing = self.gridGap;
        layout.minimumLineSpacing = self.gridGap;
        layout.sectionInset = UIEdgeInsetsMake(6.0, 0, 64.0, 0);

        self.gridView = [[UICollectionView alloc] initWithFrame:CGRectMake(leftPad, topY + 42.0, gridW, h - (topY + 42.0)) collectionViewLayout:layout];
        self.gridView.backgroundColor = [UIColor clearColor];
        self.gridView.showsVerticalScrollIndicator = NO;
        self.gridView.dataSource = self;
        self.gridView.delegate = self;
        [self.gridView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"CCTileCell"];
        [self.pagerScroll addSubview:self.gridView];

        // Drag & Drop Reorder Gesture on Grid (Active in Edit Mode)
        UILongPressGestureRecognizer *dragGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleGridDrag:)];
        dragGesture.minimumPressDuration = 0.22;
        [self.gridView addGestureRecognizer:dragGesture];

        // ---------------- PAGE 2 (y = h): Exact Video Media Player Card ----------------
        [self buildMediaPageAtY:h width:w height:h topY:topY];

        // ---------------- PAGE 3 (y = h * 2): Exact Video Connectivity Hub ----------------
        [self buildConnectivityPageAtY:h * 2.0 width:w height:h topY:topY];

        // ---------------- FLOATING TOP CHROME (+ & Power) & RIGHT RAIL ----------------
        self.plusBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.plusBtn.frame = CGRectMake(14.0, topY, 34.0, 34.0);
        ApplyCCGlass(self.plusBtn, 17.0, 0.45, NO);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
            [self.plusBtn setImage:[UIImage systemImageNamed:@"plus" withConfiguration:cfg] forState:UIControlStateNormal];
            self.plusBtn.tintColor = [UIColor whiteColor];
        }
        [self.plusBtn addTarget:self action:@selector(toggleEditMode) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.plusBtn];

        self.powerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.powerBtn.frame = CGRectMake(w - 48.0, topY, 34.0, 34.0);
        ApplyCCGlass(self.powerBtn, 17.0, 0.45, NO);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
            [self.powerBtn setImage:[UIImage systemImageNamed:@"power" withConfiguration:cfg] forState:UIControlStateNormal];
            self.powerBtn.tintColor = [UIColor whiteColor];
        }
        [self.powerBtn addTarget:self action:@selector(openPowerMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.powerBtn];

        self.addControlBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.addControlBtn.frame = CGRectMake((w - 166.0) / 2.0, h - 50.0, 166.0, 36.0);
        ApplyCCGlass(self.addControlBtn, 18.0, 0.72, NO);
        [self.addControlBtn setTitle:@" Add a Control" forState:UIControlStateNormal];
        self.addControlBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
        [self.addControlBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13.5 weight:UIImageSymbolWeightBold];
            [self.addControlBtn setImage:[UIImage systemImageNamed:@"plus.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
            self.addControlBtn.tintColor = [UIColor whiteColor];
        }
        self.addControlBtn.hidden = YES;
        [self.addControlBtn addTarget:self action:@selector(openAddControlGallery) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.addControlBtn];

        // Right-Side Vertical Rail (Heart, Music, Connectivity)
        CGFloat railH = 114.0;
        self.railView = [[UIView alloc] initWithFrame:CGRectMake(w - 26.0, floor((h - railH) / 2.0), 24.0, railH)];
        NSArray *railIcons = @[@"heart.fill", @"music.note", @"antenna.radiowaves.left.and.right"];
        for (NSInteger i = 0; i < 3; i++) {
            UIButton *rb = [UIButton buttonWithType:UIButtonTypeCustom];
            rb.tag = 500 + i;
            rb.frame = CGRectMake(0, i * 38.0, 24.0, 32.0);
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold];
                [rb setImage:[UIImage systemImageNamed:railIcons[i] withConfiguration:cfg] forState:UIControlStateNormal];
                rb.tintColor = (i == 0) ? [UIColor whiteColor] : [UIColor colorWithWhite:1.0 alpha:0.42];
            }
            [rb addTarget:self action:@selector(railButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.railView addSubview:rb];
        }
        [self addSubview:self.railView];
    }
    return self;
}

- (void)buildMediaPageAtY:(CGFloat)pageY width:(CGFloat)w height:(CGFloat)h topY:(CGFloat)topY {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(0, pageY, w, h)];
    CGFloat cardW = w - 58.0;
    CGFloat cardH = MIN(h - topY - 96.0, 410.0);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(18.0, topY + 50.0, cardW, cardH)];
    ApplyCCGlass(card, 32.0, iOS27CCGlassVal() + 0.06, NO);
    [page addSubview:card];

    // Artwork Area
    CGFloat artH = floor(cardH * 0.48);
    UIView *artBox = [[UIView alloc] initWithFrame:CGRectMake(18.0, 18.0, cardW - 36.0, artH)];
    artBox.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    artBox.layer.cornerRadius = 20.0;
    artBox.clipsToBounds = YES;
    UIImageView *noteImg = [[UIImageView alloc] initWithFrame:artBox.bounds];
    noteImg.contentMode = UIViewContentModeCenter;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightLight];
        noteImg.image = [UIImage systemImageNamed:@"music.note" withConfiguration:cfg];
        noteImg.tintColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    }
    [artBox addSubview:noteImg];
    [card addSubview:artBox];

    CGFloat y = CGRectGetMaxY(artBox.frame) + 16.0;
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(20.0, y, cardW - 40.0, 22.0)];
    titleLbl.text = @"Not Playing";
    titleLbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    titleLbl.textColor = [UIColor whiteColor];
    [card addSubview:titleLbl];

    y += 30.0;
    UIView *scrubber = [[UIView alloc] initWithFrame:CGRectMake(20.0, y, cardW - 40.0, 5.0)];
    scrubber.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25];
    scrubber.layer.cornerRadius = 2.5;
    [card addSubview:scrubber];

    y += 18.0;
    UIStackView *controlsStack = [[UIStackView alloc] initWithFrame:CGRectMake(24.0, y, cardW - 48.0, 44.0)];
    controlsStack.axis = UILayoutConstraintAxisHorizontal;
    controlsStack.distribution = UIStackViewDistributionFillEqually;
    [controlsStack addArrangedSubview:[self makeMediaIconBtn:@"backward.fill" sel:@selector(mediaPrev)]];
    [controlsStack addArrangedSubview:[self makeMediaIconBtn:@"play.fill" sel:@selector(mediaPlayPause)]];
    [controlsStack addArrangedSubview:[self makeMediaIconBtn:@"forward.fill" sel:@selector(mediaNext)]];
    [card addSubview:controlsStack];

    y += 50.0;
    UISlider *volSlider = [[UISlider alloc] initWithFrame:CGRectMake(20.0, y, cardW - 40.0, 28.0)];
    volSlider.minimumValue = 0.0;
    volSlider.maximumValue = 1.0;
    volSlider.value = iOS27GetSystemVolume();
    volSlider.minimumTrackTintColor = [UIColor whiteColor];
    [volSlider addTarget:self action:@selector(mediaVolChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:volSlider];

    UIButton *airplayPill = [UIButton buttonWithType:UIButtonTypeCustom];
    airplayPill.frame = CGRectMake((cardW - 104.0) / 2.0, cardH - 40.0, 104.0, 28.0);
    ApplyCCGlass(airplayPill, 14.0, 0.35, NO);
    [airplayPill setTitle:@" AirPlay" forState:UIControlStateNormal];
    airplayPill.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    [airplayPill setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:11.5 weight:UIImageSymbolWeightSemibold];
        [airplayPill setImage:[UIImage systemImageNamed:@"airplayaudio" withConfiguration:cfg] forState:UIControlStateNormal];
        airplayPill.tintColor = [UIColor whiteColor];
    }
    [card addSubview:airplayPill];

    [self.pagerScroll addSubview:page];
}

- (UIButton *)makeMediaIconBtn:(NSString *)symbol sel:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightBold];
        [b setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
        b.tintColor = [UIColor whiteColor];
    }
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)mediaPrev { iOS27SendMediaCmd(5); }
- (void)mediaPlayPause { iOS27SendMediaCmd(2); }
- (void)mediaNext { iOS27SendMediaCmd(4); }
- (void)mediaVolChanged:(UISlider *)s { iOS27SetSystemVolume(s.value); }

- (void)buildConnectivityPageAtY:(CGFloat)pageY width:(CGFloat)w height:(CGFloat)h topY:(CGFloat)topY {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(0, pageY, w, h)];
    self.connPageView = page;

    CGFloat pad = 16.0;
    CGFloat contentW = w - pad - 36.0;
    CGFloat y = topY + 52.0;

    // 1. Top Full-Width Airplane Mode Pill (Exact match to Video 1)
    UIButton *airPill = [self makeConnTileWithFrame:CGRectMake(pad, y, contentW, 56.0) title:@"Airplane Mode" sub:@"Tap to toggle" icon:@"airplane" cid:@"airplane" isSquare:NO];
    [page addSubview:airPill];
    y += 68.0;

    // 2. 2x2 Large Rounded Square Cards (Wi-Fi, AirDrop, Cellular Data, Bluetooth)
    CGFloat sqGap = 12.0;
    CGFloat sqW = floor((contentW - sqGap) / 2.0);
    CGFloat sqH = MIN(sqW * 1.02, 126.0);

    [page addSubview:[self makeConnTileWithFrame:CGRectMake(pad, y, sqW, sqH) title:@"Wi-Fi" sub:@"Tap to toggle" icon:@"wifi" cid:@"wifi" isSquare:YES]];
    [page addSubview:[self makeConnTileWithFrame:CGRectMake(pad + sqW + sqGap, y, sqW, sqH) title:@"AirDrop" sub:@"Settings" icon:@"airdrop" cid:@"airdrop" isSquare:YES]];
    y += sqH + sqGap;

    [page addSubview:[self makeConnTileWithFrame:CGRectMake(pad, y, sqW, sqH) title:@"Cellular Data" sub:@"Settings" icon:@"antenna.radiowaves.left.and.right" cid:@"cellular" isSquare:YES]];
    [page addSubview:[self makeConnTileWithFrame:CGRectMake(pad + sqW + sqGap, y, sqW, sqH) title:@"Bluetooth" sub:@"Tap to toggle" icon:@"dot.radiowaves.left.and.right" cid:@"bluetooth" isSquare:YES]];
    y += sqH + 14.0;

    // 3. Bottom Full-Width Pills (Personal Hotspot, VPN)
    [page addSubview:[self makeConnTileWithFrame:CGRectMake(pad, y, contentW, 52.0) title:@"Personal Hotspot" sub:@"Off" icon:@"personalhotspot" cid:@"hotspot" isSquare:NO]];
    y += 62.0;
    [page addSubview:[self makeConnTileWithFrame:CGRectMake(pad, y, contentW, 52.0) title:@"VPN" sub:@"Off" icon:@"network" cid:@"vpn" isSquare:NO]];

    [self.pagerScroll addSubview:page];
}

- (UIButton *)makeConnTileWithFrame:(CGRect)frame title:(NSString *)title sub:(NSString *)sub icon:(NSString *)icon cid:(NSString *)cid isSquare:(BOOL)isSquare {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    ApplyCCGlass(btn, isSquare ? 26.0 : (frame.size.height / 2.0), iOS27CCGlassVal() + 0.06, NO);

    UIImageView *iv = [[UIImageView alloc] initWithFrame:isSquare ? CGRectMake(14, 14, 28, 28) : CGRectMake(16, (frame.size.height - 24) / 2.0, 24, 24)];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.userInteractionEnabled = NO;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
        iv.image = [UIImage systemImageNamed:icon withConfiguration:cfg];
        iv.tintColor = [UIColor whiteColor];
    }
    [btn addSubview:iv];

    UILabel *t = [[UILabel alloc] initWithFrame:isSquare ? CGRectMake(14, frame.size.height - 44, frame.size.width - 24, 18) : CGRectMake(50, 9, frame.size.width - 64, 18)];
    t.text = title;
    t.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    t.textColor = [UIColor whiteColor];
    t.userInteractionEnabled = NO;
    [btn addSubview:t];

    UILabel *s = [[UILabel alloc] initWithFrame:isSquare ? CGRectMake(14, frame.size.height - 25, frame.size.width - 24, 15) : CGRectMake(50, 28, frame.size.width - 64, 15)];
    s.text = sub;
    s.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    s.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    s.userInteractionEnabled = NO;
    [btn addSubview:s];

    objc_setAssociatedObject(btn, "cid", cid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [btn addTarget:self action:@selector(connTileTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)connTileTapped:(UIButton *)sender {
    NSString *cid = objc_getAssociatedObject(sender, "cid");
    if ([cid isEqualToString:@"hotspot"]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=INTERNET_TETHERING"] options:@{} completionHandler:nil];
    } else if ([cid isEqualToString:@"vpn"]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=General&path=VPN"] options:@{} completionHandler:nil];
    } else {
        [self executeControlAction:cid];
    }
}

// ---------------- Drag & Drop Reorder Handler ----------------
- (void)handleGridDrag:(UILongPressGestureRecognizer *)gesture {
    if (!self.isEditMode) return;
    CGPoint loc = [gesture locationInView:self.gridView];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath *ip = [self.gridView indexPathForItemAtPoint:loc];
            if (ip) {
                UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
                [h impactOccurred];
                [self.gridView beginInteractiveMovementForItemAtIndexPath:ip];
            }
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.gridView updateInteractiveMovementTargetPosition:loc];
            break;
        case UIGestureRecognizerStateEnded:
            [self.gridView endInteractiveMovement];
            break;
        default:
            [self.gridView cancelInteractiveMovement];
            break;
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.isEditMode;
}

- (void)collectionView:(UICollectionView *)collectionView moveItemAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSDictionary *moved = self.controls[sourceIndexPath.item];
    [self.controls removeObjectAtIndex:sourceIndexPath.item];
    [self.controls insertObject:moved atIndex:destinationIndexPath.item];
    iOS27SaveCCLayout(self.controls);
}

// ---------------- UICollectionView DataSource & Layout ----------------
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.controls.count;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.controls[indexPath.item];
    NSInteger span = [item[@"span"] integerValue];
    CGFloat w = (span == 2) ? (self.unitSize * 2.0 + self.gridGap) : self.unitSize;
    return CGSizeMake(w, self.unitSize);
}

- (BOOL)isControlActive:(NSString *)cid {
    if ([cid isEqualToString:@"wifi"])        return iOS27IsWiFiOn();
    if ([cid isEqualToString:@"bluetooth"])   return iOS27IsBluetoothOn();
    if ([cid isEqualToString:@"airplane"])    return iOS27IsAirplaneOn();
    if ([cid isEqualToString:@"flashlight"])  return iOS27IsTorchOn();
    if ([cid isEqualToString:@"orientation"]) return iOS27IsOrientationLocked();
    if ([cid isEqualToString:@"darkmode"])    return iOS27IsDarkModeOn();
    if ([cid isEqualToString:@"lowpower"])    return iOS27IsLowPowerOn();
    return NO;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"CCTileCell" forIndexPath:indexPath];
    for (UIView *sub in cell.contentView.subviews) [sub removeFromSuperview];
    cell.contentView.clipsToBounds = NO;

    NSDictionary *entry = self.controls[indexPath.item];
    NSString *cid = entry[@"id"];
    NSInteger span = [entry[@"span"] integerValue];
    NSDictionary *def = iOS27ControlDefByID(cid);
    if (!def) return cell;

    CGRect bounds = cell.contentView.bounds;

    if ([cid isEqualToString:@"brightness"] || [cid isEqualToString:@"volume"]) {
        IOS27GlassSliderPill *slider = [[IOS27GlassSliderPill alloc] initWithFrame:bounds];
        BOOL isBri = [cid isEqualToString:@"brightness"];
        float initVal = isBri ? [UIScreen mainScreen].brightness : iOS27GetSystemVolume();
        [slider configureWithIcon:def[@"icon"] title:(span == 2 ? def[@"title"] : @"") tint:iOS27AccentColor(def[@"accent"]) initialValue:initVal];
        slider.userInteractionEnabled = !self.isEditMode;
        slider.onValueChanged = ^(CGFloat val) {
            if (isBri) [UIScreen mainScreen].brightness = val;
            else iOS27SetSystemVolume((float)val);
        };
        [cell.contentView addSubview:slider];
    } else {
        BOOL active = [self isControlActive:cid];
        UIView *tile = [[UIView alloc] initWithFrame:bounds];
        tile.userInteractionEnabled = NO;
        ApplyCCGlass(tile, bounds.size.height / 2.0, iOS27CCGlassVal(), active);
        [cell.contentView addSubview:tile];

        UIColor *accent = iOS27AccentColor(def[@"accent"]);
        UIColor *iconColor = active ? accent : [UIColor whiteColor];
        if (active && [def[@"accent"] isEqualToString:@"white"]) iconColor = [UIColor blackColor];

        UIImageView *iv = [[UIImageView alloc] initWithFrame:(span == 2) ? CGRectMake(14.0, (bounds.size.height - 24.0) / 2.0, 24.0, 24.0) : CGRectInset(bounds, 18.0, 18.0)];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
            iv.image = [UIImage systemImageNamed:def[@"icon"] withConfiguration:cfg];
            iv.tintColor = iconColor;
        }
        [tile addSubview:iv];

        if (span == 2) {
            UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(44.0, (bounds.size.height - 32.0) / 2.0, bounds.size.width - 52.0, 17.0)];
            titleLbl.text = def[@"title"];
            titleLbl.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
            titleLbl.textColor = active ? [UIColor blackColor] : [UIColor whiteColor];
            [tile addSubview:titleLbl];

            UILabel *subLbl = [[UILabel alloc] initWithFrame:CGRectMake(44.0, CGRectGetMaxY(titleLbl.frame), bounds.size.width - 52.0, 14.0)];
            subLbl.text = active ? @"On" : @"Off";
            subLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
            subLbl.textColor = active ? [UIColor colorWithWhite:0.2 alpha:0.85] : [UIColor colorWithWhite:1.0 alpha:0.65];
            [tile addSubview:subLbl];
        }
    }

    // Edit Mode Controls: Top-Left (-) Remove & Bottom-Right Curved Resize Handle
    if (self.isEditMode) {
        UIButton *minusBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        minusBtn.tag = indexPath.item;
        minusBtn.frame = CGRectMake(-4.0, -4.0, 22.0, 22.0);
        minusBtn.backgroundColor = [UIColor colorWithWhite:0.24 alpha:0.95];
        minusBtn.layer.cornerRadius = 11.0;
        minusBtn.layer.borderWidth = 1.0;
        minusBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightBold];
            [minusBtn setImage:[UIImage systemImageNamed:@"minus" withConfiguration:cfg] forState:UIControlStateNormal];
            minusBtn.tintColor = [UIColor whiteColor];
        }
        [minusBtn addTarget:self action:@selector(removeTileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:minusBtn];

        UIButton *resizeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        resizeBtn.tag = indexPath.item;
        resizeBtn.frame = CGRectMake(bounds.size.width - 20.0, bounds.size.height - 20.0, 22.0, 22.0);
        CAShapeLayer *arc = [CAShapeLayer layer];
        arc.fillColor = [UIColor clearColor].CGColor;
        arc.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;
        arc.lineWidth = 3.5;
        arc.lineCap = kCALineCapRound;
        arc.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(5, 5) radius:13 startAngle:0.1 endAngle:M_PI_2 - 0.1 clockwise:YES].CGPath;
        [resizeBtn.layer addSublayer:arc];
        [resizeBtn addTarget:self action:@selector(resizeTileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:resizeBtn];

        CAKeyframeAnimation *jiggle = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation"];
        jiggle.values = @[@(-0.02), @(0.02), @(-0.02)];
        jiggle.duration = 0.26;
        jiggle.repeatCount = HUGE_VALF;
        [cell.contentView.layer addAnimation:jiggle forKey:@"jiggle"];
    } else {
        [cell.contentView.layer removeAnimationForKey:@"jiggle"];
    }

    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isEditMode) return;
    NSDictionary *entry = self.controls[indexPath.item];
    [self executeControlAction:entry[@"id"]];
}

- (void)executeControlAction:(NSString *)cid {
    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [h impactOccurred];

    if ([cid isEqualToString:@"wifi"])             iOS27ToggleWiFi();
    else if ([cid isEqualToString:@"bluetooth"])   iOS27ToggleBluetooth();
    else if ([cid isEqualToString:@"airplane"])    iOS27ToggleAirplane();
    else if ([cid isEqualToString:@"flashlight"])  iOS27ToggleTorch();
    else if ([cid isEqualToString:@"orientation"]) iOS27ToggleOrientationLock();
    else if ([cid isEqualToString:@"darkmode"])    iOS27ToggleDarkMode();
    else if ([cid isEqualToString:@"lowpower"])    iOS27ToggleLowPower();
    else if ([cid isEqualToString:@"airdrop"])     [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=General&path=AIRDROP"] options:@{} completionHandler:nil];
    else if ([cid isEqualToString:@"cellular"])    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=MOBILE_DATA_SETTINGS_ID"] options:@{} completionHandler:nil];
    else if ([cid isEqualToString:@"calculator"])  iOS27LaunchAppOrURL(@"com.apple.calculator", nil);
    else if ([cid isEqualToString:@"camera"])      iOS27LaunchAppOrURL(@"com.apple.camera", nil);
    else if ([cid isEqualToString:@"timer"])       iOS27LaunchAppOrURL(@"com.apple.mobiletimer", nil);
    else if ([cid isEqualToString:@"notes"])       iOS27LaunchAppOrURL(@"com.apple.mobilenotes", nil);
    else if ([cid isEqualToString:@"settings"])    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:"] options:@{} completionHandler:nil];
    else if ([cid isEqualToString:@"respring"]) {
        char *const args[] = { "sbreload", NULL };
        pid_t pid;
        if (posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, args, environ) != 0) {
            char *const killArgs[] = { "killall", "-9", "SpringBoard", NULL };
            iOS27RunRootlessBin("/var/jb/usr/bin/killall", killArgs);
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.gridView reloadData];
    });
}

// ---------------- Edit Mode Actions ----------------
- (void)toggleEditMode {
    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [h impactOccurred];

    self.isEditMode = !self.isEditMode;
    self.addControlBtn.hidden = !self.isEditMode;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
        [self.plusBtn setImage:[UIImage systemImageNamed:(self.isEditMode ? @"checkmark" : @"plus") withConfiguration:cfg] forState:UIControlStateNormal];
    }
    if (self.isEditMode) {
        [self.pagerScroll setContentOffset:CGPointZero animated:YES];
    }
    [self.gridView reloadData];
}

- (void)removeTileTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.controls.count) return;
    [self.controls removeObjectAtIndex:idx];
    iOS27SaveCCLayout(self.controls);
    [self.gridView reloadData];
}

- (void)resizeTileTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.controls.count) return;
    NSMutableDictionary *m = [self.controls[idx] mutableCopy];
    NSInteger curSpan = [m[@"span"] integerValue];
    m[@"span"] = (curSpan == 2) ? @(1) : @(2);
    self.controls[idx] = m;
    iOS27SaveCCLayout(self.controls);
    [self.gridView reloadData];
}

// ---------------- Right-Side Page Rail ----------------
- (void)railButtonTapped:(UIButton *)sender {
    NSInteger page = sender.tag - 500;
    CGFloat h = self.bounds.size.height;
    [self.pagerScroll setContentOffset:CGPointMake(0, page * h) animated:YES];
    [self highlightRailPage:page];
}

- (void)highlightRailPage:(NSInteger)page {
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *rb = (UIButton *)[self.railView viewWithTag:500 + i];
        rb.tintColor = (i == page) ? [UIColor whiteColor] : [UIColor colorWithWhite:1.0 alpha:0.42];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.pagerScroll) return;
    CGFloat h = MAX(self.bounds.size.height, 1.0);
    NSInteger page = (NSInteger)round(scrollView.contentOffset.y / h);
    page = MAX(0, MIN(2, page));
    [self highlightRailPage:page];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *v = touch.view;
    while (v && v != self) {
        if ([v isKindOfClass:[UIControl class]] || [v isKindOfClass:[UICollectionViewCell class]]) return NO;
        v = v.superview;
    }
    return YES;
}

// ---------------- Modals: Power & Controls Gallery ----------------
- (void)dismissModal {
    if (self.modalBackdrop) {
        [self.modalBackdrop removeFromSuperview];
        self.modalBackdrop = nil;
    }
}

- (void)openPowerMenu {
    [self dismissModal];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat sw = MIN(w - 32.0, 276.0);
    CGFloat sh = 200.0;

    self.modalBackdrop = [[UIView alloc] initWithFrame:self.bounds];
    self.modalBackdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.48];
    [self addSubview:self.modalBackdrop];

    IOS27CustomPowerSheet *sheet = [[IOS27CustomPowerSheet alloc] initWithFrame:CGRectMake((w - sw) / 2.0, (h - sh) / 2.0, sw, sh)];
    __weak typeof(self) weakSelf = self;
    sheet.onClose = ^{ [weakSelf dismissModal]; };
    [self.modalBackdrop addSubview:sheet];
}

- (void)openAddControlGallery {
    [self dismissModal];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat sh = h * 0.68;

    self.modalBackdrop = [[UIView alloc] initWithFrame:self.bounds];
    self.modalBackdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    [self addSubview:self.modalBackdrop];

    IOS27CustomGallerySheet *sheet = [[IOS27CustomGallerySheet alloc] initWithFrame:CGRectMake(10.0, h, w - 20.0, sh)];
    __weak typeof(self) weakSelf = self;
    __weak typeof(sheet) weakSheet = sheet;

    void (^refreshGallery)(void) = ^{
        NSMutableSet *active = [NSMutableSet set];
        for (NSDictionary *d in weakSelf.controls) [active addObject:d[@"id"]];
        [weakSheet reloadAvailableWithActiveIDs:active];
    };
    refreshGallery();

    sheet.onAddControl = ^(NSString *cid) {
        NSDictionary *def = iOS27ControlDefByID(cid);
        if (def) {
            [weakSelf.controls addObject:@{@"id": cid, @"span": def[@"span"]}];
            iOS27SaveCCLayout(weakSelf.controls);
            [weakSelf.gridView reloadData];
            refreshGallery();
        }
    };
    sheet.onResetLayout = ^{
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"kCustomCCLayout"];
        NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
        [prefs removeObjectForKey:@"kCustomCCLayout"];
        [prefs synchronize];
        weakSelf.controls = iOS27LoadCCLayout();
        [weakSelf.gridView reloadData];
        refreshGallery();
    };
    sheet.onGlassChanged = ^{
        [weakSelf.gridView reloadData];
    };
    sheet.onClose = ^{ [weakSelf dismissModal]; };

    [self.modalBackdrop addSubview:sheet];
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        sheet.frame = CGRectMake(10.0, h - sh - 12.0, w - 20.0, sh);
    } completion:nil];
}

- (void)refreshLiveStates {
    [self.gridView reloadData];
}

- (void)exitEditAndModals {
    [self dismissModal];
    if (self.isEditMode) {
        [self toggleEditMode];
    }
}

@end

// =========================================================================
// 7. Inject Custom Control Center Inside SpringBoard's Native CC Overlay
// =========================================================================
static const void *kCustomCCKey = &kCustomCCKey;

%group ControlCenterHooks

%hook CCUIModularControlCenterOverlayViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    // Hide stock iOS 15 Control Center subviews so our Custom iOS 27 CC takes over cleanly
    for (UIView *sub in self.view.subviews) {
        if (sub.tag != 27700) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }

    IOS27CustomControlCenterView *customCC = objc_getAssociatedObject(self, kCustomCCKey);
    if (!customCC) {
        customCC = [[IOS27CustomControlCenterView alloc] initWithFrame:self.view.bounds];
        customCC.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:customCC];
        objc_setAssociatedObject(self, kCustomCCKey, customCC, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    customCC.frame = self.view.bounds;
    customCC.hidden = NO;
    customCC.alpha = 1.0;
    [self.view bringSubviewToFront:customCC];
    [customCC refreshLiveStates];
}

- (void)viewDidLayoutSubviews {
    %orig;
    for (UIView *sub in self.view.subviews) {
        if (sub.tag != 27700) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
    }
    IOS27CustomControlCenterView *customCC = objc_getAssociatedObject(self, kCustomCCKey);
    if (customCC) {
        customCC.frame = self.view.bounds;
        [self.view bringSubviewToFront:customCC];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    IOS27CustomControlCenterView *customCC = objc_getAssociatedObject(self, kCustomCCKey);
    if (customCC) {
        [customCC exitEditAndModals];
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
