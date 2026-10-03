#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================
//  AimAssist.dylib — собственный мод 8 Ball Pool
//  Своё меню (UIKit overlay), без ImGui и без Substrate
// ============================================================

#pragma mark - Конфиг

typedef struct {
    BOOL trajectory;   // showCueBallTrajectory
    BOOL wide;         // wideGuideline
    BOOL ruler;        // showFineTuningRuler
    BOOL offlineHide;  // noGuidelinesOffline (нам нужно NO)
} AACfg;

static AACfg g_cfg = { YES, YES, YES, NO };
static BOOL  g_hooksOK = NO;

static NSString *const kP_traj  = @"aa_traj";
static NSString *const kP_wide  = @"aa_wide";
static NSString *const kP_ruler = @"aa_ruler";
static NSString *const kP_off   = @"aa_offhide";

static void cfgLoad(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:kP_traj])  g_cfg.trajectory  = [d boolForKey:kP_traj];
    if ([d objectForKey:kP_wide])  g_cfg.wide        = [d boolForKey:kP_wide];
    if ([d objectForKey:kP_ruler]) g_cfg.ruler       = [d boolForKey:kP_ruler];
    if ([d objectForKey:kP_off])   g_cfg.offlineHide = [d boolForKey:kP_off];
}
static void cfgSave(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:g_cfg.trajectory  forKey:kP_traj];
    [d setBool:g_cfg.wide        forKey:kP_wide];
    [d setBool:g_cfg.ruler       forKey:kP_ruler];
    [d setBool:g_cfg.offlineHide forKey:kP_off];
}

#pragma mark - Хуки UserSettingsManager

static IMP orig_setTraj, orig_setWide, orig_setRuler, orig_setOff;

static BOOL get_traj (id s, SEL c){ return g_cfg.trajectory; }
static BOOL get_wide (id s, SEL c){ return g_cfg.wide; }
static BOOL get_ruler(id s, SEL c){ return g_cfg.ruler; }
static BOOL get_off  (id s, SEL c){ return g_cfg.offlineHide; }

// игра пытается писать своё значение — пишем наше вместо него
static void set_traj (id s, SEL c, BOOL v){ ((void(*)(id,SEL,BOOL))orig_setTraj)(s,c,g_cfg.trajectory); }
static void set_wide (id s, SEL c, BOOL v){ ((void(*)(id,SEL,BOOL))orig_setWide)(s,c,g_cfg.wide); }
static void set_ruler(id s, SEL c, BOOL v){ ((void(*)(id,SEL,BOOL))orig_setRuler)(s,c,g_cfg.ruler); }
static void set_off  (id s, SEL c, BOOL v){ ((void(*)(id,SEL,BOOL))orig_setOff)(s,c,g_cfg.offlineHide); }

static void installHooks(Class cls) {
    Method m;
    m = class_getInstanceMethod(cls, sel_registerName("showCueBallTrajectory"));
    if (m) method_setImplementation(m, (IMP)get_traj);
    m = class_getInstanceMethod(cls, sel_registerName("wideGuideline"));
    if (m) method_setImplementation(m, (IMP)get_wide);
    m = class_getInstanceMethod(cls, sel_registerName("showFineTuningRuler"));
    if (m) method_setImplementation(m, (IMP)get_ruler);
    m = class_getInstanceMethod(cls, sel_registerName("noGuidelinesOffline"));
    if (m) method_setImplementation(m, (IMP)get_off);

    m = class_getInstanceMethod(cls, sel_registerName("setShowCueBallTrajectory:"));
    if (m) orig_setTraj = method_setImplementation(m, (IMP)set_traj);
    m = class_getInstanceMethod(cls, sel_registerName("setWideGuideline:"));
    if (m) orig_setWide = method_setImplementation(m, (IMP)set_wide);
    m = class_getInstanceMethod(cls, sel_registerName("setShowFineTuningRuler:"));
    if (m) orig_setRuler = method_setImplementation(m, (IMP)set_ruler);
    m = class_getInstanceMethod(cls, sel_registerName("setNoGuidelinesOffline:"));
    if (m) orig_setOff  = method_setImplementation(m, (IMP)set_off);

    g_hooksOK = YES;
    NSLog(@"[AimAssist] hooks installed");
}

// прогоняем наши значения через сеттеры (сработают callback-и игры)
static void applyToGame(void) {
    Class cls = objc_getClass("UserSettingsManager");
    if (!cls) return;
    SEL sh = sel_registerName("sharedUserSettingsManager");
    if (!((id(*)(Class,SEL))objc_msgSend)((Class)cls, sel_registerName("respondsToSelector:")) ? NO : ![cls respondsToSelector:sh]) return;
    id s = ((id(*)(Class,SEL))objc_msgSend)((Class)cls, sh);
    if (!s) return;
    ((void(*)(id,SEL,BOOL))objc_msgSend)(s, sel_registerName("setShowCueBallTrajectory:"), g_cfg.trajectory);
    ((void(*)(id,SEL,BOOL))objc_msgSend)(s, sel_registerName("setWideGuideline:"),        g_cfg.wide);
    ((void(*)(id,SEL,BOOL))objc_msgSend)(s, sel_registerName("setShowFineTuningRuler:"),  g_cfg.ruler);
    ((void(*)(id,SEL,BOOL))objc_msgSend)(s, sel_registerName("setNoGuidelinesOffline:"),  g_cfg.offlineHide);
}

#pragma mark - Окно-призрак (тачи мимо меню уходят в игру)

@interface AAWindow : UIWindow
@end
@implementation AAWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self.rootViewController.view) return nil; // прозрачная подложка -> игра
    return v;
}
@end

#pragma mark - Меню

@interface AAUI : NSObject
@property (nonatomic,strong) AAWindow *win;
@property (nonatomic,strong) UIButton *fab;
@property (nonatomic,strong) UIView   *panel;
@property (nonatomic,assign) BOOL      panelShown;
+ (instancetype)shared;
- (void)show;
@end

@implementation AAUI
+ (instancetype)shared { static AAUI *i; static dispatch_once_t t; dispatch_once(&t,^{ i=[AAUI new]; }); return i; }

- (void)show {
    if (self.win) return;
    UIWindowScene *scene = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene*)sc;
            if (sc.activationState == UISceneActivationStateForegroundActive) break;
        }
    }
    AAWindow *w = scene ? [[AAWindow alloc] initWithWindowScene:scene]
                        : [[AAWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.windowLevel = UIWindowLevelAlert + 1;
    w.backgroundColor = [UIColor clearColor];
    w.rootViewController = [UIViewController new];
    w.rootViewController.view.backgroundColor = [UIColor clearColor];
    w.hidden = NO;
    self.win = w;

    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(16, 120, 52, 52);
    b.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.85];
    b.layer.cornerRadius = 26;
    b.layer.borderWidth = 1; b.layer.borderColor = [UIColor cyanColor].CGColor;
    [b setTitle:@"◎" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:26];
    [b addTarget:self action:@selector(fabTap) forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(fabPan:)]];
    [w.rootViewController.view addSubview:b];
    self.fab = b;

    [self buildPanel];
}

- (void)buildPanel {
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0,0,290,330)];
    p.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    p.layer.cornerRadius = 18;
    p.layer.borderWidth = 1; p.layer.borderColor = [UIColor cyanColor].CGColor;
    p.hidden = YES;
    [self.win.rootViewController.view addSubview:p];
    self.panel = p;

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0,12,290,24)];
    t.text = @"AimAssist Menu";
    t.textColor = [UIColor cyanColor];
    t.font = [UIFont boldSystemFontOfSize:17];
    t.textAlignment = NSTextAlignmentCenter;
    [p addSubview:t];

    NSArray *rows = @[
        @[@"Cue Ball Trajectory", @(0)],
        @[@"Wide Guideline",      @(1)],
        @[@"Fine Tuning Ruler",   @(2)],
        @[@"Hide lines offline",  @(3)],
    ];
    CGFloat y = 48;
    for (NSArray *r in rows) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16,y,190,32)];
        l.text = r[0]; l.textColor = [UIColor whiteColor]; l.font = [UIFont systemFontOfSize:15];
        [p addSubview:l];
        UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(205,y-2,80,36)];
        s.tag = [r[1] integerValue];
        switch (s.tag) {
            case 0: s.on = g_cfg.trajectory;  break;
            case 1: s.on = g_cfg.wide;        break;
            case 2: s.on = g_cfg.ruler;       break;
            case 3: s.on = g_cfg.offlineHide; break;
        }
        [s addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
        [p addSubview:s];
        y += 44;
    }
    UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(15,y+2,260,18)];
    st.tag = 99;
    st.textColor = [UIColor lightGrayColor];
    st.font = [UIFont systemFontOfSize:11];
    st.textAlignment = NSTextAlignmentCenter;
    st.text = g_hooksOK ? @"hooks: OK" : @"hooks: waiting...";
    [p addSubview:st];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(95, y+26, 100, 34);
    [close setTitle:@"Close" forState:UIControlStateNormal];
    close.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    close.layer.cornerRadius = 8;
    [close addTarget:self action:@selector(fabTap) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:close];
}

- (void)fabTap {
    self.panelShown = !self.panelShown;
    if (self.panelShown) {
        self.panel.center = self.win.rootViewController.view.center;
        ((UILabel*)[self.panel viewWithTag:99]).text = g_hooksOK ? @"hooks: OK" : @"hooks: waiting...";
        self.panel.alpha = 0; self.panel.hidden = NO;
        [UIView animateWithDuration:0.18 animations:^{ self.panel.alpha = 1; }];
    } else {
        [UIView animateWithDuration:0.15 animations:^{ self.panel.alpha = 0; }
                         completion:^(BOOL f){ self.panel.hidden = YES; }];
    }
}

- (void)fabPan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint tr = [g translationInView:v.superview];
    CGPoint c = v.center; c.x += tr.x; c.y += tr.y;
    CGRect b = v.superview.bounds;
    c.x = MAX(26, MIN(b.size.width -26, c.x));
    c.y = MAX(26, MIN(b.size.height-26, c.y));
    v.center = c;
    [g setTranslation:CGPointZero inView:v.superview];
}

- (void)swChanged:(UISwitch *)s {
    switch (s.tag) {
        case 0: g_cfg.trajectory  = s.on; break;
        case 1: g_cfg.wide        = s.on; break;
        case 2: g_cfg.ruler       = s.on; break;
        case 3: g_cfg.offlineHide = s.on; break;
    }
    cfgSave();
    applyToGame();   // линии переключаются ПРЯМО в игре, без перезахода
}
@end

#pragma mark - Точка входа

__attribute__((constructor))
static void aa_ctor(void) {
    cfgLoad();
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("UserSettingsManager");
        if (cls) { installHooks(cls); applyToGame(); }
        else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Class c2 = objc_getClass("UserSettingsManager");
            if (c2) { installHooks(c2); applyToGame(); }
            else NSLog(@"[AimAssist] ERROR: UserSettingsManager not found");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[AAUI shared] show];
        });
    });
}
