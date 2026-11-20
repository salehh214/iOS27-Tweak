#ifndef IOS27_PREFS_H
#define IOS27_PREFS_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#define kPrefsSuiteName @"com.elite.ios27"
#define kIOS27LSStyleChanged @"iOS27LSStyleDidChange"

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

#endif
