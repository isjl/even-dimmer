#import "KeyboardBacklight.h"
#include <dlfcn.h>

// Private API, discovered via the Objective-C runtime on macOS 26 / Apple Silicon.
// Optional methods are checked with -respondsToSelector: so older systems don't crash.
@interface KeyboardBrightnessClient : NSObject
- (NSArray *)copyKeyboardBacklightIDs;
- (BOOL)isKeyboardBuiltIn:(unsigned long long)keyboardID;
- (float)brightnessForKeyboard:(unsigned long long)keyboardID;
- (BOOL)setBrightness:(float)brightness fadeSpeed:(int)speed commit:(BOOL)commit forKeyboard:(unsigned long long)keyboardID;
- (float)backlightLevelForKeyboard:(unsigned long long)keyboardID;
- (BOOL)isAutoBrightnessEnabledForKeyboard:(unsigned long long)keyboardID;
- (BOOL)enableAutoBrightness:(BOOL)enable forKeyboard:(unsigned long long)keyboardID;
- (BOOL)isBacklightDimmedOnKeyboard:(unsigned long long)keyboardID;
- (BOOL)isBacklightSuppressedOnKeyboard:(unsigned long long)keyboardID;
@end

@implementation EDKeyboardBacklight {
    KeyboardBrightnessClient *_client;
    NSArray<NSNumber *> *_keyboards;
}

- (instancetype)init {
    if ((self = [super init])) {
        _keyboards = @[];
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW);
        Class cls = NSClassFromString(@"KeyboardBrightnessClient");
        SEL required[] = {
            @selector(copyKeyboardBacklightIDs), @selector(isKeyboardBuiltIn:),
            @selector(brightnessForKeyboard:), @selector(setBrightness:fadeSpeed:commit:forKeyboard:),
        };
        BOOL ok = cls != nil;
        for (size_t i = 0; ok && i < sizeof(required) / sizeof(*required); i++) {
            ok = [cls instancesRespondToSelector:required[i]];
        }
        if (ok) {
            _client = [cls new];
            NSMutableArray *builtIn = [NSMutableArray array];
            for (NSNumber *n in [_client copyKeyboardBacklightIDs]) {
                if ([_client isKeyboardBuiltIn:n.unsignedLongLongValue]) [builtIn addObject:n];
            }
            _keyboards = builtIn;
        }
    }
    return self;
}

- (BOOL)isAvailable { return _client != nil && _keyboards.count > 0; }

- (unsigned long long)primary { return _keyboards.firstObject.unsignedLongLongValue; }

- (float)brightness {
    if (!self.isAvailable) return 0;
    return [_client brightnessForKeyboard:self.primary];
}

- (BOOL)setBrightness:(float)value commit:(BOOL)commit {
    if (!self.isAvailable) return NO;
    value = MAX(0.0f, MIN(1.0f, value));
    if (getenv("EVENDIMMER_DEBUG")) {
        NSLog(@"EvenDimmer: set %.6f commit=%d (was %.6f)\n%@", value, commit, self.brightness,
              [NSThread.callStackSymbols subarrayWithRange:NSMakeRange(1, MIN(6, NSThread.callStackSymbols.count - 1))]);
    }
    BOOL ok = YES;
    for (NSNumber *n in _keyboards) {
        ok &= [_client setBrightness:value fadeSpeed:0 commit:commit forKeyboard:n.unsignedLongLongValue];
    }
    return ok;
}

- (BOOL)setBrightness:(float)value { return [self setBrightness:value commit:YES]; }
- (BOOL)setBrightnessTemporarily:(float)value { return [self setBrightness:value commit:NO]; }

- (float)lightLevel {
    if (!self.isAvailable || ![_client respondsToSelector:@selector(backlightLevelForKeyboard:)]) return 0;
    return [_client backlightLevelForKeyboard:self.primary];
}

- (BOOL)isAutoBrightnessEnabled {
    if (!self.isAvailable || ![_client respondsToSelector:@selector(isAutoBrightnessEnabledForKeyboard:)]) return NO;
    return [_client isAutoBrightnessEnabledForKeyboard:self.primary];
}

- (void)setAutoBrightnessEnabled:(BOOL)enabled {
    if (!self.isAvailable || ![_client respondsToSelector:@selector(enableAutoBrightness:forKeyboard:)]) return;
    for (NSNumber *n in _keyboards) {
        [_client enableAutoBrightness:enabled forKeyboard:n.unsignedLongLongValue];
    }
}

- (BOOL)isIdleDimmed {
    return self.isAvailable && [_client respondsToSelector:@selector(isBacklightDimmedOnKeyboard:)]
        && [_client isBacklightDimmedOnKeyboard:self.primary];
}

- (BOOL)isSuppressed {
    return self.isAvailable && [_client respondsToSelector:@selector(isBacklightSuppressedOnKeyboard:)]
        && [_client isBacklightSuppressedOnKeyboard:self.primary];
}

@end
