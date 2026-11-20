#ifndef IOS27_PREFS_H
#define IOS27_PREFS_H

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#define kPrefsSuiteName @"com.elite.ios27"
#define kIOS27LSStyleChanged @"iOS27LSStyleDidChange"
#define kIOS27WallpaperChanged @"iOS27WallpaperDidChange"
#define kIOS27ThemeCount 12

static inline BOOL iOS27BoolPref(NSString *key, BOOL defaultValue) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
    id val = [prefs objectForKey:key];
    return val ? [val boolValue] : defaultValue;
}

static inline CGFloat iOS27FloatPref(NSString *key, CGFloat defaultValue) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
    id val = [prefs objectForKey:key];
    return val ? (CGFloat)[val doubleValue] : defaultValue;
}

static inline NSInteger iOS27IntPref(NSString *key, NSInteger defaultValue) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
    id val = [prefs objectForKey:key];
    return val ? [val integerValue] : defaultValue;
}

static inline void iOS27SetIntPref(NSString *key, NSInteger value) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
    [prefs setInteger:value forKey:key];
    [prefs synchronize];
}

static inline NSString *iOS27WallpapersDir(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libDir = paths.firstObject ?: @"/var/mobile/Library";
    NSString *dir = [libDir stringByAppendingPathComponent:@"Preferences/iOS27_Wallpapers"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static inline NSString *iOS27PhotoPathForName(NSString *fileName) {
    if (!fileName || fileName.length == 0) return nil;
    return [iOS27WallpapersDir() stringByAppendingPathComponent:fileName];
}

static inline NSMutableArray<NSDictionary *> *iOS27LoadSavedWallpapers(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
    NSArray *saved = [prefs arrayForKey:@"kSavedWallpapers"];
    if ([saved isKindOfClass:[NSArray class]] && saved.count > 0) {
        return [saved mutableCopy];
    }
    // Default 2 starter cards so switcher carousel works immediately
    NSMutableArray *defaults = [NSMutableArray arrayWithObjects:
        @{
            @"id": @"default-1",
            @"mode": @(2),
            @"photoFile": @"",
            @"fontIndex": @(0),
            @"colorIndex": @(0)
        },
        @{
            @"id": @"default-2",
            @"mode": @(4),
            @"photoFile": @"",
            @"fontIndex": @(1),
            @"colorIndex": @(3)
        },
        nil];
    [prefs setObject:defaults forKey:@"kSavedWallpapers"];
    [prefs setInteger:0 forKey:@"kActiveWallpaperIndex"];
    [prefs synchronize];
    return defaults;
}

static inline void iOS27SaveWallpapers(NSArray<NSDictionary *> *list, NSInteger activeIdx) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuiteName];
    [prefs setObject:list forKey:@"kSavedWallpapers"];
    NSInteger safeIdx = (list.count > 0) ? MAX(0, MIN(activeIdx, (NSInteger)list.count - 1)) : 0;
    [prefs setInteger:safeIdx forKey:@"kActiveWallpaperIndex"];
    [prefs synchronize];
}

static inline NSInteger iOS27ActiveWallpaperIndex(void) {
    NSArray *list = iOS27LoadSavedWallpapers();
    NSInteger idx = iOS27IntPref(@"kActiveWallpaperIndex", 0);
    if (idx < 0 || idx >= (NSInteger)list.count) return 0;
    return idx;
}

static inline NSDictionary *iOS27ActiveWallpaperProfile(void) {
    NSArray *list = iOS27LoadSavedWallpapers();
    NSInteger idx = iOS27ActiveWallpaperIndex();
    return (list.count > 0) ? list[idx] : @{@"mode": @(0), @"fontIndex": @(0), @"colorIndex": @(0)};
}

static inline UIFont *iOS27ClockFontForIndex(NSInteger idx, CGFloat size) {
    UIFontDescriptor *base = [UIFont systemFontOfSize:size weight:UIFontWeightHeavy].fontDescriptor;
    switch (idx % 5) {
        case 1:
            return [UIFont systemFontOfSize:size weight:UIFontWeightBold];
        case 2: {
            UIFontDescriptor *serif = [base fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
            return serif ? [UIFont fontWithDescriptor:serif size:size] : [UIFont fontWithName:@"Georgia-Bold" size:size * 0.94];
        }
        case 3: {
            UIFontDescriptor *mono = [base fontDescriptorWithDesign:UIFontDescriptorSystemDesignMonospaced];
            return mono ? [UIFont fontWithDescriptor:mono size:size * 0.88] : [UIFont monospacedDigitSystemFontOfSize:size * 0.90 weight:UIFontWeightBold];
        }
        case 4:
            return [UIFont systemFontOfSize:size * 1.04 weight:UIFontWeightThin];
        default: {
            UIFontDescriptor *rounded = [base fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
            return rounded ? [UIFont fontWithDescriptor:rounded size:size] : [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
        }
    }
}

static inline UIColor *iOS27ClockColorForIndex(NSInteger idx) {
    switch (idx % 8) {
        case 1: return [UIColor colorWithWhite:1.0 alpha:0.98];                    // Pure White
        case 2: return [UIColor colorWithRed:0.45 green:1.00 blue:0.78 alpha:0.98]; // Neon Mint
        case 3: return [UIColor colorWithRed:1.00 green:0.84 blue:0.35 alpha:0.98]; // Sunset Gold
        case 4: return [UIColor colorWithRed:1.00 green:0.62 blue:0.78 alpha:0.98]; // Soft Rose
        case 5: return [UIColor colorWithRed:0.78 green:0.65 blue:1.00 alpha:0.98]; // Lavender
        case 6: return [UIColor colorWithRed:1.00 green:0.48 blue:0.25 alpha:0.98]; // Vibrant Orange
        case 7: return [UIColor colorWithRed:0.30 green:0.80 blue:1.00 alpha:0.98]; // Electric Blue
        default: return [UIColor colorWithRed:0.86 green:0.96 blue:1.00 alpha:0.98];// Ice Cyan
    }
}

static inline void iOS27ApplyProfileToImageView(NSDictionary *profile, UIImageView *wpView, BOOL isPreviewCard) {
    if (!wpView) return;

    for (CALayer *sub in [wpView.layer.sublayers copy]) {
        if ([sub.name isEqualToString:@"iOS27PresetGradient"]) {
            [sub removeFromSuperlayer];
        }
    }

    NSInteger mode = [profile[@"mode"] integerValue];
    NSString *photoFile = profile[@"photoFile"];

    if (mode == 0) {
        wpView.image = nil;
        if (isPreviewCard) {
            wpView.hidden = NO;
            wpView.backgroundColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:1.0];
        } else {
            wpView.hidden = YES;
        }
        return;
    }

    if (mode == 1 && photoFile.length > 0) {
        NSString *path = iOS27PhotoPathForName(photoFile);
        UIImage *savedImg = path ? [UIImage imageWithContentsOfFile:path] : nil;
        if (savedImg) {
            wpView.image = savedImg;
            wpView.hidden = NO;
            return;
        }
        wpView.image = nil;
        wpView.hidden = !isPreviewCard;
        wpView.backgroundColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:1.0];
        return;
    }

    wpView.image = nil;
    wpView.hidden = NO;

    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.name = @"iOS27PresetGradient";
    grad.frame = wpView.bounds;
    grad.startPoint = CGPointMake(0.1, 0.0);
    grad.endPoint = CGPointMake(0.9, 1.0);

    NSInteger themeIdx = (mode - 2) % kIOS27ThemeCount;
    if (themeIdx < 0) themeIdx = 0;

    switch (themeIdx) {
        case 0: // Cyber Ocean
            grad.colors = @[
                (id)[UIColor colorWithRed:0.02 green:0.10 blue:0.26 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.04 green:0.38 blue:0.58 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.10 green:0.74 blue:0.78 alpha:1.0].CGColor
            ];
            break;
        case 1: // Midnight Aurora
            grad.colors = @[
                (id)[UIColor colorWithRed:0.05 green:0.03 blue:0.18 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.30 green:0.10 blue:0.46 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.08 green:0.52 blue:0.60 alpha:1.0].CGColor
            ];
            break;
        case 2: // Sunset Glass
            grad.colors = @[
                (id)[UIColor colorWithRed:0.16 green:0.05 blue:0.24 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.68 green:0.18 blue:0.36 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.96 green:0.56 blue:0.24 alpha:1.0].CGColor
            ];
            break;
        case 3: // Obsidian Minimal
            grad.colors = @[
                (id)[UIColor colorWithRed:0.03 green:0.04 blue:0.07 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.12 green:0.16 blue:0.24 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.04 green:0.06 blue:0.10 alpha:1.0].CGColor
            ];
            break;
        case 4: // Emerald Forest
            grad.colors = @[
                (id)[UIColor colorWithRed:0.02 green:0.14 blue:0.12 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.06 green:0.42 blue:0.34 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.24 green:0.76 blue:0.56 alpha:1.0].CGColor
            ];
            break;
        case 5: // Royal Amethyst
            grad.colors = @[
                (id)[UIColor colorWithRed:0.14 green:0.04 blue:0.28 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.44 green:0.14 blue:0.68 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.84 green:0.36 blue:0.78 alpha:1.0].CGColor
            ];
            break;
        case 6: // Solar Flare
            grad.colors = @[
                (id)[UIColor colorWithRed:0.24 green:0.04 blue:0.06 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.78 green:0.20 blue:0.12 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.98 green:0.74 blue:0.20 alpha:1.0].CGColor
            ];
            break;
        case 7: // Arctic Frost
            grad.colors = @[
                (id)[UIColor colorWithRed:0.14 green:0.28 blue:0.48 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.42 green:0.68 blue:0.88 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.82 green:0.92 blue:0.98 alpha:1.0].CGColor
            ];
            break;
        case 8: // Cherry Blossom
            grad.colors = @[
                (id)[UIColor colorWithRed:0.28 green:0.08 blue:0.20 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.76 green:0.32 blue:0.48 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.98 green:0.74 blue:0.80 alpha:1.0].CGColor
            ];
            break;
        case 9: // Deep Space
            grad.colors = @[
                (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.08 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.08 green:0.10 blue:0.30 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.18 green:0.08 blue:0.34 alpha:1.0].CGColor
            ];
            break;
        case 10: // Golden Horizon
            grad.colors = @[
                (id)[UIColor colorWithRed:0.16 green:0.10 blue:0.04 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.58 green:0.38 blue:0.14 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.94 green:0.78 blue:0.42 alpha:1.0].CGColor
            ];
            break;
        default: // Neon Cyberpunk
            grad.colors = @[
                (id)[UIColor colorWithRed:0.06 green:0.04 blue:0.22 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.86 green:0.12 blue:0.52 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.08 green:0.82 blue:0.92 alpha:1.0].CGColor
            ];
            break;
    }

    [wpView.layer insertSublayer:grad atIndex:0];
}

static inline void iOS27ApplyWallpaperToView(UIImageView *wpView) {
    iOS27ApplyProfileToImageView(iOS27ActiveWallpaperProfile(), wpView, NO);
}

#endif
