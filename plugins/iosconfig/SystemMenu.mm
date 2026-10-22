// iosconfig - システムメニュー (krkrz_android の左ドロワー相当)。
//
// SDL のウィンドウ (UIWindow) のルートビューの上に、左から出るパネルを重ねる。
// 項目は「設定」「権利情報」と、他のプラグインが KrkrzSystemMenu に登録した項目
// (Game Center など)。開く操作は暫定で左端からのスワイプ
// (ジェスチャー全体の割り当ては他環境も含めて別途検討)。TJS からは
// IosSystemMenu.open() でも開ける。

#import <UIKit/UIKit.h>

#import "IosConfig.h"
#import "ViewControllers.h"

#include <SDL3/SDL.h>

// ---- 他プラグインからの項目登録口 ----
// 依存を持たせないため、使う側は NSClassFromString(@"KrkrzSystemMenu") で引く。
@interface KrkrzSystemMenu : NSObject
// 項目を追加する (同じ identifier なら置き換え)。action はメニューを閉じてから呼ばれる。
+ (void)addItemWithIdentifier:(NSString *)identifier title:(NSString *)title action:(void (^)(void))action;
+ (void)removeItemWithIdentifier:(NSString *)identifier;
// 画面を出すときの親 (SDL のルートビューコントローラ)
+ (UIViewController *)presentingViewController;
@end

@interface KrkrzMenuItem : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) void (^action)(void);
@end
@implementation KrkrzMenuItem
@end

// ---- パネル本体 ----

@interface KrkrzMenuOverlay : UIView
@property (nonatomic, strong) UIControl *dimmer;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIStackView *itemStack;
@property (nonatomic, assign) BOOL open;
- (void)rebuildItems;
- (void)showAnimated:(BOOL)animated;
- (void)hideAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end

namespace {
__weak UIViewController *gRootVC;   // SDL が保持している
KrkrzMenuOverlay *gOverlay;
UIScreenEdgePanGestureRecognizer *gEdgePan;
NSMutableArray<KrkrzMenuItem *> *gExtraItems;
bool gEdgeSwipeEnabled = true;

constexpr CGFloat kPanelWidthMax = 320;
constexpr CGFloat kPanelWidthRatio = 0.45;
constexpr NSTimeInterval kAnimDuration = 0.22;

UIWindow *FindSDLWindow() {
    int count = 0;
    SDL_Window **windows = SDL_GetWindows(&count);
    UIWindow *found = nil;
    if (windows) {
        for (int i = 0; i < count && !found; ++i) {
            SDL_PropertiesID props = SDL_GetWindowProperties(windows[i]);
            found = (__bridge UIWindow *)SDL_GetPointerProperty(
                props, SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, nullptr);
        }
        SDL_free(windows);
    }
    return found;
}

void PresentModal(UIViewController *content) {
    if (!gRootVC) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:content];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [gRootVC presentViewController:nav animated:YES completion:nil];
}
} // namespace

@interface KrkrzEdgePanTarget : NSObject
@end
@implementation KrkrzEdgePanTarget
- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) iosconfig::OpenMenu();
}
@end
static KrkrzEdgePanTarget *gEdgePanTarget;

@implementation KrkrzMenuOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.hidden = YES;

        _dimmer = [[UIControl alloc] initWithFrame:self.bounds];
        _dimmer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
        [_dimmer addTarget:self action:@selector(dimmerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_dimmer];

        _panel = [[UIView alloc] init];
        _panel.backgroundColor = iosconfig::OpaqueBackground(UIColor.systemBackgroundColor);
        [self addSubview:_panel];

        UISwipeGestureRecognizer *swipe =
            [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dimmerTapped)];
        swipe.direction = UISwipeGestureRecognizerDirectionLeft;
        [self addGestureRecognizer:swipe];

        [self buildPanel];
    }
    return self;
}

- (void)buildPanel {
    // ヘッダ (アプリ名 + 「メニュー」)。Android の krkrz_drawer_header と同じ構成
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.systemIndigoColor;
    [_panel addSubview:header];

    NSString *appName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
        ?: [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"krkrz";
    UILabel *title = [[UILabel alloc] init];
    title.text = appName;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    title.textColor = UIColor.whiteColor;
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = iosconfig::L(@"drawer_header_subtitle");
    subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    UIStackView *headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[ title, subtitle ]];
    headerStack.axis = UILayoutConstraintAxisVertical;
    headerStack.spacing = 2;
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:headerStack];

    _itemStack = [[UIStackView alloc] init];
    _itemStack.axis = UILayoutConstraintAxisVertical;
    _itemStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:_itemStack];

    UILayoutGuide *safe = _panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:_panel.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor],
        [headerStack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [headerStack.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-16],
        [headerStack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],
        [headerStack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16],
        [_itemStack.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [_itemStack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_itemStack.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor],
    ]];
}

- (UIButton *)makeItemButton:(NSString *)titleText action:(void (^)(void))action {
    UIButtonConfiguration *conf = [UIButtonConfiguration plainButtonConfiguration];
    conf.title = titleText;
    conf.baseForegroundColor = UIColor.labelColor;
    conf.contentInsets = NSDirectionalEdgeInsetsMake(14, 16, 14, 16);
    void (^act)(void) = [action copy];
    UIButton *b = [UIButton buttonWithConfiguration:conf primaryAction:
        [UIAction actionWithHandler:^(__kindof UIAction *) {
            iosconfig::CloseMenu();
            if (act) act();
        }]];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    return b;
}

- (void)rebuildItems {
    for (UIView *v in _itemStack.arrangedSubviews) {
        [_itemStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [_itemStack addArrangedSubview:[self makeItemButton:iosconfig::L(@"menu_settings") action:^{
        iosconfig::OpenSettings();
    }]];
    [_itemStack addArrangedSubview:[self makeItemButton:iosconfig::L(@"menu_license") action:^{
        iosconfig::OpenLicense();
    }]];
    for (KrkrzMenuItem *item in gExtraItems) {
        [_itemStack addArrangedSubview:[self makeItemButton:item.title action:item.action]];
    }
}

- (CGFloat)panelWidth {
    CGFloat w = self.bounds.size.width * kPanelWidthRatio + self.safeAreaInsets.left;
    return MIN(w, kPanelWidthMax + self.safeAreaInsets.left);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = [self panelWidth];
    CGRect f = CGRectMake(_open ? 0 : -w, 0, w, self.bounds.size.height);
    _panel.frame = f;
}

- (void)showAnimated:(BOOL)animated {
    if (_open) return;
    _open = YES;
    [self.superview bringSubviewToFront:self];
    self.hidden = NO;
    [self rebuildItems];
    CGFloat w = [self panelWidth];
    _panel.frame = CGRectMake(-w, 0, w, self.bounds.size.height);
    _dimmer.alpha = 0;
    [UIView animateWithDuration:animated ? kAnimDuration : 0 animations:^{
        self.panel.frame = CGRectMake(0, 0, w, self.bounds.size.height);
        self.dimmer.alpha = 1;
    }];
}

- (void)hideAnimated:(BOOL)animated completion:(void (^)(void))completion {
    if (!_open) {
        if (completion) completion();
        return;
    }
    _open = NO;
    CGFloat w = [self panelWidth];
    [UIView animateWithDuration:animated ? kAnimDuration : 0 animations:^{
        self.panel.frame = CGRectMake(-w, 0, w, self.bounds.size.height);
        self.dimmer.alpha = 0;
    } completion:^(BOOL) {
        if (!self.open) self.hidden = YES;
        if (completion) completion();
    }];
}

- (void)dimmerTapped {
    iosconfig::CloseMenu();
}

@end

@implementation KrkrzSystemMenu

+ (void)addItemWithIdentifier:(NSString *)identifier title:(NSString *)title action:(void (^)(void))action {
    if (!gExtraItems) gExtraItems = [NSMutableArray array];
    [self removeItemWithIdentifier:identifier];
    KrkrzMenuItem *item = [[KrkrzMenuItem alloc] init];
    item.identifier = identifier;
    item.title = title;
    item.action = action;
    [gExtraItems addObject:item];
    if (gOverlay.open) [gOverlay rebuildItems];
}

+ (void)removeItemWithIdentifier:(NSString *)identifier {
    NSIndexSet *idx = [gExtraItems indexesOfObjectsPassingTest:^BOOL(KrkrzMenuItem *it, NSUInteger, BOOL *) {
        return [it.identifier isEqualToString:identifier];
    }];
    [gExtraItems removeObjectsAtIndexes:idx];
    if (gOverlay.open) [gOverlay rebuildItems];
}

+ (UIViewController *)presentingViewController {
    UIViewController *vc = gRootVC;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

@end

namespace iosconfig {

UIColor *OpaqueBackground(UIColor *base) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        UIColor *c = [base resolvedColorWithTraitCollection:tc];
        CGFloat r = 0, g = 0, b = 0, a = 0;
        if ([c getRed:&r green:&g blue:&b alpha:&a] && r < 0.02 && g < 0.02 && b < 0.02)
            return [UIColor colorWithWhite:0.07 alpha:1.0];
        return [c colorWithAlphaComponent:1.0];
    }];
}

void InstallMenuIfReady() {
    if (gOverlay) return;
    UIWindow *window = FindSDLWindow();
    UIViewController *root = window.rootViewController;
    if (!root || !root.view) return;
    gRootVC = root;

    gOverlay = [[KrkrzMenuOverlay alloc] initWithFrame:root.view.bounds];
    [root.view addSubview:gOverlay];

    gEdgePanTarget = [[KrkrzEdgePanTarget alloc] init];
    gEdgePan = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:gEdgePanTarget
                                                                 action:@selector(handleEdgePan:)];
    gEdgePan.edges = UIRectEdgeLeft;
    gEdgePan.enabled = gEdgeSwipeEnabled;
    [root.view addGestureRecognizer:gEdgePan];
}

void OpenMenu() {
    InstallMenuIfReady();
    if (gRootVC.presentedViewController) return;   // 設定画面などを表示中
    [gOverlay showAnimated:YES];
}

void OpenSettings() {
    InstallMenuIfReady();
    if (gRootVC.presentedViewController) return;
    PresentModal([[KrkrzSettingsViewController alloc] init]);
}

void OpenLicense() {
    InstallMenuIfReady();
    if (gRootVC.presentedViewController) return;
    PresentModal([[KrkrzLicenseViewController alloc] init]);
}

void CloseMenu() {
    [gOverlay hideAnimated:YES completion:nil];
}

bool IsMenuOpen() {
    return gOverlay && gOverlay.open;
}

void SetEdgeSwipeEnabled(bool enabled) {
    gEdgeSwipeEnabled = enabled;
    gEdgePan.enabled = enabled;
}

void ShutdownMenu() {
    if (gEdgePan) [gEdgePan.view removeGestureRecognizer:gEdgePan];
    [gOverlay removeFromSuperview];
    gEdgePan = nil;
    gEdgePanTarget = nil;
    gOverlay = nil;
    gRootVC = nil;
}

} // namespace iosconfig
