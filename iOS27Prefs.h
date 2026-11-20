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

static inline NSString *iOS27WallpaperFilePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libDir = paths.firstObject ?: @"/var/mobile/Library";
    return [libDir stringByAppendingPathComponent:@"Preferences/iOS27_CustomLSWallpaper.jpg"];
}

static inline void iOS27ApplyWallpaperToView(UIImageView *wpView) {
    if (!wpView) return;

    for (CALayer *sub in [wpView.layer.sublayers copy]) {
        if ([sub.name isEqualToString:@"iOS27PresetGradient"]) {
            [sub removeFromSuperlayer];
        }
    }

    // Mode: 0 = Stock iOS, 1 = Custom Photo, 2..13 = 12 Built-in Themes
    NSInteger mode = iOS27IntPref(@"kLSWallpaperMode", 0);

    if (mode == 0) {
        wpView.image = nil;
        wpView.hidden = YES;
        return;
    }

    if (mode == 1) {
        UIImage *savedImg = [UIImage imageWithContentsOfFile:iOS27WallpaperFilePath()];
        if (savedImg) {
            wpView.image = savedImg;
            wpView.hidden = NO;
            return;
        }
        wpView.hidden = YES;
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

#endif
