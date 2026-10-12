//
//  AccountLoginViewController.h
//  Amethyst
//
//  Account login screen modeled on the FCL (Fold Craft Launcher) Android version:
//  uses a card list to show four sign-in options: Microsoft / LittleSkin / custom third party / local,
//  replacing the original rudimentary ActionSheet + UIAlertController interaction.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AccountLoginViewController : UIViewController

/// Sign-in method enumeration.
typedef NS_ENUM(NSInteger, AccountLoginType) {
    AccountLoginTypeMicrosoft = 0,
    AccountLoginTypeLittleSkin,
    AccountLoginTypeThirdParty,
    AccountLoginTypeLocal,
};

/// Callback after the user selects a sign-in method (AccountListViewController handles the actual sign-in flow).
@property (nonatomic, copy) void (^onSelectLoginType)(AccountLoginType type);

@end

NS_ASSUME_NONNULL_END
