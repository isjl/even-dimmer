#import "NightShift.h"
#include <dlfcn.h>

// Layout of CoreBrightness's status struct, from its type encoding {?=BBBi{?={?=ii}{?=ii}}QB}.
typedef struct { int hour; int minute; } EDTime;
typedef struct { EDTime fromTime; EDTime toTime; } EDSchedule;
typedef struct {
    BOOL active;
    BOOL enabled;
    BOOL sunSchedulePermitted;
    int mode;
    EDSchedule schedule;
    unsigned long long disableFlags;
    BOOL available;
} EDBlueLightStatus;

@interface CBBlueLightClient : NSObject
+ (BOOL)supportsBlueLightReduction;
- (BOOL)getBlueLightStatus:(EDBlueLightStatus *)status;
- (BOOL)setEnabled:(BOOL)enabled;
- (BOOL)getStrength:(float *)strength;
- (BOOL)setStrength:(float)strength commit:(BOOL)commit;
@end

@implementation EDNightShift {
    CBBlueLightClient *_client;
}

- (instancetype)init {
    if ((self = [super init])) {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW);
        Class cls = NSClassFromString(@"CBBlueLightClient");
        SEL required[] = {
            @selector(getBlueLightStatus:), @selector(setEnabled:),
            @selector(getStrength:), @selector(setStrength:commit:),
        };
        BOOL ok = cls != nil;
        for (size_t i = 0; ok && i < sizeof(required) / sizeof(*required); i++) {
            ok = [cls instancesRespondToSelector:required[i]];
        }
        if (ok) _client = [cls new];
    }
    return self;
}

- (BOOL)isAvailable {
    if (!_client) return NO;
    EDBlueLightStatus s = {0};
    return [_client getBlueLightStatus:&s] && s.available;
}

- (BOOL)isEnabled {
    EDBlueLightStatus s = {0};
    return _client && [_client getBlueLightStatus:&s] && s.enabled;
}

- (void)setEnabled:(BOOL)enabled { [_client setEnabled:enabled]; }

- (float)strength {
    float value = 0;
    if (_client) [_client getStrength:&value];
    return value;
}

- (void)setStrength:(float)strength {
    [_client setStrength:MAX(0.0f, MIN(1.0f, strength)) commit:YES];
}

@end
