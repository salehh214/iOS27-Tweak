#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "iOS27Prefs.h"

@interface SBHomeScreenButton : UIButton
@end

@interface SBHAddWidgetButton : UIButton
@end

@interface SBHTitledHomeScreenButton : UIButton
@end

@interface SBRootFolderView : UIView
- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
- (BOOL)isEditing;
- (UIControl *)pageControl;
- (void)ios27_updateEditOverlay:(BOOL)editing;
- (void)ios27_hideStockTopButtonsInWindow:(UIWindow *)win;
- (void)ios27_brushTapped;
- (void)ios27_doneTapped;
- (void)ios27_dismissMenu;
- (void)ios27_menuAddWidget;
- (void)ios27_menuCustomize;
- (void)ios27_menuEditWallpaper;
- (void)ios27_menuEditPages;
@end

@interface SBRootFolderController : UIViewController
@end

@interface SBHIconManager : NSObject
- (BOOL)isEditing;
- (void)setEditing:(BOOL)editing;
- (SBRootFolderController *)rootFolderController;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
- (void)setEditing:(BOOL)editing;
@end

static __weak UIControl *gStockAddButton = nil;
static __weak UIControl *gStockDoneButton = nil;

static void ApplyHSEditorGlass(UIView *view, CGFloat radius, CGFloat alpha) {
    view.backgroundColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:alpha];
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    view.clipsToBounds = YES;

    CAGradientLayer *sheen = nil;
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"iOS27HSSheen"]) {
            sheen = (CAGradientLayer *)layer;
            break;
        }
    }
    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.name = @"iOS27HSSheen";
        sheen.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.22].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor
        ];
        sheen.locations = @[@0.0, @0.5, @1.0];
        [view.layer insertSublayer:sheen atIndex:0];
    }
    sheen.frame = view.bounds;
    sheen.cornerRadius = radius;
}

static void RefreshAllVisibleIconsInView(UIView *root) {
    if (!root) return;
    NSString *cls = NSStringFromClass([root class]);
    if ([cls isEqualToString:@"SBIconView"] || [cls isEqualToString:@"SBIconListPageControl"]) {
        [root setNeedsLayout];
        [root layoutIfNeeded];
        return;
    }
    for (UIView *sub in root.subviews) {
        RefreshAllVisibleIconsInView(sub);
    }
}

// Safely fire every target-action registered on a hidden UIControl
static BOOL FireControlActionsDirectly(UIControl *control) {
    if (!control) return NO;
    BOOL fired = NO;
    UIControlEvents eventsToCheck[] = {
        UIControlEventTouchUpInside,
        UIControlEventPrimaryActionTriggered,
        UIControlEventTouchDown
    };

    NSSet *targets = [control allTargets];
    for (id target in targets) {
        if (!target || target == [NSNull null]) continue;
        for (int i = 0; i < 3; i++) {
            NSArray<NSString *> *actions = [control actionsForTarget:target forControlEvent:eventsToCheck[i]];
            for (NSString *actionName in actions) {
                SEL sel = NSSelectorFromString(actionName);
                if ([target respondsToSelector:sel]) {
                    if ([actionName hasSuffix:@":"]) {
                        ((void (*)(id, SEL, id))objc_msgSend)(target, sel, control);
                    } else {
                        ((void (*)(id, SEL))objc_msgSend)(target, sel);
                    }
                    fired = YES;
                }
            }
            if (fired) return YES;
        }
    }

    // Fallback: standard UIControl sendActions
    BOOL prevEnabled = control.enabled;
    control.enabled = YES;
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    control.enabled = prevEnabled;
    return YES;
}

static UIControl *FindPageControlInView(UIView *root) {
    if (!root) return nil;
    if ([NSStringFromClass([root class]) containsString:@"PageControl"] && [root isKindOfClass:[UIControl class]]) {
        return (UIControl *)root;
    }
    for (UIView *sub in root.subviews) {
        UIControl *found = FindPageControlInView(sub);
        if (found) return found;
    }
    return nil;
}

static void ScanAndHideStockButtons(UIView *view, UIWindow *win) {
    if (!view || !win) return;
    // Skip our own custom overlay views (tags 27500..27599)
    if (view.tag >= 27500 && view.tag <= 27599) return;

    NSString *cls = NSStringFromClass([view class]);
    BOOL isCandidate = [view isKindOfClass:[UIControl class]] &&
                       ([cls containsString:@"HomeScreenButton"] ||
                        [cls containsString:@"AddWidget"] ||
                        [cls containsString:@"PlusButton"] ||
                        [cls containsString:@"DoneButton"] ||
                        [view isKindOfClass:[UIButton class]]);

    if (isCandidate) {
        CGRect winRect = [view convertRect:view.bounds toView:win];
        if (winRect.origin.y >= -4.0 && winRect.origin.y < 85.0 &&
            winRect.size.width > 18.0 && winRect.size.width < 130.0 &&
            winRect.size.height > 18.0 && winRect.size.height < 65.0) {

            if (winRect.origin.x < win.bounds.size.width / 2.0) {
                gStockAddButton = (UIControl *)view;
            } else {
                gStockDoneButton = (UIControl *)view;
            }
            view.alpha = 0.0;
            view.hidden = YES;
            view.userInteractionEnabled = NO;
            return;
        }
    }

    for (UIView *sub in view.subviews) {
        ScanAndHideStockButtons(sub, win);
    }
}

static UIImage *iOS27HSLoadThumb(NSString *path, CGFloat maxPixelSize) {
    if (!path) return nil;
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

static NSArray<NSString *> *iOS27HSScanPhotos(void) {
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

    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    }];

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSUInteger limit = MIN(items.count, (NSUInteger)60);
    for (NSUInteger i = 0; i < limit; i++) {
        [result addObject:items[i][@"path"]];
    }
    return result;
}

// =========================================================================
// 1. Crash-Free Home Screen Photo Picker Sheet
// =========================================================================
@interface IOS27HSPhotoSheet : UIView <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) NSArray<NSString *> *photoPaths;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbCache;
@property (nonatomic, copy) void (^onSelectPath)(NSString *path);
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation IOS27HSPhotoSheet

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.tag = 27520;
        self.thumbCache = [[NSCache alloc] init];
        self.thumbCache.countLimit = 40;
        self.photoPaths = iOS27HSScanPhotos();

        self.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.97];
        self.layer.cornerRadius = 24.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        self.clipsToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, frame.size.width - 70, 28)];
        title.text = @"Home Screen Photo";
        title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(frame.size.width - 42, 8, 32, 32);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold];
            [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
            closeBtn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.8];
        }
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        CGFloat spacing = 6.0;
        CGFloat itemW = floor((frame.size.width - 24.0 - spacing * 2.0) / 3.0);
        layout.itemSize = CGSizeMake(itemW, itemW * 1.25);
        layout.minimumInteritemSpacing = spacing;
        layout.minimumLineSpacing = spacing;
        layout.sectionInset = UIEdgeInsetsMake(6, 12, 14, 12);

        UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 44, frame.size.width, frame.size.height - 44) collectionViewLayout:layout];
        cv.backgroundColor = [UIColor clearColor];
        cv.dataSource = self;
        cv.delegate = self;
        [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"HSPhotoCell"];
        [self addSubview:cv];
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
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HSPhotoCell" forIndexPath:indexPath];
    UIImageView *iv = (UIImageView *)[cell.contentView viewWithTag:911];
    if (!iv) {
        iv = [[UIImageView alloc] initWithFrame:cell.contentView.bounds];
        iv.tag = 911;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 10.0;
        iv.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
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
            UIImage *thumb = iOS27HSLoadThumb(path, 200.0);
            if (thumb) {
                [self.thumbCache setObject:thumb forKey:path];
                dispatch_async(dispatch_get_main_queue(), ^{
                    UICollectionViewCell *vCell = [collectionView cellForItemAtIndexPath:indexPath];
                    UIImageView *vIV = (UIImageView *)[vCell.contentView viewWithTag:911];
                    if (vIV) vIV.image = thumb;
                });
            }
        });
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.onSelectPath) self.onSelectPath(self.photoPaths[indexPath.item]);
}

@end

// =========================================================================
// 2. Full-Screen Home Screen Wallpaper Studio (Pair / Color / Gradient / Photo | Blur)
// =========================================================================
@interface IOS27HomeWallpaperStudioView : UIView
@property (nonatomic, assign) NSInteger draftMode;
@property (nonatomic, assign) NSInteger draftColorIdx;
@property (nonatomic, assign) NSInteger draftGradIdx;
@property (nonatomic, assign) BOOL draftBlur;
@property (nonatomic, strong) UIImageView *previewWallpaper;
@property (nonatomic, strong) UIButton *pairCircle;
@property (nonatomic, strong) UIButton *colorCircle;
@property (nonatomic, strong) UIButton *gradCircle;
@property (nonatomic, strong) UIButton *photoCircle;
@property (nonatomic, strong) UIButton *blurCircle;
@property (nonatomic, strong) IOS27HSPhotoSheet *photoSheet;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation IOS27HomeWallpaperStudioView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.tag = 27510;
        self.backgroundColor = [UIColor blackColor];

        self.draftMode = iOS27IntPref(@"kHSWallpaperMode", 0);
        self.draftColorIdx = iOS27IntPref(@"kHSColorIndex", 0);
        self.draftGradIdx = iOS27IntPref(@"kHSGradientIndex", 0);
        self.draftBlur = iOS27BoolPref(@"kHSBlurEnabled", NO);

        CGFloat w = frame.size.width;
        CGFloat h = frame.size.height;
        CGFloat topY = (h > 600.0) ? 44.0 : 22.0;

        UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        cancelBtn.frame = CGRectMake(14.0, topY, 74.0, 32.0);
        [cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
        cancelBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
        [cancelBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        ApplyHSEditorGlass(cancelBtn, 16.0, 0.55);
        [cancelBtn addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:cancelBtn];

        UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        doneBtn.frame = CGRectMake(w - 86.0, topY, 72.0, 32.0);
        [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
        doneBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
        [doneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        ApplyHSEditorGlass(doneBtn, 16.0, 0.55);
        [doneBtn addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:doneBtn];

        CGFloat bottomBarH = 92.0;
        CGFloat availH = h - (topY + 46.0) - bottomBarH - 12.0;
        CGFloat aspect = w / h;
        CGFloat cardH = availH;
        CGFloat cardW = MIN(w - 56.0, floor(cardH * aspect));
        cardH = floor(cardW / aspect);
        CGFloat cardY = topY + 44.0 + floor((availH - cardH) / 2.0);

        UIView *cardBox = [[UIView alloc] initWithFrame:CGRectMake((w - cardW) / 2.0, cardY, cardW, cardH)];
        cardBox.layer.cornerRadius = 24.0;
        cardBox.layer.cornerCurve = kCACornerCurveContinuous;
        cardBox.layer.borderWidth = 1.5;
        cardBox.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
        cardBox.clipsToBounds = YES;
        [self addSubview:cardBox];

        self.previewWallpaper = [[UIImageView alloc] initWithFrame:cardBox.bounds];
        self.previewWallpaper.contentMode = UIViewContentModeScaleAspectFill;
        self.previewWallpaper.clipsToBounds = YES;
        [cardBox addSubview:self.previewWallpaper];

        CGFloat pad = 14.0;
        CGFloat gap = 10.0;
        CGFloat iconS = floor((cardW - pad * 2.0 - gap * 3.0) / 4.0);
        NSArray *miniColors = @[
            [UIColor colorWithRed:0.15 green:0.17 blue:0.22 alpha:0.92],
            [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:0.92],
            [UIColor colorWithRed:0.95 green:0.35 blue:0.25 alpha:0.92],
            [UIColor colorWithRed:0.18 green:0.75 blue:0.45 alpha:0.92],
            [UIColor colorWithRed:0.65 green:0.30 blue:0.90 alpha:0.92],
            [UIColor colorWithRed:0.95 green:0.72 blue:0.15 alpha:0.92]
        ];

        UIView *miniWidget = [[UIView alloc] initWithFrame:CGRectMake(pad, 20.0, iconS * 2.0 + gap, iconS * 2.0 + gap)];
        miniWidget.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.88];
        miniWidget.layer.cornerRadius = 12.0;
        miniWidget.layer.borderWidth = 0.8;
        miniWidget.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        [cardBox addSubview:miniWidget];

        for (int r = 0; r < 3; r++) {
            for (int c = 0; c < 4; c++) {
                if (r < 2 && c < 2) continue;
                UIView *ic = [[UIView alloc] initWithFrame:CGRectMake(pad + c * (iconS + gap), 20.0 + r * (iconS + gap), iconS, iconS)];
                ic.backgroundColor = miniColors[(r * 4 + c) % miniColors.count];
                ic.layer.cornerRadius = iconS * 0.24;
                [cardBox addSubview:ic];
            }
        }

        UIView *miniSearch = [[UIView alloc] initWithFrame:CGRectMake((cardW - 58.0) / 2.0, cardH - iconS - 42.0, 58.0, 16.0)];
        ApplyHSEditorGlass(miniSearch, 8.0, 0.35);
        UILabel *msLbl = [[UILabel alloc] initWithFrame:miniSearch.bounds];
        msLbl.text = @"Search";
        msLbl.textAlignment = NSTextAlignmentCenter;
        msLbl.font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightSemibold];
        msLbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
        [miniSearch addSubview:msLbl];
        [cardBox addSubview:miniSearch];

        CGFloat dockH = iconS + 14.0;
        UIView *miniDock = [[UIView alloc] initWithFrame:CGRectMake(8.0, cardH - dockH - 8.0, cardW - 16.0, dockH)];
        ApplyHSEditorGlass(miniDock, 16.0, 0.32);
        [cardBox addSubview:miniDock];

        CGFloat dGap = floor((miniDock.bounds.size.width - 16.0 - iconS * 4.0) / 3.0);
        for (int c = 0; c < 4; c++) {
            UIView *dic = [[UIView alloc] initWithFrame:CGRectMake(8.0 + c * (iconS + dGap), 7.0, iconS, iconS)];
            dic.backgroundColor = miniColors[(c + 2) % miniColors.count];
            dic.layer.cornerRadius = iconS * 0.24;
            [miniDock addSubview:dic];
        }

        CGFloat btnSize = (w <= 330.0) ? 44.0 : 50.0;
        CGFloat spacing = (w <= 330.0) ? 11.0 : 16.0;
        CGFloat divW = 1.0;
        CGFloat totalW = btnSize * 5.0 + spacing * 4.0 + divW + 10.0;
        CGFloat startX = floor((w - totalW) / 2.0);
        CGFloat btnY = h - bottomBarH + 10.0;

        self.pairCircle = [self makeToolButtonAtX:startX y:btnY size:btnSize title:@"Pair" symbol:nil action:@selector(pairTapped)];
        self.colorCircle = [self makeToolButtonAtX:startX + (btnSize + spacing) y:btnY size:btnSize title:@"Color" symbol:nil action:@selector(colorTapped)];
        self.gradCircle = [self makeToolButtonAtX:startX + (btnSize + spacing) * 2 y:btnY size:btnSize title:@"Gradient" symbol:nil action:@selector(gradTapped)];
        self.photoCircle = [self makeToolButtonAtX:startX + (btnSize + spacing) * 3 y:btnY size:btnSize title:@"Photo" symbol:@"photo.on.rectangle" action:@selector(photoTapped)];

        CGFloat divX = startX + (btnSize + spacing) * 4 - (spacing / 2.0) + 4.0;
        UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(divX, btnY + 6.0, divW, btnSize - 12.0)];
        divider.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25];
        [self addSubview:divider];

        self.blurCircle = [self makeToolButtonAtX:divX + 10.0 y:btnY size:btnSize title:@"Blur" symbol:@"drop.fill" action:@selector(blurTapped)];

        [self refreshPreviewAndSelections];
    }
    return self;
}

- (UIButton *)makeToolButtonAtX:(CGFloat)x y:(CGFloat)y size:(CGFloat)size title:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(x, y, size, size);
    btn.layer.cornerRadius = size / 2.0;
    btn.clipsToBounds = YES;
    btn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];

    if (symbol) {
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightMedium];
            [btn setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
            btn.tintColor = [UIColor whiteColor];
        }
    }

    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:btn];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(x - 6.0, y + size + 5.0, size + 12.0, 15.0)];
    lbl.text = title;
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    lbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    [self addSubview:lbl];

    return btn;
}

- (void)refreshPreviewAndSelections {
    BOOL dimOn = iOS27BoolPref(@"kHSDimWallpaper", NO);
    iOS27ApplyHomeWallpaperToView(self.previewWallpaper, self.draftMode, self.draftColorIdx, self.draftGradIdx, self.draftBlur, dimOn, YES);

    self.colorCircle.backgroundColor = iOS27HSSolidColorForIndex(self.draftColorIdx);

    for (CALayer *l in [self.gradCircle.layer.sublayers copy]) {
        if ([l.name isEqualToString:@"GradSwatch"]) [l removeFromSuperlayer];
    }
    CAGradientLayer *gSwatch = [CAGradientLayer layer];
    gSwatch.name = @"GradSwatch";
    gSwatch.frame = self.gradCircle.bounds;
    gSwatch.colors = iOS27GradientColorsForTheme(self.draftGradIdx);
    [self.gradCircle.layer insertSublayer:gSwatch atIndex:0];

    NSArray<UIButton *> *modeBtns = @[self.pairCircle, self.colorCircle, self.gradCircle, self.photoCircle];
    for (NSInteger i = 0; i < (NSInteger)modeBtns.count; i++) {
        UIButton *b = modeBtns[i];
        BOOL selected = (self.draftMode == i);
        b.layer.borderWidth = selected ? 2.8 : 1.2;
        b.layer.borderColor = selected ? [UIColor whiteColor].CGColor : [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
    }

    self.blurCircle.backgroundColor = self.draftBlur ? [UIColor whiteColor] : [UIColor colorWithWhite:0.20 alpha:1.0];
    self.blurCircle.tintColor = self.draftBlur ? [UIColor blackColor] : [UIColor whiteColor];
    self.blurCircle.layer.borderWidth = self.draftBlur ? 2.0 : 1.0;
    self.blurCircle.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
}

- (void)pairTapped { self.draftMode = 0; [self refreshPreviewAndSelections]; }
- (void)colorTapped {
    if (self.draftMode == 1) self.draftColorIdx = (self.draftColorIdx + 1) % kIOS27HSColorCount;
    else self.draftMode = 1;
    [self refreshPreviewAndSelections];
}
- (void)gradTapped {
    if (self.draftMode == 2) self.draftGradIdx = (self.draftGradIdx + 1) % kIOS27ThemeCount;
    else self.draftMode = 2;
    [self refreshPreviewAndSelections];
}
- (void)photoTapped {
    if (self.photoSheet) [self.photoSheet removeFromSuperview];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat sheetH = h * 0.64;

    IOS27HSPhotoSheet *sheet = [[IOS27HSPhotoSheet alloc] initWithFrame:CGRectMake(10.0, h, w - 20.0, sheetH)];
    self.photoSheet = sheet;

    __weak typeof(self) weakSelf = self;
    __weak typeof(sheet) weakSheet = sheet;

    sheet.onClose = ^{
        [UIView animateWithDuration:0.22 animations:^{
            weakSheet.frame = CGRectMake(10.0, h, w - 20.0, sheetH);
        } completion:^(BOOL finished) {
            [weakSheet removeFromSuperview];
            weakSelf.photoSheet = nil;
        }];
    };

    sheet.onSelectPath = ^(NSString *selectedPath) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            CGFloat maxDim = MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height) * MIN([UIScreen mainScreen].scale, 2.0);
            UIImage *resized = iOS27HSLoadThumb(selectedPath, maxDim);
            NSData *jpegData = UIImageJPEGRepresentation(resized, 0.85);
            if (jpegData) {
                [jpegData writeToFile:iOS27HomePhotoPath() atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.draftMode = 3;
                    [weakSelf refreshPreviewAndSelections];
                    if (weakSheet.onClose) weakSheet.onClose();
                });
            }
        });
    };

    [self addSubview:sheet];
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        sheet.frame = CGRectMake(10.0, h - sheetH - 12.0, w - 20.0, sheetH);
    } completion:nil];
}
- (void)blurTapped { self.draftBlur = !self.draftBlur; [self refreshPreviewAndSelections]; }
- (void)cancelTapped { if (self.onClose) self.onClose(); }
- (void)doneTapped {
    iOS27SetIntPref(@"kHSWallpaperMode", self.draftMode);
    iOS27SetIntPref(@"kHSColorIndex", self.draftColorIdx);
    iOS27SetIntPref(@"kHSGradientIndex", self.draftGradIdx);
    iOS27SetBoolPref(@"kHSBlurEnabled", self.draftBlur);
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27HSStyleChanged object:nil];
    if (self.onClose) self.onClose();
}

@end

// =========================================================================
// 3. Exact iOS 27 Video-Style Customize Sheet (Default / Dark / Clear / Tinted + Rainbow Slider)
// =========================================================================
@interface IOS27HomeCustomizeSheet : UIView
@property (nonatomic, strong) UIButton *dimBtn;
@property (nonatomic, strong) UIButton *sizeBtn;
@property (nonatomic, strong) NSArray<UIButton *> *styleCards;
@property (nonatomic, strong) UIView *slidersContainer;
@property (nonatomic, strong) UISlider *hueSlider;
@property (nonatomic, strong) UISlider *briSlider;
@property (nonatomic, strong) CAGradientLayer *briTrackGrad;
@property (nonatomic, strong) UISegmentedControl *subModeSeg;
@property (nonatomic, copy) void (^onLiveRefresh)(void);
@property (nonatomic, copy) void (^onHeightChanged)(CGFloat newHeight);
@property (nonatomic, copy) void (^onClose)(void);
- (CGFloat)desiredHeight;
@end

@implementation IOS27HomeCustomizeSheet

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.tag = 27515;
        ApplyHSEditorGlass(self, 28.0, 0.84);

        CGFloat w = frame.size.width;

        self.dimBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.dimBtn.frame = CGRectMake(12.0, 10.0, 32.0, 32.0);
        [self.dimBtn addTarget:self action:@selector(toggleDim) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.dimBtn];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(50.0, 12.0, w - 100.0, 28.0)];
        title.text = @"Customize";
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        self.sizeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.sizeBtn.frame = CGRectMake(w - 44.0, 10.0, 32.0, 32.0);
        [self.sizeBtn addTarget:self action:@selector(toggleSize) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.sizeBtn];

        CGFloat pad = 10.0;
        CGFloat gap = 6.0;
        CGFloat cardW = floor((w - pad * 2.0 - gap * 3.0) / 4.0);
        CGFloat cardH = 84.0;
        NSArray *titles = @[@"Default", @"Dark", @"Clear", @"Tinted"];
        NSMutableArray *cards = [NSMutableArray array];

        for (NSInteger i = 0; i < 4; i++) {
            UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
            card.tag = i;
            card.frame = CGRectMake(pad + i * (cardW + gap), 50.0, cardW, cardH);
            card.layer.cornerRadius = 16.0;
            card.layer.cornerCurve = kCACornerCurveContinuous;
            card.clipsToBounds = YES;
            card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
            [card addTarget:self action:@selector(styleCardTapped:) forControlEvents:UIControlEventTouchUpInside];

            CGFloat iconS = MIN(cardW - 22.0, 42.0);
            UIView *miniIcon = [[UIView alloc] initWithFrame:CGRectMake((cardW - iconS) / 2.0, 10.0, iconS, iconS)];
            miniIcon.layer.cornerRadius = 10.0;
            miniIcon.layer.cornerCurve = kCACornerCurveContinuous;
            miniIcon.userInteractionEnabled = NO;
            miniIcon.clipsToBounds = YES;

            UIImageView *sym = [[UIImageView alloc] initWithFrame:CGRectInset(miniIcon.bounds, 6.0, 6.0)];
            sym.contentMode = UIViewContentModeScaleAspectFit;
            if (@available(iOS 13.0, *)) {
                sym.image = [UIImage systemImageNamed:@"cloud.sun.fill"];
            }

            if (i == 0) {
                miniIcon.backgroundColor = [UIColor colorWithRed:0.15 green:0.58 blue:0.98 alpha:1.0];
                sym.tintColor = [UIColor whiteColor];
            } else if (i == 1) {
                miniIcon.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
                sym.tintColor = [UIColor colorWithRed:1.0 green:0.84 blue:0.25 alpha:1.0];
            } else if (i == 2) {
                miniIcon.backgroundColor = [UIColor colorWithWhite:0.82 alpha:0.42];
                miniIcon.layer.borderWidth = 1.0;
                miniIcon.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;
                sym.tintColor = [UIColor colorWithWhite:1.0 alpha:0.92];
            } else {
                miniIcon.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.92];
                sym.tintColor = [UIColor colorWithRed:0.92 green:0.88 blue:0.78 alpha:0.95];
            }
            [miniIcon addSubview:sym];
            [card addSubview:miniIcon];

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(2, cardH - 22.0, cardW - 4, 16.0)];
            lbl.text = titles[i];
            lbl.textAlignment = NSTextAlignmentCenter;
            lbl.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
            lbl.textColor = [UIColor whiteColor];
            lbl.userInteractionEnabled = NO;
            [card addSubview:lbl];

            [self addSubview:card];
            [cards addObject:card];
        }
        self.styleCards = cards;

        self.slidersContainer = [[UIView alloc] initWithFrame:CGRectMake(14.0, 144.0, w - 28.0, 74.0)];
        self.slidersContainer.backgroundColor = [UIColor clearColor];

        UIView *hueTrack = [[UIView alloc] initWithFrame:CGRectMake(0, 6.0, w - 28.0, 18.0)];
        hueTrack.layer.cornerRadius = 9.0;
        hueTrack.clipsToBounds = YES;
        CAGradientLayer *rainbow = [CAGradientLayer layer];
        rainbow.frame = hueTrack.bounds;
        rainbow.startPoint = CGPointMake(0.0, 0.5);
        rainbow.endPoint = CGPointMake(1.0, 0.5);
        rainbow.colors = @[
            (id)[UIColor redColor].CGColor,
            (id)[UIColor orangeColor].CGColor,
            (id)[UIColor yellowColor].CGColor,
            (id)[UIColor greenColor].CGColor,
            (id)[UIColor cyanColor].CGColor,
            (id)[UIColor blueColor].CGColor,
            (id)[UIColor magentaColor].CGColor,
            (id)[UIColor redColor].CGColor
        ];
        [hueTrack.layer addSublayer:rainbow];
        [self.slidersContainer addSubview:hueTrack];

        self.hueSlider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, w - 28.0, 30.0)];
        self.hueSlider.minimumValue = 0.0;
        self.hueSlider.maximumValue = 1.0;
        self.hueSlider.value = iOS27FloatPref(@"kHSTintHue", 0.55);
        self.hueSlider.minimumTrackTintColor = [UIColor clearColor];
        self.hueSlider.maximumTrackTintColor = [UIColor clearColor];
        [self.hueSlider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
        [self.slidersContainer addSubview:self.hueSlider];

        UIView *briTrack = [[UIView alloc] initWithFrame:CGRectMake(0, 44.0, w - 28.0, 18.0)];
        briTrack.layer.cornerRadius = 9.0;
        briTrack.clipsToBounds = YES;
        self.briTrackGrad = [CAGradientLayer layer];
        self.briTrackGrad.frame = briTrack.bounds;
        self.briTrackGrad.startPoint = CGPointMake(0.0, 0.5);
        self.briTrackGrad.endPoint = CGPointMake(1.0, 0.5);
        [briTrack.layer addSublayer:self.briTrackGrad];
        [self.slidersContainer addSubview:briTrack];

        self.briSlider = [[UISlider alloc] initWithFrame:CGRectMake(0, 38.0, w - 28.0, 30.0)];
        self.briSlider.minimumValue = 0.25;
        self.briSlider.maximumValue = 1.0;
        self.briSlider.value = iOS27FloatPref(@"kHSTintBrightness", 0.85);
        self.briSlider.minimumTrackTintColor = [UIColor clearColor];
        self.briSlider.maximumTrackTintColor = [UIColor clearColor];
        [self.briSlider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
        [self.slidersContainer addSubview:self.briSlider];

        [self addSubview:self.slidersContainer];

        self.subModeSeg = [[UISegmentedControl alloc] initWithItems:@[@"Light", @"Dark", @"Auto"]];
        self.subModeSeg.frame = CGRectMake(24.0, 148.0, w - 48.0, 32.0);
        [self.subModeSeg addTarget:self action:@selector(subModeChanged) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.subModeSeg];

        [self syncUIState:NO];
    }
    return self;
}

- (CGFloat)desiredHeight {
    NSInteger style = iOS27IntPref(@"kHSIconStyle", 0);
    if (style == 0) return 150.0;
    if (style == 1 || style == 2) return 194.0;
    return 264.0;
}

- (void)syncUIState:(BOOL)animateResize {
    BOOL dimOn = iOS27BoolPref(@"kHSDimWallpaper", NO);
    BOOL largeOn = iOS27BoolPref(@"kHSLargeIcons", YES);
    NSInteger style = iOS27IntPref(@"kHSIconStyle", 0);
    NSInteger subMode = iOS27IntPref(@"kHSIconSubMode", 0);

    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
        [self.dimBtn setImage:[UIImage systemImageNamed:(dimOn ? @"sun.min.fill" : @"sun.max") withConfiguration:cfg] forState:UIControlStateNormal];
        self.dimBtn.tintColor = dimOn ? [UIColor systemYellowColor] : [UIColor whiteColor];

        [self.sizeBtn setImage:[UIImage systemImageNamed:(largeOn ? @"square.fill" : @"square.grid.2x2") withConfiguration:cfg] forState:UIControlStateNormal];
        self.sizeBtn.tintColor = [UIColor whiteColor];
    }

    for (NSInteger i = 0; i < (NSInteger)self.styleCards.count; i++) {
        UIButton *c = self.styleCards[i];
        BOOL sel = (i == style);
        c.layer.borderWidth = sel ? 1.8 : 0.6;
        c.layer.borderColor = sel ? [UIColor whiteColor].CGColor : [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
        c.backgroundColor = sel ? [UIColor colorWithWhite:1.0 alpha:0.20] : [UIColor colorWithWhite:1.0 alpha:0.06];
    }

    UIColor *hueCol = [UIColor colorWithHue:self.hueSlider.value saturation:0.85 brightness:1.0 alpha:1.0];
    self.briTrackGrad.colors = @[(id)[UIColor whiteColor].CGColor, (id)hueCol.CGColor];

    self.slidersContainer.hidden = (style != 3);
    self.subModeSeg.hidden = (style == 0);

    if (style == 1) {
        if (self.subModeSeg.numberOfSegments != 2) {
            [self.subModeSeg removeAllSegments];
            [self.subModeSeg insertSegmentWithTitle:@"Always" atIndex:0 animated:NO];
            [self.subModeSeg insertSegmentWithTitle:@"Auto" atIndex:1 animated:NO];
        }
        self.subModeSeg.selectedSegmentIndex = MIN(subMode, 1);
        self.subModeSeg.frame = CGRectMake(28.0, 148.0, self.bounds.size.width - 56.0, 32.0);
    } else if (style == 2 || style == 3) {
        if (self.subModeSeg.numberOfSegments != 3) {
            [self.subModeSeg removeAllSegments];
            [self.subModeSeg insertSegmentWithTitle:@"Light" atIndex:0 animated:NO];
            [self.subModeSeg insertSegmentWithTitle:@"Dark" atIndex:1 animated:NO];
            [self.subModeSeg insertSegmentWithTitle:@"Auto" atIndex:2 animated:NO];
        }
        self.subModeSeg.selectedSegmentIndex = MIN(subMode, 2);
        CGFloat segY = (style == 3) ? 222.0 : 148.0;
        self.subModeSeg.frame = CGRectMake(24.0, segY, self.bounds.size.width - 48.0, 32.0);
    }

    if (animateResize && self.onHeightChanged) {
        self.onHeightChanged([self desiredHeight]);
    }
}

- (void)toggleDim {
    BOOL cur = iOS27BoolPref(@"kHSDimWallpaper", NO);
    iOS27SetBoolPref(@"kHSDimWallpaper", !cur);
    [self syncUIState:NO];
    if (self.onLiveRefresh) self.onLiveRefresh();
}

- (void)toggleSize {
    BOOL cur = iOS27BoolPref(@"kHSLargeIcons", YES);
    iOS27SetBoolPref(@"kHSLargeIcons", !cur);
    [self syncUIState:NO];
    if (self.onLiveRefresh) self.onLiveRefresh();
}

- (void)styleCardTapped:(UIButton *)sender {
    iOS27SetIntPref(@"kHSIconStyle", sender.tag);
    [self syncUIState:YES];
    if (self.onLiveRefresh) self.onLiveRefresh();
}

- (void)sliderChanged {
    iOS27SetFloatPref(@"kHSTintHue", self.hueSlider.value);
    iOS27SetFloatPref(@"kHSTintBrightness", self.briSlider.value);
    [self syncUIState:NO];
    if (self.onLiveRefresh) self.onLiveRefresh();
}

- (void)subModeChanged {
    iOS27SetIntPref(@"kHSIconSubMode", self.subModeSeg.selectedSegmentIndex);
    if (self.onLiveRefresh) self.onLiveRefresh();
}

@end

// =========================================================================
// 4. SpringBoard Home Screen Edit Mode Hooks (Stock +/Done Locked Hidden + Working Actions)
// =========================================================================
static const void *kTopBarKey = &kTopBarKey;
static const void *kMenuOverlayKey = &kMenuOverlayKey;
static const void *kStudioViewKey = &kStudioViewKey;
static const void *kCustomizeOverlayKey = &kCustomizeOverlayKey;

static void HandleStockButtonHook(UIButton *btn) {
    if (!btn.window) return;
    if (btn.tag >= 27500 && btn.tag <= 27599) return;
    CGRect winRect = [btn convertRect:btn.bounds toView:btn.window];
    if (winRect.origin.y >= -4.0 && winRect.origin.y < 85.0) {
        if (winRect.origin.x < btn.window.bounds.size.width / 2.0) {
            gStockAddButton = btn;
        } else {
            gStockDoneButton = btn;
        }
        btn.userInteractionEnabled = NO;
    }
}

%group HomeScreenEditorHooks

// Lock alpha=0 and hidden=YES on stock '+' and 'Done' button classes so SpringBoard animations cannot reveal them
%hook SBHomeScreenButton
- (void)setAlpha:(CGFloat)alpha {
    HandleStockButtonHook(self);
    %orig(0.0);
}
- (void)setHidden:(BOOL)hidden {
    HandleStockButtonHook(self);
    %orig(YES);
}
- (void)layoutSubviews {
    %orig;
    HandleStockButtonHook(self);
    self.alpha = 0.0;
    self.hidden = YES;
}
%end

%hook SBHAddWidgetButton
- (void)setAlpha:(CGFloat)alpha {
    HandleStockButtonHook(self);
    %orig(0.0);
}
- (void)setHidden:(BOOL)hidden {
    HandleStockButtonHook(self);
    %orig(YES);
}
- (void)layoutSubviews {
    %orig;
    HandleStockButtonHook(self);
    self.alpha = 0.0;
    self.hidden = YES;
}
%end

%hook SBHTitledHomeScreenButton
- (void)setAlpha:(CGFloat)alpha {
    HandleStockButtonHook(self);
    %orig(0.0);
}
- (void)setHidden:(BOOL)hidden {
    HandleStockButtonHook(self);
    %orig(YES);
}
- (void)layoutSubviews {
    %orig;
    HandleStockButtonHook(self);
    self.alpha = 0.0;
    self.hidden = YES;
}
%end

%hook SBRootFolderView

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    %orig;
    [self ios27_updateEditOverlay:editing];
    RefreshAllVisibleIconsInView(self);

    if (editing && self.window) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf ios27_hideStockTopButtonsInWindow:weakSelf.window];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf ios27_hideStockTopButtonsInWindow:weakSelf.window];
        });
    }
}

- (void)layoutSubviews {
    %orig;
    if ([self respondsToSelector:@selector(isEditing)] && [self isEditing]) {
        [self ios27_updateEditOverlay:YES];
    }
}

%new
- (void)ios27_hideStockTopButtonsInWindow:(UIWindow *)win {
    if (!win) return;
    ScanAndHideStockButtons(win, win);

    // Align our Brush & Checkmark topBar to the exact Y position of stock '+' button
    UIView *topBar = objc_getAssociatedObject(self, kTopBarKey);
    if (topBar && gStockAddButton && gStockAddButton.window == win) {
        CGRect r = [gStockAddButton convertRect:gStockAddButton.bounds toView:win];
        if (r.origin.y >= 0.0 && r.origin.y < 80.0) {
            topBar.frame = CGRectMake(0, r.origin.y, win.bounds.size.width, 32.0);
        }
    }
}

%new
- (void)ios27_updateEditOverlay:(BOOL)editing {
    UIWindow *win = self.window;
    if (!win) return;

    UIView *topBar = objc_getAssociatedObject(self, kTopBarKey);
    if (!editing) {
        [self ios27_dismissMenu];
        if (topBar) {
            [UIView animateWithDuration:0.18 animations:^{
                topBar.alpha = 0.0;
            } completion:^(BOOL finished) {
                [topBar removeFromSuperview];
                objc_setAssociatedObject(self, kTopBarKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }];
        }
        return;
    }

    [self ios27_hideStockTopButtonsInWindow:win];

    CGFloat w = win.bounds.size.width;
    CGFloat topY = (win.bounds.size.height > 600.0) ? 44.0 : 4.0;
    if (gStockAddButton && gStockAddButton.window == win) {
        CGRect r = [gStockAddButton convertRect:gStockAddButton.bounds toView:win];
        if (r.origin.y >= 0.0 && r.origin.y < 80.0) {
            topY = r.origin.y;
        }
    }

    if (!topBar) {
        topBar = [[UIView alloc] initWithFrame:CGRectMake(0, topY, w, 32.0)];
        topBar.tag = 27500;
        topBar.backgroundColor = [UIColor clearColor];
        topBar.alpha = 0.0;

        UIButton *brushBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        brushBtn.tag = 27501;
        brushBtn.frame = CGRectMake(12.0, 0.0, 52.0, 28.0);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightSemibold];
            [brushBtn setImage:[UIImage systemImageNamed:@"paintbrush.fill" withConfiguration:cfg] forState:UIControlStateNormal];
            brushBtn.tintColor = [UIColor whiteColor];
        }
        ApplyHSEditorGlass(brushBtn, 14.0, 0.62);
        [brushBtn addTarget:self action:@selector(ios27_brushTapped) forControlEvents:UIControlEventTouchUpInside];
        [topBar addSubview:brushBtn];

        UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        doneBtn.tag = 27502;
        doneBtn.frame = CGRectMake(w - 64.0, 0.0, 52.0, 28.0);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14.5 weight:UIImageSymbolWeightBold];
            [doneBtn setImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:cfg] forState:UIControlStateNormal];
            doneBtn.tintColor = [UIColor whiteColor];
        }
        ApplyHSEditorGlass(doneBtn, 14.0, 0.62);
        [doneBtn addTarget:self action:@selector(ios27_doneTapped) forControlEvents:UIControlEventTouchUpInside];
        [topBar addSubview:doneBtn];

        [win addSubview:topBar];
        objc_setAssociatedObject(self, kTopBarKey, topBar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [UIView animateWithDuration:0.18 animations:^{
            topBar.alpha = 1.0;
        }];
    } else {
        topBar.frame = CGRectMake(0, topY, w, 32.0);
        [win bringSubviewToFront:topBar];
    }
}

%new
- (void)ios27_brushTapped {
    UIWindow *win = self.window;
    if (!win) return;

    UIView *existing = objc_getAssociatedObject(self, kMenuOverlayKey);
    if (existing) {
        [self ios27_dismissMenu];
        return;
    }

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    UIView *backdrop = [[UIView alloc] initWithFrame:win.bounds];
    backdrop.tag = 27505;
    backdrop.backgroundColor = [UIColor clearColor];
    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ios27_dismissMenu)];
    [backdrop addGestureRecognizer:dismissTap];
    [win addSubview:backdrop];
    objc_setAssociatedObject(self, kMenuOverlayKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *topBar = objc_getAssociatedObject(self, kTopBarKey);
    CGFloat menuY = topBar ? (CGRectGetMaxY(topBar.frame) + 6.0) : 42.0;
    CGFloat w = win.bounds.size.width;
    CGFloat menuW = MIN(w - 96.0, 214.0);
    CGFloat rowH = 42.0;
    CGFloat menuH = rowH * 4.0 + 10.0;

    UIView *menuBox = [[UIView alloc] initWithFrame:CGRectMake(12.0, menuY, menuW, menuH)];
    menuBox.tag = 27506;
    ApplyHSEditorGlass(menuBox, 20.0, 0.82);
    menuBox.transform = CGAffineTransformMakeScale(0.86, 0.86);
    menuBox.alpha = 0.0;
    [backdrop addSubview:menuBox];

    NSArray *items = @[
        @{@"title": @"Add Widget",     @"icon": @"rectangle.badge.plus",   @"sel": @"ios27_menuAddWidget"},
        @{@"title": @"Customize",      @"icon": @"paintbrush.pointed",     @"sel": @"ios27_menuCustomize"},
        @{@"title": @"Edit Wallpaper", @"icon": @"sparkles",               @"sel": @"ios27_menuEditWallpaper"},
        @{@"title": @"Edit Pages",     @"icon": @"rectangle.on.rectangle", @"sel": @"ios27_menuEditPages"}
    ];

    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        NSDictionary *item = items[i];
        UIButton *rowBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        rowBtn.frame = CGRectMake(6.0, 5.0 + i * rowH, menuW - 12.0, rowH);
        rowBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        rowBtn.contentEdgeInsets = UIEdgeInsetsMake(0, 10.0, 0, 10.0);
        rowBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 10.0, 0, 0);

        [rowBtn setTitle:item[@"title"] forState:UIControlStateNormal];
        rowBtn.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        [rowBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.5 weight:UIImageSymbolWeightMedium];
            [rowBtn setImage:[UIImage systemImageNamed:item[@"icon"] withConfiguration:cfg] forState:UIControlStateNormal];
            rowBtn.tintColor = [UIColor whiteColor];
        }

        [rowBtn addTarget:self action:NSSelectorFromString(item[@"sel"]) forControlEvents:UIControlEventTouchUpInside];
        [menuBox addSubview:rowBtn];
    }

    [UIView animateWithDuration:0.20
                          delay:0
         usingSpringWithDamping:0.84
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        menuBox.transform = CGAffineTransformIdentity;
        menuBox.alpha = 1.0;
    } completion:nil];
}

%new
- (void)ios27_dismissMenu {
    UIView *backdrop = objc_getAssociatedObject(self, kMenuOverlayKey);
    if (!backdrop) return;
    [UIView animateWithDuration:0.14 animations:^{
        backdrop.alpha = 0.0;
    } completion:^(BOOL finished) {
        [backdrop removeFromSuperview];
        objc_setAssociatedObject(self, kMenuOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
}

%new
- (void)ios27_doneTapped {
    [self ios27_dismissMenu];
    if (gStockDoneButton) {
        FireControlActionsDirectly(gStockDoneButton);
    }
    SBIconController *ic = [%c(SBIconController) sharedInstance];
    if ([ic respondsToSelector:@selector(iconManager)]) {
        SBHIconManager *mgr = [ic iconManager];
        if ([mgr respondsToSelector:@selector(setEditing:)]) {
            [mgr setEditing:NO];
        }
    }
    if ([ic respondsToSelector:@selector(setEditing:)]) {
        [ic setEditing:NO];
    }
}

%new
- (void)ios27_menuAddWidget {
    [self ios27_dismissMenu];
    if (!gStockAddButton && self.window) {
        ScanAndHideStockButtons(self.window, self.window);
    }

    // 1. Direct target-action invocation on stock '+' button (Most reliable on iOS 15)
    if (gStockAddButton && FireControlActionsDirectly(gStockAddButton)) {
        return;
    }

    // 2. Fallbacks on SBIconController & SBHIconManager
    SBIconController *ic = [%c(SBIconController) sharedInstance];
    NSArray *sels = @[@"presentAddWidgetSheetFromViewController:", @"_presentAddWidgetSheetFromViewController:", @"addWidgetButtonTapped:", @"_addWidgetButtonTapped:", @"presentAddWidgetSheet"];
    for (NSString *s in sels) {
        SEL sel = NSSelectorFromString(s);
        if ([ic respondsToSelector:sel]) {
            if ([s hasSuffix:@":"]) {
                ((void (*)(id, SEL, id))objc_msgSend)(ic, sel, ic);
            } else {
                ((void (*)(id, SEL))objc_msgSend)(ic, sel);
            }
            return;
        }
    }
}

%new
- (void)ios27_menuCustomize {
    [self ios27_dismissMenu];
    UIWindow *win = self.window;
    if (!win) return;

    UIView *oldOverlay = objc_getAssociatedObject(self, kCustomizeOverlayKey);
    if (oldOverlay) [oldOverlay removeFromSuperview];

    CGFloat w = win.bounds.size.width;
    CGFloat h = win.bounds.size.height;

    UIView *overlay = [[UIView alloc] initWithFrame:win.bounds];
    overlay.tag = 27514;
    overlay.backgroundColor = [UIColor clearColor];

    UIButton *dismissArea = [UIButton buttonWithType:UIButtonTypeCustom];
    dismissArea.frame = win.bounds;
    [overlay addSubview:dismissArea];

    IOS27HomeCustomizeSheet *sheet = [[IOS27HomeCustomizeSheet alloc] initWithFrame:CGRectMake(8.0, h, w - 16.0, 150.0)];
    CGFloat targetH = [sheet desiredHeight];
    [overlay addSubview:sheet];

    __weak typeof(self) weakSelf = self;
    __weak typeof(overlay) weakOverlay = overlay;
    __weak typeof(sheet) weakSheet = sheet;

    void (^closeBlock)(void) = ^{
        [UIView animateWithDuration:0.22 animations:^{
            weakSheet.frame = CGRectMake(8.0, h, w - 16.0, weakSheet.frame.size.height);
        } completion:^(BOOL finished) {
            [weakOverlay removeFromSuperview];
            objc_setAssociatedObject(weakSelf, kCustomizeOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
    };

    sheet.onClose = closeBlock;
    sheet.onHeightChanged = ^(CGFloat newH) {
        [UIView animateWithDuration:0.24 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            weakSheet.frame = CGRectMake(8.0, h - newH - 10.0, w - 16.0, newH);
            ApplyHSEditorGlass(weakSheet, 28.0, 0.84);
        } completion:nil];
    };
    sheet.onLiveRefresh = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27HSStyleChanged object:nil];
        RefreshAllVisibleIconsInView(weakSelf);
    };

    [dismissArea addTarget:sheet action:@selector(ios27_dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(sheet, "closeBlock", closeBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);

    [win addSubview:overlay];
    objc_setAssociatedObject(self, kCustomizeOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        sheet.frame = CGRectMake(8.0, h - targetH - 10.0, w - 16.0, targetH);
        ApplyHSEditorGlass(sheet, 28.0, 0.84);
    } completion:nil];
}

%new
- (void)ios27_menuEditWallpaper {
    [self ios27_dismissMenu];
    UIWindow *win = self.window;
    if (!win) return;

    UIView *oldStudio = objc_getAssociatedObject(self, kStudioViewKey);
    if (oldStudio) [oldStudio removeFromSuperview];

    IOS27HomeWallpaperStudioView *studio = [[IOS27HomeWallpaperStudioView alloc] initWithFrame:win.bounds];
    studio.alpha = 0.0;
    [win addSubview:studio];
    objc_setAssociatedObject(self, kStudioViewKey, studio, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak typeof(self) weakSelf = self;
    __weak typeof(studio) weakStudio = studio;

    studio.onClose = ^{
        [UIView animateWithDuration:0.22 animations:^{
            weakStudio.alpha = 0.0;
        } completion:^(BOOL finished) {
            [weakStudio removeFromSuperview];
            objc_setAssociatedObject(weakSelf, kStudioViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
    };

    [UIView animateWithDuration:0.24 animations:^{
        studio.alpha = 1.0;
    }];
}

%new
- (void)ios27_menuEditPages {
    [self ios27_dismissMenu];

    // 1. Primary iOS 15 trigger: PageControl delegate tap method (exact same as tapping page dots in jiggle mode)
    UIControl *pc = [self respondsToSelector:@selector(pageControl)] ? [self pageControl] : FindPageControlInView(self);
    SEL delegateTapSel = NSSelectorFromString(@"pageControlDidReceiveButtonTap:");
    if (pc) {
        if ([pc respondsToSelector:@selector(delegate)]) {
            id del = ((id (*)(id, SEL))objc_msgSend)(pc, @selector(delegate));
            if (del && [del respondsToSelector:delegateTapSel]) {
                ((void (*)(id, SEL, id))objc_msgSend)(del, delegateTapSel, pc);
                return;
            }
        }
        if ([self respondsToSelector:delegateTapSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(self, delegateTapSel, pc);
            return;
        }
    }

    // 2. Fallback: SBRootFolderController page management selectors
    SBIconController *ic = [%c(SBIconController) sharedInstance];
    SBHIconManager *mgr = [ic respondsToSelector:@selector(iconManager)] ? [ic iconManager] : nil;
    SBRootFolderController *rfc = [mgr respondsToSelector:@selector(rootFolderController)] ? [mgr rootFolderController] : nil;

    if (rfc) {
        SEL s1 = NSSelectorFromString(@"presentPageManagementAnimated:completion:");
        if ([rfc respondsToSelector:s1]) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(rfc, s1, YES, nil);
            return;
        }
        SEL s2 = NSSelectorFromString(@"enterPageManagement");
        if ([rfc respondsToSelector:s2]) {
            ((void (*)(id, SEL))objc_msgSend)(rfc, s2);
            return;
        }
        SEL s3 = NSSelectorFromString(@"enterPageManagementAnimated:");
        if ([rfc respondsToSelector:s3]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(rfc, s3, YES);
            return;
        }
        SEL s4 = NSSelectorFromString(@"presentPageManagementAnimated:");
        if ([rfc respondsToSelector:s4]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(rfc, s4, YES);
            return;
        }
        SEL s5 = NSSelectorFromString(@"setPageManagementMode:");
        if ([rfc respondsToSelector:s5]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(rfc, s5, YES);
            return;
        }
        SEL s6 = NSSelectorFromString(@"rootFolderViewDidReceivePageControlTap:");
        if ([rfc respondsToSelector:s6]) {
            ((void (*)(id, SEL, id))objc_msgSend)(rfc, s6, self);
            return;
        }
    }

    // 3. Final fallback: fire control actions on pageControl
    if (pc) {
        FireControlActionsDirectly(pc);
    }
}

%end

%end

@implementation IOS27HomeCustomizeSheet (DismissHelper)
- (void)ios27_dismissSelf {
    void (^cb)(void) = objc_getAssociatedObject(self, "closeBlock");
    if (cb) cb();
}
@end

%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (iOS27BoolPref(@"kEnabled", YES) && iOS27BoolPref(@"kEnableHomeScreen", YES)) {
        %init(HomeScreenEditorHooks);
    }
}
