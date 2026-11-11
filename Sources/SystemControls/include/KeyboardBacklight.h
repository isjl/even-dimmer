#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// (Prefixed "ED" because CoreBrightness already has a class named KeyboardBacklight.)
/// Thin wrapper around the private CoreBrightness `KeyboardBrightnessClient`.
/// Brightness values are 0.0 ... 1.0. The brightness keys only move in fixed
/// steps, but the controller accepts any value in between.
NS_SWIFT_NAME(KeyboardBacklight)
@interface EDKeyboardBacklight : NSObject

/// YES if CoreBrightness loaded and a built-in keyboard backlight was found.
@property (nonatomic, readonly) BOOL isAvailable;

- (float)brightness;
/// Sets and saves the brightness (it survives restarts).
- (BOOL)setBrightness:(float)value;
/// Sets the brightness without saving it, for quick tests.
- (BOOL)setBrightnessTemporarily:(float)value;

/// CoreBrightness's own estimate of the light output for the current brightness,
/// or 0 if this macOS version doesn't provide it.
- (float)lightLevel;

- (BOOL)isAutoBrightnessEnabled;
- (void)setAutoBrightnessEnabled:(BOOL)enabled;

/// YES while macOS has dimmed the backlight because the keyboard hasn't been used
/// for a while. The brightness then reads 0 until the next key press.
- (BOOL)isIdleDimmed;
/// YES while the backlight is held off (lid closed, bright room, or the level is 0).
- (BOOL)isSuppressed;

@end

NS_ASSUME_NONNULL_END
