#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Modpack export controller (based on FCL ExportModpackViewModel / HMCL ExportModpackPanel / ZL2 ModpackExportScreen).
///
/// Standalone export interface providing:
///   - Profile selection (including gameDir preview and loader information).
///   - Five format choices (Modrinth / CurseForge / MMC / Plain Zip / link list).
///   - Name / version / author input.
///   - File-filter options (mods / configs / resourcepacks / shaderpacks / saves / options / servers / scripts).
///   - Progress card (percentage + stage text + cancel button).
///   - Share button on completion.
@interface ModpackExportViewController : UIViewController

/// Profile name preselected on initialization (may be empty; uses currentProfile when empty).
@property (nonatomic, copy, nullable) NSString *preselectedProfileName;

@end

NS_ASSUME_NONNULL_END
