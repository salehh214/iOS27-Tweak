#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <Vision/Vision.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

@interface CAMViewfinderViewController : UIViewController
@end

@interface CAMViewfinderViewController (iOS27CameraUI)
- (void)ios27cam_setupOverlay;
- (void)ios27cam_layoutOverlay;
- (void)ios27cam_togglePortrait;
- (void)ios27cam_toggleApertureBar;
- (void)ios27cam_apertureChanged:(UISlider *)slider;
- (void)ios27cam_showToast:(NSString *)message isSuccess:(BOOL)success;
@end

// =========================================================================
// Lightweight Hardware Glass Helper (Zero UIVisualEffectView)
// =========================================================================
static void ApplyCamGlass(UIView *view, CGFloat radius, BOOL activeGold) {
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0;
    view.clipsToBounds = YES;

    if (activeGold) {
        view.backgroundColor = [UIColor colorWithRed:0.98 green:0.78 blue:0.15 alpha:0.92];
        view.layer.borderColor = [UIColor colorWithRed:1.0 green:0.92 blue:0.55 alpha:0.90].CGColor;
    } else {
        view.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.62];
        view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.32].CGColor;
    }
}

// =========================================================================
// Post-Capture AI Portrait & DSLR Bokeh Engine (2GB RAM Safe)
// =========================================================================
@interface IOS27PortraitEngine : NSObject <PHPhotoLibraryChangeObserver>
@property (nonatomic, assign) BOOL portraitEnabled;
@property (nonatomic, assign) CGFloat fStop; // 1.4 (heaviest bokeh) to 4.5 (subtle bokeh)
@property (nonatomic, strong) NSDate *enabledSince;
@property (nonatomic, strong) PHFetchResult<PHAsset *> *lastFetchResult;
@property (nonatomic, strong) NSMutableSet<NSString *> *processedIDs;
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, copy) void (^onStatusToast)(NSString *msg, BOOL success);
+ (instancetype)shared;
- (void)startObserving;
@end

@implementation IOS27PortraitEngine

+ (instancetype)shared {
    static IOS27PortraitEngine *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[IOS27PortraitEngine alloc] init];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _portraitEnabled = NO;
        _fStop = 1.8;
        _processedIDs = [NSMutableSet set];
        _renderQueue = dispatch_queue_create("com.elite.ios27.portraitQueue", DISPATCH_QUEUE_SERIAL);
        _ciContext = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,
            kCIContextCacheIntermediates: @NO
        }];
    }
    return self;
}

- (void)startObserving {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PHFetchOptions *opts = [[PHFetchOptions alloc] init];
        opts.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        opts.fetchLimit = 10;
        self.lastFetchResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:opts];
        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    });
}

- (void)setPortraitEnabled:(BOOL)portraitEnabled {
    _portraitEnabled = portraitEnabled;
    if (portraitEnabled) {
        self.enabledSince = [NSDate date];
    }
}

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    if (!self.portraitEnabled) return;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;

    PHFetchResultChangeDetails *details = [changeInstance changeDetailsForFetchResult:self.lastFetchResult];
    if (!details) return;

    self.lastFetchResult = details.fetchResultAfterChanges;
    NSArray<PHAsset *> *inserted = details.insertedObjects;
    if (inserted.count == 0) return;

    for (PHAsset *asset in inserted) {
        if (asset.mediaType != PHAssetMediaTypeImage) continue;

        @synchronized (self.processedIDs) {
            if ([self.processedIDs containsObject:asset.localIdentifier]) continue;
        }

        // Only process brand-new captures taken while Portrait Mode is ON
        if (asset.creationDate && self.enabledSince) {
            if ([asset.creationDate timeIntervalSinceDate:self.enabledSince] < -2.0) continue;
            if (fabs([asset.creationDate timeIntervalSinceNow]) > 15.0) continue;
        }

        @synchronized (self.processedIDs) {
            [self.processedIDs addObject:asset.localIdentifier];
        }

        [self processCapturedAsset:asset fStop:self.fStop];
    }
}

- (UIImage *)normalizeUprightImage:(UIImage *)src maxDimension:(CGFloat)maxDim {
    if (!src) return nil;
    CGSize origSize = src.size;
    CGFloat longest = MAX(origSize.width, origSize.height);
    CGFloat scaleFactor = (longest > maxDim) ? (maxDim / longest) : 1.0;
    CGSize targetSize = CGSizeMake(floor(origSize.width * scaleFactor), floor(origSize.height * scaleFactor));

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [src drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    }];
}

- (void)processCapturedAsset:(PHAsset *)asset fStop:(CGFloat)fStop {
    if (self.onStatusToast) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.onStatusToast(@"Rendering Portrait...", YES);
        });
    }

    PHImageRequestOptions *reqOpts = [[PHImageRequestOptions alloc] init];
    reqOpts.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    reqOpts.resizeMode = PHImageResizeModeExact;
    reqOpts.networkAccessAllowed = NO;
    reqOpts.synchronous = NO;

    // 1800px cap keeps peak RAM ultra-safe on 2GB iPhone SE while staying razor-sharp
    CGSize reqSize = CGSizeMake(1800.0, 1800.0);

    [[PHImageManager defaultManager] requestImageForAsset:asset
                                               targetSize:reqSize
                                              contentMode:PHImageContentModeAspectFit
                                                  options:reqOpts
                                            resultHandler:^(UIImage *result, NSDictionary *info) {
        BOOL isDegraded = [info[PHImageResultIsDegradedKey] boolValue];
        if (isDegraded || !result) return;

        dispatch_async(self.renderQueue, ^{
            @autoreleasepool {
                [self renderBokehPortraitFromImage:result fStop:fStop];
            }
        });
    }];
}

- (BOOL)maskContainsPerson:(CIImage *)maskCI {
    CIFilter *avgFilter = [CIFilter filterWithName:@"CIAreaAverage"];
    if (!avgFilter) return YES;

    [avgFilter setValue:maskCI forKey:kCIInputImageKey];
    [avgFilter setValue:[CIVector vectorWithCGRect:maskCI.extent] forKey:kCIInputExtentKey];
    CIImage *avgOut = avgFilter.outputImage;
    if (!avgOut) return YES;

    uint8_t pixel[4] = {0, 0, 0, 0};
    [self.ciContext render:avgOut
                  toBitmap:pixel
                  rowBytes:4
                    bounds:CGRectMake(0, 0, 1, 1)
                    format:kCIFormatRGBA8
                colorSpace:NULL];

    CGFloat coverage = (CGFloat)pixel[0] / 255.0;
    return (coverage > 0.015 && coverage < 0.985);
}

- (void)renderBokehPortraitFromImage:(UIImage *)rawImage fStop:(CGFloat)fStop {
    if (@available(iOS 15.0, *)) {
        UIImage *upright = [self normalizeUprightImage:rawImage maxDimension:1800.0];
        if (!upright || !upright.CGImage) return;

        // 1. Run Vision Accurate Person Segmentation
        VNGeneratePersonSegmentationRequest *segReq = [[VNGeneratePersonSegmentationRequest alloc] init];
        segReq.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
        segReq.outputPixelFormat = kCVPixelFormatType_OneComponent8;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:upright.CGImage options:@{}];
        NSError *vnErr = nil;
        [handler performRequests:@[segReq] error:&vnErr];

        VNPixelBufferObservation *obs = segReq.results.firstObject;
        if (vnErr || !obs || !obs.pixelBuffer) {
            if (self.onStatusToast) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.onStatusToast(@"No Person Detected", NO);
                });
            }
            return;
        }

        CIImage *origCI = [CIImage imageWithCGImage:upright.CGImage];
        CIImage *rawMaskCI = [CIImage imageWithCVPixelBuffer:obs.pixelBuffer];

        // Verify a person is actually framed before blurring
        if (![self maskContainsPerson:rawMaskCI]) {
            if (self.onStatusToast) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.onStatusToast(@"No Person Detected", NO);
                });
            }
            return;
        }

        // 2. Scale & Feather Mask Edges for Natural Hair/Shoulder Blending
        CGFloat sx = origCI.extent.size.width / MAX(rawMaskCI.extent.size.width, 1.0);
        CGFloat sy = origCI.extent.size.height / MAX(rawMaskCI.extent.size.height, 1.0);
        CIImage *scaledMask = [rawMaskCI imageByApplyingTransform:CGAffineTransformMakeScale(sx, sy)];

        CIFilter *feather = [CIFilter filterWithName:@"CIGaussianBlur"];
        [feather setValue:[scaledMask imageByClampingToExtent] forKey:kCIInputImageKey];
        [feather setValue:@(2.2) forKey:kCIInputRadiusKey];
        CIImage *softMask = [feather.outputImage imageByCroppingToRect:origCI.extent] ?: scaledMask;

        // 3. Map f-stop (1.4 .. 4.5) to Rich DSLR Bokeh Radius (28.0 .. 7.0)
        CGFloat normalized = (4.5 - MAX(1.4, MIN(4.5, fStop))) / (4.5 - 1.4); // 1.0 at f/1.4, 0.0 at f/4.5
        CGFloat blurRadius = 7.0 + normalized * 21.0;

        CIImage *clampedOrig = [origCI imageByClampingToExtent];
        CIImage *blurredBG = nil;

        // Primary: Optical CIBokehBlur (Creamy DSLR Bokeh with Soft Highlight Rings)
        CIFilter *bokeh = [CIFilter filterWithName:@"CIBokehBlur"];
        if (bokeh) {
            [bokeh setValue:clampedOrig forKey:kCIInputImageKey];
            [bokeh setValue:@(blurRadius) forKey:@"inputRadius"];
            [bokeh setValue:@(0.22) forKey:@"inputRingAmount"];
            [bokeh setValue:@(0.08) forKey:@"inputRingSize"];
            [bokeh setValue:@(1.0) forKey:@"inputSoftness"];
            blurredBG = [bokeh.outputImage imageByCroppingToRect:origCI.extent];
        }

        // Fallback: CIDiscBlur / CIGaussianBlur
        if (!blurredBG) {
            CIFilter *disc = [CIFilter filterWithName:@"CIDiscBlur"] ?: [CIFilter filterWithName:@"CIGaussianBlur"];
            [disc setValue:clampedOrig forKey:kCIInputImageKey];
            [disc setValue:@(blurRadius) forKey:kCIInputRadiusKey];
            blurredBG = [disc.outputImage imageByCroppingToRect:origCI.extent];
        }

        if (!blurredBG) return;

        // 4. Blend Crisp Foreground Subject Over Creamy Bokeh Background
        CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
        [blend setValue:origCI forKey:kCIInputImageKey];
        [blend setValue:blurredBG forKey:kCIInputBackgroundImageKey];
        [blend setValue:softMask forKey:kCIInputMaskImageKey];

        CIImage *outputCI = blend.outputImage;
        if (!outputCI) return;

        CGImageRef outCG = [self.ciContext createCGImage:outputCI fromRect:origCI.extent];
        if (!outCG) return;

        UIImage *finalPortrait = [UIImage imageWithCGImage:outCG];
        CGImageRelease(outCG);

        NSData *jpegData = UIImageJPEGRepresentation(finalPortrait, 0.92);
        if (!jpegData) return;

        // 5. Save Final Portrait to Photos Library (Pre-register ID to prevent re-triggering)
        __block NSString *createdLocalID = nil;
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
            [req addResourceWithType:PHAssetResourceTypePhoto data:jpegData options:nil];
            createdLocalID = req.placeholderForCreatedAsset.localIdentifier;
            if (createdLocalID) {
                @synchronized (self.processedIDs) {
                    [self.processedIDs addObject:createdLocalID];
                }
            }
        } completionHandler:^(BOOL success, NSError *error) {
            if (self.onStatusToast) {
                NSString *msg = success ? [NSString stringWithFormat:@"Portrait Saved (f/%.1f)", fStop] : @"Portrait Save Failed";
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.onStatusToast(msg, success);
                });
            }
        }];
    }
}

@end

// =========================================================================
// Camera Viewfinder UI Hooks (iPhone SE 2016 Compact Glass Pill + f-stop Slider)
// =========================================================================
static const void *kPortraitPillKey = &kPortraitPillKey;
static const void *kFStopBtnKey = &kFStopBtnKey;
static const void *kSliderBarKey = &kSliderBarKey;
static const void *kToastLblKey = &kToastLblKey;

%hook CAMViewfinderViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[IOS27PortraitEngine shared] startObserving];
    [self ios27cam_setupOverlay];
    [self ios27cam_layoutOverlay];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [self ios27cam_layoutOverlay];
}

%new
- (void)ios27cam_setupOverlay {
    if (objc_getAssociatedObject(self, kPortraitPillKey)) return;

    __weak typeof(self) weakSelf = self;
    [IOS27PortraitEngine shared].onStatusToast = ^(NSString *msg, BOOL success) {
        [weakSelf ios27cam_showToast:msg isSuccess:success];
    };

    // 1. Portrait Toggle Pill (Compact iOS 27 Glass)
    UIButton *portraitPill = [UIButton buttonWithType:UIButtonTypeCustom];
    [portraitPill setTitle:@" PORTRAIT" forState:UIControlStateNormal];
    portraitPill.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    [portraitPill setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:11.5 weight:UIImageSymbolWeightBold];
        [portraitPill setImage:[UIImage systemImageNamed:@"f.cursive.circle.fill" withConfiguration:cfg] forState:UIControlStateNormal];
        portraitPill.tintColor = [UIColor whiteColor];
    }
    ApplyCamGlass(portraitPill, 14.0, NO);
    [portraitPill addTarget:self action:@selector(ios27cam_togglePortrait) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:portraitPill];
    objc_setAssociatedObject(self, kPortraitPillKey, portraitPill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 2. f-stop Aperture Pill (Appears next to Portrait pill when ON)
    UIButton *fBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [fBtn setTitle:@"f/1.8" forState:UIControlStateNormal];
    fBtn.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightBold];
    [fBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ApplyCamGlass(fBtn, 14.0, NO);
    fBtn.hidden = YES;
    [fBtn addTarget:self action:@selector(ios27cam_toggleApertureBar) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fBtn];
    objc_setAssociatedObject(self, kFStopBtnKey, fBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 3. Expandable Aperture Depth Slider Bar
    UIView *sliderBar = [[UIView alloc] initWithFrame:CGRectZero];
    ApplyCamGlass(sliderBar, 18.0, NO);
    sliderBar.hidden = YES;

    UILabel *leftL = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 34, 24)];
    leftL.text = @"f/1.4";
    leftL.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    leftL.textColor = [UIColor systemYellowColor];
    [sliderBar addSubview:leftL];

    UILabel *rightL = [[UILabel alloc] initWithFrame:CGRectZero];
    rightL.tag = 901;
    rightL.text = @"f/4.5";
    rightL.textAlignment = NSTextAlignmentRight;
    rightL.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    rightL.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
    [sliderBar addSubview:rightL];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
    slider.tag = 902;
    slider.minimumValue = 1.4;
    slider.maximumValue = 4.5;
    slider.value = [IOS27PortraitEngine shared].fStop;
    slider.minimumTrackTintColor = [UIColor systemYellowColor];
    [slider addTarget:self action:@selector(ios27cam_apertureChanged:) forControlEvents:UIControlEventValueChanged];
    [sliderBar addSubview:slider];

    [self.view addSubview:sliderBar];
    objc_setAssociatedObject(self, kSliderBarKey, sliderBar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 4. Status Toast Pill ("Portrait Saved (f/1.8)")
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectZero];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    toast.textColor = [UIColor whiteColor];
    ApplyCamGlass(toast, 14.0, NO);
    toast.alpha = 0.0;
    [self.view addSubview:toast];
    objc_setAssociatedObject(self, kToastLblKey, toast, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)ios27cam_layoutOverlay {
    UIButton *portraitPill = objc_getAssociatedObject(self, kPortraitPillKey);
    UIButton *fBtn = objc_getAssociatedObject(self, kFStopBtnKey);
    UIView *sliderBar = objc_getAssociatedObject(self, kSliderBarKey);
    UILabel *toast = objc_getAssociatedObject(self, kToastLblKey);
    if (!portraitPill) return;

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    // Positioned cleanly just below the Camera top bar on SE 2016 (568pt) & taller screens
    CGFloat topY = (h > 600.0) ? 94.0 : 50.0;

    CGFloat pillW = 98.0;
    CGFloat fW = 52.0;
    CGFloat totalW = fBtn.hidden ? pillW : (pillW + 8.0 + fW);
    CGFloat startX = floor((w - totalW) / 2.0);

    portraitPill.frame = CGRectMake(startX, topY, pillW, 28.0);
    fBtn.frame = CGRectMake(startX + pillW + 8.0, topY, fW, 28.0);

    CGFloat barW = MIN(w - 28.0, 260.0);
    sliderBar.frame = CGRectMake(floor((w - barW) / 2.0), topY + 34.0, barW, 36.0);
    UIView *rightL = [sliderBar viewWithTag:901];
    UIView *slider = [sliderBar viewWithTag:902];
    rightL.frame = CGRectMake(barW - 44.0, 6.0, 34.0, 24.0);
    slider.frame = CGRectMake(46.0, 3.0, barW - 92.0, 30.0);

    CGFloat toastW = 176.0;
    toast.frame = CGRectMake(floor((w - toastW) / 2.0), topY + (sliderBar.hidden ? 36.0 : 78.0), toastW, 28.0);

    [self.view bringSubviewToFront:portraitPill];
    [self.view bringSubviewToFront:fBtn];
    [self.view bringSubviewToFront:sliderBar];
    [self.view bringSubviewToFront:toast];
}

%new
- (void)ios27cam_togglePortrait {
    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [h impactOccurred];

    IOS27PortraitEngine *eng = [IOS27PortraitEngine shared];
    eng.portraitEnabled = !eng.portraitEnabled;

    UIButton *portraitPill = objc_getAssociatedObject(self, kPortraitPillKey);
    UIButton *fBtn = objc_getAssociatedObject(self, kFStopBtnKey);
    UIView *sliderBar = objc_getAssociatedObject(self, kSliderBarKey);

    ApplyCamGlass(portraitPill, 14.0, eng.portraitEnabled);
    UIColor *fg = eng.portraitEnabled ? [UIColor blackColor] : [UIColor whiteColor];
    [portraitPill setTitleColor:fg forState:UIControlStateNormal];
    portraitPill.tintColor = fg;

    fBtn.hidden = !eng.portraitEnabled;
    if (!eng.portraitEnabled) {
        sliderBar.hidden = YES;
    }

    [UIView animateWithDuration:0.20 animations:^{
        [self ios27cam_layoutOverlay];
    }];
}

%new
- (void)ios27cam_toggleApertureBar {
    UIView *sliderBar = objc_getAssociatedObject(self, kSliderBarKey);
    sliderBar.hidden = !sliderBar.hidden;
    [self ios27cam_layoutOverlay];
}

%new
- (void)ios27cam_apertureChanged:(UISlider *)slider {
    CGFloat val = round(slider.value * 10.0) / 10.0;
    [IOS27PortraitEngine shared].fStop = val;
    UIButton *fBtn = objc_getAssociatedObject(self, kFStopBtnKey);
    [fBtn setTitle:[NSString stringWithFormat:@"f/%.1f", val] forState:UIControlStateNormal];
}

%new
- (void)ios27cam_showToast:(NSString *)message isSuccess:(BOOL)success {
    UILabel *toast = objc_getAssociatedObject(self, kToastLblKey);
    if (!toast) return;

    toast.text = message;
    toast.textColor = success ? [UIColor systemYellowColor] : [UIColor whiteColor];
    [self ios27cam_layoutOverlay];

    [UIView animateWithDuration:0.20 animations:^{
        toast.alpha = 1.0;
    }];

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(ios27cam_hideToast) object:nil];
    [self performSelector:@selector(ios27cam_hideToast) withObject:nil afterDelay:2.2];
}

%new
- (void)ios27cam_hideToast {
    UILabel *toast = objc_getAssociatedObject(self, kToastLblKey);
    if (!toast) return;
    [UIView animateWithDuration:0.25 animations:^{
        toast.alpha = 0.0;
    }];
}

%end
