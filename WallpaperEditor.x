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
- (void)ios27_openSwitcherWithAction:(NSInteger)actionMode;
@end

static __weak CSCoverSheetViewController *gActiveCoverSheetVC = nil;

static void ApplyEditorGlass(UIView *view, CGFloat radius) {
    view.backgroundColor = [UIColor colorWithRed:0.12 green:0.15 blue:0.22 alpha:MAX(gEditorGlassAlpha, 0.45)];
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
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
            (id)[UIColor colorWithWhite:1.0 alpha:0.24].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor
        ];
        sheen.locations = @[@0.0, @0.5, @1.0];
        [view.layer insertSublayer:sheen atIndex:0];
    }
    sheen.frame = view.bounds;
    sheen.cornerRadius = radius;
}

static UIImage *iOS27LoadThumbnailAtPath(NSString *path, CGFloat maxPixelSize) {
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
// 1. Crash-Free Camera Roll Sheet
// =========================================================================
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

        self.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.96];
        self.layer.cornerRadius = 26.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        self.clipsToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(18, 12, frame.size.width - 80, 28)];
        title.text = @"Photos";
        title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        title.textColor = [UIColor whiteColor];
        [self addSubview:title];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(frame.size.width - 44, 10, 32, 32);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold];
            [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
            closeBtn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.8];
        }
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        if (self.photoPaths.count == 0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, frame.size.width - 40, 80)];
            empty.text = @"No photos found in Camera Roll.";
            empty.textAlignment = NSTextAlignmentCenter;
            empty.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
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

// =========================================================================
// 2. Full-Screen Black Multi-Wallpaper Card Switcher & Editor
// =========================================================================
@interface IOS27WallpaperSwitcherView : UIView <UICollectionViewDataSource, UICollectionViewDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *wallpapers;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) UICollectionView *carousel;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) UILabel *topHeaderLabel;
@property (nonatomic, strong) UIView *mainBar;
@property (nonatomic, strong) UIView *iconsDock;
@property (nonatomic, strong) IOS27SafePhotoSheet *photoSheet;
@property (nonatomic, assign) CGFloat cardWidth;
@property (nonatomic, assign) CGFloat cardSpacing;
@property (nonatomic, copy) void (^onApplyAndClose)(void);
@property (nonatomic, copy) void (^onLiveUpdate)(void);
- (void)enterCustomizeMode;
- (void)addNewWallpaperCard;
@end

static UIButton *CreateIconBtn(NSString *symbolName, id target, SEL action) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightMedium];
        [btn setImage:[UIImage systemImageNamed:symbolName withConfiguration:cfg] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
    }
    [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

@implementation IOS27WallpaperSwitcherView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.wallpapers = iOS27LoadSavedWallpapers();
        self.currentIndex = iOS27ActiveWallpaperIndex();

        CGFloat w = frame.size.width;
        CGFloat h = frame.size.height;

        // Top Bar: Trash (Left), Header (Center), Done (Right)
        UIButton *trashBtn = CreateIconBtn(@"trash", self, @selector(deleteCurrentCard));
        trashBtn.frame = CGRectMake(16.0, 32.0, 36.0, 36.0);
        ApplyEditorGlass(trashBtn, 18.0);
        [self addSubview:trashBtn];

        self.topHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(64.0, 34.0, w - 156.0, 32.0)];
        self.topHeaderLabel.textAlignment = NSTextAlignmentCenter;
        self.topHeaderLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
        self.topHeaderLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
        [self addSubview:self.topHeaderLabel];

        UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        doneBtn.frame = CGRectMake(w - 84.0, 32.0, 70.0, 34.0);
        [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
        doneBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
        [doneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        ApplyEditorGlass(doneBtn, 17.0);
        [doneBtn addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:doneBtn];

        // Card Carousel
        self.cardWidth = floor(w * 0.68);
        CGFloat cardHeight = floor(h * 0.62);
        self.cardSpacing = 16.0;
        CGFloat sideInset = floor((w - self.cardWidth) / 2.0);

        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.itemSize = CGSizeMake(self.cardWidth, cardHeight);
        layout.minimumLineSpacing = self.cardSpacing;
        layout.sectionInset = UIEdgeInsetsMake(0, sideInset, 0, sideInset);

        self.carousel = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 82.0, w, cardHeight + 16.0) collectionViewLayout:layout];
        self.carousel.backgroundColor = [UIColor blackColor];
        self.carousel.showsHorizontalScrollIndicator = NO;
        self.carousel.decelerationRate = UIScrollViewDecelerationRateFast;
        self.carousel.dataSource = self;
        self.carousel.delegate = self;
        [self.carousel registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"WallpaperCard"];
        [self addSubview:self.carousel];

        // Page Dots below cards
        self.pageControl = [[UIPageControl alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(self.carousel.frame) + 4.0, w, 24.0)];
        self.pageControl.numberOfPages = self.wallpapers.count;
        self.pageControl.currentPage = self.currentIndex;
        self.pageControl.userInteractionEnabled = NO;
        [self addSubview:self.pageControl];

        // Stage 1 Bottom Bar: "Customize" Pill + "+" Circle Button
        CGFloat barY = h - 72.0;
        self.mainBar = [[UIView alloc] initWithFrame:CGRectMake(0, barY, w, 46.0)];

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
        [customizeBtn addTarget:self action:@selector(enterCustomizeMode) forControlEvents:UIControlEventTouchUpInside];
        [self.mainBar addSubview:customizeBtn];

        UIButton *plusBtn = CreateIconBtn(@"plus", self, @selector(addNewWallpaperCard));
        plusBtn.frame = CGRectMake(startX + custW + 14.0, 1.0, plusSize, plusSize);
        ApplyEditorGlass(plusBtn, plusSize / 2.0);
        [self.mainBar addSubview:plusBtn];

        [self addSubview:self.mainBar];

        // Stage 2 Bottom Bar: Icon-Only Customize Dock
        CGFloat dockH = 52.0;
        CGFloat dockW = MIN(w - 36.0, 290.0);
        self.iconsDock = [[UIView alloc] initWithFrame:CGRectMake((w - dockW) / 2.0, h - dockH - 22.0, dockW, dockH)];
        ApplyEditorGlass(self.iconsDock, 26.0);
        self.iconsDock.alpha = 0.0;
        self.iconsDock.hidden = YES;

        UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectInset(self.iconsDock.bounds, 10.0, 4.0)];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionFillEqually;
        stack.alignment = UIStackViewAlignmentFill;
        stack.spacing = 4.0;

        [stack addArrangedSubview:CreateIconBtn(@"photo.on.rectangle", self, @selector(openPhotoPicker))];
        [stack addArrangedSubview:CreateIconBtn(@"sparkles", self, @selector(cycleTheme))];
        [stack addArrangedSubview:CreateIconBtn(@"textformat", self, @selector(cycleFont))];
        [stack addArrangedSubview:CreateIconBtn(@"paintpalette", self, @selector(cycleColor))];
        [stack addArrangedSubview:CreateIconBtn(@"checkmark", self, @selector(exitCustomizeMode))];
        [self.iconsDock addSubview:stack];
        [self addSubview:self.iconsDock];

        [self updateHeaderTitle];

        // Scroll to active wallpaper card
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentIndex < (NSInteger)self.wallpapers.count) {
                NSIndexPath *ip = [NSIndexPath indexPathForItem:self.currentIndex inSection:0];
                [self.carousel scrollToItemAtIndexPath:ip atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:NO];
            }
        });
    }
    return self;
}

- (void)updateHeaderTitle {
    if (self.currentIndex >= (NSInteger)self.wallpapers.count) return;
    NSDictionary *p = self.wallpapers[self.currentIndex];
    NSInteger mode = [p[@"mode"] integerValue];
    if (mode == 1) {
        self.topHeaderLabel.text = @"PHOTO";
    } else if (mode == 0) {
        self.topHeaderLabel.text = @"DEFAULT";
    } else {
        self.topHeaderLabel.text = [NSString stringWithFormat:@"THEME %ld", (long)((mode - 2) % kIOS27ThemeCount + 1)];
    }
}

- (void)syncActiveProfile {
    iOS27SaveWallpapers(self.wallpapers, self.currentIndex);
    [self updateHeaderTitle];
    if (self.onLiveUpdate) self.onLiveUpdate();
}

- (void)enterCustomizeMode {
    self.iconsDock.hidden = NO;
    [UIView animateWithDuration:0.22 animations:^{
        self.mainBar.alpha = 0.0;
        self.iconsDock.alpha = 1.0;
    } completion:^(BOOL finished) {
        self.mainBar.hidden = YES;
    }];
}

- (void)exitCustomizeMode {
    self.mainBar.hidden = NO;
    [UIView animateWithDuration:0.22 animations:^{
        self.iconsDock.alpha = 0.0;
        self.mainBar.alpha = 1.0;
    } completion:^(BOOL finished) {
        self.iconsDock.hidden = YES;
    }];
}

- (void)addNewWallpaperCard {
    NSInteger randomTheme = 2 + (self.wallpapers.count % kIOS27ThemeCount);
    NSDictionary *newCard = @{
        @"id": [[NSUUID UUID] UUIDString],
        @"mode": @(randomTheme),
        @"photoFile": @"",
        @"fontIndex": @(0),
        @"colorIndex": @(0)
    };
    [self.wallpapers addObject:newCard];
    self.currentIndex = self.wallpapers.count - 1;
    self.pageControl.numberOfPages = self.wallpapers.count;
    self.pageControl.currentPage = self.currentIndex;

    [self.carousel reloadData];
    NSIndexPath *ip = [NSIndexPath indexPathForItem:self.currentIndex inSection:0];
    [self.carousel scrollToItemAtIndexPath:ip atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:YES];

    [self syncActiveProfile];
    [self enterCustomizeMode];
}

- (void)deleteCurrentCard {
    if (self.wallpapers.count <= 1) {
        // Reset single card to default instead of leaving empty
        NSMutableDictionary *m = [self.wallpapers[0] mutableCopy];
        m[@"mode"] = @(0);
        m[@"photoFile"] = @"";
        m[@"fontIndex"] = @(0);
        m[@"colorIndex"] = @(0);
        self.wallpapers[0] = m;
        [self.carousel reloadData];
        [self syncActiveProfile];
        return;
    }

    [self.wallpapers removeObjectAtIndex:self.currentIndex];
    if (self.currentIndex >= (NSInteger)self.wallpapers.count) {
        self.currentIndex = self.wallpapers.count - 1;
    }
    self.pageControl.numberOfPages = self.wallpapers.count;
    self.pageControl.currentPage = self.currentIndex;
    [self.carousel reloadData];
    [self syncActiveProfile];
}

- (void)cycleTheme {
    NSMutableDictionary *m = [self.wallpapers[self.currentIndex] mutableCopy];
    NSInteger cur = [m[@"mode"] integerValue];
    NSInteger maxMode = 2 + kIOS27ThemeCount - 1;
    NSInteger next = (cur < 2 || cur >= maxMode) ? 2 : (cur + 1);
    m[@"mode"] = @(next);
    self.wallpapers[self.currentIndex] = m;

    [self reloadCurrentCard];
    [self syncActiveProfile];
}

- (void)cycleFont {
    NSMutableDictionary *m = [self.wallpapers[self.currentIndex] mutableCopy];
    NSInteger next = ([m[@"fontIndex"] integerValue] + 1) % 5;
    m[@"fontIndex"] = @(next);
    self.wallpapers[self.currentIndex] = m;

    [self reloadCurrentCard];
    [self syncActiveProfile];
}

- (void)cycleColor {
    NSMutableDictionary *m = [self.wallpapers[self.currentIndex] mutableCopy];
    NSInteger next = ([m[@"colorIndex"] integerValue] + 1) % 8;
    m[@"colorIndex"] = @(next);
    self.wallpapers[self.currentIndex] = m;

    [self reloadCurrentCard];
    [self syncActiveProfile];
}

- (void)reloadCurrentCard {
    NSIndexPath *ip = [NSIndexPath indexPathForItem:self.currentIndex inSection:0];
    [self.carousel reloadItemsAtIndexPaths:@[ip]];
}

- (void)openPhotoPicker {
    if (self.photoSheet) [self.photoSheet removeFromSuperview];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat sheetH = h * 0.62;

    IOS27SafePhotoSheet *sheet = [[IOS27SafePhotoSheet alloc] initWithFrame:CGRectMake(12.0, h, w - 24.0, sheetH)];
    self.photoSheet = sheet;

    __weak typeof(self) weakSelf = self;
    __weak typeof(sheet) weakSheet = sheet;

    sheet.onClose = ^{
        [UIView animateWithDuration:0.24 animations:^{
            weakSheet.frame = CGRectMake(12.0, h, w - 24.0, sheetH);
        } completion:^(BOOL finished) {
            [weakSheet removeFromSuperview];
            weakSelf.photoSheet = nil;
        }];
    };

    sheet.onSelectPath = ^(NSString *selectedPath) {
        NSInteger targetIdx = weakSelf.currentIndex;
        NSDictionary *card = weakSelf.wallpapers[targetIdx];
        NSString *cardID = card[@"id"] ?: [[NSUUID UUID] UUIDString];
        NSString *fileName = [NSString stringWithFormat:@"%@.jpg", cardID];
        NSString *destPath = iOS27PhotoPathForName(fileName);

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            CGFloat maxDim = MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height) * MIN([UIScreen mainScreen].scale, 2.0);
            UIImage *resized = iOS27LoadThumbnailAtPath(selectedPath, maxDim);
            NSData *jpegData = UIImageJPEGRepresentation(resized, 0.85);
            if (jpegData && destPath) {
                [jpegData writeToFile:destPath atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (targetIdx < (NSInteger)weakSelf.wallpapers.count) {
                        NSMutableDictionary *m = [weakSelf.wallpapers[targetIdx] mutableCopy];
                        m[@"id"] = cardID;
                        m[@"mode"] = @(1);
                        m[@"photoFile"] = fileName;
                        weakSelf.wallpapers[targetIdx] = m;
                        [weakSelf reloadCurrentCard];
                        [weakSelf syncActiveProfile];
                    }
                    if (weakSheet.onClose) weakSheet.onClose();
                });
            }
        });
    };

    [self addSubview:sheet];
    [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        sheet.frame = CGRectMake(12.0, h - sheetH - 16.0, w - 24.0, sheetH);
    } completion:nil];
}

- (void)doneTapped {
    [self syncActiveProfile];
    if (self.onApplyAndClose) self.onApplyAndClose();
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.wallpapers.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"WallpaperCard" forIndexPath:indexPath];
    NSDictionary *profile = self.wallpapers[indexPath.item];

    UIImageView *bg = (UIImageView *)[cell.contentView viewWithTag:801];
    UILabel *dateLbl = (UILabel *)[cell.contentView viewWithTag:802];
    UILabel *clockLbl = (UILabel *)[cell.contentView viewWithTag:803];
    UIView *pill = [cell.contentView viewWithTag:804];

    if (!bg) {
        cell.contentView.layer.cornerRadius = 26.0;
        cell.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        cell.contentView.layer.borderWidth = 1.5;
        cell.contentView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        cell.contentView.clipsToBounds = YES;

        bg = [[UIImageView alloc] initWithFrame:cell.contentView.bounds];
        bg.tag = 801;
        bg.contentMode = UIViewContentModeScaleAspectFill;
        bg.clipsToBounds = YES;
        bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [cell.contentView addSubview:bg];

        dateLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 34, cell.contentView.bounds.size.width - 24, 18)];
        dateLbl.tag = 802;
        dateLbl.textAlignment = NSTextAlignmentCenter;
        dateLbl.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        dateLbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
        [cell.contentView addSubview:dateLbl];

        clockLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 52, cell.contentView.bounds.size.width - 20, 68)];
        clockLbl.tag = 803;
        clockLbl.textAlignment = NSTextAlignmentCenter;
        clockLbl.adjustsFontSizeToFitWidth = YES;
        [cell.contentView addSubview:clockLbl];

        pill = [[UIView alloc] initWithFrame:CGRectMake((cell.contentView.bounds.size.width - 110) / 2.0, cell.contentView.bounds.size.height - 44.0, 110.0, 26.0)];
        pill.tag = 804;
        ApplyEditorGlass(pill, 13.0);
        UILabel *pLbl = [[UILabel alloc] initWithFrame:pill.bounds];
        pLbl.text = @"hello";
        pLbl.textAlignment = NSTextAlignmentCenter;
        pLbl.font = [UIFont fontWithName:@"SnellRoundhand-Bold" size:16.0] ?: [UIFont italicSystemFontOfSize:14.0];
        pLbl.textColor = [UIColor whiteColor];
        [pill addSubview:pLbl];
        [cell.contentView addSubview:pill];
    }

    bg.frame = cell.contentView.bounds;
    iOS27ApplyProfileToImageView(profile, bg, YES);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"EEE d MMM";
    dateLbl.text = [df stringFromDate:[NSDate date]];

    df.dateFormat = @"h:mm";
    clockLbl.text = [df stringFromDate:[NSDate date]];
    clockLbl.font = iOS27ClockFontForIndex([profile[@"fontIndex"] integerValue], 54.0);
    clockLbl.textColor = iOS27ClockColorForIndex([profile[@"colorIndex"] integerValue]);

    return cell;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    CGFloat pageWidth = self.cardWidth + self.cardSpacing;
    CGFloat approxPage = targetContentOffset->x / pageWidth;
    NSInteger page = (NSInteger)round(approxPage);
    page = MAX(0, MIN(page, (NSInteger)self.wallpapers.count - 1));
    targetContentOffset->x = page * pageWidth;

    if (page != self.currentIndex) {
        self.currentIndex = page;
        self.pageControl.currentPage = page;
        [self updateHeaderTitle];
    }
}

@end

// =========================================================================
// 3. SpringBoard CoverSheet Integration
// =========================================================================
static const void *kGestureAddedKey = &kGestureAddedKey;
static const void *kSwitcherViewKey = &kSwitcherViewKey;

static void TriggerSpringBoardEditor(NSInteger actionMode) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SBCoverSheetPresentationManager *pm = [%c(SBCoverSheetPresentationManager) sharedInstance];
        if (pm && [pm respondsToSelector:@selector(setCoverSheetPresented:animated:withCompletion:)]) {
            [pm setCoverSheetPresented:YES animated:YES withCompletion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (gActiveCoverSheetVC) {
                        [gActiveCoverSheetVC ios27_openSwitcherWithAction:actionMode];
                    }
                });
            }];
        } else if (gActiveCoverSheetVC) {
            [gActiveCoverSheetVC ios27_openSwitcherWithAction:actionMode];
        }
    });
}

static void DarwinOpenSwitcherCallback(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    TriggerSpringBoardEditor(0);
}
static void DarwinOpenCustomizeCallback(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    TriggerSpringBoardEditor(1);
}
static void DarwinOpenAddCallback(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    TriggerSpringBoardEditor(2);
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
    if (objc_getAssociatedObject(self, kSwitcherViewKey)) return NO;

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
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27WallpaperChanged object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIOS27LSStyleChanged object:nil];
}

%new
- (void)ios27_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self ios27_openSwitcherWithAction:0];
}

// actionMode: 0 = Switcher, 1 = Customize Active, 2 = Add New Card
%new
- (void)ios27_openSwitcherWithAction:(NSInteger)actionMode {
    if (objc_getAssociatedObject(self, kSwitcherViewKey)) return;

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    UIWindow *hostWindow = self.view.window;
    if (!hostWindow) return;

    IOS27WallpaperSwitcherView *switcher = [[IOS27WallpaperSwitcherView alloc] initWithFrame:hostWindow.bounds];
    switcher.alpha = 0.0;
    [hostWindow addSubview:switcher];
    objc_setAssociatedObject(self, kSwitcherViewKey, switcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak typeof(self) weakSelf = self;
    __weak typeof(switcher) weakSwitcher = switcher;

    switcher.onLiveUpdate = ^{
        [weakSelf ios27_applySavedWallpaper];
    };

    switcher.onApplyAndClose = ^{
        [weakSelf ios27_applySavedWallpaper];
        [UIView animateWithDuration:0.24 animations:^{
            weakSwitcher.alpha = 0.0;
        } completion:^(BOOL finished) {
            [weakSwitcher removeFromSuperview];
            objc_setAssociatedObject(weakSelf, kSwitcherViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
    };

    [UIView animateWithDuration:0.26 animations:^{
        switcher.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (actionMode == 1) {
            [switcher enterCustomizeMode];
        } else if (actionMode == 2) {
            [switcher addNewWallpaperCard];
        }
    }];
}

%end

%end

// =========================================================================
// 4. Settings App -> Wallpaper Page (Customize + Add New Wallpaper)
// =========================================================================
@interface IOS27SettingsWallpaperController : UIViewController
@property (nonatomic, strong) UIImageView *previewImgView;
@property (nonatomic, strong) UILabel *previewClock;
@end

@implementation IOS27SettingsWallpaperController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Wallpaper";
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor blackColor];
    }

    CGFloat w = self.view.bounds.size.width;
    CGFloat cardW = MIN(w * 0.54, 210.0);
    CGFloat cardH = cardW * 1.75;

    UIView *cardBox = [[UIView alloc] initWithFrame:CGRectMake((w - cardW) / 2.0, 96.0, cardW, cardH)];
    cardBox.layer.cornerRadius = 24.0;
    cardBox.layer.cornerCurve = kCACornerCurveContinuous;
    cardBox.clipsToBounds = YES;
    cardBox.layer.borderWidth = 1.5;
    cardBox.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.35].CGColor;
    [self.view addSubview:cardBox];

    self.previewImgView = [[UIImageView alloc] initWithFrame:cardBox.bounds];
    self.previewImgView.contentMode = UIViewContentModeScaleAspectFill;
    [cardBox addSubview:self.previewImgView];

    self.previewClock = [[UILabel alloc] initWithFrame:CGRectMake(8, 36, cardW - 16, 54)];
    self.previewClock.textAlignment = NSTextAlignmentCenter;
    self.previewClock.text = @"9:41";
    [cardBox addSubview:self.previewClock];

    CGFloat btnY = CGRectGetMaxY(cardBox.frame) + 22.0;

    UIButton *customizeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    customizeBtn.frame = CGRectMake((w - cardW) / 2.0, btnY, cardW, 44.0);
    [customizeBtn setTitle:@"Customize" forState:UIControlStateNormal];
    customizeBtn.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [customizeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    customizeBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.18 blue:0.24 alpha:1.0];
    customizeBtn.layer.cornerRadius = 14.0;
    [customizeBtn addTarget:self action:@selector(openCustomize) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:customizeBtn];

    UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    addBtn.frame = CGRectMake(24.0, CGRectGetMaxY(customizeBtn.frame) + 18.0, w - 48.0, 48.0);
    [addBtn setTitle:@"+ Add New Wallpaper" forState:UIControlStateNormal];
    addBtn.titleLabel.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightSemibold];
    [addBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    addBtn.backgroundColor = [UIColor systemBlueColor];
    addBtn.layer.cornerRadius = 14.0;
    [addBtn addTarget:self action:@selector(openAddNew) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:addBtn];

    UIButton *switcherBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    switcherBtn.frame = CGRectMake(24.0, CGRectGetMaxY(addBtn.frame) + 10.0, w - 48.0, 40.0);
    [switcherBtn setTitle:@"Open Saved Wallpapers" forState:UIControlStateNormal];
    switcherBtn.titleLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
    [switcherBtn addTarget:self action:@selector(openSwitcher) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:switcherBtn];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSDictionary *active = iOS27ActiveWallpaperProfile();
    iOS27ApplyProfileToImageView(active, self.previewImgView, YES);
    self.previewClock.font = iOS27ClockFontForIndex([active[@"fontIndex"] integerValue], 42.0);
    self.previewClock.textColor = iOS27ClockColorForIndex([active[@"colorIndex"] integerValue]);
}

- (void)openCustomize {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.elite.ios27.openEditorCustomize"),
                                         NULL, NULL, true);
}

- (void)openAddNew {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.elite.ios27.openEditorAdd"),
                                         NULL, NULL, true);
}

- (void)openSwitcher {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.elite.ios27.openEditorSwitcher"),
                                         NULL, NULL, true);
}

@end

%group SettingsWallpaperRedirectHooks

%hook PSUIPrefsListController

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self respondsToSelector:@selector(specifierAtIndexPath:)] ? [self specifierAtIndexPath:indexPath] : nil;
    NSString *ident = ([spec respondsToSelector:@selector(identifier)] && spec.identifier) ? [spec.identifier lowercaseString] : @"";
    NSString *name = ([spec respondsToSelector:@selector(name)] && spec.name) ? [spec.name lowercaseString] : @"";

    if ([ident isEqualToString:@"wallpaper"] || [name isEqualToString:@"wallpaper"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        IOS27SettingsWallpaperController *vc = [[IOS27SettingsWallpaperController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
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
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DarwinOpenSwitcherCallback, CFSTR("com.elite.ios27.openEditorSwitcher"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DarwinOpenCustomizeCallback, CFSTR("com.elite.ios27.openEditorCustomize"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DarwinOpenAddCallback, CFSTR("com.elite.ios27.openEditorAdd"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    } else if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
        %init(SettingsWallpaperRedirectHooks);
    }
}
