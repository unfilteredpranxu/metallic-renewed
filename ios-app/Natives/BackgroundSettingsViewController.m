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
#import "AMEGlassStyle.h"   // ★ [GLASS-STYLE] UI style (auto / native / Liquid Glass) resolution layer

@interface BackgroundSettingsViewController ()
@property (nonatomic, strong) NSArray<NSArray *> *sections;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UISlider *opacitySlider;
@property (nonatomic, weak) UILabel *opacityValueLabel;
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
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    }
    
    // Setup table view
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.tableFooterView = [[UIView alloc] init];
    // ★ [GLASS-STYLE] The "UI Style" footer contains multiple lines ⇒ use adaptive height (otherwise
    // the text will be clipped or compressed).
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    
    // Setup preview header
    [self setupPreviewHeader];
    
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
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updatePreview];
    [self.tableView reloadData];
    
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
    placeholderLabel.font = [UIFont systemFontOfSize:16];
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

- (void)setupSections {
    // Sections: [UI effect settings], [Choose background type], [Image background, Video background],
    // [Restore default background, Clear background].
    self.sections = @[
        @[localize(@"i18n_str_57", nil), localize(@"i18n_str_1296", nil), localize(@"i18n_str_1297", nil)],
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
          localize(@"preference.title.glass_strength", nil)]
    ];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Hide the UI effect settings section if no custom background is set.
    if (section == 0 && ![[BackgroundManager sharedManager] hasBackground]) {
        return 0;
    }
    return [self.sections[section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0 && ![[BackgroundManager sharedManager] hasBackground]) {
        return nil;
    }
    return self.sections[section][0];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"BackgroundCell";
    static NSString *sliderCellIdentifier = @"SliderCell";
    static NSString *blurSliderCellIdentifier = @"BlurSliderCell";
    
    BackgroundManager *manager = [BackgroundManager sharedManager];
    BOOL hasBackground = [manager hasBackground];
    
    // UI effect settings section.
    if (indexPath.section == 0 && hasBackground) {
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
            // Opacity slider.
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sliderCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sliderCellIdentifier];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                
                // Create slider.
                UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 0, cell.bounds.size.width - 120, 30)];
                slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                slider.minimumValue = 0.1f;
                slider.maximumValue = 1.0f;
                slider.tag = 200;
                [slider addTarget:self action:@selector(opacitySliderChanged:) forControlEvents:UIControlEventValueChanged];
                
                // Create value label.
                UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(cell.bounds.size.width - 80, 0, 60, 30)];
                valueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                valueLabel.textAlignment = NSTextAlignmentRight;
                valueLabel.tag = 201;
                valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
                
                [cell.contentView addSubview:slider];
                [cell.contentView addSubview:valueLabel];
                
                cell.contentView.layoutMargins = UIEdgeInsetsMake(8, 16, 8, 16);
            }
            
            [self styleCell:cell hasBackground:hasBackground];
            
            UISlider *slider = [cell.contentView viewWithTag:200];
            slider.value = manager.uiOpacity;
            
            UILabel *valueLabel = [cell.contentView viewWithTag:201];
            valueLabel.text = [NSString stringWithFormat:@"%.0f%%", manager.uiOpacity * 100];
            valueLabel.textColor = hasBackground ? [UIColor whiteColor] : [UIColor labelColor];
            self.opacityValueLabel = valueLabel;
            
            cell.textLabel.text = nil;
            cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
            
            return cell;
            
        } else if (indexPath.row == 2) {
            // Blur-intensity slider.
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:blurSliderCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:blurSliderCellIdentifier];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                
                // Create slider.
                UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 0, cell.bounds.size.width - 120, 30)];
                slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                slider.minimumValue = 0.0f;
                slider.maximumValue = 1.0f;
                slider.tag = 300;
                [slider addTarget:self action:@selector(blurIntensitySliderChanged:) forControlEvents:UIControlEventValueChanged];
                
                // Create value label.
                UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(cell.bounds.size.width - 80, 0, 60, 30)];
                valueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                valueLabel.textAlignment = NSTextAlignmentRight;
                valueLabel.tag = 301;
                valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
                
                [cell.contentView addSubview:slider];
                [cell.contentView addSubview:valueLabel];
                
                cell.contentView.layoutMargins = UIEdgeInsetsMake(8, 16, 8, 16);
            }
            
            [self styleCell:cell hasBackground:hasBackground];
            
            UISlider *slider = [cell.contentView viewWithTag:300];
            slider.value = manager.blurIntensity;
            
            UILabel *valueLabel = [cell.contentView viewWithTag:301];
            valueLabel.text = [NSString stringWithFormat:@"%.0f%%", manager.blurIntensity * 100];
            valueLabel.textColor = hasBackground ? [UIColor whiteColor] : [UIColor labelColor];
            
            cell.textLabel.text = nil;
            cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
            
            return cell;
        }
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
            valueLabel.textColor = hasBackground ? [UIColor whiteColor] : [UIColor labelColor];
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
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)styleCell:(UITableViewCell *)cell hasBackground:(BOOL)hasBackground {
    if (hasBackground) {
        [[BackgroundManager sharedManager] applyEffectToCell:cell];
        cell.textLabel.textColor = [UIColor whiteColor];
    } else {
        cell.backgroundColor = [UIColor secondarySystemBackgroundColor];
        cell.textLabel.textColor = [UIColor labelColor];
    }
}

#pragma mark - Slider Actions

- (void)opacitySliderChanged:(UISlider *)slider {
    CGFloat value = slider.value;
    [BackgroundManager sharedManager].uiOpacity = value;
    
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100];
    
    // Refresh UI effect in real time.
    [[BackgroundManager sharedManager] refreshUIEffect];
}

- (void)blurIntensitySliderChanged:(UISlider *)slider {
    CGFloat value = slider.value;
    [BackgroundManager sharedManager].blurIntensity = value;
    
    // Update the label display.
    UITableViewCell *cell = (UITableViewCell *)slider.superview.superview;
    if ([cell isKindOfClass:[UITableViewCell class]]) {
        UILabel *valueLabel = [cell.contentView viewWithTag:301];
        valueLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100];
    }
    
    // Refresh UI effect in real time.
    [[BackgroundManager sharedManager] refreshUIEffect];
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
    
    BackgroundManager *manager = [BackgroundManager sharedManager];
    BOOL hasBackground = [manager hasBackground];
    
    // UI effect settings section.
    if (indexPath.section == 0 && hasBackground) {
        if (indexPath.row == 0) {
            [self showUIEffectPicker];
        }
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
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundUIEffectChanged" object:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_68", nil)
                                              style:manager.uiEffect == BackgroundUIEffectTranslucent ? UIAlertActionStyleDefault : UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        manager.uiEffect = BackgroundUIEffectTranslucent;
        [manager refreshUIEffect];
        [self.tableView reloadData];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundUIEffectChanged" object:nil];
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
        
        [self updatePreview];
        [self.tableView reloadData];
        
        // Restore default background color.
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        self.tableView.backgroundColor = [UIColor systemBackgroundColor];
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
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        self.tableView.backgroundColor = [UIColor systemBackgroundColor];
        
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
        UIImage *image = [UIImage imageWithContentsOfFile:url.path];
        if (ame92Scoped) [url stopAccessingSecurityScopedResource];
        if (image) [self processSelectedImage:image];
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
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end