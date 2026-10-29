#import "utils.h"
//
//  BackgroundSettingsViewController.m
//  Amethyst
//
//  Background wallpaper settings implementation
//

#import "BackgroundSettingsViewController.h"
#import "BackgroundManager.h"
#import "ImageCropperViewController.h"
#import "UIKit+GlassSurface.h"
#import "AMEGlassStyle.h"   // ★ [GLASS-STYLE] UI style (auto / native / Liquid Glass) resolution layer

static NSString *MetallicPresentationText(NSString *key, NSString *fallback) {
    NSString *translated = localize(key, fallback);
    return translated.length && ![translated isEqualToString:key] ? translated : (fallback ?: key);
}

static CGFloat MetallicAppearanceReferenceScale(UIView *view) {
    CGFloat width=view.window.bounds.size.width;
    if(width<=0)width=UIScreen.mainScreen.bounds.size.width;
    return width>=900?width/1536.0:.72;
}
@interface BackgroundSettingsViewController ()
- (UITableViewCell *)appearanceSliderCell:(NSString *)identifier title:(NSString *)title
                                  value:(CGFloat)value minimum:(CGFloat)minimum action:(SEL)action;
- (void)updatePercentageForSlider:(UISlider *)slider value:(CGFloat)value;
- (void)interfaceBlurSliderChanged:(UISlider *)slider;
- (void)wallpaperDimmingSliderChanged:(UISlider *)slider;
- (void)resetInterfaceAppearance;
- (void)wallpaperChanged:(NSNotification *)notification;
@property (nonatomic, strong) NSArray<NSArray *> *sections;
@property(nonatomic, strong) UISlider *referenceBlurSlider;
@property(nonatomic, strong) UISlider *referenceOpacitySlider;
@property(nonatomic, strong) UILabel *referenceResetState;
@property(nonatomic, strong) UIStackView *referenceAppearanceStack;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, weak) UILabel *glassStrengthValueLabel;   // ★ [GLASSUI] Glass-intensity value label
@end

@implementation BackgroundSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = localize(@"i18n_str_53", nil);
    
    // Set transparent background if global background is active
    if ([[BackgroundManager sharedManager] hasBackground]) {
        self.view.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundView = nil;
    } else {
        self.view.backgroundColor = [UIColor clearColor];
    }
    
    // Setup table view
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.tableFooterView = [[UIView alloc] init];
    // ★ [GLASS-STYLE] The "UI Style" footer contains multiple lines ⇒ use adaptive height (otherwise
    // the text will be clipped or compressed).
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 96.0;
    
    // Setup preview header
    [self setupPreviewHeader];
    if (self.launcherPresentation) {
        self.tableView.tableFooterView = self.tableView.tableHeaderView;
        [self setupLauncherThemeHeader];
    }
    
    // Setup sections
    [self setupSections];
    
    // ★ [GLASSUI] Read back glass settings: BackgroundManager loads the switch/intensity from NSUserDefaults
    //   during init (keys background_glass_rim_enabled / background_glass_rim_strength; defaults: on / 1.0).
    //   This page does not keep a separate local state — UISwitch/UISlider are synchronized from the
    //   shared instance in cellForRowAtIndexPath each time (and the slider setter clamps the value),
    //   so the "current value" always matches Settings.
    
    // Add close button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self
                                                                                           action:@selector(closeTapped)];

    // Adapt to the custom launcher background: make this view controller transparent so the global
    // background (image/video) shows through.
    // Even this Background Settings page must be transparent to preview the effect in real time.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // Listen for background UI-effect changes: when the user switches between frosted glass/translucent
    // or adjusts opacity in Background Settings, call makeViewControllerTransparent again to apply the
    // latest appearance and keep the background showing through correctly.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wallpaperChanged:)
                                                 name:@"BackgroundChanged" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updatePreview];
    [self.tableView reloadData];
    if(self.launcherPresentation) [self.tableView setContentOffset:CGPointMake(0,-self.tableView.adjustedContentInset.top) animated:NO];
    
    // Maintain transparency
    if ([[BackgroundManager sharedManager] hasBackground]) {
        self.view.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundView = nil;
    }
}

- (void)setupPreviewHeader {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 200)];
    
    // Transparent header if background is active
    if ([[BackgroundManager sharedManager] hasBackground]) {
        headerView.backgroundColor = [UIColor clearColor];
    } else {
        headerView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    }
    
    // Preview image view
    self.previewImageView = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, headerView.bounds.size.width - 32, 168)];
    self.previewImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.previewImageView.clipsToBounds = YES;
    self.previewImageView.layer.cornerRadius = 12;
    self.previewImageView.layer.cornerCurve = kCACornerCurveContinuous;   // ★ [CORNER-FIX] Continuous corners (match system cards).
    self.previewImageView.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    self.previewImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // Add placeholder label
    UILabel *placeholderLabel = [[UILabel alloc] init];
    placeholderLabel.text = localize(@"i18n_str_54", nil);
    placeholderLabel.textColor = [UIColor secondaryLabelColor];
    placeholderLabel.font = AmeUIFont(AmeUIFontRoleDescription);
    placeholderLabel.adjustsFontForContentSizeCategory = YES;
    placeholderLabel.textAlignment = NSTextAlignmentCenter;
    placeholderLabel.tag = 100;
    placeholderLabel.frame = self.previewImageView.bounds;
    placeholderLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.previewImageView addSubview:placeholderLabel];
    
    [headerView addSubview:self.previewImageView];
    
    self.tableView.tableHeaderView = headerView;
}

- (void)updatePreview {
    BackgroundManager *manager = [BackgroundManager sharedManager];
    UIImage *preview = [manager backgroundPreview];
    
    if (preview) {
        self.previewImageView.image = preview;
        UILabel *placeholder = (UILabel *)[self.previewImageView viewWithTag:100];
        placeholder.hidden = YES;
    } else if ([manager hasVideoBackground]) {
        self.previewImageView.image = nil;
        UILabel *placeholder = (UILabel *)[self.previewImageView viewWithTag:100];
        placeholder.hidden = NO;
        placeholder.text = localize(@"i18n_str_55", nil);
    } else {
        self.previewImageView.image = nil;
        UILabel *placeholder = (UILabel *)[self.previewImageView viewWithTag:100];
        placeholder.hidden = NO;
        placeholder.text = localize(@"i18n_str_56", nil);
    }
}

- (UILabel *)referenceText:(NSString *)text size:(CGFloat)size secondary:(BOOL)secondary {
    CGFloat scale=MetallicAppearanceReferenceScale(self.view);
    UILabel *label=[[UILabel alloc] init]; label.text=text; label.numberOfLines=0;
    label.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:size*scale weight:size>=28 ? UIFontWeightSemibold : UIFontWeightRegular]];
    label.textColor=secondary ? AmeUISecondaryTextColor() : AmeUIPrimaryTextColor(); label.adjustsFontForContentSizeCategory=YES;
    return label;
}
- (UIView *)referenceCard:(UIStackView *)content top:(CGFloat)top {
    CGFloat scale=MetallicAppearanceReferenceScale(self.view);
    UIView *card=[[UIView alloc] init]; card.layer.cornerRadius=32*scale; card.clipsToBounds=YES;
    [[BackgroundManager sharedManager] applyEffectToView:card]; content.translatesAutoresizingMaskIntoConstraints=NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:26*scale], [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-26*scale], [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:top*scale], [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-28*scale]]];
    return card;
}

- (void)setupLauncherThemeHeader {
    CGFloat scale=MetallicAppearanceReferenceScale(self.view);
    UIStackView *all=[[UIStackView alloc] init]; all.axis=UILayoutConstraintAxisVertical; all.spacing=26*scale; all.translatesAutoresizingMaskIntoConstraints=NO;
    self.referenceAppearanceStack=all;
    UILabel *title=[self referenceText:@"Theme" size:28 secondary:NO];
    UISegmentedControl *theme=[[UISegmentedControl alloc] initWithItems:@[@"System",@"Light",@"Dark"]];
    theme.selectedSegmentIndex=self.themeIndex>=0&&self.themeIndex<3?self.themeIndex:0;
    [theme addTarget:self action:@selector(launcherThemeChanged:) forControlEvents:UIControlEventValueChanged];
    [theme.heightAnchor constraintGreaterThanOrEqualToConstant:MAX(36,40*scale)].active=YES;
    UIStackView *themeStack=[[UIStackView alloc] initWithArrangedSubviews:@[title,theme,[self referenceText:@"Changes apply across the launcher immediately." size:16 secondary:YES]]];
    themeStack.axis=UILayoutConstraintAxisVertical; themeStack.spacing=22*scale;
    [all addArrangedSubview:[self referenceCard:themeStack top:0]];
    BackgroundManager *manager=BackgroundManager.sharedManager;
    UITableViewCell *blur=[self appearanceSliderCell:@"InterfaceBlur" title:@"UI Blur" value:manager.interfaceBlurIntensity minimum:0 action:@selector(interfaceBlurSliderChanged:)];
    UITableViewCell *opacity=[self appearanceSliderCell:@"InterfaceOpacity" title:@"UI Panel Opacity" value:manager.uiOpacity minimum:.1 action:@selector(opacitySliderChanged:)];
    self.referenceBlurSlider=(UISlider *)[blur.contentView viewWithTag:500]; self.referenceOpacitySlider=(UISlider *)[opacity.contentView viewWithTag:500];
    NSMutableArray *sliders=[NSMutableArray array];
    for (UITableViewCell *cell in @[blur,opacity]) {
        UIView *body=cell.contentView; [body removeFromSuperview]; body.directionalLayoutMargins=NSDirectionalEdgeInsetsZero;
        body.insetsLayoutMarginsFromSafeArea=NO; body.preservesSuperviewLayoutMargins=NO;
        ((UILabel *)[body viewWithTag:502]).font=[UIFont systemFontOfSize:22*scale];
        ((UILabel *)[body viewWithTag:501]).font=[UIFont systemFontOfSize:22*scale];
        [sliders addObject:body];
    }
    UILabel *interfaceTitle=[self referenceText:@"Interface Glass" size:28 secondary:NO];
    UILabel *interfaceHelp=[self referenceText:@"Controls launcher panels only. Wallpaper blur and dimming stay in the Wallpaper section." size:16 secondary:YES];
    UIButton *reset=[UIButton buttonWithType:UIButtonTypeSystem]; [reset setTitle:@"Reset to Recommended" forState:UIControlStateNormal];
    reset.titleLabel.font=[UIFont systemFontOfSize:22*scale]; reset.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    reset.tintColor=AmeUIPrimaryTextColor(); [reset addTarget:self action:@selector(resetInterfaceAppearance) forControlEvents:UIControlEventTouchUpInside];
    [reset.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    self.referenceResetState=[self referenceText:@"" size:16 secondary:YES];
    UIStackView *resetRow=[[UIStackView alloc] initWithArrangedSubviews:@[reset,self.referenceResetState]]; resetRow.alignment=UIStackViewAlignmentCenter;
    UIStackView *glass=[[UIStackView alloc] initWithArrangedSubviews:@[interfaceTitle,interfaceHelp,sliders[0],[self referenceText:@"0% removes the material. Higher values use denser system materials; Apple does not expose a custom blur radius." size:16 secondary:YES],sliders[1],[self referenceText:@"Changes the tint strength of cards, bars and sheets. It never dims the wallpaper." size:16 secondary:YES],resetRow,[self referenceText:@"These cards update live while you drag either control." size:16 secondary:YES]]];
    glass.axis=UILayoutConstraintAxisVertical; glass.spacing=18*scale; [glass setCustomSpacing:22*scale afterView:interfaceTitle];
    [all addArrangedSubview:[self referenceCard:glass top:32]];
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,900*scale)];
    [header addSubview:all];
    [NSLayoutConstraint activateConstraints:@[[all.leadingAnchor constraintEqualToAnchor:header.leadingAnchor], [all.trailingAnchor constraintEqualToAnchor:header.trailingAnchor], [all.topAnchor constraintEqualToAnchor:header.topAnchor], [all.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-26*scale]]];
    self.tableView.tableHeaderView=header;
    [self refreshReferenceInterfaceControls];
}
- (void)refreshReferenceInterfaceControls {
    BackgroundManager *manager=BackgroundManager.sharedManager;
    if (!self.referenceBlurSlider.tracking) self.referenceBlurSlider.value=manager.interfaceBlurIntensity;
    if (!self.referenceOpacitySlider.tracking) self.referenceOpacitySlider.value=manager.uiOpacity;
    self.referenceBlurSlider.enabled=manager.uiEffect==BackgroundUIEffectBlur;
    [self updatePercentageForSlider:self.referenceBlurSlider value:manager.interfaceBlurIntensity];
    [self updatePercentageForSlider:self.referenceOpacitySlider value:manager.uiOpacity];
    BOOL recommended=manager.uiEffect==BackgroundUIEffectBlur&&fabs(manager.uiOpacity-.7)<.001&&fabs(manager.interfaceBlurIntensity-.79)<.001;
    self.referenceResetState.text=recommended?@"Recommended":@"Custom";
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.launcherPresentation) return;
    UIView *header = self.tableView.tableHeaderView;
    CGFloat width = self.tableView.bounds.size.width;
    CGSize fitting = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect frame = CGRectMake(0,0,width,MAX(168,ceil(fitting.height)));
    if (!CGRectEqualToRect(header.frame,frame)) { header.frame=frame; self.tableView.tableHeaderView=header; }
}
- (void)launcherThemeChanged:(UISegmentedControl *)sender {
    if (self.themeSelection) self.themeSelection(sender.selectedSegmentIndex);
}

- (void)setupSections {
    // Sections: [UI effect settings], [Choose background type], [Image background, Video background],
    // [Restore default background, Clear background].
    self.sections = @[
        @[localize(@"i18n_str_57", nil), MetallicPresentationText(@"renewed.appearance.panel_opacity", @"UI Panel Opacity"),
          MetallicPresentationText(@"renewed.appearance.ui_blur", @"UI Blur"), MetallicPresentationText(@"renewed.appearance.reset", @"Reset to Recommended")],
        @[localize(@"i18n_str_60", nil)],
        @[localize(@"i18n_str_61", nil), localize(@"i18n_str_55", nil)],
        @[localize(@"i18n_str_62", nil), localize(@"i18n_str_63", nil)],
        // ★ [GLASSUI] Glass effect: row0=highlight switch (UISwitch), row1=intensity slider (UISlider, 0…1).
        // ★ [GLASS-STYLE] This section is now called "UI Style": row0=style (auto/native/Liquid Glass),
        //   row1=highlight switch (UISwitch), row2=intensity slider (UISlider, 0…1).
        //   ★ Integrated rather than parallel: in native style, highlight switch/intensity are disabled,
        //   avoiding "two conflicting sets of switches".
        @[localize(@"preference.title.glass_style", nil),
          localize(@"preference.title.glass_handdrawn", nil),
          localize(@"preference.title.glass_strength", nil)],
        @[MetallicPresentationText(@"renewed.appearance.wallpaper_blur", @"Wallpaper Blur"),
          MetallicPresentationText(@"renewed.appearance.wallpaper_dimming", @"Wallpaper Dimming")]
    ];
}

- (void)closeTapped {
    if (self.launcherPresentation) { [self.navigationController popViewControllerAnimated:YES]; return; }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.launcherPresentation && section==0) return 1;
    return [self.sections[section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.launcherPresentation && section==0) return @"More appearance options";
    if (section == 0) return MetallicPresentationText(@"renewed.appearance.interface", @"Interface Glass");
    if (section == 5) return MetallicPresentationText(@"renewed.appearance.wallpaper", @"Wallpaper");
    return self.sections[section][0];
}

- (UITableViewCell *)appearanceSliderCell:(NSString *)identifier title:(NSString *)title
                                      value:(CGFloat)value minimum:(CGFloat)minimum action:(SEL)action {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UILabel *heading = [[UILabel alloc] init];
        heading.tag = 502;
        heading.numberOfLines = 0;
        heading.font = AmeUIFont(AmeUIFontRoleBody);
        heading.adjustsFontForContentSizeCategory = YES;
        UILabel *percentage = [[UILabel alloc] init];
        percentage.tag = 501;
        percentage.font = AmeUIFont(AmeUIFontRoleStatus);
        percentage.adjustsFontForContentSizeCategory = YES;
        percentage.textAlignment = NSTextAlignmentRight;
        UISlider *slider = [[UISlider alloc] init];
        slider.tag = 500;
        slider.minimumValue = minimum;
        slider.maximumValue = 1.0;
        [slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
        for (UIView *view in @[heading, percentage, slider]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:view];
        }
        UILayoutGuide *guide = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [heading.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [heading.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8],
            [heading.trailingAnchor constraintLessThanOrEqualToAnchor:percentage.leadingAnchor constant:-8],
            [percentage.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [percentage.topAnchor constraintEqualToAnchor:heading.topAnchor],
            [percentage.widthAnchor constraintGreaterThanOrEqualToConstant:56],
            [slider.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [slider.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [slider.topAnchor constraintGreaterThanOrEqualToAnchor:heading.bottomAnchor constant:8],
            [slider.topAnchor constraintGreaterThanOrEqualToAnchor:percentage.bottomAnchor constant:8],
            [slider.heightAnchor constraintEqualToConstant:AmeUIMinimumTouchSize],
            [slider.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-8]
        ]];
    }
    [self styleCell:cell hasBackground:[[BackgroundManager sharedManager] hasBackground]];
    UILabel *heading = (UILabel *)[cell.contentView viewWithTag:502];
    heading.text = title;
    heading.textColor = AmeUIPrimaryTextColor();
    UILabel *percentage = (UILabel *)[cell.contentView viewWithTag:501];
    percentage.text = [NSString stringWithFormat:@"%.0f%%", value * 100];
    percentage.textColor = AmeUISecondaryTextColor();
    UISlider *slider = (UISlider *)[cell.contentView viewWithTag:500];
    if (!slider.tracking) slider.value = value;
    slider.enabled = [identifier isEqualToString:@"InterfaceBlur"] ? [BackgroundManager sharedManager].uiEffect == BackgroundUIEffectBlur
        : (![identifier hasPrefix:@"Wallpaper"] || [[BackgroundManager sharedManager] hasBackground]);
    slider.minimumTrackTintColor = AmeUIAccentColor();
    slider.accessibilityLabel = title;
    slider.accessibilityValue = percentage.text;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    static NSString *cellIdentifier = @"BackgroundCell";
    
    BackgroundManager *manager = [BackgroundManager sharedManager];
    BOOL hasBackground = [manager hasBackground];
    
    // UI effect settings section.
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            // UI effect selection.
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
            }
            
            cell.textLabel.text = localize(@"i18n_str_57", nil);
            
            NSString *effectName = manager.uiEffect == BackgroundUIEffectBlur ? localize(@"i18n_str_2017", nil) : localize(@"i18n_str_65", nil);
            cell.detailTextLabel.text = effectName;
            cell.imageView.image = [UIImage systemImageNamed:@"rectangle.split.3x3"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            
            [self styleCell:cell hasBackground:hasBackground];
            return cell;
            
        } else if (indexPath.row == 1) {
            return [self appearanceSliderCell:@"InterfaceOpacity" title:self.sections[0][1]
                                       value:manager.uiOpacity minimum:0.1 action:@selector(opacitySliderChanged:)];
        } else if (indexPath.row == 2) {
            return [self appearanceSliderCell:@"InterfaceBlur" title:self.sections[0][2]
                                       value:manager.interfaceBlurIntensity minimum:0.0 action:@selector(interfaceBlurSliderChanged:)];
        } else {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.textLabel.text = self.sections[0][3];
            cell.textLabel.textColor = AmeUIAccentColor();
            [manager applyEffectToCell:cell];
            return cell;
        }
    }
    if (indexPath.section == 5) {
        return indexPath.row == 0
            ? [self appearanceSliderCell:@"WallpaperBlur" title:self.sections[5][0] value:manager.blurIntensity minimum:0.0 action:@selector(blurIntensitySliderChanged:)]
            : [self appearanceSliderCell:@"WallpaperDimming" title:self.sections[5][1] value:manager.wallpaperDimming minimum:0.0 action:@selector(wallpaperDimmingSliderChanged:)];
    }

    // ★ [GLASS-STYLE] "UI Style" section: row0=style (auto/native/Liquid Glass) · row1=highlight switch · row2=intensity slider.
    if (indexPath.section == 4) {
        // ★ [GLASS-STYLE] row0: UI-style segmented control (iOS<26 ⇒ "Liquid Glass" disabled + footer explanation).
        if (indexPath.row == 0) {
            static NSString *glassStyleCellIdentifier = @"GlassStyleCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:glassStyleCellIdentifier];
            UISegmentedControl *seg = nil;
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:glassStyleCellIdentifier];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                seg = [[UISegmentedControl alloc] initWithItems:@[
                    localize(@"preference.style.auto", nil),
                    localize(@"preference.style.native", nil),
                    localize(@"preference.style.liquid", nil),
                ]];
                seg.tag = 420;   // ★ [GLASS-STYLE]
                [seg addTarget:self action:@selector(glassStyleChanged:) forControlEvents:UIControlEventValueChanged];
                // ★ Lay out within the content area (constrained by layoutMarginsGuide) ⇒ no clipping on either a
                // 320pt-wide iPhone in portrait or a 1366pt-wide iPad in landscape.
                seg.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:seg];
                UILayoutGuide *ameMarginGuide = cell.contentView.layoutMarginsGuide;
                [NSLayoutConstraint activateConstraints:@[
                    [seg.leadingAnchor  constraintEqualToAnchor:ameMarginGuide.leadingAnchor],
                    [seg.trailingAnchor constraintEqualToAnchor:ameMarginGuide.trailingAnchor],
                    [seg.centerYAnchor  constraintEqualToAnchor:cell.contentView.centerYAnchor],
                    [seg.heightAnchor    constraintGreaterThanOrEqualToConstant:32.0],
                ]];
                cell.accessoryView = nil;
            } else {
                seg = (UISegmentedControl *)[cell.contentView viewWithTag:420];
            }
            cell.textLabel.text = nil;
            cell.imageView.image = nil;
            if ([seg isKindOfClass:[UISegmentedControl class]]) {
                // Localized text (reset by reloadData after a language switch) + read back current setting (unset ⇒ auto).
                [seg setTitle:localize(@"preference.style.auto", nil)   forSegmentAtIndex:AMEGlassStyleAuto];
                [seg setTitle:localize(@"preference.style.native", nil) forSegmentAtIndex:AMEGlassStyleNative];
                [seg setTitle:localize(@"preference.style.liquid", nil) forSegmentAtIndex:AMEGlassStyleLiquid];
                seg.selectedSegmentIndex = (NSInteger)AMEGlassStyleConfigured();
                // ★ iOS < 26 (or when the system cannot load UIGlassEffect): disable "Liquid Glass".
                [seg setEnabled:AMEGlassStyleSystemSupportsLiquid() forSegmentAtIndex:AMEGlassStyleLiquid];
            }
            [self styleCell:cell hasBackground:hasBackground];
            return cell;
        }

        // ★ [GLASS-STYLE] row1: hand-drawn highlight switch (off by default per the "pure liquid" definition;
        // enabled only when the system supports Liquid Glass).
        if (indexPath.row == 1) {
            static NSString *glassSwitchCellIdentifier = @"GlassSwitchCell";   // ★ [GLASSUI]
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:glassSwitchCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:glassSwitchCellIdentifier];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISwitch *sw = [[UISwitch alloc] init];
                sw.tag = 400;   // ★ [GLASSUI]
                [sw addTarget:self action:@selector(glassSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
            cell.textLabel.text = self.sections[indexPath.section][indexPath.row];
            cell.imageView.image = [UIImage systemImageNamed:@"sparkles"];
            // ★ [GLASS-LIQUID] Switch = whether to overlay "hand-drawn highlights" (off by default).
            // Enabled only when the system supports Liquid Glass (iOS≥26).
            BOOL ameLiquidOK = AMEGlassStyleSystemSupportsLiquid();
            UISwitch *sw = (UISwitch *)cell.accessoryView;
            if ([sw isKindOfClass:[UISwitch class]]) {
                sw.on = AMEGlassStyleHandDrawnOverlayEnabled();   // Read back the actual switch (no longer mixed with glassRimEnabled).
                sw.enabled = ameLiquidOK;
            }
            cell.textLabel.enabled = ameLiquidOK;
            cell.imageView.alpha = ameLiquidOK ? 1.0 : 0.35;
            [self styleCell:cell hasBackground:hasBackground];
            return cell;
        }

        // ★ [GLASS-STYLE] row2: highlight-intensity slider (also disabled in native style).
        static NSString *glassSliderCellIdentifier = @"GlassSliderCell";   // ★ [GLASSUI]
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:glassSliderCellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:glassSliderCellIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 0, cell.bounds.size.width - 120, 30)];
            slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            slider.minimumValue = 0.0f;
            slider.maximumValue = 1.0f;   // ★ Matches BackgroundManager's clamp range.
            slider.tag = 410;             // ★ [GLASSUI]
            [slider addTarget:self action:@selector(glassStrengthSliderChanged:) forControlEvents:UIControlEventValueChanged];

            UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(cell.bounds.size.width - 80, 0, 60, 30)];
            valueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            valueLabel.textAlignment = NSTextAlignmentRight;
            valueLabel.tag = 411;         // ★ [GLASSUI]
            valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];

            [cell.contentView addSubview:slider];
            [cell.contentView addSubview:valueLabel];
            cell.contentView.layoutMargins = UIEdgeInsetsMake(8, 16, 8, 16);
        }

        [self styleCell:cell hasBackground:hasBackground];
        cell.textLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];

        BOOL ameHandOn = AMEGlassStyleHandDrawnOverlayEnabled();
        BOOL ameSliderEnabled = AMEGlassStyleSystemSupportsLiquid() && ameHandOn;
        UISlider *slider = [cell.contentView viewWithTag:410];
        if ([slider isKindOfClass:[UISlider class]]) {
            slider.value = manager.glassRimStrength;      // Read back current value (already clamped).
            slider.enabled = ameSliderEnabled;            // Disabled if "Hand-drawn Highlights" is off or unsupported (HIG).
        }
        UILabel *valueLabel = [cell.contentView viewWithTag:411];
        if ([valueLabel isKindOfClass:[UILabel class]]) {
            valueLabel.text = [NSString stringWithFormat:@"%.0f%%", manager.glassRimStrength * 100];
            valueLabel.textColor = AmeUISecondaryTextColor();
            valueLabel.alpha = ameSliderEnabled ? 1.0 : 0.35;
        }
        cell.imageView.alpha = ameSliderEnabled ? 1.0 : 0.35;
        self.glassStrengthValueLabel = valueLabel;
        return cell;
    }

    // Other sections.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    
    NSString *title = self.sections[indexPath.section][indexPath.row];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = nil;
    
    [self styleCell:cell hasBackground:hasBackground];
    
    if (indexPath.section == 1) {
        // Background-type selection title.
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:@"photo"];
            cell.accessoryType = [manager hasImageBackground] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else if (indexPath.row == 1) {
            cell.imageView.image = [UIImage systemImageNamed:@"film"];
            cell.accessoryType = [manager hasVideoBackground] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            // Restore default background.
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.counterclockwise"];
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else if (indexPath.row == 1) {
            // Clear background.
            cell.imageView.image = [UIImage systemImageNamed:@"xmark.circle"];
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }
    
    return cell;
}

// ★ [GLASS-STYLE] "UI Style" footer: explain the automatic decision / reason for disabling
// controls (native style / hand-drawn highlight state).
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return MetallicPresentationText(@"renewed.appearance.interface_help", @"UI Blur changes material visibility in Blur mode, not a Gaussian blur radius. Panel Opacity changes only panel tint. Wallpaper controls are separate.");
    if (section == 5) return MetallicPresentationText(@"renewed.appearance.wallpaper_help", @"Wallpaper Blur changes the background material. Wallpaper Dimming is a separate, gentler overlay in Light mode. Neither changes panel opacity. Choose a custom image or video to enable these controls.");
    if (section == 4) {
        NSMutableString *ameFooter = [NSMutableString string];
        [ameFooter appendString:AMEGlassStyleSystemSupportsLiquid()
                                 ? localize(@"preference.style.footer.supported", nil)
                                 : localize(@"preference.style.footer.unsupported", nil)];
        if (!AMEGlassStyleSystemSupportsLiquid()) {
            // iOS < 26: the system has no Liquid Glass ⇒ hand-drawn switch/intensity unavailable.
            [ameFooter appendFormat:@"\n%@", localize(@"preference.style.footer.native", nil)];
        } else if (AMEGlassStyleHandDrawnOverlayEnabled()) {
            // Hand-drawn highlights explicitly enabled.
            [ameFooter appendFormat:@"\n%@", localize(@"preference.style.footer.handdrawn", nil)];
        } else {
            // Default: pure system material (per the "pure liquid" definition).
            [ameFooter appendFormat:@"\n%@", localize(@"preference.style.footer.pure", nil)];
        }
        return ameFooter;
    }
    return nil;
}

// ★ [GLASS-STYLE] The footer contains multiple lines ⇒ use adaptive height (supported for
// titleForFooterInSection since iOS 11).
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Existing style controls use centered/frame layout. Retain a stable touch-height for those rows.
    if (indexPath.section == 4) return 52.0;
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)styleCell:(UITableViewCell *)cell hasBackground:(BOOL)hasBackground {
    [[BackgroundManager sharedManager] applyEffectToCell:cell];
    cell.textLabel.textColor = AmeUIPrimaryTextColor();
    cell.detailTextLabel.textColor = AmeUISecondaryTextColor();
    cell.textLabel.font = AmeUIFont(AmeUIFontRoleBody);
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
}

#pragma mark - Slider Actions

- (void)updatePercentageForSlider:(UISlider *)slider value:(CGFloat)value {
    UILabel *label = (UILabel *)[slider.superview viewWithTag:501];
    label.text = [NSString stringWithFormat:@"%.0f%%", value * 100];
    slider.accessibilityValue = label.text;
}

- (void)opacitySliderChanged:(UISlider *)slider {
    BackgroundManager *manager = [BackgroundManager sharedManager];
    manager.uiOpacity = slider.value;
    [self updatePercentageForSlider:slider value:manager.uiOpacity];
    [manager refreshUIEffect];
}

- (void)interfaceBlurSliderChanged:(UISlider *)slider {
    BackgroundManager *manager = [BackgroundManager sharedManager];
    manager.interfaceBlurIntensity = slider.value;
    [self updatePercentageForSlider:slider value:manager.interfaceBlurIntensity];
    [manager refreshUIEffect];
}

- (void)blurIntensitySliderChanged:(UISlider *)slider {
    BackgroundManager *manager = [BackgroundManager sharedManager];
    manager.blurIntensity = slider.value;
    [self updatePercentageForSlider:slider value:manager.blurIntensity];
    [manager refreshUIEffect];
}

- (void)wallpaperDimmingSliderChanged:(UISlider *)slider {
    BackgroundManager *manager = [BackgroundManager sharedManager];
    manager.wallpaperDimming = slider.value;
    [self updatePercentageForSlider:slider value:manager.wallpaperDimming];
    [manager refreshUIEffect];
}

- (void)resetInterfaceAppearance {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.sections[0][3]
        message:MetallicPresentationText(@"renewed.appearance.reset_help", @"Reset UI effect, UI Blur and Panel Opacity only. Wallpaper, theme, accounts and game settings stay unchanged.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:MetallicPresentationText(@"renewed.appearance.reset", @"Reset to Recommended") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[BackgroundManager sharedManager] resetInterfaceAppearance];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - ★ [GLASSUI] Glass switch / intensity

// Switch: on = restore highlights at the current intensity; off = remove highlights (AmeDetachGlassRim path).
// The setter already persists, writes the global intensity, and refreshes immediately; here we only
// synchronize the enabled state of controls on this page.
- (void)glassSwitchChanged:(UISwitch *)sw {
    // ★ [GLASS-LIQUID] Switch = whether to overlay "hand-drawn highlights" (off by default per the
    // "pure liquid" definition).
    //   Write the single source-of-truth key (background_glass_handdrawn) + broadcast
    //   AMEGlassStyleChanged ⇒ BackgroundManager immediately refreshes using the new value.
    [BackgroundManager sharedManager].glassRimEnabled = sw.on;      // Preserve existing global intensity constraints (0 ⇒ no highlight).
    AMEGlassStyleSetHandDrawnOverlayEnabled(sw.on);

    // The enabled state of the row2 slider and this section's footer explanation must also follow the switch.
    // ★ Defer by one run loop: this method is triggered by a UISwitch in this section; reloading
    // synchronously during touch dispatch would replace that control.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:4]
                      withRowAnimation:UITableViewRowAnimationNone];
    });
}

// ★ [GLASS-STYLE] UI style (auto / native / Liquid Glass).
//   Segmented-control indices map directly to AMEGlassStyle (0=auto, 1=native, 2=Liquid Glass).
//   AMEGlassStyleSetConfigured internally: ① writes NSUserDefaults (key background_glass_style,
//   same store as this section's highlight switch/intensity); ② broadcasts
//   AMEGlassStyleChangedNotification ⇒ BackgroundManager immediately refreshes with the new style.
//   On iOS<26 the segment is already disabled; repeat the "native only" check here to ensure
//   older devices cannot be set to Liquid Glass.
- (void)glassStyleChanged:(UISegmentedControl *)seg {
    AMEGlassStyle picked = AMEGlassStyleEnumFromString(AMEGlassStyleStringFromEnum((AMEGlassStyle)seg.selectedSegmentIndex));
    if (picked == AMEGlassStyleLiquid && !AMEGlassStyleSystemSupportsLiquid()) {
        picked = AMEGlassStyleNative;   // ★ Force native on iOS<26.
    }
    AMEGlassStyleSetConfigured(picked);
    seg.selectedSegmentIndex = (NSInteger)AMEGlassStyleConfigured();

    // Reload this section: the enabled state of the switch/slider and the footer explanation must all
    // follow the style.
    // ★ Defer by one run loop: this method is triggered by the segmented control in this section;
    //   reloading during touch dispatch would replace the control and its cell (occasionally losing
    //   the highlight or interrupting the gesture).
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:4]
                      withRowAnimation:UITableViewRowAnimationNone];
    });
}

// Intensity: the setter clamps (0…1), persists, and refreshes immediately; here only update the value label.
- (void)glassStrengthSliderChanged:(UISlider *)slider {
    [BackgroundManager sharedManager].glassRimStrength = slider.value;

    UITableViewCell *cell = (UITableViewCell *)slider.superview.superview;
    if ([cell isKindOfClass:[UITableViewCell class]]) {
        UILabel *valueLabel = [cell.contentView viewWithTag:411];
        valueLabel.text = [NSString stringWithFormat:@"%.0f%%", [BackgroundManager sharedManager].glassRimStrength * 100];
    }
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // UI effect settings section.
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self showUIEffectPicker];
        else if (indexPath.row == 3) [self resetInterfaceAppearance];
        return;
    }
    
    // ★ [GLASSUI] Tapping the entire row also toggles the glass switch (same as tapping UISwitch; HIG convention).
    // ★ [GLASS-STYLE] row0 (UI style) is handled by the segmented control itself and does not respond
    // to row-wide taps; the switch moved to row1.
    if (indexPath.section == 4) {
        if (indexPath.row == 1) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            UISwitch *sw = (UISwitch *)cell.accessoryView;
            if ([sw isKindOfClass:[UISwitch class]] && sw.enabled) {
                [sw setOn:!sw.on animated:YES];
                [self glassSwitchChanged:sw];
            }
        }
        return;
    }
    
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            [self selectImageBackground];
        } else if (indexPath.row == 1) {
            [self selectVideoBackground];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            [self restoreDefaultBackground];
        } else if (indexPath.row == 1) {
            [self clearBackground];
        }
    }
}

- (void)showUIEffectPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_66", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    BackgroundManager *manager = [BackgroundManager sharedManager];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_67", nil)
                                              style:manager.uiEffect == BackgroundUIEffectBlur ? UIAlertActionStyleDefault : UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        manager.uiEffect = BackgroundUIEffectBlur;
        [manager refreshUIEffect];
        [self.tableView reloadData];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_68", nil)
                                              style:manager.uiEffect == BackgroundUIEffectTranslucent ? UIAlertActionStyleDefault : UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        manager.uiEffect = BackgroundUIEffectTranslucent;
        [manager refreshUIEffect];
        [self.tableView reloadData];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        alert.popoverPresentationController.sourceView = cell ?: self.view;
        alert.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Background Selection

- (void)selectImageBackground {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_70", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_71", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openPhotoLibraryForImage];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_72", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openDocumentPickerForImage];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        alert.popoverPresentationController.sourceView = cell;
        alert.popoverPresentationController.sourceRect = cell.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectVideoBackground {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_73", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_71", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openPhotoLibraryForVideo];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_72", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openDocumentPickerForVideo];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
        alert.popoverPresentationController.sourceView = cell;
        alert.popoverPresentationController.sourceRect = cell.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restoreDefaultBackground {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_62", nil)
                                                                   message:localize(@"i18n_str_74", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_75", nil)
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction * _Nonnull action) {
        // Clear background.
        [[BackgroundManager sharedManager] clearBackground];
        
        // Reset UI effect settings.
        BackgroundManager *manager = [BackgroundManager sharedManager];
        manager.uiEffect = BackgroundUIEffectBlur;
        manager.uiOpacity = 0.7;
        [manager refreshUIEffect];
        
        [self updatePreview];
        [self.tableView reloadData];
        
        // Restore default background color.
        self.view.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundView = nil;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearBackground {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_63", nil)
                                                                   message:localize(@"i18n_str_76", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_77", nil)
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction * _Nonnull action) {
        [[BackgroundManager sharedManager] clearBackground];
        [self updatePreview];
        [self.tableView reloadData];
        
        // Restore default background color
        self.view.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundColor = [UIColor clearColor];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Image Picker

- (void)openPhotoLibraryForImage {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.image"];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)openPhotoLibraryForVideo {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.movie"];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Document Picker

- (void)openDocumentPickerForImage {
    NSArray<UTType *> *contentTypes = @[
        UTTypeJPEG,
        UTTypePNG,
        UTTypeImage
    ];
    
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)openDocumentPickerForVideo {
    NSArray<UTType *> *contentTypes = @[
        UTTypeMovie,
        UTTypeVideo,
        UTTypeMPEG4Movie
    ];
    
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    
    if ([mediaType isEqualToString:@"public.image"]) {
        UIImage *image = info[UIImagePickerControllerOriginalImage];
        [picker dismissViewControllerAnimated:YES completion:^{
            [self processSelectedImage:image];
        }];
    } else if ([mediaType isEqualToString:@"public.movie"]) {
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        [picker dismissViewControllerAnimated:YES completion:^{
            [self processSelectedVideo:videoURL];
        }];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    
    NSURL *url = urls.firstObject;
    NSString *extension = url.pathExtension.lowercaseString;
    
    if ([@[@"jpg", @"jpeg", @"png", @"heic"] containsObject:extension]) {
        // ★ [ISSUE-FIX] #92 (same class of issue): Document Picker returns a security-scoped URL;
        //   without accessing its scope, imageWithContentsOfFile: returns nil (appearing as "image
        //   selection does nothing").
        BOOL ame92Scoped = [url startAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *image = [UIImage imageWithContentsOfFile:url.path];
            if (ame92Scoped) [url stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (image) [self processSelectedImage:image];
                else {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_42", @"Error")
                        message:localize(@"i18n_str_48", @"The image could not be read.") preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", @"OK") style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                }
            });
        });
    } else if ([@[@"mp4", @"mov", @"m4v"] containsObject:extension]) {
        [self processSelectedVideo:url];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // Cancelled
}

#pragma mark - Process Selection

- (void)processSelectedImage:(UIImage *)image {
    if (!image) return;
    
    UIAlertController *processingAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_78", nil)
                                                                             message:localize(@"i18n_str_79", nil)
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:processingAlert animated:YES completion:nil];
    
    [[BackgroundManager sharedManager] setImageBackground:image completion:^(BOOL success, NSError * _Nullable error) {
        [processingAlert dismissViewControllerAnimated:YES completion:^{
            if (success) {
                [self updatePreview];
                [self.tableView reloadData];
                
                // Apply transparency
                self.view.backgroundColor = [UIColor clearColor];
                self.tableView.backgroundColor = [UIColor clearColor];
                self.tableView.backgroundView = nil;
                
                [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
                
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_80", nil)
                                                                                      message:localize(@"i18n_str_81", nil)
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
            } else {
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_42", nil)
                                                                                    message:error.localizedDescription ?: localize(@"i18n_str_82", nil)
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            }
        }];
    }];
}

- (void)processSelectedVideo:(NSURL *)videoURL {
    if (!videoURL) return;
    
    UIAlertController *processingAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_78", nil)
                                                                             message:localize(@"i18n_str_83", nil)
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:processingAlert animated:YES completion:nil];
    
    [[BackgroundManager sharedManager] setVideoBackgroundWithURL:videoURL completion:^(BOOL success, NSError * _Nullable error) {
        [processingAlert dismissViewControllerAnimated:YES completion:^{
            if (success) {
                [self updatePreview];
                [self.tableView reloadData];
                
                // Apply transparency
                self.view.backgroundColor = [UIColor clearColor];
                self.tableView.backgroundColor = [UIColor clearColor];
                self.tableView.backgroundView = nil;
                
                [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
                
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_80", nil)
                                                                                      message:localize(@"i18n_str_84", nil)
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
            } else {
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_42", nil)
                                                                                    message:error.localizedDescription ?: localize(@"i18n_str_85", nil)
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            }
        }];
    }];
}

/// Reapply the background effect when the BackgroundUIEffectChanged notification arrives:
/// use BackgroundManager to reset this view controller's opacity/frosted-glass effect, and
/// manually clear the tableView background and backgroundView so the global background can
/// show through correctly.
- (void)reapplyBackgroundEffect {
    if (self.launcherPresentation) [self refreshReferenceInterfaceControls];
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
    BackgroundManager *manager = [BackgroundManager sharedManager];
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        // Synchronize the existing style controls too, without replacing an actively tracking cell.
        UISegmentedControl *style = (UISegmentedControl *)[cell.contentView viewWithTag:420];
        if (style && !style.tracking) style.selectedSegmentIndex = AMEGlassStyleConfigured();
        UISwitch *highlights = (UISwitch *)[cell.accessoryView viewWithTag:400];
        if (highlights && !highlights.tracking) {
            highlights.on = AMEGlassStyleHandDrawnOverlayEnabled();
            highlights.enabled = AMEGlassStyleSystemSupportsLiquid();
        }
        UISlider *strength = (UISlider *)[cell.contentView viewWithTag:410];
        if (strength && !strength.tracking) {
            strength.value = manager.glassRimStrength;
            strength.enabled = AMEGlassStyleSystemSupportsLiquid() && AMEGlassStyleHandDrawnOverlayEnabled();
            UILabel *label = (UILabel *)[cell.contentView viewWithTag:411];
            label.text = [NSString stringWithFormat:@"%.0f%%", manager.glassRimStrength * 100];
            label.alpha = strength.enabled ? 1.0 : 0.35;
        }
        UISlider *slider = (UISlider *)[cell.contentView viewWithTag:500];
        NSIndexPath *path = [self.tableView indexPathForCell:cell];
        if (path.section == 0 && path.row == 0) cell.detailTextLabel.text = manager.uiEffect == BackgroundUIEffectBlur
            ? localize(@"i18n_str_2017", nil) : localize(@"i18n_str_65", nil);
        if (!slider || slider.tracking || !path) continue;
        slider.enabled = path.section == 5 ? [manager hasBackground] : (path.row != 2 || manager.uiEffect == BackgroundUIEffectBlur);
        CGFloat value = path.section == 5 ? (path.row == 0 ? manager.blurIntensity : manager.wallpaperDimming)
            : (path.row == 1 ? manager.uiOpacity : manager.interfaceBlurIntensity);
        slider.value = value;
        [self updatePercentageForSlider:slider value:value];
    }
}

- (void)wallpaperChanged:(NSNotification *)notification {
    [self updatePreview];
    [self reapplyBackgroundEffect];
    BackgroundManager *manager = [BackgroundManager sharedManager];
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        NSIndexPath *path = [self.tableView indexPathForCell:cell];
        if (path && path.section == 2) cell.accessoryType = (path.row == 0 ? manager.hasImageBackground : manager.hasVideoBackground)
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
@implementation MetallicAppearanceContainerViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.clearColor;
    [self addChildViewController:self.appearance];
    self.appearance.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.appearance.view];
    [self.appearance didMoveToParentViewController:self];
    self.navigationItem.rightBarButtonItem = self.appearance.navigationItem.rightBarButtonItem;
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *width = [self.appearance.view.widthAnchor constraintEqualToAnchor:g.widthAnchor multiplier:1240.0/1536.0]; width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[self.appearance.view.centerXAnchor constraintEqualToAnchor:g.centerXAnchor], [self.appearance.view.topAnchor constraintEqualToAnchor:g.topAnchor], [self.appearance.view.bottomAnchor constraintEqualToAnchor:g.bottomAnchor], [self.appearance.view.leadingAnchor constraintGreaterThanOrEqualToAnchor:g.leadingAnchor constant:8], [self.appearance.view.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor constant:-8], width]];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setNavigationBarHidden:YES animated:NO]; }
@end
