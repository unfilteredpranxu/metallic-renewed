#import <UIKit/UIKit.h>

// Stable native slots. Existing SwiftUI/menu/shortcut consumers continue using these values.
typedef NS_ENUM(NSInteger, AMELauncherTab) {
    AMELauncherTabHome = 0,
    AMELauncherTabDownloads = 1,
    AMELauncherTabAI = 2,
    AMELauncherTabInstances = 3,
    AMELauncherTabSettings = 4,
};

typedef NS_ENUM(NSInteger, AMEPrimaryDestination) {
    AMEPrimaryDestinationHome,
    AMEPrimaryDestinationInstances,
    AMEPrimaryDestinationDownloads,
    AMEPrimaryDestinationAppearance,
    AMEPrimaryDestinationSettings,
};

// Appearance is a real settings sheet, not a sixth internal tab.
static inline NSInteger AMETabForPrimaryDestination(AMEPrimaryDestination destination) {
    switch (destination) {
        case AMEPrimaryDestinationHome: return AMELauncherTabHome;
        case AMEPrimaryDestinationInstances: return AMELauncherTabInstances;
        case AMEPrimaryDestinationDownloads: return AMELauncherTabDownloads;
        case AMEPrimaryDestinationSettings: return AMELauncherTabSettings;
        default: return NSNotFound;
    }
}

static inline NSInteger AMEPrimaryDestinationForTab(NSInteger tab) {
    switch (tab) {
        case AMELauncherTabHome: return AMEPrimaryDestinationHome;
        case AMELauncherTabInstances: return AMEPrimaryDestinationInstances;
        case AMELauncherTabDownloads: return AMEPrimaryDestinationDownloads;
        case AMELauncherTabSettings: return AMEPrimaryDestinationSettings;
        default: return NSNotFound; // AI is available through Tools; no false primary highlight.
    }
}

@interface HomeTopNavView : UIView
@property (nonatomic, copy) void (^onSelect)(AMEPrimaryDestination destination);
// Remains an INTERNAL index for legacy notification/caller compatibility.
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) BOOL appearanceActive;
@property (nonatomic, assign) CGFloat referenceScale;
@property(nonatomic, strong) UIMenu *moreMenu;
@end

/// Optional launcher-only feedback; never configures the game audio session.
FOUNDATION_EXPORT void MetallicPlayUIFeedback(NSString *event);
