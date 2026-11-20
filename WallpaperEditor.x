#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import "iOS27Prefs.h"

static CGFloat gEditorGlassAlpha = 0.28;

@interface CSCoverSheetViewController : UIViewController
@end

@interface SBCoverSheetPresentationManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isPresented;
- (void)setCoverSheetPresented:(BOOL)presented animated:(BOOL)animated withCompletion:(void (^)(void))completion;
@end

@interface PSSpecifier : NSObject
- (NSString *)identifier;
- (NSString *)name;
@end

@interface PSUIPrefsListController : UIViewController
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface CSCoverSheetViewController (iOS27Editor) <UIGestureRecognizerDelegate>
- (void)ios27_ensureEditorSetup;
- (void)ios27_setupWallpaperLayer;
- (void)ios27_applySavedWallpaper;
- (void)ios27_handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)ios27_enterEditorMode;
- (void)ios27_exitEditorMode;
- (void)ios27_showCustomizeIconsBar;
- (void)ios27_showMainSwitcherBar;
- (void)ios27_openSafePhotoSheet;
- (void)ios27_cycleWallpaperPreset;
- (void)ios27_cycleClockFont;
- (void)ios27_cycleClockColor;
- (void)ios27_resetWallpaper;
@end

static __weak CSCoverSheetViewController *gActiveCoverSheetVC = nil;

static void ApplyEditorGlass(UIView *view, CGFloat radius) {
    view.backgroundColor = [UIColor colorWithRed:0.08 green:0.12 blue:0.20 alpha:MAX(gEditorGlassAlpha, 0.40)];
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
            (id)[UIColor colorWithWhite:1.0 alpha:0.26].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor
        ];
        sheen.locations = @[@0.0, @0.5, @1.0];
        [view.layer insertSublayer:sheen atIndex:0];
    }
    sheen.frame = view.bounds;
    sheen.cornerRadius = radius;
}

static UIImage *iOS27LoadThumbnailAtPath(NSString *path, CGFloat maxPixelSize) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return nil;

    NSDictionary *opts = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
        (id)kCGImageSourceShouldCacheImmediately: @YES
    };
    CGImageRef cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!cgImg) return nil;

    UIImage *img = [UIImage imageWithCGImage:cgImg];
    CGImageRelease(cgImg);
    return img;
}

static NSArray<NSString *> *iOS27ScanCameraRollPhotos(void) {
    NSString *dcimPath = @"/var/mobile/Media/DCIM";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];

    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:dcimPath];
    NSString *relPath = nil;
    while ((relPath = [enumerator nextObject])) {
        NSString *ext = [[relPath pathExtension] lowercaseString];
        if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ||
            [ext isEqualToString:@"png"] || [ext isEqualToString:@"heic"]) {
            NSString *fullPath = [dcimPath stringByAppendingPathComponent:relPath];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            NSDate *modDate = attrs[NSFileModificationDate] ?: [NSDate distantPast];
            [items addObject:@{@"path": fullPath, @"date": modDate}];
        }
    }

    // Sort newest photos first
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    }];

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSUInteger limit = MIN(items.count, (NSUInteger)60); // Cap at 60 for 2GB RAM speed
    for (NSUInteger i = 0; i < limit; i++) {
        [result addObject:items[i][@"path"]];
    }
    return result;
}

// Crash-Free Lightweight In-SpringBoard Photo Gallery Sheet
@interface IOS27SafePhotoSheet : UIView <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) NSArray<NSString *> *photoPaths;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbCache;
@property (nonatomic, copy) void (^onSelectPath)(NSString *path);
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation IOS27SafePhotoSheet

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.thumbCache = [[NSCache alloc] init];
        self.thumbCache.countLimit = 45;
        self.photoPaths = iOS27ScanCameraRollPhotos();

        ApplyEditorGlass(self, 28.0);

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, frame.size.width - 80, 28)];
        title.text = @"Photos";
        title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(frame.size.width - 44, 10, 32, 32);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold];
            [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
            closeBtn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85];
        } else {
            [closeBtn setTitle:@"X" forState:UIControlStateNormal];
        }
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        if (self.photoPaths.count == 0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, frame.size.width - 40, 80)];
            empty.text = @"No photos found in Camera Roll.";
            empty.textAlignment = NSTextAlignmentCenter;
            empty.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
            empty.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
            [self addSubview:empty];
        } else {
            UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
            CGFloat spacing = 6.0;
            CGFloat itemW = floor((frame.size.width - 24.0 - spacing * 2.0) / 3.0);
            layout.itemSize = CGSizeMake(itemW, itemW * 1.25);
            layout.minimumInteritemSpacing = spacing;
            layout.minimumLineSpacing = spacing;
            layout.sectionInset = UIEdgeInsetsMake(6, 12, 16, 12);

            UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 48, frame.size.width, frame.size.height - 48) collectionViewLayout:layout];
            cv.backgroundColor = [UIColor clearColor];
            cv.dataSource = self;
            cv.delegate = self;
            [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"PhotoCell"];
            [self addSubview:cv];
        }
    }
    return self;
}

- (void)closeTapped {
    if (self.onClose) self.onClose();
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.photoPaths.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"PhotoCell" forIndexPath:indexPath];
    UIImageView *iv = (UIImageView *)[cell.contentView viewWithTag:901];
    if (!iv) {
        iv = [[UIImageView alloc] initWithFrame:cell.contentView.bounds];
        iv.tag = 901;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 10.0;
        iv.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
        iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [cell.contentView addSubview:iv];
    }

    NSString *path = self.photoPaths[indexPath.item];
    iv.image = nil;
    UIImage *cached = [self.thumbCache objectForKey:path];
    if (cached) {
        iv.image = cached;
    } else {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *thumb = iOS27LoadThumbnailAtPath(path, 220.0);
            if (thumb) {
                [self.thumbCache setObject:thumb forKey:path];
                dispatch_async(dispatch_get_main_queue(), ^{
                    UICollectionViewCell *visibleCell = [collectionView cellForItemAtIndexPath:indexPath];
                    UIImageView *visibleIV = (UIImageView *)[visibleCell.contentView viewWithTag:901];
                    if (visibleIV) visibleIV.image = thumb;
                });
            }
        });
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *path = self.photoPaths[indexPath.item];
    if (self.onSelectPath) self.onSelectPath(path);
}

@end

static UIButton *CreateIconOnlyButton(NSString *symbolName, id target, SEL action) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightMedium];
        UIImage *img = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
        [btn setImage:img forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
    }
    [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

static const void *kGestureAddedKey = &kGestureAddedKey;
static const void *kIsEditingKey = &kIsEditingKey;
static const void *kEditorOverlayKey = &kEditorOverlayKey;
static const void *kMainBarKey = &kMainBarKey;
static const void *kIconsBarKey = &kIconsBarKey;
static const void *kPhotoSheetKey = &kPhotoSheetKey;

static void DarwinOpenEditorCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SBCoverSheetPresentationManager *pm = [%c(SBCoverSheetPresentationManager) sharedInstance];
        if (pm && [pm respondsToSelector:@selector(setCoverSheetPresented:animated:withCompletion:)]) {
            [pm setCoverSheetPresented:YES animated:YES withCompletion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (gActiveCoverSheetVC) {
                        [gActiveCoverSheetVC ios27_enterEditorMode];
                    }
                });
            }];
        } else if (gActiveCoverSheetVC) {
            [gActiveCoverSheetVC ios27_enterEditorMode];
        }
    });
}

%group WallpaperEditorHooks

%hook CSCoverSheetViewController

- (void)viewDidLoad {
    %orig;
    gActiveCoverSheetVC = self;
    [self ios27_ensureEditorSetup];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gActiveCoverSheetVC = self;
    [self ios27_ensureEditorSetup];
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
- (void)ios27_ensureEditorSetup {
    [self ios27_setupWallpaperLayer];
    [self ios27_applySavedWallpaper];

    if (!objc_getAssociatedObject(self, kGestureAddedKey)) {
        objc_setAssociatedObject(self, kGestureAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(ios27_handleLongPress:)];
        longPress.minimumPressDuration = 0.5;
        longPress.allowableMovement = 25.0;
        longPress.cancelsTouchesInView = NO;
        longPress.delaysTouchesBegan = NO;
        longPress.delegate = self;
        [self.view addGestureRecognizer:longPress];
    }
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([objc_getAssociatedObject(self, kIsEditingKey) boolValue]) {
        return NO;
    }
    UIView *v = touch.view;
    while (v && v != self.view) {
        NSString *cls = NSStringFromClass([v class]);
        if ([v isKindOfClass:[UIControl class]] ||
            [cls containsString:@"ShortLook"] ||
            [cls containsString:@"PlatterView"]) {
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
    iOS27ApplyWallpaperToView(wpView);
    // Notify Home Screen to sync wallpaper live
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27WallpaperChanged object:nil];
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
    if ([objc_getAssociatedObject(self, kIsEditingKey) boolValue]) return;
    objc_setAssociatedObject(self, kIsEditingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    UIWindow *hostWindow = self.view.window;
    if (!hostWindow) return;

    UIView *oldOverlay = objc_getAssociatedObject(self, kEditorOverlayKey);
    if (oldOverlay) [oldOverlay removeFromSuperview];

    UIView *overlay = [[UIView alloc] initWithFrame:hostWindow.bounds];
    overlay.backgroundColor = [UIColor clearColor];
    overlay.alpha = 0.0;
    [hostWindow addSubview:overlay];
    objc_setAssociatedObject(self, kEditorOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGFloat w = hostWindow.bounds.size.width;
    CGFloat h = hostWindow.bounds.size.height;

    // Top Buttons: Reset (Left) & Done (Right)
    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    doneBtn.frame = CGRectMake(w - 84.0, 32.0, 70.0, 32.0);
    [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    [doneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ApplyEditorGlass(doneBtn, 16.0);
    [doneBtn addTarget:self action:@selector(ios27_exitEditorMode) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:doneBtn];

    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    resetBtn.frame = CGRectMake(14.0, 32.0, 70.0, 32.0);
    [resetBtn setTitle:@"Reset" forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    [resetBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.9] forState:UIControlStateNormal];
    ApplyEditorGlass(resetBtn, 16.0);
    [resetBtn addTarget:self action:@selector(ios27_resetWallpaper) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:resetBtn];

    // Stage 1 Bottom Bar: "Customize" Pill + "+" Circle Button (iOS 27 Switcher Style)
    CGFloat barY = h - 70.0;
    UIView *mainBar = [[UIView alloc] initWithFrame:CGRectMake(0, barY, w, 46.0)];
    mainBar.backgroundColor = [UIColor clearColor];

    CGFloat custW = 148.0;
    CGFloat plusSize = 44.0;
    CGFloat totalW = custW + 14.0 + plusSize;
    CGFloat startX = (w - totalW) / 2.0;

    UIButton *customizeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    customizeBtn.frame = CGRectMake(startX, 1.0, custW, 44.0);
    [customizeBtn setTitle:@"Customize" forState:UIControlStateNormal];
    customizeBtn.titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
    [customizeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ApplyEditorGlass(customizeBtn, 22.0);
    [customizeBtn addTarget:self action:@selector(ios27_showCustomizeIconsBar) forControlEvents:UIControlEventTouchUpInside];
    [mainBar addSubview:customizeBtn];

    UIButton *plusBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    plusBtn.frame = CGRectMake(startX + custW + 14.0, 1.0, plusSize, plusSize);
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightSemibold];
        [plusBtn setImage:[UIImage systemImageNamed:@"plus" withConfiguration:cfg] forState:UIControlStateNormal];
        plusBtn.tintColor = [UIColor whiteColor];
    } else {
        [plusBtn setTitle:@"+" forState:UIControlStateNormal];
    }
    ApplyEditorGlass(plusBtn, plusSize / 2.0);
    [plusBtn addTarget:self action:@selector(ios27_cycleWallpaperPreset) forControlEvents:UIControlEventTouchUpInside];
    [mainBar addSubview:plusBtn];

    [overlay addSubview:mainBar];
    objc_setAssociatedObject(self, kMainBarKey, mainBar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Stage 2 Bottom Bar: Icon-Only Customization Dock (Hidden initially until Customize is tapped)
    CGFloat dockH = 52.0;
    CGFloat dockW = MIN(w - 36.0, 290.0);
    UIView *iconsDock = [[UIView alloc] initWithFrame:CGRectMake((w - dockW) / 2.0, h - dockH - 22.0, dockW, dockH)];
    ApplyEditorGlass(iconsDock, 26.0);
    iconsDock.alpha = 0.0;
    iconsDock.hidden = YES;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectInset(iconsDock.bounds, 10.0, 4.0)];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 4.0;

    [stack addArrangedSubview:CreateIconOnlyButton(@"photo.on.rectangle", self, @selector(ios27_openSafePhotoSheet))];
    [stack addArrangedSubview:CreateIconOnlyButton(@"sparkles", self, @selector(ios27_cycleWallpaperPreset))];
    [stack addArrangedSubview:CreateIconOnlyButton(@"textformat", self, @selector(ios27_cycleClockFont))];
    [stack addArrangedSubview:CreateIconOnlyButton(@"paintpalette", self, @selector(ios27_cycleClockColor))];
    [stack addArrangedSubview:CreateIconOnlyButton(@"chevron.down", self, @selector(ios27_showMainSwitcherBar))];
    [iconsDock addSubview:stack];

    [overlay addSubview:iconsDock];
    objc_setAssociatedObject(self, kIconsBarKey, iconsDock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Zoom-Out Card Animation
    self.view.clipsToBounds = YES;
    [UIView animateWithDuration:0.32
                          delay:0.0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.view.transform = CGAffineTransformMakeScale(0.78, 0.78);
        self.view.layer.cornerRadius = 30.0;
        self.view.layer.borderWidth = 2.0;
        self.view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
        overlay.alpha = 1.0;
    } completion:nil];
}

%new
- (void)ios27_showCustomizeIconsBar {
    UIView *mainBar = objc_getAssociatedObject(self, kMainBarKey);
    UIView *iconsDock = objc_getAssociatedObject(self, kIconsBarKey);
    iconsDock.hidden = NO;

    [UIView animateWithDuration:0.22 animations:^{
        mainBar.alpha = 0.0;
        iconsDock.alpha = 1.0;
    } completion:^(BOOL finished) {
        mainBar.hidden = YES;
    }];
}

%new
- (void)ios27_showMainSwitcherBar {
    UIView *mainBar = objc_getAssociatedObject(self, kMainBarKey);
    UIView *iconsDock = objc_getAssociatedObject(self, kIconsBarKey);
    mainBar.hidden = NO;

    [UIView animateWithDuration:0.22 animations:^{
        iconsDock.alpha = 0.0;
        mainBar.alpha = 1.0;
    } completion:^(BOOL finished) {
        iconsDock.hidden = YES;
    }];
}

%new
- (void)ios27_openSafePhotoSheet {
    UIView *overlay = objc_getAssociatedObject(self, kEditorOverlayKey);
    if (!overlay) return;

    UIView *oldSheet = objc_getAssociatedObject(self, kPhotoSheetKey);
    if (oldSheet) [oldSheet removeFromSuperview];

    CGFloat w = overlay.bounds.size.width;
    CGFloat h = overlay.bounds.size.height;
    CGFloat sheetH = h * 0.62;

    IOS27SafePhotoSheet *sheet = [[IOS27SafePhotoSheet alloc] initWithFrame:CGRectMake(12.0, h, w - 24.0, sheetH)];
    __weak typeof(self) weakSelf = self;
    __weak typeof(sheet) weakSheet = sheet;

    sheet.onClose = ^{
        [UIView animateWithDuration:0.25 animations:^{
            weakSheet.frame = CGRectMake(12.0, h, w - 24.0, sheetH);
        } completion:^(BOOL finished) {
            [weakSheet removeFromSuperview];
            objc_setAssociatedObject(weakSelf, kPhotoSheetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
    };

    sheet.onSelectPath = ^(NSString *selectedPath) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            CGFloat maxDim = MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height) * MIN([UIScreen mainScreen].scale, 2.0);
            UIImage *resized = iOS27LoadThumbnailAtPath(selectedPath, maxDim);
            NSData *jpegData = UIImageJPEGRepresentation(resized, 0.85);
            if (jpegData) {
                [jpegData writeToFile:iOS27WallpaperFilePath() atomically:YES];
                iOS27SetIntPref(@"kLSWallpaperMode", 1);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf ios27_applySavedWallpaper];
                    if (weakSheet.onClose) weakSheet.onClose();
                });
            }
        });
    };

    [overlay addSubview:sheet];
    objc_setAssociatedObject(self, kPhotoSheetKey, sheet, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        sheet.frame = CGRectMake(12.0, h - sheetH - 16.0, w - 24.0, sheetH);
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
        objc_setAssociatedObject(self, kMainBarKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kIconsBarKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kPhotoSheetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
}

%new
- (void)ios27_cycleWallpaperPreset {
    NSInteger current = iOS27IntPref(@"kLSWallpaperMode", 0);
    NSInteger maxMode = 2 + kIOS27ThemeCount - 1; // Modes 2..13 (12 themes)
    NSInteger next = (current < 2 || current >= maxMode) ? 2 : (current + 1);
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
    NSInteger next = (current + 1) % 8;
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

// Hook Settings App (com.apple.Preferences) -> Redirect "Wallpaper" to our iOS 27 Editor
%group SettingsWallpaperRedirectHooks

%hook PSUIPrefsListController

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self respondsToSelector:@selector(specifierAtIndexPath:)] ? [self specifierAtIndexPath:indexPath] : nil;
    NSString *ident = ([spec respondsToSelector:@selector(identifier)] && spec.identifier) ? [spec.identifier lowercaseString] : @"";
    NSString *name = ([spec respondsToSelector:@selector(name)] && spec.name) ? [spec.name lowercaseString] : @"";

    if ([ident isEqualToString:@"wallpaper"] || [name isEqualToString:@"wallpaper"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR("com.elite.ios27.openWallpaperEditor"),
                                             NULL, NULL, true);
        return;
    }
    %orig;
}

%end

%end

%ctor {
    if (!iOS27BoolPref(@"kEnabled", YES) || !iOS27BoolPref(@"kEnableLockScreen", YES)) return;

    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        gEditorGlassAlpha = iOS27FloatPref(@"kGlassAlpha", 0.28);
        %init(WallpaperEditorHooks);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        DarwinOpenEditorCallback,
                                        CFSTR("com.elite.ios27.openWallpaperEditor"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    } else if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
        %init(SettingsWallpaperRedirectHooks);
    }
}
