// ===========================================================================
//  ★ [SWIFT-BAR] AmeTabBar.swift — bottom tab bar (system SwiftUI TabView)
//  ---------------------------------------------------------------------------
//  Why SwiftUI (empirical results from the first three rounds; see _uibuild/TABC_REPORT.md
//  and _uibuild/SYS_TABBAR_REPORT.md):
//    · v1, a standalone UITabBar (outside UITabBarController), showed no text on iOS 26.
//    · v2, a real UITabBarController + UITabBarAppearance(stacked), placed titles to the
//      right of icons (inline layout); increasing the container from 68 to 92 did not help
//      (the screenshot MD5 was identical to ②).
//    · The reference, LiveContainer (LiveContainerSwiftUI/Views/LCTabView.swift), simply uses
//      `TabView { … .tabItem { Label(…) } }`, with no custom drawing or appearance.
//  ⇒ This file follows that approach: a pure SwiftUI TabView with five .tabItem { Label }.
//    **No appearance is customized at all** (glass, corners, and the system icon-above-title
//    layout are all left to the system). It only:
//      ① defines the five menu items (the multiplayer item was removed as requested);
//      ② posts the ObjC notification AmeTabSelected (userInfo = @{@"index": @(v)}) on selection;
//      ③ exposes setIconSize:, setHeight:, and setStyle: (UserDefaults keys).
//
//  There are only two boundaries with ObjC:
//    Entry = +[AmeTabBarHost makeHostWithTag:] → a UIViewController (used as a child VC)
//    Exit = NSNotificationCenter notification "AmeTabSelected"
//    The ObjC side (LauncherMenuViewController.m) only embeds the child VC, pins it to the
//    container, listens for the notification, and calls handleMenuSelection: (navigation is unchanged).
// ===========================================================================
import SwiftUI
import UIKit

// MARK: - ★ Notification names / UserDefaults keys

/// Notification name posted when a tab is selected. The ObjC side listens with
/// [[NSNotificationCenter defaultCenter] addObserver:… name:@"AmeTabSelected"]
/// and receives userInfo = @{@"index": @(v)} (v is the menu index, 0…4).
/// Swift's NotificationCenter.default is ObjC's defaultCenter; the name must match exactly.
let AmeTabSelectedNotificationName = "AmeTabSelected"

/// ★ UserDefaults keys for the three adjustable settings, wired to the
/// LauncherPreferencesViewController settings page and written by ObjC +[AmeTabBarHost setXxx:]:
///   ameTabStyle    : 0 = floating capsule (default) / 1 = full width
///   ameTabHeight   : 56…96, default 83
///   ameTabIconSize : 20…44, default 34 (SF Symbol pointSize)
enum AmeTabBarPrefKey {
    static let style    = "ameTabStyle"
    static let height   = "ameTabHeight"
    static let iconSize = "ameTabIconSize"
}

// MARK: - Menu definition (★ 5 items; id == tag == ObjC menuItems index)

struct AmeTabItem: Identifiable {
    let id: Int          // == menuItems index
    let title: String    // Short tab title (limited tab-bar width; two characters / AI)
    let symbol: String   // SF Symbol
}

/// ★ Five items, in the exact order of LauncherMenuViewController.m's menuItems (no multiplayer):
///   0 Home · 1 Downloads · 2 AI · 3 Instances · 4 Settings
let AmeTabItems: [AmeTabItem] = [
    AmeTabItem(id: 0, title: "Home", symbol: "house.fill"),
    AmeTabItem(id: 1, title: "Downloads", symbol: "arrow.down.circle.fill"),
    AmeTabItem(id: 2, title: "AI",   symbol: "sparkles"),
    AmeTabItem(id: 3, title: "Instances", symbol: "square.stack.3d.up.fill"),
    AmeTabItem(id: 4, title: "Settings", symbol: "gearshape.fill"),
]

// MARK: - State

/// The host-owned selection state. @Published triggers SwiftUI rendering; AmeBar's custom
/// Binding performs the actual notification (only user taps invoke the setter).
final class AmeBarModel: ObservableObject {
    @Published var selection: Int = 0
}

// MARK: - View

/// The tab bar itself. No appearance modifiers beyond `TabView + .tabItem { Label }`:
/// glass and the icon-above-title layout come from the system, as in LiveContainer.
struct AmeBar: View {
    @Binding var sel: Int

    /// Icon size (SF Symbol pointSize): default 34, key ameTabIconSize (20…44).
    /// Applies only to the icon; the title keeps the system font size.
    @AppStorage("ameTabIconSize") private var iconSize: Double = 34

    /// ★ Selection binding: a tab tap updates sel and posts AmeTabSelected.
    ///   A custom Binding rather than .onChange ensures one notification per tap and none for the initial value.
    private var ameSelection: Binding<Int> {
        Binding(get: { sel },
                set: { newValue in
                    guard newValue != sel else { return }   // Do not post again for the same value.
                    sel = newValue
                    NotificationCenter.default.post(
                        name: Notification.Name(AmeTabSelectedNotificationName),
                        object: nil,
                        userInfo: ["index": newValue])
                })
    }

    var body: some View {
        TabView(selection: ameSelection) {
            ForEach(AmeTabItems) { item in
                Color.clear
                    .tabItem {
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(systemName: item.symbol)
                                .font(.system(size: CGFloat(iconSize)))
                        }
                    }
                    .tag(item.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Host root view: projects the ObservableObject as the @Binding required by AmeBar.
struct AmeBarRoot: View {
    @ObservedObject var model: AmeBarModel
    var body: some View {
        AmeBar(sel: $model.selection)
    }
}

// MARK: - Host controller (provides the SwiftUI view as a child VC to the ObjC container)

final class AmeTabBarHostController: UIViewController {

    private let tag: Int
    private let model = AmeBarModel()
    private var healTimer: Timer?
    private var healTicks = 0

    init(tag: Int) {
        self.tag = tag
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { healTimer?.invalidate() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let hc = UIHostingController(rootView: AmeBarRoot(model: model))
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hc)
        view.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hc.didMove(toParent: self)

        model.selection = tag          // Set the initial selection without posting a notification.
        applySizeHints()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyUnselectedTint()
        _ = healIcons()                // Handle the cold-start first-call race immediately.
        startIconSelfHeal()            // Then use bounded retries, as in the previous ObjC implementation.
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyUnselectedTint()          // The native tab bar is created lazily, so reapply on each layout.
    }

    // MARK: Adjustable settings

    /// ameTabHeight is reported to the host as a preferredContentSize hint only.
    /// The ObjC container constraints determine the actual size (92.0 in portrait in
    /// LauncherRootViewController.m); no hard constraint is added, avoiding conflicts
    /// with the parent container's edge constraints.
    private func applySizeHints() {
        let raw = UserDefaults.standard.object(forKey: AmeTabBarPrefKey.height) as? Double
        let h = min(max(raw ?? 83, 56), 96)
        preferredContentSize = CGSize(width: UIView.noIntrinsicMetric, height: CGFloat(h))
    }

    /// Tint for unselected items (capability of the old applyCustomAppearance).
    /// Changes only tint, not UITabBarAppearance or the background, preserving system glass.
    func applyUnselectedTint() {
        guard let bar = findTabBar() else { return }
        bar.unselectedItemTintColor = AmeTabBarHost.unselectedTintColor()
    }

    // MARK: Icon recovery (previous ObjC strategy: bounded retries every 0.25s; fill nil items only)

    private func startIconSelfHeal() {
        guard healTimer == nil else { return }
        healTicks = 0
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.healTicks += 1
            let allLoaded = self.healIcons()
            if (allLoaded && self.healTicks >= 8) || self.healTicks >= 40 {
                timer.invalidate()
                self.healTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        healTimer = t
    }

    /// Fill only items whose image == nil; do not overwrite icons already rendered by the system.
    @discardableResult
    private func healIcons() -> Bool {
        guard let bar = findTabBar(), let items = bar.items else { return false }
        let raw = UserDefaults.standard.object(forKey: AmeTabBarPrefKey.iconSize) as? Double
        let pt = min(max(raw ?? 34, 20), 44)
        var allLoaded = true
        for (i, item) in items.enumerated() where i < AmeTabItems.count {
            if item.image != nil { continue }
            allLoaded = false
            let cfg = UIImage.SymbolConfiguration(pointSize: CGFloat(pt), weight: .regular)
            if let img = UIImage(systemName: AmeTabItems[i].symbol, withConfiguration: cfg) {
                item.image = img
            }
        }
        return allLoaded
    }

    private func findTabBar() -> UITabBar? { findTabBar(in: view) }

    private func findTabBar(in root: UIView) -> UITabBar? {
        if let bar = root as? UITabBar { return bar }
        for sub in root.subviews {
            if let bar = findTabBar(in: sub) { return bar }
        }
        return nil
    }
}

// MARK: - ★ ObjC entry point (the only class referenced by ObjC)

/// ★ This is the only class used by the ObjC side (selectors are the @objc exported names):
///   UIViewController *bar = [AmeTabBarHost makeHostWithTag:0];
///   [AmeTabBarHost setIconSize:34];
///   [AmeTabBarHost setHeight:83];
///   [AmeTabBarHost setStyle:0];
///   [AmeTabBarHost setUnselectedTintColor:color];   // Pass nil to restore the system default.
///
/// This file does not generate -Swift.h (CMake compiles directly to .o without a module),
/// so the ObjC side uses a handwritten forward declaration (see LauncherMenuViewController.m).
/// Selectors must match exactly.
@objc(AmeTabBarHost)
public final class AmeTabBarHost: NSObject {

    /// Weak references to active hosts, allowing setXxx: to update an attached tab bar immediately.
    private static let hosts = NSHashTable<AmeTabBarHostController>.weakObjects()
    private static var tint: UIColor?

    static func unselectedTintColor() -> UIColor? { tint }

    /// Create a host. The returned child VC pins its view to its own bounds in viewDidLoad;
    /// the ObjC side only needs to pin that view to its container. tag is the initial selection.
    /// The selector is explicitly named makeHostWithTag: to match the ObjC forward declaration.
    @objc(makeHostWithTag:)
    public static func makeHost(tag: Int) -> UIViewController {
        let vc = AmeTabBarHostController(tag: tag)
        hosts.add(vc)
        return vc
    }

    /// Icon size (20…44; stored under the UserDefaults key ameTabIconSize).
    /// @AppStorage updates immediately; clamp the value to keep settings-page input in range.
    @objc(setIconSize:)
    public static func setIconSize(_ size: Double) {
        let v = min(max(size, 20), 44)
        UserDefaults.standard.set(v, forKey: AmeTabBarPrefKey.iconSize)
    }

    /// Suggested tab-bar height (56…96; stored under the UserDefaults key ameTabHeight).
    /// Actual size comes from ObjC container constraints (92.0 in portrait in
    /// LauncherRootViewController.m); see the wiring point in the report.
    @objc(setHeight:)
    public static func setHeight(_ height: Double) {
        let v = min(max(height, 56), 96)
        UserDefaults.standard.set(v, forKey: AmeTabBarPrefKey.height)
        for vc in hosts.allObjects {
            vc.preferredContentSize = CGSize(width: UIView.noIntrinsicMetric, height: CGFloat(v))
        }
    }

    /// Layout (0 = floating capsule / 1 = full width; stored under ameTabStyle in UserDefaults).
    @objc(setStyle:)
    public static func setStyle(_ style: Int) {
        UserDefaults.standard.set(style == 1 ? 1 : 0, forKey: AmeTabBarPrefKey.style)
    }

    /// Tint for unselected items (a capability of the old applyCustomAppearance).
    /// Changes only unselectedItemTintColor, not UITabBarAppearance or the background, preserving glass.
    /// Can be called before a host exists: the color is cached and applied when a host is created.
    @objc(setUnselectedTintColor:)
    public static func setUnselectedTintColor(_ color: UIColor?) {
        tint = color
        for vc in hosts.allObjects { vc.applyUnselectedTint() }
    }
}
