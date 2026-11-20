#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "iOS27Prefs.h"

static CGFloat gLSGlassAlpha = 0.25;
static BOOL gHasLSNotifications = NO;
static NSString *const kIOS27NotifStateChanged = @"iOS27LSNotificationStateChanged";

@interface _UILegibilitySettings : NSObject
- (instancetype)initWithStyle:(NSInteger)style primaryColor:(UIColor *)primary secondaryColor:(UIColor *)secondary shadowColor:(UIColor *)shadow;
@end

@interface SBUILegibilityLabel : UIView
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, copy) NSAttributedString *attributedText;
@property (nonatomic, assign) double strength;
@property (nonatomic, strong) _UILegibilitySettings *legibilitySettings;
- (void)_updateLegibilityView;
@end

@interface SBFLockScreenDateView : UIView
- (void)ios27_handleNotificationChange:(NSNotification *)note;
- (void)ios27_applyClockStyle;
- (void)_updateLabels;
- (void)setLegibilitySettings:(id)settings;
- (void)setTextColor:(UIColor *)color;
@end

@interface CSQuickActionsButton : UIControl
@end

@interface NCNotificationStructuredListViewController : UIViewController
- (BOOL)hasVisibleContent;
- (void)insertNotificationRequest:(id)request;
- (void)removeNotificationRequest:(id)request;
@end

@interface NCNotificationMasterList : NSObject
- (NSUInteger)notificationCount;
- (void)insertNotificationRequest:(id)request;
- (void)removeNotificationRequest:(id)request;
- (void)clearAllNotificationRequests;
@end

static void ApplyLSGlassySheen(UIView *view, CGFloat radius, CGFloat alpha) {
    view.backgroundColor = [UIColor colorWithRed:0.12 green:0.16 blue:0.24 alpha:alpha];
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.1;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
    view.clipsToBounds = YES;

    CAGradientLayer *sheen = nil;
    for (CALayer *layer in view.layer.sublayers) {
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
            (id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor
        ];
        sheen.locations = @[@0.0, @0.52, @1.0];
        sheen.startPoint = CGPointMake(0.5, 0.0);
        sheen.endPoint = CGPointMake(0.5, 1.0);
        [view.layer insertSublayer:sheen atIndex:0];
    }
    sheen.frame = view.bounds;
    sheen.cornerRadius = radius;
}

static void PostLSNotificationState(BOOL hasNotifs) {
    if (gHasLSNotifications == hasNotifs) return;
    gHasLSNotifications = hasNotifs;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27NotifStateChanged
                                                            object:nil
                                                          userInfo:@{@"hasNotifications": @(hasNotifs)}];
    });
}

%group LockScreenHooks

// Intercept SBUILegibilityLabel specifically for our tagged Lock Screen Clock (tag 27999)
%hook SBUILegibilityLabel

- (void)setFont:(UIFont *)font {
    if (self.tag == 27999) {
        NSDictionary *profile = iOS27ActiveWallpaperProfile();
        %orig(iOS27ClockFontForIndex([profile[@"fontIndex"] integerValue], 78.0));
        return;
    }
    %orig;
}

- (void)setTextColor:(UIColor *)color {
    if (self.tag == 27999) {
        NSDictionary *profile = iOS27ActiveWallpaperProfile();
        %orig(iOS27ClockColorForIndex([profile[@"colorIndex"] integerValue]));
        return;
    }
    %orig;
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (self.tag == 27999 && attributedText.length > 0) {
        NSDictionary *profile = iOS27ActiveWallpaperProfile();
        UIFont *f = iOS27ClockFontForIndex([profile[@"fontIndex"] integerValue], 78.0);
        UIColor *c = iOS27ClockColorForIndex([profile[@"colorIndex"] integerValue]);
        NSMutableAttributedString *mut = [attributedText mutableCopy];
        NSRange full = NSMakeRange(0, mut.length);
        [mut addAttribute:NSFontAttributeName value:f range:full];
        [mut addAttribute:NSForegroundColorAttributeName value:c range:full];
        %orig(mut);
        return;
    }
    %orig;
}

%end

%hook NCNotificationStructuredListViewController
- (void)insertNotificationRequest:(id)request {
    %orig;
    if ([self respondsToSelector:@selector(hasVisibleContent)]) {
        PostLSNotificationState([self hasVisibleContent]);
    } else {
        PostLSNotificationState(YES);
    }
}
- (void)removeNotificationRequest:(id)request {
    %orig;
    if ([self respondsToSelector:@selector(hasVisibleContent)]) {
        PostLSNotificationState([self hasVisibleContent]);
    }
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if ([self respondsToSelector:@selector(hasVisibleContent)]) {
        PostLSNotificationState([self hasVisibleContent]);
    }
}
%end

%hook NCNotificationMasterList
- (void)insertNotificationRequest:(id)request {
    %orig;
    if ([self respondsToSelector:@selector(notificationCount)]) {
        PostLSNotificationState([self notificationCount] > 0);
    }
}
- (void)removeNotificationRequest:(id)request {
    %orig;
    if ([self respondsToSelector:@selector(notificationCount)]) {
        PostLSNotificationState([self notificationCount] > 0);
    }
}
- (void)clearAllNotificationRequests {
    %orig;
    PostLSNotificationState(NO);
}
%end

%hook SBFLockScreenDateView

- (void)_updateLabels {
    %orig;
    [self ios27_applyClockStyle];
}

- (void)setLegibilitySettings:(id)settings {
    %orig;
    [self ios27_applyClockStyle];
}

- (void)layoutSubviews {
    %orig;

    [self ios27_applyClockStyle];

    static const void *kObserverKey = &kObserverKey;
    if (!objc_getAssociatedObject(self, kObserverKey)) {
        objc_setAssociatedObject(self, kObserverKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ios27_handleNotificationChange:)
                                                     name:kIOS27NotifStateChanged
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(ios27_applyClockStyle)
                                                     name:kIOS27LSStyleChanged
                                                   object:nil];
    }

    UIView *widgetPill = [self viewWithTag:27101];
    if (!widgetPill) {
        widgetPill = [[UIView alloc] initWithFrame:CGRectZero];
        widgetPill.tag = 27101;
        widgetPill.userInteractionEnabled = NO;
        widgetPill.alpha = gHasLSNotifications ? 0.0 : 1.0;

        UILabel *helloLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        helloLabel.tag = 27102;
        helloLabel.textAlignment = NSTextAlignmentCenter;
        helloLabel.adjustsFontSizeToFitWidth = YES;
        helloLabel.minimumScaleFactor = 0.75;
        [widgetPill addSubview:helloLabel];

        [self addSubview:widgetPill];
    }

    UILabel *helloLabel = (UILabel *)[widgetPill viewWithTag:27102];
    if (helloLabel) {
        NSString *deviceName = [UIDevice currentDevice].name ?: @"iPhone";
        UIFont *helloFont = [UIFont fontWithName:@"SnellRoundhand-Bold" size:22.0] ?: [UIFont italicSystemFontOfSize:20.0];
        UIFont *nameFont = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];

        NSMutableAttributedString *attrText = [[NSMutableAttributedString alloc] init];
        [attrText appendAttributedString:[[NSAttributedString alloc] initWithString:@"hello  "
                                                                         attributes:@{
                                                                             NSFontAttributeName: helloFont,
                                                                             NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.98]
                                                                         }]];
        [attrText appendAttributedString:[[NSAttributedString alloc] initWithString:deviceName
                                                                         attributes:@{
                                                                             NSFontAttributeName: nameFont,
                                                                             NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.88],
                                                                             NSBaselineOffsetAttributeName: @(1.5)
                                                                         }]];
        helloLabel.attributedText = attrText;

        CGSize textSize = [attrText size];
        CGFloat maxPillWidth = MIN(self.bounds.size.width - 36.0, 260.0);
        CGFloat pillWidth = MIN(MAX(textSize.width + 34.0, 150.0), maxPillWidth);
        CGFloat pillHeight = 38.0;

        widgetPill.frame = CGRectMake((self.bounds.size.width - pillWidth) / 2.0, self.bounds.size.height + 10.0, pillWidth, pillHeight);
        helloLabel.frame = CGRectInset(widgetPill.bounds, 12.0, 0.0);
        ApplyLSGlassySheen(widgetPill, pillHeight / 2.0, gLSGlassAlpha);
    }
}

%new
- (void)ios27_applyClockStyle {
    UIView *timeLabel = nil;
    @try {
        timeLabel = [self valueForKey:@"_timeLabel"];
    } @catch (NSException *e) {}
    if (!timeLabel) return;

    timeLabel.tag = 27999;

    NSDictionary *profile = iOS27ActiveWallpaperProfile();
    UIFont *targetFont = iOS27ClockFontForIndex([profile[@"fontIndex"] integerValue], 78.0);
    UIColor *targetColor = iOS27ClockColorForIndex([profile[@"colorIndex"] integerValue]);

    SBUILegibilityLabel *legLabel = (SBUILegibilityLabel *)timeLabel;

    // Disable heavy shadow bitmap cache so crisp UILabel updates color & font instantly
    if ([legLabel respondsToSelector:@selector(setStrength:)]) {
        legLabel.strength = 0.0;
    }

    if ([legLabel respondsToSelector:@selector(setFont:)]) {
        legLabel.font = targetFont;
    }
    if ([legLabel respondsToSelector:@selector(setTextColor:)]) {
        legLabel.textColor = targetColor;
    }

    if ([legLabel respondsToSelector:@selector(attributedText)] && legLabel.attributedText.length > 0) {
        legLabel.attributedText = legLabel.attributedText; // Triggers our hook above
    }

    Class legClass = NSClassFromString(@"_UILegibilitySettings");
    if (legClass && [legLabel respondsToSelector:@selector(setLegibilitySettings:)]) {
        id legSettings = [[legClass alloc] initWithStyle:1
                                            primaryColor:targetColor
                                          secondaryColor:targetColor
                                             shadowColor:[UIColor clearColor]];
        legLabel.legibilitySettings = legSettings;
    }

    @try {
        UILabel *lookaside = [legLabel valueForKey:@"_lookasideLabel"];
        if ([lookaside isKindOfClass:[UILabel class]]) {
            lookaside.font = targetFont;
            lookaside.textColor = targetColor;
        }
    } @catch (NSException *e) {}

    if ([legLabel respondsToSelector:@selector(_updateLegibilityView)]) {
        [legLabel _updateLegibilityView];
    }
    [timeLabel setNeedsLayout];
    [timeLabel layoutIfNeeded];
}

%new
- (void)ios27_handleNotificationChange:(NSNotification *)note {
    BOOL hasNotifs = [note.userInfo[@"hasNotifications"] boolValue];
    UIView *widgetPill = [self viewWithTag:27101];
    if (!widgetPill) return;

    [UIView animateWithDuration:0.35
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        widgetPill.alpha = hasNotifs ? 0.0 : 1.0;
    } completion:nil];
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
    ApplyLSGlassySheen(self, self.bounds.size.width / 2.0, gLSGlassAlpha);
}
%end

%end

%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (iOS27BoolPref(@"kEnabled", YES) && iOS27BoolPref(@"kEnableLockScreen", YES)) {
        gLSGlassAlpha = iOS27FloatPref(@"kGlassAlpha", 0.25);
        %init(LockScreenHooks);
    }
}
