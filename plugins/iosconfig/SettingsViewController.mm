// iosconfig - 機能設定画面 / 権利情報画面。
// 項目と並び・文言は krkrz_android の SettingsActivity / LicenseActivity と揃える。

#import "ViewControllers.h"
#import "IosConfig.h"

using iosconfig::L;

// エンジン本体 (common/msg/MsgIntf.cpp)
extern ttstr TVPGetLicenseString();

namespace {

constexpr CGFloat kContentMaxWidth = 640;   // 横長の画面で行が間延びしないように

int Clamp(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

long long AsLong(NSDictionary *m, NSString *key, long long def) {
    id o = m[key];
    if ([o isKindOfClass:[NSNumber class]]) return [o longLongValue];
    if ([o isKindOfClass:[NSString class]]) return [o longLongValue];
    return def;
}

NSString *AsString(NSDictionary *m, NSString *key, NSString *def) {
    id o = m[key];
    if ([o isKindOfClass:[NSString class]]) return o;
    if ([o isKindOfClass:[NSNumber class]]) return [o stringValue];
    return def;
}

// "値<TAB>表示名" の改行区切り (TAB 無しは値 = 表示名)
void ParseOptionList(NSString *src, NSMutableArray *values, NSMutableArray *labels) {
    for (NSString *raw in [src componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (line.length == 0) continue;
        NSRange tab = [line rangeOfString:@"\t"];
        if (tab.location != NSNotFound) {
            [values addObject:[[line substringToIndex:tab.location]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
            [labels addObject:[[line substringFromIndex:tab.location + 1]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
        } else {
            [values addObject:line];
            [labels addObject:line];
        }
    }
}

UINavigationItem *SetupCloseButton(UIViewController *vc) {
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithPrimaryAction:[UIAction actionWithTitle:L(@"close") image:nil identifier:nil
            handler:^(__kindof UIAction *) {
                [vc dismissViewControllerAnimated:YES completion:nil];
            }]];
    return vc.navigationItem;
}

} // namespace

// ============================================================
// 設定画面
// ============================================================

@interface KrkrzSettingsViewController ()
@property (nonatomic, strong) UIStackView *stack;            // 全体
@property (nonatomic, strong) UIStackView *configStack;      // TJS 由来の項目
@property (nonatomic, strong) NSMutableDictionary *editedConfig;
@property (nonatomic, assign) BOOL haveConfig;
@end

@implementation KrkrzSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = L(@"menu_settings");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    SetupCloseButton(self);
    _editedConfig = [NSMutableDictionary dictionary];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 6;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:_stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *fullWidth = [_stack.widthAnchor constraintEqualToAnchor:safe.widthAnchor constant:-32];
    fullWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8],
        [_stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [_stack.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_stack.widthAnchor constraintLessThanOrEqualToConstant:kContentMaxWidth],
        fullWidth,
    ]];

    if (iosconfig::PadAvailable()) [self buildPadSection];

    _configStack = [[UIStackView alloc] init];
    _configStack.axis = UILayoutConstraintAxisVertical;
    _configStack.spacing = 6;
    [_stack addArrangedSubview:_configStack];
    [self addCaption:L(@"settings_cfg_loading") to:_configStack];

    __weak KrkrzSettingsViewController *weakSelf = self;
    iosconfig::FetchConfig(^(NSDictionary *config, NSDictionary *volumes) {
        [weakSelf onConfigReady:config volumes:volumes];
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // 画面を閉じたら音量以外の編集値をまとめて本体へ渡す (Android は onPause)
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed) {
        if (_haveConfig && _editedConfig.count) iosconfig::ApplyConfig(_editedConfig);
    }
}

// ---- 仮想パッド ----

- (void)buildPadSection {
    [self addHeader:L(@"settings_section_virtualpad") to:_stack];
    [self addSwitchTitle:L(@"settings_vpad_enabled") on:iosconfig::PadEnabled() to:_stack
                 changed:^(BOOL on) { iosconfig::SetPadEnabled(on); }];
    [self addDescription:L(@"settings_vpad_enabled_desc") to:_stack];

    int pct = iosconfig::PadOpacityPercent();
    NSString *fmt = L(@"settings_vpad_opacity");
    UILabel *label = [self addCaption:[NSString stringWithFormat:fmt, pct] to:_stack];
    [self addSliderMin:iosconfig::kPadOpacityMin max:iosconfig::kPadOpacityMax value:pct to:_stack
               changed:^(int v) { label.text = [NSString stringWithFormat:fmt, v]; }
                 ended:^(int v) { iosconfig::SetPadOpacityPercent(v); }];
    [self addDescription:L(@"settings_vpad_opacity_desc") to:_stack];
    [_stack setCustomSpacing:20 afterView:_stack.arrangedSubviews.lastObject];
}

// ---- TJS 由来の項目 ----

- (void)onConfigReady:(NSDictionary *)config volumes:(NSDictionary *)volumes {
    for (UIView *v in _configStack.arrangedSubviews) {
        [_configStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    if (!config) {
        // 本体側に取得関数 (KrkrzAndroidGetConfig) が無い
        [self addCaption:L(@"settings_cfg_unavailable") to:_configStack];
        return;
    }
    _haveConfig = YES;

    UIStackView *s = _configStack;
    [self addHeader:L(@"settings_cfg_sec_system") to:s];
    [self addSwitch:config key:@"screenEffect" label:@"settings_cfg_screen_effect"];
    [self addSwitch:config key:@"systemEffect" label:@"settings_cfg_system_effect"];
    [self addConfigSlider:config key:@"windowOpacity" label:@"settings_cfg_window_opacity" min:0 max:100];

    [self addHeader:L(@"settings_cfg_sec_message") to:s];
    [self addConfigSlider:config key:@"messageSpeed" label:@"settings_cfg_message_speed" min:0 max:100];
    [self addConfigSlider:config key:@"autoModeSpeed" label:@"settings_cfg_auto_speed" min:0 max:100];
    [self addSwitch:config key:@"autoReleaseOnChoice" label:@"settings_cfg_auto_release_choice"];
    [self addSwitch:config key:@"autoWaitVoice" label:@"settings_cfg_auto_wait_voice"];
    [self addEnum:config key:@"skipMode" label:@"settings_cfg_skip_mode"
           values:@[ @"0", @"1" ]
           labels:@[ L(@"settings_cfg_skip_existing"), L(@"settings_cfg_skip_all") ]];
    [self addSwitch:config key:@"skipReleaseOnChoice" label:@"settings_cfg_skip_release_choice"];
    [self addSwitch:config key:@"skipReadText" label:@"settings_cfg_skip_read_text"];

    [self addHeader:L(@"settings_cfg_sec_volume") to:s];
    [self addVolume:volumes key:@"master" label:L(@"settings_cfg_vol_master")];
    [self addVolume:volumes key:@"bgm" label:L(@"settings_cfg_vol_bgm")];
    [self addVolume:volumes key:@"se" label:L(@"settings_cfg_vol_se")];
    [self addVolume:volumes key:@"systemSe" label:L(@"settings_cfg_vol_system_se")];

    [self addHeader:L(@"settings_cfg_sec_voice") to:s];
    [self addVolume:volumes key:@"voice" label:L(@"settings_cfg_vol_voice")];
    [self addVolume:volumes key:@"systemVoice" label:L(@"settings_cfg_vol_system_voice")];
    [self addSwitch:config key:@"lowerBgmOnVoice" label:@"settings_cfg_lower_bgm_on_voice"];
    [self addSwitch:config key:@"lowerSeOnVoice" label:@"settings_cfg_lower_se_on_voice"];

    NSString *names = AsString(config, @"charVoiceNames", @"");
    if (names.length) {
        [self addCaption:L(@"settings_cfg_char_voice") to:s];
        for (NSString *raw in [names componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *name = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (name.length == 0) continue;
            [self addVolume:volumes key:[@"charVoice:" stringByAppendingString:name] label:name];
        }
    }

    BOOL hasMain = config[@"mainTextLang"] != nil;
    BOOL hasSub = config[@"subTextLang"] != nil;
    if (hasMain || hasSub) {
        [self addHeader:L(@"settings_cfg_sec_language") to:s];
        if (hasMain) [self addLang:config key:@"mainTextLang" list:@"mainTextLangList" label:@"settings_cfg_main_text"];
        if (hasSub) [self addLang:config key:@"subTextLang" list:@"subTextLangList" label:@"settings_cfg_sub_text"];
    }
}

- (void)addSwitch:(NSDictionary *)c key:(NSString *)key label:(NSString *)labelKey {
    if (!c[key]) return;
    BOOL cur = AsLong(c, key, 0) != 0;
    _editedConfig[key] = @(cur ? 1 : 0);
    __weak KrkrzSettingsViewController *weakSelf = self;
    [self addSwitchTitle:L(labelKey) on:cur to:_configStack changed:^(BOOL on) {
        weakSelf.editedConfig[key] = @(on ? 1 : 0);
    }];
}

// 音量以外の数値 (閉じるときにまとめて渡す)
- (void)addConfigSlider:(NSDictionary *)c key:(NSString *)key label:(NSString *)labelKey min:(int)lo max:(int)hi {
    if (!c[key]) return;
    int cur = Clamp((int)AsLong(c, key, lo), lo, hi);
    _editedConfig[key] = @(cur);
    NSString *labelText = L(labelKey);
    UILabel *label = [self addCaption:[NSString stringWithFormat:@"%@ (%d)", labelText, cur] to:_configStack];
    __weak KrkrzSettingsViewController *weakSelf = self;
    [self addSliderMin:lo max:hi value:cur to:_configStack
               changed:^(int v) {
                   label.text = [NSString stringWithFormat:@"%@ (%d)", labelText, v];
                   weakSelf.editedConfig[key] = @(v);
               }
                 ended:nil];
}

// 音量 (操作中も即時反映)
- (void)addVolume:(NSDictionary *)volumes key:(NSString *)key label:(NSString *)labelText {
    NSNumber *n = volumes[key];
    if (!n) return;
    int cur = Clamp(n.intValue, 0, 100);
    UILabel *label = [self addCaption:[NSString stringWithFormat:@"%@ (%d)", labelText, cur] to:_configStack];
    __block int last = cur;
    [self addSliderMin:0 max:100 value:cur to:_configStack
               changed:^(int v) {
                   label.text = [NSString stringWithFormat:@"%@ (%d)", labelText, v];
                   if (v != last) {
                       last = v;
                       iosconfig::SetVolume(key, v);
                   }
               }
                 ended:nil];
}

- (void)addEnum:(NSDictionary *)c key:(NSString *)key label:(NSString *)labelKey
         values:(NSArray<NSString *> *)values labels:(NSArray<NSString *> *)labels {
    if (!c[key]) return;
    long long cur = AsLong(c, key, 0);
    _editedConfig[key] = @(cur);
    __weak KrkrzSettingsViewController *weakSelf = self;
    [self addChoiceTitle:L(labelKey) labels:labels
                selected:[values indexOfObject:[NSString stringWithFormat:@"%lld", cur]]
                 changed:^(NSUInteger i) { weakSelf.editedConfig[key] = @([values[i] longLongValue]); }];
}

- (void)addLang:(NSDictionary *)c key:(NSString *)key list:(NSString *)listKey label:(NSString *)labelKey {
    NSString *cur = AsString(c, key, @"");
    NSMutableArray *values = [NSMutableArray array];
    NSMutableArray *labels = [NSMutableArray array];
    ParseOptionList(AsString(c, listKey, @""), values, labels);
    if (values.count == 0) {
        // 選択肢が無ければ現在値だけ
        [values addObject:cur];
        [labels addObject:cur.length ? cur : @"-"];
    }
    _editedConfig[key] = cur;
    __weak KrkrzSettingsViewController *weakSelf = self;
    [self addChoiceTitle:L(labelKey) labels:labels selected:[values indexOfObject:cur]
                 changed:^(NSUInteger i) { weakSelf.editedConfig[key] = values[i]; }];
}

// ---- 行ウィジェット ----

- (void)addHeader:(NSString *)text to:(UIStackView *)parent {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    l.numberOfLines = 0;
    [parent addArrangedSubview:l];
    [parent setCustomSpacing:4 afterView:l];
    UIView *prev = parent.arrangedSubviews.count >= 2
        ? parent.arrangedSubviews[parent.arrangedSubviews.count - 2] : nil;
    if (prev) [parent setCustomSpacing:20 afterView:prev];
}

- (UILabel *)addCaption:(NSString *)text to:(UIStackView *)parent {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    l.numberOfLines = 0;
    [parent addArrangedSubview:l];
    return l;
}

- (void)addDescription:(NSString *)text to:(UIStackView *)parent {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    l.textColor = UIColor.secondaryLabelColor;
    l.numberOfLines = 0;
    [parent addArrangedSubview:l];
}

- (void)addSwitchTitle:(NSString *)title on:(BOOL)on to:(UIStackView *)parent changed:(void (^)(BOOL))changed {
    UILabel *l = [[UILabel alloc] init];
    l.text = title;
    l.numberOfLines = 0;
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    void (^cb)(BOOL) = [changed copy];
    [sw addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        cb(((UISwitch *)a.sender).on);
    }] forControlEvents:UIControlEventValueChanged];
    [sw setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ l, sw ]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    [parent addArrangedSubview:row];
}

- (void)addSliderMin:(int)lo max:(int)hi value:(int)value to:(UIStackView *)parent
             changed:(void (^)(int))changed ended:(void (^)(int))ended {
    UISlider *slider = [[UISlider alloc] init];
    slider.minimumValue = lo;
    slider.maximumValue = hi;
    slider.value = Clamp(value, lo, hi);
    void (^onChange)(int) = [changed copy];
    void (^onEnd)(int) = [ended copy];
    [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        if (onChange) onChange((int)lroundf(((UISlider *)a.sender).value));
    }] forControlEvents:UIControlEventValueChanged];
    [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        if (onEnd) onEnd((int)lroundf(((UISlider *)a.sender).value));
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [parent addArrangedSubview:slider];
}

// 選択肢 (Android の Spinner 相当)。タップでメニューが出るボタン
- (void)addChoiceTitle:(NSString *)title labels:(NSArray<NSString *> *)labels
              selected:(NSUInteger)selected changed:(void (^)(NSUInteger))changed {
    [self addCaption:title to:_configStack];
    void (^cb)(NSUInteger) = [changed copy];
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    for (NSUInteger i = 0; i < labels.count; ++i) {
        UIAction *a = [UIAction actionWithTitle:labels[i] image:nil identifier:nil
                                        handler:^(__kindof UIAction *) { cb(i); }];
        if (i == selected) a.state = UIMenuElementStateOn;
        [actions addObject:a];
    }
    UIButtonConfiguration *conf = [UIButtonConfiguration grayButtonConfiguration];
    UIButton *b = [UIButton buttonWithConfiguration:conf primaryAction:nil];
    b.menu = [UIMenu menuWithChildren:actions];
    b.showsMenuAsPrimaryAction = YES;
    b.changesSelectionAsPrimaryAction = YES;   // 選んだ項目がボタンの表示になる
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [_configStack addArrangedSubview:b];
}

@end

// ============================================================
// 権利情報画面
// ============================================================

@implementation KrkrzLicenseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = L(@"menu_license");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    SetupCloseButton(self);

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    tv.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    NSString *text = nil;
    try {
        text = iosconfig::ToNSString(TVPGetLicenseString());
    } catch (...) {
        text = nil;
    }
    tv.text = text.length ? text : L(@"license_placeholder");
    [self.view addSubview:tv];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
    ]];
}

@end
