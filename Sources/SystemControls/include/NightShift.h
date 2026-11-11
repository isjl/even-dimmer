#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrapper around the private CoreBrightness `CBBlueLightClient` (Night Shift).
NS_SWIFT_NAME(NightShift)
@interface EDNightShift : NSObject

/// YES if this Mac supports Night Shift and the API is present.
@property (nonatomic, readonly) BOOL isAvailable;

/// Whether Night Shift is on right now.
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)enabled;

/// Warmth, 0.0 (least warm) ... 1.0 (most warm).
- (float)strength;
- (void)setStrength:(float)strength;

@end

NS_ASSUME_NONNULL_END
