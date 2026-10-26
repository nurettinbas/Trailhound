#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Observes the Duo hinge when this SDK includes `UIHinge` (iOS 27.1). Older SDKs no-op.
void TrailhoundInstallHingeInteraction(UIView *view, void (^onFullyOpen)(BOOL fullyOpen));

/// Starts the iOS 27 asynchronous audio-session activate when this SDK has it.
/// Returns YES if `completion` will be called later. Returns NO when the caller should use `setActive`.
BOOL TrailhoundActivateAudioSessionIfAvailable(void (^completion)(BOOL activated));

NS_ASSUME_NONNULL_END
