#ifndef IOS27_PREFS_H
#define IOS27_PREFS_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#define kPrefsSuiteName @"com.elite.ios27"

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

#endif
