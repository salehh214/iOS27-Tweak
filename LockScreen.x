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
@property (nonatomic, strong) _UILegibilitySettings *legibilitySettings;
- (void)_updateLegibilityView;
@end

@interface SBFLockScreenDateView : UIView
- (void)ios27_handleNotificationChange:(NSNotification *)note;
- (void)ios27_applyClockStyle;
- (void)_updateLabels;
- (void)setLegibilitySettings:(id)settings;
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

static UIFont *iOS27ClockFontForIndex(NSInteger idx) {
    UIFontDescriptor *base = [UIFont systemFontOfSize:78.0 weight:UIFontWeightHeavy].fontDescriptor;
    switch (idx) {
        case 1:
            return [UIFont systemFontOfSize:78.0 weight:UIFontWeightBold];
        case 2: {
            UIFontDescriptor *serif = [base fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
            return serif ? [UIFont fontWithDescriptor:serif size:78.0] : [UIFont fontWithName:@"Georgia-Bold" size:74.0];
        }
        case 3: {
            UIFontDescriptor *mono = [base fontDescriptorWithDesign:UIFontDescriptorSystemDesignMonospaced];
            return mono ? [UIFont fontWithDescriptor:mono size:70.0] : [UIFont monospacedDigitSystemFontOfSize:72.0 weight:UIFontWeightBold];
        }
        case 4:
            return [UIFont systemFontOfSize:82.0 weight:UIFontWeightUltraLight];
        default: {
            UIFontDescriptor *rounded = [base fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
            return rounded ? [UIFont fontWithDescriptor:rounded size:78.0] : [UIFont systemFontOfSize:78.0 weight:UIFontWeightHeavy];
        }
    }
}

static UIColor *iOS27ClockColorForIndex(NSInteger idx) {
    switch (idx) {
        case 1: return [UIColor colorWithWhite:1.0 alpha:0.98];                                // Pure White
        case 2: return [UIColor colorWithRed:0.55 green:1.00 blue:0.80 alpha:0.96];             // Neon Mint
        case 3: return [UIColor colorWithRed:1.00 green:0.84 blue:0.42 alpha:0.96];             // Sunset Gold
        case 4: return [UIColor colorWithRed:1.00 green:0.68 blue:0.80 alpha:0.96];             // Soft Rose
        case 5: return [UIColor colorWithRed:0.80 green:0.70 blue:1.00 alpha:0.96];             // Lavender
        case 6: return [UIColor colorWithRed:1.00 green:0.52 blue:0.32 alpha:0.96];             // Vibrant Orange
        case 7: return [UIColor colorWithRed:0.35 green:0.82 blue:1.00 alpha:0.96];             // Electric Blue
        default: return [UIColor colorWithRed:0.88 green:0.96 blue:1.00 alpha:0.96];            // Ice Cyan
    }
}

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
    id timeLabel = nil;
    @try {
        timeLabel = [self valueForKey:@"_timeLabel"];
    } @catch (NSException *e) {}
    if (!timeLabel) return;

    NSInteger fontIdx = iOS27IntPref(@"kLSClockFontIndex", 0);
    NSInteger colorIdx = iOS27IntPref(@"kLSClockColorIndex", 0);
    UIFont *targetFont = iOS27ClockFontForIndex(fontIdx);
    UIColor *targetColor = iOS27ClockColorForIndex(colorIdx);

    if ([timeLabel respondsToSelector:@selector(setFont:)]) {
        [timeLabel setFont:targetFont];
    }
    if ([timeLabel respondsToSelector:@selector(setTextColor:)]) {
        [timeLabel setTextColor:targetColor];
    }

    Class legClass = NSClassFromString(@"_UILegibilitySettings");
    if (legClass && [timeLabel respondsToSelector:@selector(setLegibilitySettings:)]) {
        id legSettings = [[legClass alloc] initWithStyle:1
                                            primaryColor:targetColor
                                          secondaryColor:targetColor
                                             shadowColor:[UIColor colorWithWhite:0.0 alpha:0.25]];
        [timeLabel setLegibilitySettings:legSettings];
    }

    @try {
        UILabel *lookaside = [timeLabel valueForKey:@"_lookasideLabel"];
        if ([lookaside isKindOfClass:[UILabel class]]) {
            lookaside.font = targetFont;
            lookaside.textColor = targetColor;
        }
    } @catch (NSException *e) {}

    if ([timeLabel respondsToSelector:@selector(_updateLegibilityView)]) {
        [timeLabel _updateLegibilityView];
    }
    if ([timeLabel isKindOfClass:[UIView class]]) {
        [(UIView *)timeLabel setNeedsLayout];
        [(UIView *)timeLabel layoutIfNeeded];
    }
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
