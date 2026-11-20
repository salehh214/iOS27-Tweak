#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>
#import "iOS27Prefs.h"

static CGFloat gEditorGlassAlpha = 0.28;

@interface CSCoverSheetViewController : UIViewController
@end

@interface CSCoverSheetViewController (iOS27Editor) <PHPickerViewControllerDelegate, UIGestureRecognizerDelegate>
- (void)ios27_setupWallpaperLayer;
- (void)ios27_applySavedWallpaper;
- (void)ios27_handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)ios27_enterEditorMode;
- (void)ios27_exitEditorMode;
- (void)ios27_openPhotoPicker;
- (void)ios27_cycleWallpaperPreset;
- (void)ios27_cycleClockFont;
- (void)ios27_cycleClockColor;
- (void)ios27_resetWallpaper;
@end

static NSString *iOS27WallpaperFilePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libDir = paths.firstObject ?: @"/var/mobile/Library";
    return [libDir stringByAppendingPathComponent:@"Preferences/iOS27_CustomLSWallpaper.jpg"];
}

static UIImage *iOS27ResizeImageForScreen(UIImage *image) {
    if (!image) return nil;
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat scale = MIN([UIScreen mainScreen].scale, 2.0); // Cap scale at 2x for 2GB RAM safety
    CGSize targetSize = CGSizeMake(screenSize.width * scale, screenSize.height * scale);

    CGFloat widthRatio = targetSize.width / image.size.width;
    CGFloat heightRatio = targetSize.height / image.size.height;
    CGFloat ratio = MAX(widthRatio, heightRatio);
    CGSize newSize = CGSizeMake(image.size.width * ratio, image.size.height * ratio);

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    }];
}

static void ApplyEditorGlass(UIView *view, CGFloat radius) {
    view.backgroundColor = [UIColor colorWithRed:0.08 green:0.12 blue:0.20 alpha:MAX(gEditorGlassAlpha, 0.35)];
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.1;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
    view.clipsToBounds = YES;

    CAGradientLayer *sheen = nil;
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"iOS27EditorSheen"]) {
            sheen = (CAGradientLayer *)layer;
            break;
        }
    }
    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.name = @"iOS27EditorSheen";
        sheen.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.25].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor
        ];
        sheen.locations = @[@0.0, @0.5, @1.0];
        [view.layer insertSublayer:sheen atIndex:0];
    }
    sheen.frame = view.bounds;
    sheen.cornerRadius = radius;
}

static UIButton *CreateEditorButton(NSString *symbolName, NSString *title, id target, SEL action) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn setTitle:title forState:UIControlStateNormal];

    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightMedium];
        UIImage *img = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
        [btn setImage:img forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
    }

    btn.contentEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);
    btn.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
    [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

static const void *kIsEditingKey = &kIsEditingKey;
static const void *kEditorOverlayKey = &kEditorOverlayKey;

%group WallpaperEditorHooks

%hook CSCoverSheetViewController

- (void)viewDidLoad {
    %orig;
    [self ios27_setupWallpaperLayer];
    [self ios27_applySavedWallpaper];

    // Long-press gesture on Lock Screen / Notification Center
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(ios27_handleLongPress:)];
    longPress.minimumPressDuration = 0.55;
    longPress.cancelsTouchesInView = NO;
    longPress.delegate = self;
    [self.view addGestureRecognizer:longPress];
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *wpContainer = [self.view viewWithTag:27300];
    if (wpContainer) {
        wpContainer.frame = self.view.bounds;
        for (CALayer *sub in wpContainer.layer.sublayers) {
            if ([sub.name isEqualToString:@"iOS27PresetGradient"]) {
                sub.frame = wpContainer.bounds;
            }
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if ([objc_getAssociatedObject(self, kIsEditingKey) boolValue]) {
        [self ios27_exitEditorMode];
    }
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *v = touch.view;
    while (v && v != self.view) {
        // Ignore taps on buttons, sliders, or notification cells
        if ([v isKindOfClass:[UIControl class]] ||
            [NSStringFromClass([v class]) containsString:@"Notification"] ||
            [NSStringFromClass([v class]) containsString:@"Platter"]) {
            return NO;
        }
        v = v.superview;
    }
    return YES;
}

%new
- (void)ios27_setupWallpaperLayer {
    if ([self.view viewWithTag:27300]) return;

    UIImageView *wpView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    wpView.tag = 27300;
    wpView.contentMode = UIViewContentModeScaleAspectFill;
    wpView.clipsToBounds = YES;
    wpView.userInteractionEnabled = NO;
    wpView.hidden = YES;
    wpView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:wpView atIndex:0];
}

%new
- (void)ios27_applySavedWallpaper {
    UIImageView *wpView = (UIImageView *)[self.view viewWithTag:27300];
    if (!wpView) return;

    // Remove old preset gradient if any
    for (CALayer *sub in [wpView.layer.sublayers copy]) {
        if ([sub.name isEqualToString:@"iOS27PresetGradient"]) {
            [sub removeFromSuperlayer];
        }
    }

    // Mode: 0 = Stock iOS Wallpaper, 1 = Custom Photo, 2..5 = Built-in iOS 27 Presets
    NSInteger mode = iOS27IntPref(@"kLSWallpaperMode", 0);

    if (mode == 0) {
        wpView.image = nil;
        wpView.hidden = YES;
        return;
    }

    if (mode == 1) {
        NSString *path = iOS27WallpaperFilePath();
        UIImage *savedImg = [UIImage imageWithContentsOfFile:path];
        if (savedImg) {
            wpView.image = savedImg;
            wpView.hidden = NO;
            return;
        } else {
            wpView.hidden = YES;
            return;
        }
    }

    // Built-in Lightweight iOS 27 Gradient Themes (Zero RAM overhead)
    wpView.image = nil;
    wpView.hidden = NO;

    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.name = @"iOS27PresetGradient";
    grad.frame = wpView.bounds;
    grad.startPoint = CGPointMake(0.1, 0.0);
    grad.endPoint = CGPointMake(0.9, 1.0);

    if (mode == 2) {
        // Cyber Ocean
        grad.colors = @[
            (id)[UIColor colorWithRed:0.03 green:0.10 blue:0.25 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.05 green:0.35 blue:0.55 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.10 green:0.70 blue:0.75 alpha:1.0].CGColor
        ];
    } else if (mode == 3) {
        // Midnight Aurora
        grad.colors = @[
            (id)[UIColor colorWithRed:0.06 green:0.04 blue:0.18 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.28 green:0.10 blue:0.42 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.10 green:0.45 blue:0.55 alpha:1.0].CGColor
        ];
    } else if (mode == 4) {
        // Sunset Glass
        grad.colors = @[
            (id)[UIColor colorWithRed:0.15 green:0.05 blue:0.22 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.65 green:0.18 blue:0.35 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.95 green:0.55 blue:0.25 alpha:1.0].CGColor
        ];
    } else {
        // Obsidian Minimal
        grad.colors = @[
            (id)[UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.12 green:0.15 blue:0.22 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.05 green:0.07 blue:0.10 alpha:1.0].CGColor
        ];
    }
    [wpView.layer insertSublayer:grad atIndex:0];
}

%new
- (void)ios27_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    BOOL isEditing = [objc_getAssociatedObject(self, kIsEditingKey) boolValue];
    if (!isEditing) {
        [self ios27_enterEditorMode];
    }
}

%new
- (void)ios27_enterEditorMode {
    objc_setAssociatedObject(self, kIsEditingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    UIWindow *hostWindow = self.view.window;
    if (!hostWindow) return;

    // Remove existing overlay if any
    UIView *oldOverlay = objc_getAssociatedObject(self, kEditorOverlayKey);
    if (oldOverlay) [oldOverlay removeFromSuperview];

    // Transparent HUD container on window so controls stay full-size while Lock Screen zooms out
    UIView *overlay = [[UIView alloc] initWithFrame:hostWindow.bounds];
    overlay.backgroundColor = [UIColor clearColor];
    overlay.alpha = 0.0;
    [hostWindow addSubview:overlay];
    objc_setAssociatedObject(self, kEditorOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGFloat w = hostWindow.bounds.size.width;
    CGFloat h = hostWindow.bounds.size.height;

    // Top Header: Title + Done + Reset
    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    doneBtn.frame = CGRectMake(w - 86.0, 34.0, 72.0, 32.0);
    [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    [doneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ApplyEditorGlass(doneBtn, 16.0);
    [doneBtn addTarget:self action:@selector(ios27_exitEditorMode) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:doneBtn];

    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    resetBtn.frame = CGRectMake(14.0, 34.0, 72.0, 32.0);
    [resetBtn setTitle:@"Reset" forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    [resetBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.9] forState:UIControlStateNormal];
    ApplyEditorGlass(resetBtn, 16.0);
    [resetBtn addTarget:self action:@selector(ios27_resetWallpaper) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:resetBtn];

    // Bottom Glassy Customization Dock
    CGFloat dockH = 54.0;
    CGFloat dockW = MIN(w - 24.0, 340.0);
    UIView *dock = [[UIView alloc] initWithFrame:CGRectMake((w - dockW) / 2.0, h - dockH - 22.0, dockW, dockH)];
    ApplyEditorGlass(dock, 27.0);
    [overlay addSubview:dock];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectInset(dock.bounds, 8.0, 4.0)];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 2.0;

    [stack addArrangedSubview:CreateEditorButton(@"photo.on.rectangle", @"Photos", self, @selector(ios27_openPhotoPicker))];
    [stack addArrangedSubview:CreateEditorButton(@"sparkles", @"Themes", self, @selector(ios27_cycleWallpaperPreset))];
    [stack addArrangedSubview:CreateEditorButton(@"textformat", @"Font", self, @selector(ios27_cycleClockFont))];
    [stack addArrangedSubview:CreateEditorButton(@"paintpalette", @"Color", self, @selector(ios27_cycleClockColor))];
    [dock addSubview:stack];

    // Zoom-Out Card Animation on CoverSheet View
    self.view.clipsToBounds = YES;
    [UIView animateWithDuration:0.32
                          delay:0.0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.view.transform = CGAffineTransformMakeScale(0.80, 0.80);
        self.view.layer.cornerRadius = 30.0;
        self.view.layer.borderWidth = 2.0;
        self.view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
        overlay.alpha = 1.0;
    } completion:nil];
}

%new
- (void)ios27_exitEditorMode {
    objc_setAssociatedObject(self, kIsEditingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *overlay = objc_getAssociatedObject(self, kEditorOverlayKey);

    [UIView animateWithDuration:0.26
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.view.transform = CGAffineTransformIdentity;
        self.view.layer.cornerRadius = 0.0;
        self.view.layer.borderWidth = 0.0;
        overlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
        objc_setAssociatedObject(self, kEditorOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
}

%new
- (void)ios27_openPhotoPicker {
    if (@available(iOS 14.0, *)) {
        // Temporarily hide overlay so picker isn't covered
        UIView *overlay = objc_getAssociatedObject(self, kEditorOverlayKey);
        overlay.hidden = YES;

        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
        config.selectionLimit = 1;
        config.filter = [PHPickerFilter imagesFilter];

        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        picker.delegate = self;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

%new
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:^{
        UIView *overlay = objc_getAssociatedObject(self, kEditorOverlayKey);
        overlay.hidden = NO;
    }];

    PHPickerResult *first = results.firstObject;
    if (!first || ![first.itemProvider canLoadObjectOfClass:[UIImage class]]) return;

    [first.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(__kindof id<NSItemProviderReading> object, NSError *error) {
        if (![object isKindOfClass:[UIImage class]]) return;
        UIImage *picked = (UIImage *)object;
        UIImage *resized = iOS27ResizeImageForScreen(picked);
        NSData *jpegData = UIImageJPEGRepresentation(resized, 0.85);
        if (jpegData) {
            [jpegData writeToFile:iOS27WallpaperFilePath() atomically:YES];
            iOS27SetIntPref(@"kLSWallpaperMode", 1);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self ios27_applySavedWallpaper];
            });
        }
    }];
}

%new
- (void)ios27_cycleWallpaperPreset {
    NSInteger current = iOS27IntPref(@"kLSWallpaperMode", 0);
    NSInteger next = (current < 2 || current >= 5) ? 2 : (current + 1);
    iOS27SetIntPref(@"kLSWallpaperMode", next);
    [self ios27_applySavedWallpaper];
}

%new
- (void)ios27_cycleClockFont {
    NSInteger current = iOS27IntPref(@"kLSClockFontIndex", 0);
    NSInteger next = (current + 1) % 5;
    iOS27SetIntPref(@"kLSClockFontIndex", next);
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27LSStyleChanged object:nil];
}

%new
- (void)ios27_cycleClockColor {
    NSInteger current = iOS27IntPref(@"kLSClockColorIndex", 0);
    NSInteger next = (current + 1) % 6;
    iOS27SetIntPref(@"kLSClockColorIndex", next);
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27LSStyleChanged object:nil];
}

%new
- (void)ios27_resetWallpaper {
    iOS27SetIntPref(@"kLSWallpaperMode", 0);
    iOS27SetIntPref(@"kLSClockFontIndex", 0);
    iOS27SetIntPref(@"kLSClockColorIndex", 0);
    [self ios27_applySavedWallpaper];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27LSStyleChanged object:nil];
}

%end

%end

%ctor {
    if (iOS27BoolPref(@"kEnabled", YES) && iOS27BoolPref(@"kEnableLockScreen", YES)) {
        gEditorGlassAlpha = iOS27FloatPref(@"kGlassAlpha", 0.28);
        %init(WallpaperEditorHooks);
    }
}
