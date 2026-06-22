//
//  SPAppController.m
//  sequel-pro
//
//  Created by Lorenz Textor (lorenz@textor.ch) on May 1, 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
//  Copyright (c) 2012 Sequel Pro Team. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPAppController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SPDatabaseDocument.h"
#import "SPPreferenceController.h"
#import "SPDataImport.h"
#import "SPEncodingPopupAccessory.h"
#import "SPPreferencesUpgrade.h"
#import "SPBundleEditorController.h"
#import "SPTooltip.h"
#import "SPChooseMenuItemDialog.h"
#import "SPCustomQuery.h"
#import "SPFavoritesController.h"
#import "SPEditorTokens.h"
#import "SPBundleCommandRunner.h"
#import "SPCopyTable.h"
#import "SPSyntaxParser.h"
#import "SPTextView.h"
#import "SPFunctions.h"
#import "SPBundleManager.h"
#import "MGTemplateEngine.h"
#import "ICUTemplateMatcher.h"
#import "SPTreeNode.h"
#import "SPConnectionController.h"
#import "SPFavoritesOutlineView.h"
#import "SPQueryController.h"
#import "SPNavigatorController.h"
#import "SPTablesList.h"
#import "SPKeychain.h"
#import "SPDataAdditions.h"

#import "sequel-ace-Swift.h"

#import <os/log.h>

@import FirebaseCore;
@import FirebaseAnalytics;
@import FirebaseCrashlytics;

static const double SPDelayBeforeCheckingForNewReleases = 10;
static NSString *SALightweightResumeFileName = @"LightweightResume.plist";
static NSString *SALightweightResumeStateDidChangeNotification = @"SALightweightResumeStateDidChangeNotification";
static NSString *SALightweightResumeConsoleKey = @"console";
static NSString *SALightweightResumeConsoleVisibleKey = @"visible";
static NSString *SALightweightResumeConsoleFrameKey = @"frame";
static const NSTimeInterval SALightweightResumeSaveDebounce = 5.0;
static const NSTimeInterval SAUIDiagnosticsWatchdogInterval = 1.0;
static const NSTimeInterval SAUIDiagnosticsStallThreshold = 2.0;
static const NSTimeInterval SAUIDiagnosticsMainThreadDelayThreshold = 0.5;
static const NSTimeInterval SAUIDiagnosticsSlowMenuValidationThreshold = 0.1;
static const NSTimeInterval SAUIDiagnosticsSlowWindowTimingThreshold = 0.1;
static const NSInteger SALightweightTableObjectTypeTableValue = 0;
static const NSInteger SALightweightTableObjectTypeViewValue = 1;
static const NSInteger SALightweightTableObjectTypeProcedureValue = 2;
static const NSInteger SALightweightTableObjectTypeFunctionValue = 3;

#define SAUIDiagnosticLog(fmt, ...) \
    do { \
        if (SAUIDiagnosticsEnabled()) { \
            SAUIDiagnosticLogMessage((@"[SA UI Diagnostics] " fmt), ##__VA_ARGS__); \
        } \
    } while (0)

static BOOL SAUIDiagnosticsEnabled(void)
{
    static BOOL enabled;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *environmentValue = [[[NSProcessInfo processInfo] environment] objectForKey:@"SA_ENABLE_UI_DIAGNOSTICS"];
        enabled = [environmentValue boolValue] || [[NSUserDefaults standardUserDefaults] boolForKey:@"SAEnableUIDiagnostics"];
    });

    return enabled;
}

static void SAUIDiagnosticLogMessage(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void SAUIDiagnosticLogMessage(NSString *format, ...)
{
    if (!SAUIDiagnosticsEnabled()) {
        return;
    }

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    os_log(OS_LOG_DEFAULT, "%{public}@", message);
}

static NSTimeInterval SAUIMonotonicTime(void)
{
    return [[NSProcessInfo processInfo] systemUptime];
}

typedef NS_ENUM(NSUInteger, SALightweightConnectionFileOpenResult) {
    SALightweightConnectionFileOpenUnsupported = 0,
    SALightweightConnectionFileOpenSucceeded,
    SALightweightConnectionFileOpenHandledFailure
};

@interface SPAppController ()
@property (strong) IBOutlet NSMenu *mainMenu;
@property (assign) BOOL lightweightTableMenuIsConfigured;

- (void)_copyDefaultThemes;

- (void)openConnectionFileAtPath:(NSString *)filePath;
- (SALightweightConnectionFileOpenResult)openLightweightConnectionFileAtPath:(NSString *)filePath windowController:(SPWindowController *)windowController;
- (SALightweightConnectionFileOpenResult)openLightweightConnectionFileAtPath:(NSString *)filePath windowController:(SPWindowController *)windowController savedInBundle:(BOOL)savedInBundle;
- (BOOL)applyLightweightStateDictionary:(NSDictionary *)state toWindowController:(SPWindowController *)windowController;
- (BOOL)lightweightStateDictionaryRequestsAutoConnect:(NSDictionary *)state;
- (BOOL)lightweightConnectionFileRequiresLegacyPreferences:(NSDictionary *)spf data:(NSDictionary *)data connection:(NSDictionary *)connection;
- (NSDictionary *)lightweightConnectionDocumentContextFromSPF:(NSDictionary *)spf data:(NSDictionary *)data;
- (NSDictionary *)lightweightSessionSnapshotFromLegacySession:(NSDictionary *)session connection:(NSDictionary *)connection;
- (BOOL)lightweightConnectionDataIncludesQuery:(NSDictionary *)data lightweightSession:(NSDictionary *)lightweightSession;
- (BOOL)lightweightLegacySessionQueriesObjectIsSupported:(id)queriesObject;
- (NSString *)lightweightQueryStringFromLegacySessionQueriesObject:(id)queriesObject;
- (void)populateLightweightKeychainReferencesInConnection:(NSMutableDictionary *)connection;
- (NSString *)promptForLightweightEncryptedConnectionFilePasswordAtPath:(NSString *)filePath;
- (NSDictionary *)lightweightConnectionDataFromEncryptedSPF:(NSDictionary *)spf password:(NSString *)password;
- (void)showLightweightConnectionFileReadError:(NSString *)message;
- (void)openSQLFileAtPath:(NSString *)filePath;
- (void)openSessionBundleAtPath:(NSString *)filePath;
- (void)openColorThemeFileAtPath:(NSString *)filePath;
- (void)checkForNewVersionWithDelay:(double)delay andIsFromMenuCheck:(BOOL)isFromMenuCheck;
- (void)removeCheckForUpdatesMenuItem;
- (void)addCheckForUpdatesMenuItem;
- (void)checkForNewVersionFromMenu;
- (NSString *)lightweightResumeFilePath;
- (NSDictionary *)lightweightResumeStateDictionary;
- (NSDictionary *)lightweightConsoleResumeStateDictionary;
- (NSString *)frameStringForWindowGroupContainingWindow:(NSWindow *)window;
- (BOOL)restoreLightweightResumeState;
- (void)restoreLightweightConsoleResumeStateDictionary:(NSDictionary *)consoleState;
- (BOOL)applyLightweightResumeFrameString:(NSString *)frameString toWindow:(NSWindow *)window;
- (BOOL)applyLightweightResumeFrameString:(NSString *)frameString toWindow:(NSWindow *)window minimumSize:(NSSize)minimumSize;
- (BOOL)shouldStartEmptySessionFromLaunchModifierFlags;
- (void)saveLightweightResumeState;
- (void)lightweightResumeStateDidChange:(NSNotification *)notification;
- (void)lightweightWindowFrameDidChange:(NSNotification *)notification;
- (void)windowWillClose:(NSNotification *)notification;
- (void)scheduleLightweightResumeStateSave;
- (void)savePendingLightweightResumeStateIfNeeded;
- (void)cancelScheduledLightweightResumeStateSave;
- (BOOL)bundleCommandScope:(NSString *)scope canRunWithFirstResponder:(id)firstResponder;
- (BOOL)bundleCommandMenuItemCanRun:(NSMenuItem *)menuItem;
- (void)resetTableMenuState;
- (void)restoreTableMenuStateForDatabaseDocument:(SPDatabaseDocument *)document;
- (void)configureLightweightTableMenuForWindowController:(SPWindowController *)windowController;
- (BOOL)validateLightweightTableMaintenanceMenuItem:(NSMenuItem *)menuItem forWindowController:(SPWindowController *)windowController;
- (SPDatabaseDocument *)connectedDatabaseDocumentForWindowController:(SPWindowController *)windowController;
- (BOOL)windowControllerHasActiveConnectionTarget:(SPWindowController *)windowController;
- (SPWindowController *)keyWindowControllerWithActiveConnectionTarget;
- (SPWindowController *)bundleEnvironmentWindowController;
- (SPWindowController *)windowControllerForBundleProcessID:(NSString *)processID;
- (NSDictionary *)shellEnvironmentForWindowController:(SPWindowController *)windowController;
- (void)addBundleCallbackEnvironmentToDictionary:(NSMutableDictionary *)environment processID:(NSString *)processID;
- (void)_startUIDiagnosticsIfNeeded;
- (void)_uiDiagnosticsWatchdogTick;
- (NSString *)_uiDiagnosticsContext;
- (NSString *)_uiDiagnosticsContextForWindow:(NSWindow *)window;
- (void)_logUIDiagnosticsWindowTiming:(NSString *)operation window:(NSWindow *)window startTime:(NSTimeInterval)startTime;
- (void)_uiDiagnosticsWindowDidResize:(NSNotification *)notification;
- (void)_uiDiagnosticsWindowDidUpdate:(NSNotification *)notification;

@property (readwrite, strong) NSFileManager *fileManager;

@property (nonatomic, strong, readwrite) TabManager *tabManager;
@property (nonatomic, assign) BOOL lightweightResumeStateDirty;
@property (nonatomic, assign) BOOL lightweightResumeSaveScheduled;
@property (nonatomic, strong) NSData *lastLightweightResumeStateData;
@property (nonatomic, strong) dispatch_source_t uiDiagnosticsWatchdogTimer;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *uiDiagnosticsWindowUpdateStartTimes;
@property (atomic, assign) BOOL uiDiagnosticsBeatPending;
@property (atomic, assign) NSUInteger uiDiagnosticsLastReportedStallSecond;
@property (atomic, assign) NSTimeInterval uiDiagnosticsLastBeatTime;
@property (atomic, assign) NSTimeInterval uiDiagnosticsPendingBeatTime;
@property (atomic, assign) NSTimeInterval uiDiagnosticsActivationStartTime;
@property (atomic, assign) NSTimeInterval uiDiagnosticsResignStartTime;

@end

@implementation SPAppController

@synthesize lastBundleBlobFilesDirectory;
@synthesize fileManager;
@synthesize mainMenu;
@synthesize sshProcessIDs;
#pragma mark -
#pragma mark Initialisation

/**
 * Initialise the application's main controller, setting itself as the app delegate.
 */
- (instancetype)init
{
    if ((self = [super init])) {
        aboutController = nil;
        lastBundleBlobFilesDirectory = nil;
        _spfSessionDocData = [[NSMutableDictionary alloc] init];

        runningActivitiesArray = [[NSMutableArray alloc] init];
        sshProcessIDs = [[NSMutableArray alloc] init];
        fileManager = [NSFileManager defaultManager];
        _tabManager = [[TabManager alloc] initWithAppController:self];

        //Create runtime directiories
        [fileManager createDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"tmp"] withIntermediateDirectories:true attributes:nil error:nil];
        [fileManager createDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@".keys"] withIntermediateDirectories:true attributes:nil error:nil];

        //Handle Appearance on macOS 10.14+
        if (@available(macOS 10.14, *)) {
            //Switch Appearance on Application startup (prevent Appearance blink)
            [self switchAppearance];

            //Register an observer to switch Appearance at runtime
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(defaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
        }
        [NSApp setDelegate:self];
    }
    return self;
}

/**
 * Called even before init so we can register our preference defaults
 */
+ (void)initialize
{
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

    NSMutableDictionary *preferenceDefaults = [NSMutableDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:SPPreferenceDefaultsFile ofType:@"plist"]];
    // Register application defaults
    [prefs registerDefaults:preferenceDefaults];

    // Upgrade prefs before any other parts of the app pick up on the values
    SPApplyRevisionChanges();
}

/**
 * Called when default properties had a change at runtime
 */
- (void)defaultsChanged:(NSNotification *)notification {
    [self switchAppearance];
}

/**
 * Called when need to switch application appearance - on startup and when userDefaults changed
 */
- (void)switchAppearance {
    SPMainQSync(^{
        if (@available(macOS 10.14, *)) {
            NSInteger appearance = [[NSUserDefaults standardUserDefaults] integerForKey:SPAppearance];

            if (appearance == 1) {
                NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            } else if (appearance == 2) {
                NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            } else {
                NSApp.appearance = nil;
            }
        }
    });
}

/**
 * Close any open font panels to avoid them reopening on next launch
 */
- (void)closeFontPanelIfOpen {
    NSFontPanel *fontPanel = [[NSFontManager sharedFontManager] fontPanel:NO];
    if (fontPanel && [fontPanel isVisible]) {
        [fontPanel close];
    }
}

/**
 * Initialisation stuff upon nib awakening
 */
- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // Register url scheme handle
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(handleEvent:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];

    // Set up the prefs controller
    prefsController = [[SPPreferenceController alloc] init];

    // Register SPAppController as services provider
    [NSApp setServicesProvider:self];

    // Register SPAppController for AppleScript events
    [[NSScriptExecutionContext sharedScriptExecutionContext] setTopLevelObject:self];
}

#pragma mark -
#pragma mark UI Diagnostics

- (void)_startUIDiagnosticsIfNeeded
{
    if (!SAUIDiagnosticsEnabled() || self.uiDiagnosticsWatchdogTimer) {
        return;
    }

    self.uiDiagnosticsLastBeatTime = SAUIMonotonicTime();
    self.uiDiagnosticsWindowUpdateStartTimes = [NSMutableDictionary dictionary];

    dispatch_queue_t watchdogQueue = dispatch_queue_create("com.sequel-ace.ui-diagnostics.watchdog", DISPATCH_QUEUE_SERIAL);
    self.uiDiagnosticsWatchdogTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, watchdogQueue);
    uint64_t watchdogInterval = (uint64_t)(SAUIDiagnosticsWatchdogInterval * NSEC_PER_SEC);
    dispatch_source_set_timer(self.uiDiagnosticsWatchdogTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)watchdogInterval), watchdogInterval, NSEC_PER_MSEC * 100);

    __weak SPAppController *weakSelf = self;
    dispatch_source_set_event_handler(self.uiDiagnosticsWatchdogTimer, ^{
        [weakSelf _uiDiagnosticsWatchdogTick];
    });

    dispatch_resume(self.uiDiagnosticsWatchdogTimer);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_uiDiagnosticsWindowDidResize:) name:NSWindowDidResizeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_uiDiagnosticsWindowDidUpdate:) name:NSWindowDidUpdateNotification object:nil];

    SAUIDiagnosticLog(@"enabled via SA_ENABLE_UI_DIAGNOSTICS/SAEnableUIDiagnostics watchdogInterval=%.1fs stallThreshold=%.1fs",
            SAUIDiagnosticsWatchdogInterval,
            SAUIDiagnosticsStallThreshold);
}

- (void)_uiDiagnosticsWatchdogTick
{
    if (!SAUIDiagnosticsEnabled()) {
        return;
    }

    NSTimeInterval now = SAUIMonotonicTime();

    if (self.uiDiagnosticsBeatPending) {
        NSTimeInterval stallDuration = now - self.uiDiagnosticsPendingBeatTime;
        if (stallDuration >= SAUIDiagnosticsStallThreshold) {
            NSUInteger stallSecond = (NSUInteger)stallDuration;
            if (stallSecond != self.uiDiagnosticsLastReportedStallSecond) {
                self.uiDiagnosticsLastReportedStallSecond = stallSecond;
                SAUIDiagnosticLog(@"main thread has not serviced watchdog for %.3fs lastBeatAge=%.3fs",
                        stallDuration,
                        now - self.uiDiagnosticsLastBeatTime);
            }
        }
        return;
    }

    self.uiDiagnosticsBeatPending = YES;
    self.uiDiagnosticsPendingBeatTime = now;

    __weak SPAppController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SPAppController *strongSelf = weakSelf;
        if (!strongSelf || !SAUIDiagnosticsEnabled()) {
            return;
        }

        NSTimeInterval resumedAt = SAUIMonotonicTime();
        NSTimeInterval delay = resumedAt - strongSelf.uiDiagnosticsPendingBeatTime;
        if (delay >= SAUIDiagnosticsMainThreadDelayThreshold) {
            SAUIDiagnosticLog(@"main thread serviced watchdog after %.3fs context=%@", delay, [strongSelf _uiDiagnosticsContext]);
        }

        strongSelf.uiDiagnosticsBeatPending = NO;
        strongSelf.uiDiagnosticsLastReportedStallSecond = 0;
        strongSelf.uiDiagnosticsLastBeatTime = resumedAt;
    });
}

- (NSString *)_uiDiagnosticsContext
{
    if (!SAUIDiagnosticsEnabled()) {
        return @"disabled";
    }

    if (![NSThread isMainThread]) {
        return @"non-main-thread";
    }

    NSWindow *keyWindow = [NSApp keyWindow];
    NSWindow *mainWindow = [NSApp mainWindow];
    id firstResponder = keyWindow.firstResponder;
    NSUInteger managedWindows = self.tabManager.windowControllers.count;
    NSUInteger appWindows = NSApp.windows.count;

    return [NSString stringWithFormat:@"active=%d keyWindow=%@ mainWindow=%@ firstResponder=%@ managedWindows=%lu appWindows=%lu",
            NSApp.isActive,
            keyWindow ? NSStringFromClass([keyWindow class]) : @"nil",
            mainWindow ? NSStringFromClass([mainWindow class]) : @"nil",
            firstResponder ? NSStringFromClass([firstResponder class]) : @"nil",
            (unsigned long)managedWindows,
            (unsigned long)appWindows];
}

- (NSString *)_uiDiagnosticsContextForWindow:(NSWindow *)window
{
    if (!SAUIDiagnosticsEnabled()) {
        return @"disabled";
    }

    if (![NSThread isMainThread]) {
        return @"non-main-thread";
    }

    if (!window) {
        return @"window=nil";
    }

    return [NSString stringWithFormat:@"window=%@ controller=%@ contentView=%@ visible=%d key=%d main=%d frame=%@",
            NSStringFromClass([window class]),
            window.windowController ? NSStringFromClass([window.windowController class]) : @"nil",
            window.contentView ? NSStringFromClass([window.contentView class]) : @"nil",
            window.isVisible,
            window.isKeyWindow,
            window.isMainWindow,
            NSStringFromRect(window.frame)];
}

- (void)_logUIDiagnosticsWindowTiming:(NSString *)operation window:(NSWindow *)window startTime:(NSTimeInterval)startTime
{
    if (!SAUIDiagnosticsEnabled()) {
        return;
    }

    NSTimeInterval elapsed = SAUIMonotonicTime() - startTime;
    if (elapsed >= SAUIDiagnosticsSlowWindowTimingThreshold) {
        SAUIDiagnosticLog(@"slow window %@ elapsed=%.3fs context=%@", operation, elapsed, [self _uiDiagnosticsContextForWindow:window]);
    }
}

- (void)_uiDiagnosticsWindowDidResize:(NSNotification *)notification
{
    if (!SAUIDiagnosticsEnabled() || ![NSThread isMainThread] || ![notification.object isKindOfClass:[NSWindow class]]) {
        return;
    }

    NSValue *windowKey = [NSValue valueWithNonretainedObject:notification.object];
    if (![self.uiDiagnosticsWindowUpdateStartTimes objectForKey:windowKey]) {
        [self.uiDiagnosticsWindowUpdateStartTimes setObject:@(SAUIMonotonicTime()) forKey:windowKey];
    }
}

- (void)_uiDiagnosticsWindowDidUpdate:(NSNotification *)notification
{
    if (!SAUIDiagnosticsEnabled() || ![NSThread isMainThread] || ![notification.object isKindOfClass:[NSWindow class]]) {
        return;
    }

    NSWindow *window = notification.object;
    NSValue *windowKey = [NSValue valueWithNonretainedObject:window];
    NSNumber *startTime = [self.uiDiagnosticsWindowUpdateStartTimes objectForKey:windowKey];
    if (!startTime) {
        return;
    }

    [self.uiDiagnosticsWindowUpdateStartTimes removeObjectForKey:windowKey];

    NSTimeInterval elapsed = SAUIMonotonicTime() - startTime.doubleValue;
    if (elapsed >= SAUIDiagnosticsSlowWindowTimingThreshold) {
        SAUIDiagnosticLog(@"slow window resize/update elapsed=%.3fs context=%@", elapsed, [self _uiDiagnosticsContextForWindow:window]);
    }
}

- (void)applicationWillBecomeActive:(NSNotification *)notification
{
    if (!SAUIDiagnosticsEnabled()) {
        return;
    }

    self.uiDiagnosticsActivationStartTime = SAUIMonotonicTime();
    SAUIDiagnosticLog(@"applicationWillBecomeActive context=%@", [self _uiDiagnosticsContext]);
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    if (!SAUIDiagnosticsEnabled()) {
        return;
    }

    NSTimeInterval didBecomeActiveTime = SAUIMonotonicTime();
    NSTimeInterval activationElapsed = self.uiDiagnosticsActivationStartTime > 0 ? didBecomeActiveTime - self.uiDiagnosticsActivationStartTime : 0;
    SAUIDiagnosticLog(@"applicationDidBecomeActive elapsedSinceWill=%.3fs context=%@", activationElapsed, [self _uiDiagnosticsContext]);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (SAUIDiagnosticsEnabled()) {
            SAUIDiagnosticLog(@"applicationDidBecomeActive next-runloop elapsedSinceDid=%.3fs context=%@", SAUIMonotonicTime() - didBecomeActiveTime, [self _uiDiagnosticsContext]);
        }
    });
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    if (!SAUIDiagnosticsEnabled()) {
        return;
    }

    self.uiDiagnosticsResignStartTime = SAUIMonotonicTime();
    SAUIDiagnosticLog(@"applicationWillResignActive context=%@", [self _uiDiagnosticsContext]);
}

- (void)applicationDidResignActive:(NSNotification *)notification
{
    [self savePendingLightweightResumeStateIfNeeded];

    if (!SAUIDiagnosticsEnabled()) {
        return;
    }

    NSTimeInterval elapsed = self.uiDiagnosticsResignStartTime > 0 ? SAUIMonotonicTime() - self.uiDiagnosticsResignStartTime : 0;
    SAUIDiagnosticLog(@"applicationDidResignActive elapsedSinceWill=%.3fs context=%@", elapsed, [self _uiDiagnosticsContext]);
}

/**
 * Initialisation stuff after launch is complete
 */
- (void)applicationDidFinishLaunching:(NSNotification *)notification {

    [FIRApp configure];
    [self _startUIDiagnosticsIfNeeded];
    SAUIDiagnosticLog(@"applicationDidFinishLaunching context=%@", [self _uiDiagnosticsContext]);

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    BOOL analyticsEnabled = [prefs boolForKey:SPSaveApplicationUsageAnalytics];
    [FIRAnalytics setAnalyticsCollectionEnabled:analyticsEnabled];
    [[FIRCrashlytics crashlytics] setCrashlyticsCollectionEnabled:analyticsEnabled];


    // this reRequests access to all bookmarks
    SecureBookmarkManager *secureBookmarkManager = SecureBookmarkManager.sharedInstance;

    // prompt user to recreate secure bookmarks
    if(secureBookmarkManager.staleBookmarks.count > 0){

        SPLog(@"We have stale bookmarks");

        NSMutableArray<NSString *> *staleBookmarkPaths = [[NSMutableArray alloc] initWithCapacity:secureBookmarkManager.staleBookmarks.count];

        for(NSString* staleFile in secureBookmarkManager.staleBookmarks){
            [staleBookmarkPaths addObject:staleFile];
            SPLog(@"fileNames adding stale file: %@", staleFile.lastPathComponent);
        }

        [NSAlert createScrollableListAccessoryAlertWithTitle:NSLocalizedString(@"App Sandbox Issue", @"App Sandbox Issue")
                                                     message:[SABookmarkAlertContent staleBookmarksMessageWithCount:secureBookmarkManager.staleBookmarks.count]
                                                   listItems:[SABookmarkAlertContent displayNamesForBookmarkPaths:staleBookmarkPaths]
                                               accessoryView:_staleBookmarkHelpView
                                          primaryButtonTitle:NSLocalizedString(@"Open Files Preferences", @"open files preferences button")
                                        secondaryButtonTitle:NSLocalizedString(@"Continue", @"continue launching button")
                          primaryButtonHandler:^{
            SPLog(@"re-request access now");
            [self->prefsController showWindow:self];
            [self->prefsController displayPreferencePane:self->prefsController->fileItem];
        } secondaryButtonHandler:^{
            SPLog(@"Continue launching with stale bookmarks");
        }];
    }

    // init SQLite query history
    SQLiteHistoryManager __unused *sqliteHistoryManager = SQLiteHistoryManager.sharedInstance;
    SQLitePinnedTableManager __unused *sqLitePinnedTableManager = SQLitePinnedTableManager.sharedInstance;

    NSDictionary *spfDict = nil;
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    if (args.count == 5) {
        if (([[args objectAtIndex:1] isEqualToString:@"--spfData"] && [[args objectAtIndex:3] isEqualToString:@"--dataVersion"] && [[args objectAtIndex:4] isEqualToString:@"1"]) || ([[args objectAtIndex:3] isEqualToString:@"--spfData"] && [[args objectAtIndex:1] isEqualToString:@"--dataVersion"] && [[args objectAtIndex:2] isEqualToString:@"1"])) {
            NSData* data = [[args objectAtIndex:2] dataUsingEncoding:NSUTF8StringEncoding];
            NSError *error = nil;
            spfDict = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
            if (error) {
                spfDict = nil;
            }
        }
    }
    executeOnBackgroundThread(^{
        // fake the dbViewInfoPanelSplit being open
        NSMutableArray *dbViewInfoPanelSplit = [[NSMutableArray alloc] initWithCapacity:2];
        [dbViewInfoPanelSplit addObject:@"0.000000, 0.000000, 359.500000, 577.500000, NO, NO"];
        [dbViewInfoPanelSplit addObject:@"0.000000, 586.500000, 359.500000, 190.500000, NO, NO"];
        [prefs setObject:dbViewInfoPanelSplit forKey:@"NSSplitView Subview Frames DbViewInfoPanelSplit"];
    });

    [self checkForNewVersionWithDelay:SPDelayBeforeCheckingForNewReleases andIsFromMenuCheck:NO];

    // Add menu item to check for updates
    [self addCheckForUpdatesMenuItem];

    [prefs addObserver:self forKeyPath:SPShowUpdateAvailable options:NSKeyValueObservingOptionNew context:NULL];

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(externalApplicationWantsToOpenADatabaseConnection:) name:@"ExternalApplicationWantsToOpenADatabaseConnection" object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(duplicateConnectionToTab:) name:SPDocumentDuplicateTabNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(switchToPreviousTab:) name:SPWindowSelectPreviousTabNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(switchToNextTab:) name:SPWindowSelectNextTabNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveConnectionsToSPF:) name:SPDocumentSaveToSPFNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lightweightResumeStateDidChange:) name:SALightweightResumeStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lightweightWindowFrameDidChange:) name:NSWindowDidMoveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lightweightWindowFrameDidChange:) name:NSWindowDidResizeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:nil];

    [self installFastQuitMenuAction];

    [SPBundleManager.shared reloadBundles:self];
    [self _copyDefaultThemes];

    BOOL startEmptySession = [self shouldStartEmptySessionFromLaunchModifierFlags];
    if (startEmptySession) {
        SPLog(@"Skipping startup connection restore because Shift or Option was held during launch");
        spfDict = nil;
    }

    BOOL restoredLightweightWindows = NO;
    if (!spfDict && !startEmptySession) {
        restoredLightweightWindows = [self restoreLightweightResumeState];
    }

    // If no documents are open, open one
    if (![self frontDocument] && !restoredLightweightWindows) {

        SPWindowController *newWindowController = [self.tabManager replaceTabServiceWithInitialWindow];

        BOOL appliedLaunchStateLightweight = NO;
        if (spfDict && !startEmptySession) {
            appliedLaunchStateLightweight = [self applyLightweightStateDictionary:spfDict toWindowController:newWindowController];
            if (!appliedLaunchStateLightweight) {
                [[newWindowController legacyDatabaseDocumentForExplicitFallbackWithReason:@"Startup SPF restore required legacy database view"] setState:spfDict];
            }
        }

        // Set autoconnection if appropriate
        if (!startEmptySession && [prefs boolForKey:SPAutoConnectToDefault] && secureBookmarkManager.staleBookmarks.count == 0) {
            if (spfDict) {
                if (appliedLaunchStateLightweight) {
                    if (![self lightweightStateDictionaryRequestsAutoConnect:spfDict]) {
                        [newWindowController connectSelectedLightweightConnection];
                    }
                    return;
                }
            }
            else {
                if ([newWindowController connectSelectedLightweightConnection]) {
                    return;
                }
            }

            [[newWindowController legacyDatabaseDocumentForExplicitFallbackWithReason:@"Startup default autoconnect required legacy database view"] connect];
        }
    }

    // Note: standalone connection window (SAConnectionWindowController) is available
    // programmatically but not yet exposed in the menu to avoid confusion with the
    // existing "New Connection Window" XIB menu item. Menu item can be added once
    // the standalone window fully replaces the embedded connection flow.
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)addCheckForUpdatesMenuItem {
    if (NSBundle.mainBundle.isMASVersion == NO && [[NSUserDefaults standardUserDefaults] boolForKey:SPShowUpdateAvailable] == YES) {
        SPLog(@"Adding menu item to check for updates");
        NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Check for Updates...", @"Menu item Check for Updates...") action:@selector(checkForNewVersionFromMenu) keyEquivalent:@""];
        [mainMenu insertItem:updates atIndex:1];
    }
}

- (void)removeCheckForUpdatesMenuItem {

    [mainMenu.itemArray enumerateObjectsUsingBlock:^(NSMenuItem *item2, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([item2.title isEqualToString:NSLocalizedString(@"Check for Updates...", @"Menu item Check for Updates...")]) {
            SPLog(@"Removing menu item to check for updates");
            [mainMenu removeItemAtIndex:idx];
            *stop = YES;
        }
    }];
}

- (void)checkForNewVersionFromMenu{
    [self checkForNewVersionWithDelay:0 andIsFromMenuCheck:YES];
}

- (void)checkForNewVersionWithDelay:(double)delay andIsFromMenuCheck:(BOOL)isFromMenuCheck {

    SPLog(@"isFromMenuCheck %d", isFromMenuCheck);
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SPShowUpdateAvailable] == YES) {
        SPLog(@"checking for updates");
        executeOnLowPrioQueueAfterADelay(^{
            [NSBundle.mainBundle checkForNewVersionWithIsFromMenuCheck:isFromMenuCheck];
        }, delay);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    if ([keyPath isEqualToString:SPShowUpdateAvailable]) {
        if([[change objectForKey:NSKeyValueChangeNewKey] boolValue] == YES){
            [self addCheckForUpdatesMenuItem];
        }
        else if([[change objectForKey:NSKeyValueChangeNewKey] boolValue] == NO){
            [self removeCheckForUpdatesMenuItem];
        }
    }
}

- (void)externalApplicationWantsToOpenADatabaseConnection:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    NSString *MAMP_SPFVersion = [userInfo objectForKey:@"dataVersion"];
    if ([MAMP_SPFVersion isEqualToString:@"1"]) {
        NSDictionary *spfStructure = [userInfo objectForKey:@"spfData"];
        if (spfStructure) {
            SPWindowController *windowController = [self.tabManager newWindowForWindow];
            if ([self applyLightweightStateDictionary:spfStructure toWindowController:windowController]) {
                return;
            }

            [[windowController legacyDatabaseDocumentForExplicitFallbackWithReason:@"External SPF restore required legacy database view"] setState:spfStructure];
        }
    }
}

- (void)switchToPreviousTab:(NSNotification *)notification {
    [self.tabManager switchToPreviousTab];
}

- (void)switchToNextTab:(NSNotification *)notification {
    [self.tabManager switchToNextTab];
}

- (NSString *)lightweightResumeFilePath
{
    NSError *error = nil;
    NSString *dataPath = [fileManager applicationSupportDirectoryForSubDirectory:SPDataSupportFolder createIfNotExists:YES error:&error];
    if (!dataPath || error) {
        SPLog(@"Could not resolve lightweight resume path: %@", error);
        return nil;
    }

    return [dataPath stringByAppendingPathComponent:SALightweightResumeFileName];
}

- (BOOL)shouldStartEmptySessionFromLaunchModifierFlags
{
    NSEventModifierFlags launchFlags = ([NSEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask);
    return (launchFlags & (NSEventModifierFlagShift | NSEventModifierFlagOption)) != 0;
}

- (NSDictionary *)lightweightResumeStateDictionary
{
    NSMutableArray *tabs = [NSMutableArray array];
    NSMutableDictionary *win = [NSMutableDictionary dictionary];
    NSMutableArray *processedWindows = [NSMutableArray array];

    for (NSWindow *window in [self.tabManager orderedWindows]) {
        NSArray *tabGroupWindows = [[window tabGroup] windows];
        NSArray *windowsToProcess = [tabGroupWindows count] > 0 ? tabGroupWindows : ([[window tabbedWindows] count] > 0 ? [window tabbedWindows] : @[window]);
        for (NSWindow *processedWindow in windowsToProcess) {
            SPWindowController *windowController = processedWindow.windowController;
            if (!windowController || [processedWindows containsObject:windowController.uniqueID] || ![windowController hasActiveLightweightConnection]) {
                continue;
            }

            NSDictionary *lightweightState = [windowController lightweightConnectionStateDictionaryWithIncludePasswords:NO includeSession:YES includeQuery:YES];
            if (![lightweightState count]) {
                continue;
            }

            NSMutableDictionary *tabData = [NSMutableDictionary dictionary];
            [tabData setObject:@YES forKey:@"isLightweight"];
            [tabData setObject:lightweightState forKey:@"lightweightState"];
            if ([[processedWindow tabGroup] selectedWindow] == processedWindow) {
                [win setObject:@([tabs count]) forKey:@"selectedTabIndex"];
            }
            [tabs addObject:tabData];
            if (![win objectForKey:@"frame"]) {
                [win setObject:[self frameStringForWindowGroupContainingWindow:window] forKey:@"frame"];
            }

            [processedWindows addObject:windowController.uniqueID];
        }
    }

    if (![tabs count]) {
        return nil;
    }

    [win setObject:tabs forKey:@"tabs"];
    if (![win objectForKey:@"selectedTabIndex"]) {
        [win setObject:@0 forKey:@"selectedTabIndex"];
    }

    NSMutableDictionary *resumeState = [@{
        @"version": @1,
        @"windows": @[win]
    } mutableCopy];

    NSDictionary *consoleState = [self lightweightConsoleResumeStateDictionary];
    if ([consoleState count]) {
        [resumeState setObject:consoleState forKey:SALightweightResumeConsoleKey];
    }

    return resumeState;
}

- (NSDictionary *)lightweightConsoleResumeStateDictionary
{
    SPQueryController *queryController = [SPQueryController existingSharedQueryController];
    NSWindow *consoleWindow = [queryController window];
    if (!consoleWindow) {
        return nil;
    }

    return @{
        SALightweightResumeConsoleVisibleKey: @([consoleWindow isVisible]),
        SALightweightResumeConsoleFrameKey: NSStringFromRect([consoleWindow frame])
    };
}

- (NSString *)frameStringForWindowGroupContainingWindow:(NSWindow *)window
{
    NSWindow *selectedWindow = [[window tabGroup] selectedWindow];
    return NSStringFromRect([(selectedWindow ?: window) frame]);
}

- (BOOL)restoreLightweightResumeState
{
    NSString *filePath = [self lightweightResumeFilePath];
    if (![filePath length] || ![fileManager fileExistsAtPath:filePath]) {
        return NO;
    }

    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:filePath options:NSUncachedRead error:&error];
    NSDictionary *resumeState = nil;
    if (data && !error) {
        resumeState = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    }

    if (![resumeState isKindOfClass:[NSDictionary class]] || error) {
        SPLog(@"Could not read lightweight resume state: %@", error);
        return NO;
    }

    NSArray *windowDictionaries = [resumeState objectForKey:@"windows"];
    if (![windowDictionaries isKindOfClass:[NSArray class]]) {
        return NO;
    }

    BOOL restoredAnyWindow = NO;
    NSWindow *window = nil;
    NSString *restoredFrame = nil;
    NSMutableArray *createdWindowControllers = [NSMutableArray array];

    @try {
        for (NSDictionary *windowDictionary in [windowDictionaries reverseObjectEnumerator]) {
            if (![windowDictionary isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            NSArray *tabs = [windowDictionary objectForKey:@"tabs"];
            if (![tabs isKindOfClass:[NSArray class]]) {
                continue;
            }

            NSMutableDictionary *restoredTabsByIndex = [NSMutableDictionary dictionary];
            SPWindowController *firstRestoredWindowController = nil;
            for (NSUInteger tabIndex = 0; tabIndex < [tabs count]; tabIndex++) {
                NSDictionary *tab = [tabs objectAtIndex:tabIndex];
                if (![tab isKindOfClass:[NSDictionary class]] || ![[tab objectForKey:@"isLightweight"] boolValue]) {
                    continue;
                }

                BOOL isFirstRestoredWindow = window == nil;
                SPWindowController *newWindowController = isFirstRestoredWindow ? [self.tabManager replaceTabServiceWithInitialWindow] : [self.tabManager newWindowForTabInWindow:window];
                [createdWindowControllers addObject:newWindowController];
                if (window == nil) {
                    window = newWindowController.window;
                }

                NSString *frame = [windowDictionary objectForKey:@"frame"];
                if (!restoredFrame && [frame isKindOfClass:[NSString class]]) {
                    restoredFrame = frame;
                    [self applyLightweightResumeFrameString:frame toWindow:newWindowController.window];
                }

                if ([newWindowController restoreLightweightConnectionStateDictionary:[tab objectForKey:@"lightweightState"]]) {
                    restoredAnyWindow = YES;
                    window = newWindowController.window;
                    if (!firstRestoredWindowController) {
                        firstRestoredWindowController = newWindowController;
                    }
                    [restoredTabsByIndex setObject:newWindowController forKey:@(tabIndex)];
                }
                else {
                    SPLog(@"Skipping invalid lightweight resume tab at index %lu", (unsigned long)tabIndex);
                    [newWindowController close];
                    [createdWindowControllers removeObject:newWindowController];
                    if (isFirstRestoredWindow) {
                        window = nil;
                        restoredFrame = nil;
                    }
                }
            }

            NSNumber *selectedTabIndex = [windowDictionary objectForKey:@"selectedTabIndex"];
            SPWindowController *selectedWindowController = [selectedTabIndex isKindOfClass:[NSNumber class]] ? [restoredTabsByIndex objectForKey:selectedTabIndex] : nil;
            if (!selectedWindowController) {
                selectedWindowController = firstRestoredWindowController;
            }
            if (selectedWindowController.window) {
                selectedWindowController.window.tabGroup.selectedWindow = selectedWindowController.window;
                [selectedWindowController.window makeKeyAndOrderFront:nil];
            }
        }
    }
    @catch (NSException *exception) {
        SPLog(@"Could not restore lightweight resume state, opening empty session instead: %@", exception);
        for (SPWindowController *windowController in [createdWindowControllers copy]) {
            [windowController close];
        }
        return NO;
    }

    if (restoredAnyWindow) {
        NSDictionary *consoleState = [resumeState objectForKey:SALightweightResumeConsoleKey];
        if ([consoleState isKindOfClass:[NSDictionary class]]) {
            [self restoreLightweightConsoleResumeStateDictionary:consoleState];
        }
    }

    return restoredAnyWindow;
}

- (void)restoreLightweightConsoleResumeStateDictionary:(NSDictionary *)consoleState
{
    if (![[consoleState objectForKey:SALightweightResumeConsoleVisibleKey] boolValue]) {
        return;
    }

    SPQueryController *queryController = [SPQueryController sharedQueryController];
    NSWindow *consoleWindow = [queryController window];
    NSString *frame = [consoleState objectForKey:SALightweightResumeConsoleFrameKey];
    if ([frame isKindOfClass:[NSString class]]) {
        [self applyLightweightResumeFrameString:frame toWindow:consoleWindow minimumSize:NSMakeSize(480, 140)];
    }
    [queryController resizeConsoleColumnsToFillAvailableWidth];

    if (![consoleWindow isVisible]) {
        [queryController updateEntries];
    }

    [consoleWindow orderFront:nil];
}

- (BOOL)applyLightweightResumeFrameString:(NSString *)frameString toWindow:(NSWindow *)window
{
    return [self applyLightweightResumeFrameString:frameString toWindow:window minimumSize:NSMakeSize(640, 420)];
}

- (BOOL)applyLightweightResumeFrameString:(NSString *)frameString toWindow:(NSWindow *)window minimumSize:(NSSize)minimumSize
{
    if (![frameString length] || !window) {
        return NO;
    }

    NSRect frame = NSRectFromString(frameString);
    if (NSIsEmptyRect(frame) || frame.size.width < minimumSize.width || frame.size.height < minimumSize.height) {
        return NO;
    }

    NSScreen *targetScreen = nil;
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSIntersectsRect(frame, [screen visibleFrame])) {
            targetScreen = screen;
            break;
        }
    }

    if (!targetScreen) {
        targetScreen = [NSScreen mainScreen] ?: [[NSScreen screens] firstObject];
        NSRect visibleFrame = [targetScreen visibleFrame];
        frame.size.width = MIN(frame.size.width, visibleFrame.size.width);
        frame.size.height = MIN(frame.size.height, visibleFrame.size.height);
        frame.origin.x = NSMidX(visibleFrame) - (frame.size.width / 2);
        frame.origin.y = NSMidY(visibleFrame) - (frame.size.height / 2);
    }

    NSTimeInterval frameStartTime = SAUIDiagnosticsEnabled() ? SAUIMonotonicTime() : 0;
    [window setFrame:frame display:NO];
    [self _logUIDiagnosticsWindowTiming:@"applyLightweightResumeFrameString setFrame" window:window startTime:frameStartTime];
    return YES;
}

- (void)saveLightweightResumeState
{
    NSString *filePath = [self lightweightResumeFilePath];
    if (![filePath length]) {
        return;
    }

    NSDictionary *resumeState = [self lightweightResumeStateDictionary];
    if (![resumeState count]) {
        [fileManager removeItemAtPath:filePath error:nil];
        self.lastLightweightResumeStateData = nil;
        return;
    }

    NSError *error = nil;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:resumeState format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    BOOL didWrite = plist && !error && ![plist isEqualToData:self.lastLightweightResumeStateData];
    if (didWrite) {
        [plist writeToFile:filePath options:NSAtomicWrite error:&error];
        if (!error) {
            self.lastLightweightResumeStateData = plist;
        }
    }

    if (error) {
        SPLog(@"Could not save lightweight resume state: %@", error);
    }
}

- (void)lightweightResumeStateDidChange:(NSNotification *)notification
{
    self.lightweightResumeStateDirty = YES;
    [self scheduleLightweightResumeStateSave];
}

- (void)lightweightWindowFrameDidChange:(NSNotification *)notification
{
    if (![[notification object] isKindOfClass:[NSWindow class]]) {
        return;
    }

    NSWindow *window = [notification object];
    if ([window.windowController isKindOfClass:[SPQueryController class]]) {
        [self lightweightResumeStateDidChange:nil];
        return;
    }

    SPWindowController *windowController = [window.windowController isKindOfClass:[SPWindowController class]] ? (SPWindowController *)window.windowController : nil;
    if (!windowController && [window tabGroup]) {
        for (NSWindow *tabWindow in [[window tabGroup] windows]) {
            if ([tabWindow.windowController isKindOfClass:[SPWindowController class]]) {
                windowController = (SPWindowController *)tabWindow.windowController;
                break;
            }
        }
    }

    if (!windowController) {
        return;
    }

    if (![windowController hasActiveLightweightConnection]) {
        return;
    }

    [self lightweightResumeStateDidChange:nil];
}

- (void)windowWillClose:(NSNotification *)notification
{
    if (![[notification object] isKindOfClass:[NSWindow class]]) {
        return;
    }

    NSWindow *window = [notification object];
    if (![window.windowController isKindOfClass:[SPWindowController class]]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self lightweightResumeStateDidChange:nil];
    });
}

- (void)scheduleLightweightResumeStateSave
{
    if (self.lightweightResumeSaveScheduled) {
        return;
    }

    self.lightweightResumeSaveScheduled = YES;
    [self performSelector:@selector(savePendingLightweightResumeStateIfNeeded) withObject:nil afterDelay:SALightweightResumeSaveDebounce];
}

- (void)savePendingLightweightResumeStateIfNeeded
{
    if (!self.lightweightResumeStateDirty) {
        return;
    }

    [self cancelScheduledLightweightResumeStateSave];
    self.lightweightResumeStateDirty = NO;
    [self saveLightweightResumeState];
}

- (void)cancelScheduledLightweightResumeStateSave
{
    self.lightweightResumeSaveScheduled = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(savePendingLightweightResumeStateIfNeeded) object:nil];
}

- (void)duplicateConnectionToTab:(NSNotification *)notification {

    NSDictionary *userInfo = [notification userInfo];
    if (userInfo) {
        SPWindowController *newWindowController = [self.tabManager newWindowForTab];
        if ([[userInfo objectForKey:@"isLightweight"] boolValue]) {
            if (![newWindowController restoreLightweightConnectionStateDictionary:[userInfo objectForKey:@"lightweightState"]]) {
                [newWindowController close];
            }
            return;
        }

        if ([self applyLightweightStateDictionary:userInfo toWindowController:newWindowController]) {
            return;
        }

        [[newWindowController legacyDatabaseDocumentForExplicitFallbackWithReason:@"Duplicate tab state required legacy database view"] setState:userInfo];
    }
}

- (void)saveConnectionsToSPF:(NSNotification *)notification {

    NSString *fileName = [notification object];
    NSError *error = nil;
//    NSString *contextInfo = [[notification userInfo] objectForKey:@"contextInfo"];
    NSNumber *encrypted = [[notification userInfo] objectForKey:@"encrypted"];
    NSString *saveConnectionEncryptString = [[notification userInfo] objectForKey:@"saveConnectionEncryptString"];
    NSNumber *auto_connect = [[notification userInfo] objectForKey:@"auto_connect"];
    NSNumber *save_password = [[notification userInfo] objectForKey:@"save_password"];
    NSNumber *include_session = [[notification userInfo] objectForKey:@"include_session"];
    NSNumber *save_editor_content = [[notification userInfo] objectForKey:@"save_editor_content"];

    // Sub-folder 'Contents' will contain all untitled connection as single window or tab.
    // info.plist will contain the opened structure (windows and tabs for each window). Each connection
    // is linked to a saved spf file either in 'Contents' for unTitled ones or already saved spf files.

    if(!fileName || ![fileName length]) {
        return;
    }

    // If bundle exists remove it
    if([fileManager fileExistsAtPath:fileName]) {
        [fileManager removeItemAtPath:fileName error:&error];
        if(error != nil) {
            NSAlert *errorAlert = [NSAlert alertWithError:error];
            [errorAlert runModal];
            return;
        }
    }

    [fileManager createDirectoryAtPath:fileName withIntermediateDirectories:YES attributes:nil error:&error];

    if (error != nil) {
        [[NSAlert alertWithError:error] runModal];
        return;
    }

    [fileManager createDirectoryAtPath:[NSString stringWithFormat:@"%@/Contents", fileName] withIntermediateDirectories:YES attributes:nil error:&error];

    if (error != nil) {
        [[NSAlert alertWithError:error] runModal];
        return;
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSMutableArray *windows = [NSMutableArray array];

    // retrieve save panel data for passing them to each doc
    NSMutableDictionary *spfDocData_temp = [NSMutableDictionary dictionary];
    [spfDocData_temp setObject:encrypted forKey:@"encrypted"];
    if ([[spfDocData_temp objectForKey:@"encrypted"] boolValue]) {
        [spfDocData_temp setObject:saveConnectionEncryptString forKey:@"e_string"];
    }
    [spfDocData_temp setObject:auto_connect forKey:@"auto_connect"];
    [spfDocData_temp setObject:save_password forKey:@"save_password"];
    [spfDocData_temp setObject:include_session forKey:@"include_session"];
    [spfDocData_temp setObject:save_editor_content forKey:@"save_editor_content"];

    // Save the session's accessory view settings
    [self setSpfSessionDocData:spfDocData_temp];

    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"encrypted"] boolValue]] forKey:@"encrypted"];
    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"auto_connect"] boolValue]] forKey:@"auto_connect"];
    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"save_password"] boolValue]] forKey:@"save_password"];
    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"include_session"] boolValue]] forKey:@"include_session"];
    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"save_editor_content"] boolValue]] forKey:@"save_editor_content"];
    [info setObject:@1 forKey:SPFVersionKey];
    [info setObject:@"connection bundle" forKey:SPFFormatKey];

    NSMutableArray *processedWindows = [NSMutableArray new];

    NSArray *allWindows = [self.tabManager orderedWindows];
    for (NSWindow *window in allWindows) {
        NSMutableArray *tabs = [NSMutableArray array];
        NSMutableDictionary *win = [NSMutableDictionary dictionary];

        NSArray *tabGroupWindows = [[window tabGroup] windows];
        NSArray *windowsToProcess = [tabGroupWindows count] > 0 ? tabGroupWindows : ([[window tabbedWindows] count] > 0 ? [window tabbedWindows] : @[window]);
        for (NSWindow *processedWindow in windowsToProcess) {
            SPWindowController *windowController = processedWindow.windowController;
            if ([processedWindows containsObject:windowController.uniqueID]) {
                continue;
            }

            NSMutableDictionary *tabData = [NSMutableDictionary dictionary];
            SPDatabaseDocument *databaseDocument = [windowController loadedDatabaseDocumentIfAvailable];

            if ([windowController hasActiveLightweightConnection]) {
                NSURL *lightweightFileURL = [windowController lightweightConnectionFileURLForSessionBundle];
                NSString *lightweightFilePath = nil;
                BOOL isAbsolutePath = NO;

                if (lightweightFileURL && [lightweightFileURL isFileURL] && [[lightweightFileURL path] length]) {
                    lightweightFilePath = [lightweightFileURL path];
                    isAbsolutePath = YES;
                } else {
                    NSString *newName = [NSString stringWithFormat:@"%@.%@", [NSString stringWithNewUUID], SPFileExtensionDefault];
                    lightweightFilePath = [NSString stringWithFormat:@"%@/Contents/%@", fileName, newName];
                    [tabData setObject:newName forKey:@"path"];
                }

                BOOL lightweightSaved = isAbsolutePath
                    ? [windowController saveLightweightConnectionFileAtPathUsingCurrentSaveOptions:lightweightFilePath]
                    : [windowController saveLightweightConnectionFileAtPath:lightweightFilePath
                                                                  encrypted:[[spfDocData_temp objectForKey:@"encrypted"] boolValue]
                                                         encryptionPassword:([spfDocData_temp objectForKey:@"e_string"] ?: @"")
                                                                autoConnect:[[spfDocData_temp objectForKey:@"auto_connect"] boolValue]
                                                               savePassword:[[spfDocData_temp objectForKey:@"save_password"] boolValue]
                                                             includeSession:[[spfDocData_temp objectForKey:@"include_session"] boolValue]
                                                               includeQuery:[[spfDocData_temp objectForKey:@"save_editor_content"] boolValue]];

                if (!lightweightSaved) {
                    continue;
                }

                if (isAbsolutePath) {
                    [tabData setObject:lightweightFilePath forKey:@"path"];
                } else {
                    [windowController setLightweightConnectionFileURL:[NSURL fileURLWithPath:lightweightFilePath] savedInBundle:YES];
                }
                [tabData setObject:[NSNumber numberWithBool:isAbsolutePath] forKey:@"isAbsolutePath"];
            } else if (!databaseDocument || ![databaseDocument mySQLVersion]) {
                continue;
            } else if([databaseDocument isUntitled]) {
                // new bundle file name for untitled docs
                NSString *newName = [NSString stringWithFormat:@"%@.%@", [NSString stringWithNewUUID], SPFileExtensionDefault];
                // internal bundle path to store the doc
                NSString *filePath = [NSString stringWithFormat:@"%@/Contents/%@", fileName, newName];
                // save it as temporary spf file inside the bundle with save panel options spfDocData_temp
                [databaseDocument saveDocumentWithFilePath:filePath inBackground:NO onlyPreferences:NO contextInfo:[NSDictionary dictionaryWithDictionary:spfDocData_temp]];
                [databaseDocument setIsSavedInBundle:YES];
                [tabData setObject:@NO forKey:@"isAbsolutePath"];
                [tabData setObject:newName forKey:@"path"];
            } else {
                // save it to the original location and take the file's spfDocData
                [databaseDocument saveDocumentWithFilePath:[[databaseDocument fileURL] path] inBackground:YES onlyPreferences:NO contextInfo:nil];
                [tabData setObject:@YES forKey:@"isAbsolutePath"];
                [tabData setObject:[[databaseDocument fileURL] path] forKey:@"path"];
            }
            [tabs addObject:tabData];
            [win setObject:[self frameStringForWindowGroupContainingWindow:window] forKey:@"frame"];

            [processedWindows addObject:windowController.uniqueID];
        }
        if ([tabs count] > 0) {
            [win setObject:tabs forKey:@"tabs"];
        }
        if ([[win allValues] count] > 0) {
            [windows addObject:win];
        }
    }
    [info setObject:windows forKey:@"windows"];

    error = nil;

    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];

    if (error) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while converting session data", @"error while converting session data") message:[error localizedDescription] callback:nil];
        return;
    }

    [plist writeToFile:[NSString stringWithFormat:@"%@/info.plist", fileName] options:NSAtomicWrite error:&error];

    if (error != nil){
        NSAlert *errorAlert = [NSAlert alertWithError:error];
        [errorAlert runModal];

        return;
    }

    // Register spfs bundle in Recent Files
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:fileName]];
}

- (BOOL)bundleCommandScope:(NSString *)scope canRunWithFirstResponder:(id)firstResponder
{
    if ([scope isEqualToString:SPBundleScopeGeneral]) {
        return YES;
    }

    if ([scope isEqualToString:SPBundleScopeInputField]) {
        return [firstResponder respondsToSelector:@selector(executeBundleItemForInputField:)];
    }

    if ([scope isEqualToString:SPBundleScopeDataTable]) {
        if ([firstResponder respondsToSelector:@selector(supportsDataTableBundleCommands)] && ![firstResponder supportsDataTableBundleCommands]) {
            return NO;
        }

        return [firstResponder respondsToSelector:@selector(executeBundleItemForDataTable:)];
    }

    return NO;
}

- (BOOL)bundleCommandMenuItemCanRun:(NSMenuItem *)menuItem
{
    NSString *scope = [[menuItem representedObject] objectForKey:@"scope"];
    if (![scope length]) {
        scope = SPBundleScopeGeneral;
    }

    return [self bundleCommandScope:scope canRunWithFirstResponder:[[NSApp keyWindow] firstResponder]];
}

- (void)configureMenuItemInMenu:(NSMenu *)menu action:(SEL)action title:(NSString *)title hidden:(BOOL)hidden
{
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == action) {
            [item setTitle:title];
            [item setHidden:hidden];
            return;
        }
    }
}

- (void)configureMenuItemInMenu:(NSMenu *)menu atIndex:(NSInteger)index hidden:(BOOL)hidden
{
    if (index < 0 || index >= (NSInteger)[menu numberOfItems]) return;

    [[menu itemAtIndex:index] setHidden:hidden];
}

- (void)resetTableMenuState
{
    NSMenu *tableSubMenu = [[[NSApp mainMenu] itemWithTag:SPMainMenuTable] submenu];
    if (!tableSubMenu) return;

    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(copyCreateTableSyntax:)
                            title:NSLocalizedString(@"Copy Create Table Syntax", @"copy create table syntax menu item")
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(showCreateTableSyntax:)
                            title:NSLocalizedString(@"Show Create Table Syntax...", @"show create table syntax menu item")
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(checkTable:)
                            title:NSLocalizedString(@"Check Table", @"check table menu item")
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(repairTable:)
                            title:NSLocalizedString(@"Repair Table", @"repair table menu item")
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(analyzeTable:)
                            title:NSLocalizedString(@"Analyze Table", @"analyze table menu item")
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(optimizeTable:)
                            title:NSLocalizedString(@"Optimize Table", @"optimize table menu item")
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(flushTable:)
                            title:NSLocalizedString(@"Flush Table", @"flush table menu item")
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(checksumTable:)
                            title:NSLocalizedString(@"Checksum Table", @"checksum table menu item")
                           hidden:NO];

    [self configureMenuItemInMenu:tableSubMenu atIndex:6 hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu atIndex:9 hidden:NO];
}

- (void)restoreTableMenuStateForDatabaseDocument:(SPDatabaseDocument *)document
{
    SPTablesList *tablesList = [document tablesListInstance];
    if (!tablesList) {
        [self resetTableMenuState];
        return;
    }

    NSString *tableName = [tablesList tableName];
    if (tableName) {
        [tablesList setSelectionState:@{
            @"name": tableName,
            @"type": @([tablesList tableType])
        }];
    } else {
        [tablesList setSelectionState:nil];
    }
}

- (void)configureLightweightTableMenuForWindowController:(SPWindowController *)windowController
{
    NSMenu *tableSubMenu = [[[NSApp mainMenu] itemWithTag:SPMainMenuTable] submenu];
    if (!tableSubMenu) return;
    self.lightweightTableMenuIsConfigured = YES;

    NSInteger selectedCount = [windowController selectedLightweightTableCount];
    NSInteger objectType = [windowController selectedLightweightTableSelectionObjectType];
    BOOL hasSelection = selectedCount > 0;
    BOOL hasSingleSelection = selectedCount == 1;
    BOOL selectedView = hasSingleSelection && objectType == SALightweightTableObjectTypeViewValue;
    BOOL selectedProcedure = hasSingleSelection && objectType == SALightweightTableObjectTypeProcedureValue;
    BOOL selectedFunction = hasSingleSelection && objectType == SALightweightTableObjectTypeFunctionValue;
    BOOL canCheck = [windowController canPerformLightweightTableMaintenanceAction:@selector(checkTable:)];
    BOOL canRepair = [windowController canPerformLightweightTableMaintenanceAction:@selector(repairTable:)];
    BOOL canAnalyze = [windowController canPerformLightweightTableMaintenanceAction:@selector(analyzeTable:)];
    BOOL canOptimize = [windowController canPerformLightweightTableMaintenanceAction:@selector(optimizeTable:)];
    BOOL canFlush = [windowController canPerformLightweightTableMaintenanceAction:@selector(flushTable:)];
    BOOL canChecksum = [windowController canPerformLightweightTableMaintenanceAction:@selector(checksumTable:)];

    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(copyCreateTableSyntax:)
                            title:(hasSelection && !hasSingleSelection ? NSLocalizedString(@"Copy Create Syntax", @"copy create selected items syntax menu item") :
                                   selectedView ? NSLocalizedString(@"Copy Create View Syntax", @"copy create view syntax menu item") :
                                   selectedProcedure ? NSLocalizedString(@"Copy Create Procedure Syntax", @"copy create proc syntax menu item") :
                                   selectedFunction ? NSLocalizedString(@"Copy Create Function Syntax", @"copy create func syntax menu item") :
                                   NSLocalizedString(@"Copy Create Table Syntax", @"copy create table syntax menu item"))
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(showCreateTableSyntax:)
                            title:(hasSelection && !hasSingleSelection ? NSLocalizedString(@"Show Create Syntax...", @"show create selected items syntax menu item") :
                                   selectedView ? NSLocalizedString(@"Show Create View Syntax...", @"show create view syntax menu item") :
                                   selectedProcedure ? NSLocalizedString(@"Show Create Procedure Syntax...", @"show create proc syntax menu item") :
                                   selectedFunction ? NSLocalizedString(@"Show Create Function Syntax...", @"show create func syntax menu item") :
                                   NSLocalizedString(@"Show Create Table Syntax...", @"show create table syntax menu item"))
                           hidden:NO];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(checkTable:)
                            title:(selectedCount > 1 ? NSLocalizedString(@"Check Selected Items", @"check selected items menu item") :
                                   selectedView ? NSLocalizedString(@"Check View", @"check view menu item") : NSLocalizedString(@"Check Table", @"check table menu item"))
                           hidden:(hasSelection && !canCheck)];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(repairTable:)
                            title:(selectedCount > 1 ? NSLocalizedString(@"Repair Selected Tables", @"repair selected tables menu item") : NSLocalizedString(@"Repair Table", @"repair table menu item"))
                           hidden:(hasSelection && !canRepair)];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(analyzeTable:)
                            title:(selectedCount > 1 ? NSLocalizedString(@"Analyze Selected Tables", @"analyze selected tables menu item") : NSLocalizedString(@"Analyze Table", @"analyze table menu item"))
                           hidden:(hasSelection && !canAnalyze)];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(optimizeTable:)
                            title:(selectedCount > 1 ? NSLocalizedString(@"Optimize Selected Tables", @"optimize selected tables menu item") : NSLocalizedString(@"Optimize Table", @"optimize table menu item"))
                           hidden:(hasSelection && !canOptimize)];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(flushTable:)
                            title:(selectedCount > 1 ? NSLocalizedString(@"Flush Selected Items", @"flush selected items menu item") :
                                   selectedView ? NSLocalizedString(@"Flush View", @"flush view menu item") : NSLocalizedString(@"Flush Table", @"flush table menu item"))
                           hidden:(hasSelection && !canFlush)];
    [self configureMenuItemInMenu:tableSubMenu
                           action:@selector(checksumTable:)
                            title:(selectedCount > 1 ? NSLocalizedString(@"Checksum Selected Tables", @"checksum selected tables menu item") : NSLocalizedString(@"Checksum Table", @"checksum table menu item"))
                           hidden:(hasSelection && !canChecksum)];

    [self configureMenuItemInMenu:tableSubMenu atIndex:6 hidden:(hasSelection && !canCheck && !canFlush)];
    [self configureMenuItemInMenu:tableSubMenu atIndex:9 hidden:(hasSelection && !canRepair && !canAnalyze && !canOptimize && !canChecksum)];
}

- (BOOL)validateLightweightTableMaintenanceMenuItem:(NSMenuItem *)menuItem forWindowController:(SPWindowController *)windowController
{
    SEL action = [menuItem action];
    return [windowController canPerformLightweightTableMaintenanceAction:action];
}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    BOOL uiDiagnosticsEnabled = SAUIDiagnosticsEnabled();
    NSTimeInterval validationStartTime = uiDiagnosticsEnabled ? SAUIMonotonicTime() : 0;
    BOOL isValid = YES;
    SEL action = [menuItem action];
    SPDatabaseDocument *activeDocument = nil;
    SPWindowController *activeWindowController = [self.tabManager activeWindowController];
    if (action == @selector(newWindow:) || action == @selector(openConnectionSheet:) || action == @selector(openStandaloneConnectionWindow:)) {
        isValid = YES;
        goto validateMenuItemDone;
    }
    if (action == @selector(newTab:)) {
        isValid = ([[[self.tabManager activeWindowController] window] attachedSheet] == nil);
        goto validateMenuItemDone;
    }
    if (action == @selector(duplicateTab:)) {
        isValid = [self windowControllerHasActiveConnectionTarget:activeWindowController];
        goto validateMenuItemDone;
    }
    if (action == @selector(openAboutPanel:) || action == @selector(openPreferences:) || action == @selector(visitWebsite:) || action == @selector(checkForNewVersionFromMenu)) {
        isValid = YES;
        goto validateMenuItemDone;
    }

    if (action == @selector(visitHelpWebsite:) || action == @selector(visitFAQWebsite:) || action == @selector(viewKeyboardShortcuts:)) {
        isValid = YES;
        goto validateMenuItemDone;
    }

    if (action == @selector(toggleConsole:)) {
        [menuItem setTitle:([[[SPQueryController sharedQueryController] window] isVisible] && [[[NSApp keyWindow] windowController] isKindOfClass:[SPQueryController class]]) ? NSLocalizedString(@"Hide Console", @"hide console") : NSLocalizedString(@"Show Console", @"show console")];
        isValid = YES;
        goto validateMenuItemDone;
    }

    if (action == @selector(clearConsole:)) {
        isValid = ([[SPQueryController sharedQueryController] consoleMessageCount] > 0);
        goto validateMenuItemDone;
    }

    activeDocument = [activeWindowController loadedDatabaseDocumentIfAvailable];
    if (activeDocument) {
        if (self.lightweightTableMenuIsConfigured) {
            [self restoreTableMenuStateForDatabaseDocument:activeDocument];
            self.lightweightTableMenuIsConfigured = NO;
        }
        isValid = [activeDocument validateMenuItem:menuItem];
        goto validateMenuItemDone;
    }

    if (![activeWindowController hasActiveLightweightConnection] && self.lightweightTableMenuIsConfigured) {
        [self resetTableMenuState];
        self.lightweightTableMenuIsConfigured = NO;
    }

    if (action == @selector(bundleCommandDispatcher:)) {
        isValid = [self bundleCommandMenuItemCanRun:menuItem];
        goto validateMenuItemDone;
    }

    if ([activeWindowController hasActiveLightweightConnection]) {
        [self configureLightweightTableMenuForWindowController:activeWindowController];

        if (action == @selector(viewStructure:) ||
            action == @selector(viewContent:) ||
            action == @selector(viewStatus:) ||
            action == @selector(viewRelations:) ||
            action == @selector(viewTriggers:) ||
            action == @selector(viewStructure) ||
            action == @selector(viewContent) ||
            action == @selector(viewStatus) ||
            action == @selector(viewRelations) ||
            action == @selector(viewTriggers))
        {
            isValid = [activeWindowController hasSelectedLightweightTable];
            goto validateMenuItemDone;
        }

        if (action == @selector(viewQuery:) ||
            action == @selector(showMySQLHelp:) ||
            action == @selector(viewQuery) ||
            action == @selector(showMySQLHelp))
        {
            isValid = YES;
            goto validateMenuItemDone;
        }

        if (action == @selector(focusOnTableContentFilter:) ||
            action == @selector(showFilterTable:) ||
            action == @selector(focusOnTableContentFilter) ||
            action == @selector(showFilterTable))
        {
            isValid = [activeWindowController hasSelectedLightweightTable];
            goto validateMenuItemDone;
        }

        if (action == @selector(makeTableListFilterHaveFocus:)) {
            isValid = YES;
            goto validateMenuItemDone;
        }

        if (action == @selector(backForwardInHistory:)) {
            isValid = [activeWindowController canNavigateLightweightHistory:menuItem];
            goto validateMenuItemDone;
        }

        if (action == @selector(export:)) {
            isValid = [activeWindowController canExportLightweightData];
            goto validateMenuItemDone;
        }

        if (action == @selector(printDocument:)) {
            isValid = [activeWindowController canPrintLightweightDocument];
            goto validateMenuItemDone;
        }

        if (action == @selector(saveConnectionSheet:)) {
            isValid = [activeWindowController validateLightweightSaveConnectionMenuItem:menuItem];
            goto validateMenuItemDone;
        }

        if (action == @selector(addConnectionToFavorites:)) {
            isValid = [activeWindowController canAddLightweightConnectionToFavorites];
            goto validateMenuItemDone;
        }

        if (action == @selector(import:)) {
            isValid = [activeWindowController canImportLightweightSQL];
            goto validateMenuItemDone;
        }

        if (action == @selector(importFromClipboard:)) {
            isValid = [activeWindowController canImportLightweightSQLFromClipboard];
            goto validateMenuItemDone;
        }

        if (action == @selector(copy:)) {
            isValid = [activeWindowController canCopyActiveLightweightSelection:menuItem];
            goto validateMenuItemDone;
        }

        if (action == @selector(toggleNavigator:)) {
            [menuItem setTitle:([[[SPNavigatorController sharedNavigatorController] window] isVisible]) ? NSLocalizedString(@"Hide Navigator", @"hide navigator") : NSLocalizedString(@"Show Navigator", @"show navigator")];
            isValid = YES;
            goto validateMenuItemDone;
        }

        if (action == @selector(showGotoDatabase:) ||
            action == @selector(addDatabase:) ||
            action == @selector(flushPrivileges:) ||
            action == @selector(setDatabases:) ||
            action == @selector(showUserManager:) ||
            action == @selector(showServerVariables:) ||
            action == @selector(showServerProcesses:) ||
            action == @selector(shutdownServer:))
        {
            isValid = YES;
            goto validateMenuItemDone;
        }

        if (action == @selector(chooseEncoding:)) {
            isValid = [activeWindowController validateLightweightEncodingMenuItem:menuItem];
            goto validateMenuItemDone;
        }

        if (action == @selector(copyCreateTableSyntax:) ||
            action == @selector(showCreateTableSyntax:))
        {
            isValid = [activeWindowController selectedLightweightTableCount] > 0;
            goto validateMenuItemDone;
        }

        if (action == @selector(checkTable:) ||
            action == @selector(analyzeTable:) ||
            action == @selector(repairTable:) ||
            action == @selector(optimizeTable:) ||
            action == @selector(flushTable:) ||
            action == @selector(checksumTable:))
        {
            isValid = [self validateLightweightTableMaintenanceMenuItem:menuItem forWindowController:activeWindowController];
            goto validateMenuItemDone;
        }

        if (action == @selector(removeDatabase:) ||
            action == @selector(copyDatabase:) ||
            action == @selector(renameDatabase:) ||
            action == @selector(alterDatabase:) ||
            action == @selector(refreshTables:) ||
            action == @selector(openDatabaseInNewTab:))
        {
            isValid = [activeWindowController hasSelectedLightweightDatabase];
            goto validateMenuItemDone;
        }
    }

    if (action == @selector(printDocument:)) {
        isValid = NO;
        goto validateMenuItemDone;
    }

    if (action == @selector(copy:)) {
        isValid = NO;
        goto validateMenuItemDone;
    }

    if (action == @selector(showGotoDatabase:) ||
        action == @selector(addDatabase:) ||
        action == @selector(removeDatabase:) ||
        action == @selector(copyDatabase:) ||
        action == @selector(renameDatabase:) ||
        action == @selector(alterDatabase:) ||
        action == @selector(refreshTables:) ||
        action == @selector(flushPrivileges:) ||
        action == @selector(setDatabases:) ||
        action == @selector(showUserManager:) ||
        action == @selector(chooseEncoding:) ||
        action == @selector(openDatabaseInNewTab:) ||
        action == @selector(showServerVariables:) ||
        action == @selector(showServerProcesses:) ||
        action == @selector(shutdownServer:) ||
        action == @selector(copyCreateTableSyntax:) ||
        action == @selector(showCreateTableSyntax:) ||
        action == @selector(viewStructure:) ||
        action == @selector(viewContent:) ||
        action == @selector(viewQuery:) ||
        action == @selector(viewStatus:) ||
        action == @selector(viewRelations:) ||
        action == @selector(viewTriggers:) ||
        action == @selector(showMySQLHelp:) ||
        action == @selector(focusOnTableContentFilter:) ||
        action == @selector(showFilterTable:) ||
        action == @selector(makeTableListFilterHaveFocus:) ||
        action == @selector(checkTable:) ||
        action == @selector(analyzeTable:) ||
        action == @selector(repairTable:) ||
        action == @selector(optimizeTable:) ||
        action == @selector(flushTable:) ||
        action == @selector(checksumTable:))
    {
        isValid = NO;
        goto validateMenuItemDone;
    }

validateMenuItemDone:
    if (uiDiagnosticsEnabled) {
        NSTimeInterval validationElapsed = SAUIMonotonicTime() - validationStartTime;
        if (validationElapsed >= SAUIDiagnosticsSlowMenuValidationThreshold) {
            SAUIDiagnosticLog(@"slow validateMenuItem action=%@ elapsed=%.3fs result=%d context=%@",
                    action ? NSStringFromSelector(action) : @"nil",
                    validationElapsed,
                    isValid,
                    [self _uiDiagnosticsContext]);
        }
    }
    return isValid;
}

#pragma mark -
#pragma mark Open methods

/**
 * NSOpenPanel delegate to control encoding popup and allowMultipleSelection
 */
- (void)panelSelectionDidChange:(id)sender
{
    if ([sender isKindOfClass:[NSOpenPanel class]]) {
        if([[[[[sender URL] path] pathExtension] lowercaseString] isEqualToString:SPFileExtensionSQL]) {
            [encodingPopUp setEnabled:YES];
        } else {
            [encodingPopUp setEnabled:NO];
        }
    }
}

/**
 * NSOpenPanel for selecting sql or spf file
 */
- (IBAction)openConnectionSheet:(id)sender
{
    // Avoid opening more than NSOpenPanel
    if (encodingPopUp) {
        NSBeep();
        return;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];

    [panel setDelegate:self];
    [panel setCanSelectHiddenExtension:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setResolvesAliases:YES];

    // If no lastSqlFileEncoding in prefs set it to UTF-8
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

    if (![prefs integerForKey:SPLastSQLFileEncoding]) {
        [prefs setInteger:4 forKey:SPLastSQLFileEncoding];
    }

    [panel setAccessoryView:[SPEncodingPopupAccessory encodingAccessory:[prefs integerForKey:SPLastSQLFileEncoding]
                                                    includeDefaultEntry:NO encodingPopUp:&encodingPopUp]];

    // it will enabled if user selects a *.sql file
    [encodingPopUp setEnabled:NO];

    [panel setAllowedContentTypes:@[[UTType typeWithFilenameExtension:SPFileExtensionDefault], [UTType typeWithFilenameExtension:SPFileExtensionSQL], [UTType typeWithFilenameExtension:SPBundleFileExtension]]];

    // Check if at least one document exists, if so show a sheet
    if ([self.tabManager activeWindowController]) {

        [panel beginSheetModalForWindow:[[self.tabManager activeWindowController] window] completionHandler:^(NSInteger returnCode) {
            if (returnCode) {
                [panel orderOut:self];

                NSMutableArray *filePaths = [NSMutableArray arrayWithCapacity:[[panel URLs] count]];

                [[panel URLs] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop)
                 {
                    [filePaths addObject:[obj path]];
                }];

                [self application:NSApp openFiles:filePaths];
            }
        }];
    }
    else {
        NSInteger returnCode = [panel runModal];

        if (returnCode) {
            NSMutableArray *filePaths = [NSMutableArray arrayWithCapacity:[[panel URLs] count]];

            [[panel URLs] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop)
             {
                [filePaths addObject:[obj path]];
            }];

            [self application:NSApp openFiles:filePaths];
        }
    }

    encodingPopUp = nil;
}

/**
 * Called if user drag and drops files on Sequel Ace's dock item or double-clicked
 * at files *.spf or *.sql
 */
- (void)application:(NSApplication *)app openFiles:(NSArray *)filenames
{
    for (NSString *filePath in filenames)
    {
        NSString *fileExt = [[filePath pathExtension] lowercaseString];
        // Opens a sql file and insert its content into the Custom Query editor
        if ([fileExt isEqualToString:[SPFileExtensionSQL lowercaseString]]) {
            [self openSQLFileAtPath:filePath];
            break; // open only the first SQL file
        }
        else if ([fileExt isEqualToString:[SPFileExtensionDefault lowercaseString]]) {
            [self openConnectionFileAtPath:filePath];
        }
        else if ([fileExt isEqualToString:[SPBundleFileExtension lowercaseString]]) {
            [self openSessionBundleAtPath:filePath];
        }
        else if ([fileExt isEqualToString:[SPColorThemeFileExtension lowercaseString]]) {
            [self openColorThemeFileAtPath:filePath];
        }
        else if ([fileExt isEqualToString:[SPUserBundleFileExtension lowercaseString]] || [fileExt isEqualToString:[SPUserBundleFileExtensionV2 lowercaseString]]) {
            [SPBundleManager.shared openUserBundleAtPath:filePath];
        }
        else {
            NSBeep();
            SPLog(@"Only files with the extensions ‘%@’, ‘%@’, ‘%@’, ‘%@’, ‘%@’ or ‘%@’ are allowed.", SPFileExtensionDefault, SPBundleFileExtension, SPUserBundleFileExtensionV2, SPUserBundleFileExtension, SPColorThemeFileExtension, SPFileExtensionSQL);
        }
    }
}

- (void)openConnectionFileAtPath:(NSString *)filePath {
    SPWindowController *windowController = [self.tabManager newWindowForWindow];
    switch ([self openLightweightConnectionFileAtPath:filePath windowController:windowController]) {
        case SALightweightConnectionFileOpenSucceeded:
            [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filePath]];
            break;
        case SALightweightConnectionFileOpenHandledFailure:
            [windowController close];
            break;
        case SALightweightConnectionFileOpenUnsupported:
            [[windowController legacyDatabaseDocumentForExplicitFallbackWithReason:@"Open connection file required legacy database view"] setStateFromConnectionFile:filePath];
            [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filePath]];
            break;
    }
}

- (SALightweightConnectionFileOpenResult)openLightweightConnectionFileAtPath:(NSString *)filePath windowController:(SPWindowController *)windowController
{
    return [self openLightweightConnectionFileAtPath:filePath windowController:windowController savedInBundle:NO];
}

- (SALightweightConnectionFileOpenResult)openLightweightConnectionFileAtPath:(NSString *)filePath windowController:(SPWindowController *)windowController savedInBundle:(BOOL)savedInBundle {
    NSError *error = nil;
    NSData *pData = [NSData dataWithContentsOfFile:filePath
                                           options:NSUncachedRead
                                             error:&error];
    if (!pData || error) {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Connection data file couldn't be read. (%@)", @"error while reading connection data file"), [error localizedDescription]];
        [self showLightweightConnectionFileReadError:message];
        return SALightweightConnectionFileOpenHandledFailure;
    }

    id propertyList = [NSPropertyListSerialization propertyListWithData:pData
                                                                options:NSPropertyListImmutable
                                                                 format:NULL
                                                                  error:&error];
    if (error || ![propertyList isKindOfClass:[NSDictionary class]]) {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Connection data file couldn't be read. (%@)", @"error while reading connection data file"), [error localizedDescription]];
        [self showLightweightConnectionFileReadError:message];
        return SALightweightConnectionFileOpenHandledFailure;
    }

    NSDictionary *spf = (NSDictionary *)propertyList;
    if (![[spf objectForKey:SPFFormatKey] isEqualToString:SPFConnectionContentType]) return SALightweightConnectionFileOpenUnsupported;

    id dataObject = [spf objectForKey:@"data"];
    if (!dataObject) {
        [self showLightweightConnectionFileReadError:NSLocalizedString(@"No data found.", @"no data found")];
        return SALightweightConnectionFileOpenHandledFailure;
    }

    NSDictionary *data = nil;
    NSString *encryptionPassword = @"";
    if ([[spf objectForKey:@"encrypted"] boolValue]) {
        if (![dataObject isKindOfClass:[NSData class]]) {
            [self showLightweightConnectionFileReadError:NSLocalizedString(@"Wrong data format or password.", @"wrong data format or password")];
            return SALightweightConnectionFileOpenHandledFailure;
        }

        NSString *password = nil;
        if (savedInBundle && [[[self spfSessionDocData] objectForKey:@"e_string"] isKindOfClass:[NSString class]]) {
            password = [[self spfSessionDocData] objectForKey:@"e_string"];
            data = [self lightweightConnectionDataFromEncryptedSPF:spf password:password];
        }

	        if (!data) {
	            password = [self promptForLightweightEncryptedConnectionFilePasswordAtPath:filePath];
	            if (!password) return SALightweightConnectionFileOpenHandledFailure;

	            data = [self lightweightConnectionDataFromEncryptedSPF:spf password:password];
	        }

        if (!data) {
            [self showLightweightConnectionFileReadError:NSLocalizedString(@"Wrong data format or password.", @"wrong data format or password")];
            return SALightweightConnectionFileOpenHandledFailure;
        }

	        NSMutableDictionary *spfSessionData = [NSMutableDictionary dictionary];
	        [spfSessionData addEntriesFromDictionary:[self spfSessionDocData]];
	        [spfSessionData setObject:password forKey:@"e_string"];
	        [self setSpfSessionDocData:spfSessionData];
        encryptionPassword = password ?: @"";
	    }
    else if ([dataObject isKindOfClass:[NSDictionary class]]) {
        data = (NSDictionary *)dataObject;
    }
    else {
        return SALightweightConnectionFileOpenUnsupported;
    }

    id connectionObject = [data objectForKey:@"connection"];
    if (![connectionObject isKindOfClass:[NSDictionary class]]) {
        [self showLightweightConnectionFileReadError:NSLocalizedString(@"No connection data found.", @"no connection data found")];
        return SALightweightConnectionFileOpenHandledFailure;
    }
    NSMutableDictionary *connection = [(NSDictionary *)connectionObject mutableCopy];
    [self populateLightweightKeychainReferencesInConnection:connection];
    if ([self lightweightConnectionFileRequiresLegacyPreferences:spf data:data connection:connection]) return SALightweightConnectionFileOpenUnsupported;

    NSDictionary *contextInfo = [self lightweightConnectionDocumentContextFromSPF:spf data:data];
    if ([contextInfo count]) {
        [[SPQueryController sharedQueryController] registerDocumentWithFileURL:[NSURL fileURLWithPath:filePath] andContextInfo:[contextInfo mutableCopy]];
    }

    id lightweightSession = [data objectForKey:@"lightweightSession"];
    if (lightweightSession && ![lightweightSession isKindOfClass:[NSDictionary class]]) return SALightweightConnectionFileOpenUnsupported;
    if (!lightweightSession && [[data objectForKey:@"session"] isKindOfClass:[NSDictionary class]]) {
        lightweightSession = [self lightweightSessionSnapshotFromLegacySession:[data objectForKey:@"session"] connection:connection];
    }

    BOOL autoConnect = [[spf objectForKey:@"auto_connect"] boolValue] || [[data objectForKey:@"auto_connect"] boolValue];
    BOOL includeSession = (lightweightSession != nil) || [[data objectForKey:@"session"] isKindOfClass:[NSDictionary class]];
    BOOL includeQuery = [self lightweightConnectionDataIncludesQuery:data lightweightSession:lightweightSession];
    BOOL savePassword = [[connection objectForKey:@"password"] length] > 0 || [[connection objectForKey:@"ssh_password"] length] > 0;
    [windowController setLightweightConnectionSaveOptionsEncrypted:[[spf objectForKey:@"encrypted"] boolValue]
                                               encryptionPassword:encryptionPassword
                                                     autoConnect:autoConnect
                                                    savePassword:savePassword
                                                  includeSession:includeSession
                                                    includeQuery:includeQuery];

    if (lightweightSession && autoConnect && [windowController respondsToSelector:@selector(restoreLightweightConnectionStateDictionary:)]) {
        BOOL restored = [windowController restoreLightweightConnectionStateDictionary:@{@"connection": connection, @"lightweightSession": lightweightSession}];
        if (restored) {
            [windowController setLightweightConnectionFileURL:[NSURL fileURLWithPath:filePath] savedInBundle:savedInBundle];
        }
        return restored ? SALightweightConnectionFileOpenSucceeded : SALightweightConnectionFileOpenUnsupported;
    }

    if (![windowController applyLightweightConnectionDictionary:connection autoConnect:autoConnect]) return SALightweightConnectionFileOpenUnsupported;
    [windowController setLightweightConnectionFileURL:[NSURL fileURLWithPath:filePath] savedInBundle:savedInBundle];

    if (lightweightSession && [windowController respondsToSelector:@selector(restoreLightweightSessionSnapshotDictionary:)]) {
        [windowController restoreLightweightSessionSnapshotDictionary:lightweightSession];
    }

    return SALightweightConnectionFileOpenSucceeded;
}

- (BOOL)applyLightweightStateDictionary:(NSDictionary *)state toWindowController:(SPWindowController *)windowController
{
    if (![state isKindOfClass:[NSDictionary class]] || !windowController) return NO;

    NSDictionary *data = state;
    id dataObject = [state objectForKey:@"data"];
    if (dataObject) {
        if (![dataObject isKindOfClass:[NSDictionary class]]) return NO;
        data = (NSDictionary *)dataObject;
    }

    id connectionObject = [data objectForKey:@"connection"];
    if (![connectionObject isKindOfClass:[NSDictionary class]]) return NO;

    NSMutableDictionary *connection = [(NSDictionary *)connectionObject mutableCopy];
    [self populateLightweightKeychainReferencesInConnection:connection];
    if ([self lightweightConnectionFileRequiresLegacyPreferences:state data:data connection:connection]) return NO;

    id lightweightSession = [data objectForKey:@"lightweightSession"];
    if (lightweightSession && ![lightweightSession isKindOfClass:[NSDictionary class]]) return NO;
    if (!lightweightSession && [[data objectForKey:@"session"] isKindOfClass:[NSDictionary class]]) {
        lightweightSession = [self lightweightSessionSnapshotFromLegacySession:[data objectForKey:@"session"] connection:connection];
    }

    BOOL autoConnect = [self lightweightStateDictionaryRequestsAutoConnect:state];
    if (lightweightSession && autoConnect && [windowController respondsToSelector:@selector(restoreLightweightConnectionStateDictionary:)]) {
        return [windowController restoreLightweightConnectionStateDictionary:@{@"connection": connection, @"lightweightSession": lightweightSession}];
    }

    if (![windowController applyLightweightConnectionDictionary:connection autoConnect:autoConnect]) return NO;

    if (lightweightSession && [windowController respondsToSelector:@selector(restoreLightweightSessionSnapshotDictionary:)]) {
        [windowController restoreLightweightSessionSnapshotDictionary:lightweightSession];
    }

    return YES;
}

- (BOOL)lightweightStateDictionaryRequestsAutoConnect:(NSDictionary *)state
{
    if (![state isKindOfClass:[NSDictionary class]]) return NO;

    id dataObject = [state objectForKey:@"data"];
    NSDictionary *data = [dataObject isKindOfClass:[NSDictionary class]] ? (NSDictionary *)dataObject : state;
    return [[state objectForKey:@"auto_connect"] boolValue] || [[data objectForKey:@"auto_connect"] boolValue];
}

- (NSString *)promptForLightweightEncryptedConnectionFilePasswordAtPath:(NSString *)filePath
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSAlertStyleInformational];
    [alert setMessageText:NSLocalizedString(@"Connection file is encrypted", @"Connection file is encrypted")];
    [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Please enter the password for ‘%@’:", @"Please enter the password"), [filePath lastPathComponent]]];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];

    NSSecureTextField *passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    [passwordField setStringValue:@""];
    [alert setAccessoryView:passwordField];
    [[alert window] setInitialFirstResponder:passwordField];

    return [alert runModal] == NSAlertFirstButtonReturn ? [passwordField stringValue] : nil;
}

- (NSDictionary *)lightweightConnectionDataFromEncryptedSPF:(NSDictionary *)spf password:(NSString *)password
{
    NSData *encryptedData = [spf objectForKey:@"data"];
    if (![encryptedData isKindOfClass:[NSData class]]) return nil;

    NSDictionary *data = nil;
    @try {
        NSData *decryptedData = [encryptedData dataDecryptedWithPassword:password];
        if ([decryptedData length]) {
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:decryptedData];
            id decodedData = [unarchiver decodeObjectForKey:@"data"];
            [unarchiver finishDecoding];
            if ([decodedData isKindOfClass:[NSDictionary class]]) {
                data = (NSDictionary *)decodedData;
            }
        }
    }
    @catch(NSException *exception) {
        data = nil;
    }

    return data;
}

- (void)showLightweightConnectionFileReadError:(NSString *)message
{
    [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while reading connection data file", @"error while reading connection data file") message:message callback:nil];
}

- (void)populateLightweightKeychainReferencesInConnection:(NSMutableDictionary *)connection {
    NSString *kcid = [connection objectForKey:@"kcid"];
    if (![kcid length]) return;

    SPKeychain *keychain = [[SPKeychain alloc] init];
    NSString *name = [connection objectForKey:@"name"];
    if (![name length]) return;

    if (![[connection objectForKey:@"password"] length] &&
        ![[connection objectForKey:@"connectionKeychainItemName"] length] &&
        ![[connection objectForKey:@"connectionKeychainItemAccount"] length])
    {
        NSString *keychainName = [keychain nameForFavoriteName:name id:kcid];
        NSString *keychainAccount = [keychain accountForUser:[connection objectForKey:@"user"]
                                                        host:[connection objectForKey:@"host"]
                                                    database:[connection objectForKey:@"database"]];
        if ([keychainName length] && [keychainAccount length]) {
            [connection setObject:keychainName forKey:@"connectionKeychainItemName"];
            [connection setObject:keychainAccount forKey:@"connectionKeychainItemAccount"];
        }
    }

    if (![[connection objectForKey:@"ssh_password"] length] &&
        ![[connection objectForKey:@"connectionSSHKeychainItemName"] length] &&
        ![[connection objectForKey:@"connectionSSHKeychainItemAccount"] length])
    {
        NSString *sshKeychainName = [keychain nameForSSHForFavoriteName:name id:kcid];
        NSString *sshKeychainAccount = [keychain accountForSSHUser:[connection objectForKey:@"ssh_user"]
                                                           sshHost:[connection objectForKey:@"ssh_host"]];
        if ([sshKeychainName length] && [sshKeychainAccount length]) {
            [connection setObject:sshKeychainName forKey:@"connectionSSHKeychainItemName"];
            [connection setObject:sshKeychainAccount forKey:@"connectionSSHKeychainItemAccount"];
        }
    }
}

- (BOOL)lightweightConnectionFileRequiresLegacyPreferences:(NSDictionary *)spf data:(NSDictionary *)data connection:(NSDictionary *)connection {
    if ([spf objectForKey:SPQueryFavorites] && ![[spf objectForKey:SPQueryFavorites] isKindOfClass:[NSArray class]]) return YES;
    if ([spf objectForKey:SPContentFilters] && ![[spf objectForKey:SPContentFilters] isKindOfClass:[NSDictionary class]]) return YES;
    if ([spf objectForKey:SPQueryHistory]) {
        if (![[spf objectForKey:SPQueryHistory] isKindOfClass:[NSArray class]]) return YES;
        for (id queryHistoryItem in [spf objectForKey:SPQueryHistory]) {
            if (![queryHistoryItem isKindOfClass:[NSString class]]) return YES;
        }
    }
    if ([data objectForKey:SPQueryFavorites] && ![[data objectForKey:SPQueryFavorites] isKindOfClass:[NSArray class]]) return YES;
    if ([data objectForKey:SPContentFilters] && ![[data objectForKey:SPContentFilters] isKindOfClass:[NSDictionary class]]) return YES;
    if ([data objectForKey:SPQueryHistory]) {
        if (![[data objectForKey:SPQueryHistory] isKindOfClass:[NSArray class]]) return YES;
        for (id queryHistoryItem in [data objectForKey:SPQueryHistory]) {
            if (![queryHistoryItem isKindOfClass:[NSString class]]) return YES;
        }
    }
    if ([data objectForKey:@"session"] && ![[data objectForKey:@"session"] isKindOfClass:[NSDictionary class]]) return YES;
    if ([[data objectForKey:@"session"] isKindOfClass:[NSDictionary class]] && ![self lightweightLegacySessionQueriesObjectIsSupported:[[data objectForKey:@"session"] objectForKey:@"queries"]]) return YES;

    BOOL hasLegacyKeychainID = [[connection objectForKey:@"kcid"] length] > 0;
    BOOL hasPassword = [[connection objectForKey:@"password"] length] > 0;
    BOOL hasLightweightPasswordKeychain = [[connection objectForKey:@"connectionKeychainItemName"] length] > 0 && [[connection objectForKey:@"connectionKeychainItemAccount"] length] > 0;
    if (hasLegacyKeychainID && !hasPassword && !hasLightweightPasswordKeychain) return YES;

    BOOL hasSSHDetails = [[connection objectForKey:@"ssh_host"] length] > 0 || [[connection objectForKey:@"ssh_user"] length] > 0;
    BOOL hasSSHPassword = [[connection objectForKey:@"ssh_password"] length] > 0;
    BOOL hasLightweightSSHKeychain = [[connection objectForKey:@"connectionSSHKeychainItemName"] length] > 0 && [[connection objectForKey:@"connectionSSHKeychainItemAccount"] length] > 0;
    if (hasLegacyKeychainID && hasSSHDetails && !hasSSHPassword && !hasLightweightSSHKeychain) return YES;

    return NO;
}

- (NSDictionary *)lightweightConnectionDocumentContextFromSPF:(NSDictionary *)spf data:(NSDictionary *)data
{
    NSMutableDictionary *contextInfo = [NSMutableDictionary dictionary];

    NSArray *queryFavorites = [spf objectForKey:SPQueryFavorites];
    if (![queryFavorites isKindOfClass:[NSArray class]]) queryFavorites = [data objectForKey:SPQueryFavorites];
    if ([queryFavorites isKindOfClass:[NSArray class]]) {
        [contextInfo setObject:queryFavorites forKey:SPQueryFavorites];
    }

    NSDictionary *contentFilters = [spf objectForKey:SPContentFilters];
    if (![contentFilters isKindOfClass:[NSDictionary class]]) contentFilters = [data objectForKey:SPContentFilters];
    if ([contentFilters isKindOfClass:[NSDictionary class]]) {
        [contextInfo setObject:contentFilters forKey:SPContentFilters];
    }

    NSArray *queryHistory = [spf objectForKey:SPQueryHistory];
    if (![queryHistory isKindOfClass:[NSArray class]]) queryHistory = [data objectForKey:SPQueryHistory];
    if ([queryHistory isKindOfClass:[NSArray class]]) {
        [contextInfo setObject:queryHistory forKey:SPQueryHistory];
    }

    return contextInfo;
}

- (BOOL)lightweightConnectionDataIncludesQuery:(NSDictionary *)data lightweightSession:(NSDictionary *)lightweightSession
{
    NSDictionary *legacySession = [data objectForKey:@"session"];
    if ([legacySession isKindOfClass:[NSDictionary class]]) {
        id queries = [legacySession objectForKey:@"queries"];
        if ([[self lightweightQueryStringFromLegacySessionQueriesObject:queries] length] > 0) return YES;
    }

    NSDictionary *sessionState = [lightweightSession objectForKey:@"state"];
    if ([sessionState isKindOfClass:[NSDictionary class]]) {
        id queries = [sessionState objectForKey:@"queries"];
        if ([queries isKindOfClass:[NSArray class]] && [(NSArray *)queries count] > 0) return YES;
    }

    return NO;
}

- (BOOL)lightweightLegacySessionQueriesObjectIsSupported:(id)queriesObject
{
    if (!queriesObject) return YES;
    if ([queriesObject isKindOfClass:[NSString class]]) return YES;
    if ([queriesObject isKindOfClass:[NSData class]]) {
        if (![(NSData *)queriesObject length]) return YES;
        return [[self lightweightQueryStringFromLegacySessionQueriesObject:queriesObject] length] > 0;
    }

    return NO;
}

- (NSString *)lightweightQueryStringFromLegacySessionQueriesObject:(id)queriesObject
{
    if ([queriesObject isKindOfClass:[NSString class]]) return queriesObject;
    if (![queriesObject isKindOfClass:[NSData class]] || ![(NSData *)queriesObject length]) return nil;

    NSData *queryData = nil;
    @try {
        queryData = [(NSData *)queriesObject decompress];
    }
    @catch(NSException *exception) {
        queryData = nil;
    }

    if (![queryData length]) return nil;
    return [[NSString alloc] initWithData:queryData encoding:NSUTF8StringEncoding];
}

- (NSDictionary *)lightweightSessionSnapshotFromLegacySession:(NSDictionary *)session connection:(NSDictionary *)connection
{
    if (![session isKindOfClass:[NSDictionary class]]) return nil;

    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    id databaseObject = [session objectForKey:@"database"] ?: [connection objectForKey:@"database"];
    id tableObject = [session objectForKey:@"table"];
    id viewObject = [session objectForKey:@"view"];
    NSString *database = [databaseObject isKindOfClass:[NSString class]] ? databaseObject : nil;
    NSString *table = [tableObject isKindOfClass:[NSString class]] ? tableObject : nil;
    NSString *view = [viewObject isKindOfClass:[NSString class]] ? viewObject : nil;

    if ([database length]) [snapshot setObject:database forKey:@"selectedDatabase"];
    if ([table length]) [snapshot setObject:table forKey:@"selectedTable"];

    NSNumber *viewMode = @0;
    if ([view isEqualToString:@"SP_VIEW_CONTENT"]) {
        viewMode = @1;
    } else if ([view isEqualToString:@"SP_VIEW_CUSTOMQUERY"]) {
        viewMode = @2;
    } else if ([view isEqualToString:@"SP_VIEW_STATUS"]) {
        viewMode = @3;
    } else if ([view isEqualToString:@"SP_VIEW_RELATIONS"]) {
        viewMode = @4;
    } else if ([view isEqualToString:@"SP_VIEW_TRIGGERS"]) {
        viewMode = @5;
    }
    [snapshot setObject:viewMode forKey:@"viewMode"];

    id queriesObject = [session objectForKey:@"queries"];
    NSString *queries = [self lightweightQueryStringFromLegacySessionQueriesObject:queriesObject];
    if ([queries length]) {
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        id connectionTypeObject = [connection objectForKey:@"type"];
        NSString *connectionType = [connectionTypeObject isKindOfClass:[NSString class]] ? connectionTypeObject : nil;
        BOOL socketConnection = [connectionType isEqualToString:@"SPSocketConnection"];
        id port = [connection objectForKey:@"port"];

        [query setObject:(socketConnection ? @"socket" : @"tcp") forKey:@"transport"];
        [query setObject:(socketConnection ? ([connection objectForKey:@"socket"] ?: @"") : ([connection objectForKey:@"host"] ?: @"")) forKey:@"host"];
        [query setObject:(port ? [port description] : @"") forKey:@"port"];
        [query setObject:([connection objectForKey:@"user"] ?: @"") forKey:@"username"];
        [query setObject:(database ?: @"") forKey:@"database"];
        [query setObject:(table ?: @"") forKey:@"table"];
        [query setObject:queries forKey:@"text"];

        [snapshot setObject:@{@"version": @1, @"queries": @[query]} forKey:@"state"];
    }

    return [snapshot count] ? snapshot : nil;
}

- (void)openSQLFileAtPath:(NSString *)filePath
{
    // Check size and NSFileType
    NSDictionary *attr = [fileManager attributesOfItemAtPath:filePath error:nil];

    NSURL *sqlFileURL = [NSURL fileURLWithPath:filePath];
    SPWindowController *activeWindowController = [self.tabManager activeWindowController];
    SPDatabaseDocument *frontDocument = [activeWindowController loadedDatabaseDocumentIfAvailable];

    // If the user came from an openPanel use the chosen encoding, otherwise attempt to autodetect it.
    NSStringEncoding sqlEncoding = encodingPopUp ? [[encodingPopUp selectedItem] tag] : [fileManager detectEncodingforFileAtPath:filePath];

    if (attr)
    {
        NSNumber *filesize = [attr objectForKey:NSFileSize];
        NSString *filetype = [attr objectForKey:NSFileType];
        if(filetype == NSFileTypeRegular && filesize)
        {
            // Ask for confirmation if file content is larger than 1MB
            if ([filesize unsignedLongValue] > 1000000)
            {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setAlertStyle:NSAlertStyleWarning];
                [alert setMessageText:NSLocalizedString(@"Warning",@"warning")];
                [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you really want to load a SQL file with %@ of data into the Query Editor?", @"message of panel asking for confirmation for loading large text into the query editor"), [NSByteCountFormatter stringWithByteSize:[filesize longLongValue]]]];
                [alert setHelpAnchor:filePath];


                // Order of buttons matters! first button has "firstButtonReturn" return value from runModal
                [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
                [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];

                // Show 'Import' button only if there's a connection available
                BOOL activeLightweightCanImportSQL = [activeWindowController canImportLightweightSQL];
                if (frontDocument || activeLightweightCanImportSQL) {
                    [alert addButtonWithTitle:NSLocalizedString(@"Import", @"import button")];
                }

                NSUInteger returnCode = [alert runModal];
                switch (returnCode) {
                    case NSAlertSecondButtonReturn: // Cancel
                        return;
                    case NSAlertThirdButtonReturn: { // Import
                        if (frontDocument) {
                            [[frontDocument tableDumpInstance] startSQLImportProcessWithFile:filePath];
                        }
                        else if (activeLightweightCanImportSQL) {
                            if (encodingPopUp) {
                                [[NSUserDefaults standardUserDefaults] setInteger:sqlEncoding forKey:SPLastSQLFileEncoding];
                            }
                            [activeWindowController importLightweightSQLFileAtURL:sqlFileURL encoding:@(sqlEncoding)];
                        }
                        return;
                    }
                    default: // Ok - just proceed
                        break;
                }
            }
        }
    }

    // Attempt to open the file into a string.
    NSString *sqlString = nil;

    NSError *error = nil;

    sqlString = [NSString stringWithContentsOfFile:filePath encoding:sqlEncoding error:&error];

    if (error != nil) {
        NSAlert *errorAlert = [NSAlert alertWithError:error];
        [errorAlert runModal];

        return;
    }

    // if encodingPopUp is defined the filename comes from an openPanel and
    // the encodingPopUp contains the chosen encoding; otherwise autodetect encoding
    if (encodingPopUp) {
        [[NSUserDefaults standardUserDefaults] setInteger:[[encodingPopUp selectedItem] tag] forKey:SPLastSQLFileEncoding];
    }

    if ([activeWindowController hasActiveLightweightConnection] && ![activeWindowController loadedDatabaseDocumentIfAvailable]) {
        [activeWindowController doPerformLightweightLoadQueryService:sqlString fileURL:sqlFileURL encoding:sqlEncoding];
        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:sqlFileURL];
        return;
    }

    frontDocument = [activeWindowController loadedDatabaseDocumentIfAvailable];

    // If there is no loaded legacy document, keep the new/active window lightweight and load the SQL after connect.
    if (!frontDocument) {
        SPWindowController *targetWindowController = activeWindowController ?: [self.tabManager newWindowForWindow];
        [targetWindowController queueLightweightSQLFileOpenWithString:sqlString fileURL:sqlFileURL encoding:sqlEncoding];
        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:sqlFileURL];
        return;
    }

    // Pass query to the Query editor of the current document
    [frontDocument doPerformLoadQueryService:sqlString];

    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:sqlFileURL];

    [frontDocument setSqlFileURL:sqlFileURL];
    [frontDocument setSqlFileEncoding:sqlEncoding];
}

- (void)openSessionBundleAtPath:(NSString *)filePath {
    NSError *error = nil;
    NSData *pData = [NSData dataWithContentsOfFile:[filePath stringByAppendingPathComponent:@"info.plist"]
                                           options:NSUncachedRead
                                             error:&error];

    NSDictionary *spfs = nil;
    if (pData && !error) {
        spfs = [NSPropertyListSerialization propertyListWithData:pData
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:&error];
    }

    if (!spfs || error) {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Connection data file couldn't be read. (%@)", @"error while reading connection data file"), [error localizedDescription]];
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while reading connection data file", @"error while reading connection data file") message:message callback:nil];

        return;
    }

    if ([spfs objectForKey:@"windows"] && [[spfs objectForKey:@"windows"] isKindOfClass:[NSArray class]]) {

        // Retrieve Save Panel accessory view data for remembering them globally
        NSMutableDictionary *spfsDocData = [NSMutableDictionary dictionary];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"encrypted"] boolValue]] forKey:@"encrypted"];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"auto_connect"] boolValue]] forKey:@"auto_connect"];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"save_password"] boolValue]] forKey:@"save_password"];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"include_session"] boolValue]] forKey:@"include_session"];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"save_editor_content"] boolValue]] forKey:@"save_editor_content"];

        // Set global session properties
        [self setSpfSessionDocData:spfsDocData];

        // Loop through each defined window in reversed order to reconstruct the last active window
        for (NSDictionary *windowDictionary in [[[spfs objectForKey:@"windows"] reverseObjectEnumerator] allObjects]) {

            NSWindow *window = nil;

            // Loop through all defined tabs / windows
            for (NSDictionary *tab in [windowDictionary objectForKey:@"tabs"]) {

                // Add new the tab or window
                SPWindowController *newWindowController = window == nil ? [self.tabManager newWindowForWindow] : [self.tabManager newWindowForTabInWindow:window];
                if (window == nil) {
                    window = newWindowController.window;
                }

                usleep(1000);

                NSTimeInterval frameStartTime = SAUIDiagnosticsEnabled() ? SAUIMonotonicTime() : 0;
                [window setFrameFromString:[windowDictionary objectForKey:@"frame"]];
                [self _logUIDiagnosticsWindowTiming:@"openSessionBundle setFrameFromString" window:window startTime:frameStartTime];

                if ([[tab objectForKey:@"isLightweight"] boolValue]) {
                    if (![newWindowController restoreLightweightConnectionStateDictionary:[tab objectForKey:@"lightweightState"]]) {
                        break;
                    }
                    window = newWindowController.window;
                } else {
                    NSString *fileName = nil;
                    BOOL isBundleFile = NO;

                    // If isAbsolutePath then take this path directly
                    // otherwise construct the releative path for the passed spfs file
                    if ([[tab objectForKey:@"isAbsolutePath"] boolValue]) {
                        fileName = [tab objectForKey:@"path"];
                    } else {
                        fileName = [NSString stringWithFormat:@"%@/Contents/%@", filePath, [tab objectForKey:@"path"]];
                        isBundleFile = YES;
                    }

                    // Security check if file really exists
                    if ([fileManager fileExistsAtPath:fileName]) {
                        SALightweightConnectionFileOpenResult openResult = [self openLightweightConnectionFileAtPath:fileName windowController:newWindowController savedInBundle:isBundleFile];
                        if (openResult == SALightweightConnectionFileOpenHandledFailure) {
                            break;
                        }
                        if (openResult == SALightweightConnectionFileOpenUnsupported) {
                            SPDatabaseDocument *document = [newWindowController legacyDatabaseDocumentForExplicitFallbackWithReason:@"SPFS bundle connection file required legacy database view"];
                            [document setIsSavedInBundle:isBundleFile];
                            if (![document setStateFromConnectionFile:fileName]) {
                                break;
                            }
                        }
                        window = newWindowController.window;
                    } else {
                        SPLog(@"Bundle file “%@” does not exists", fileName);
                        NSBeep();
                    }
                }
                if ([window isMiniaturized]) {
                    [window deminiaturize:self];
                }
            }
        }
    }

    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filePath]];
}

- (void)openColorThemeFileAtPath:(NSString *)filePath {
    NSString *themePath = [fileManager applicationSupportDirectoryForSubDirectory:SPThemesSupportFolder error:nil];

    if (!themePath) return;

    if (![fileManager fileExistsAtPath:themePath isDirectory:nil]) {
        if (![fileManager createDirectoryAtPath:themePath withIntermediateDirectories:YES attributes:nil error:nil]) {
            NSBeep();
            return;
        }
    }

    NSString *newPath = [NSString stringWithFormat:@"%@/%@", themePath, [filePath lastPathComponent]];

    if (![fileManager fileExistsAtPath:newPath isDirectory:nil]) {
        if (![fileManager moveItemAtPath:filePath toPath:newPath error:nil]) {
            NSBeep();
            return;
        }
    }
    else {
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Error while installing color theme file", @"error while installing color theme file")] message:[NSString stringWithFormat:NSLocalizedString(@"The color theme ‘%@’ already exists.", @"the color theme ‘%@’ already exists."), [filePath lastPathComponent]] callback:nil];
        return;
    }
}


#pragma mark -
#pragma mark URL scheme handler

/**
 * sequelace://” url dispatcher
 *
 * sequelace://PROCESS_ID@command/parameter1/parameter2/...
 *    parameters has to be escaped according to RFC 1808  eg %3F for a '?'
 *
 */
- (void)handleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
    NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];

    if ([[url scheme] isEqualToString:@"sequelace"]) {
        [self handleEventWithURL:url];
    }
    else if([[url scheme] isEqualToString:@"mysql"]) {
        [self handleMySQLConnectWithURL:url];
    }
    else {
        NSBeep();
        SPLog(@"Error in sequelace URL scheme for URL <%@>",url);
    }
}

- (void)handleMySQLConnectWithURL:(NSURL *)url {
    // Parse connection string using Swift helper
    ConnectionStringParseResult *result = [ConnectionStringParser parse:url];
    NSMutableDictionary *details = [result.details mutableCopy];
    BOOL connect = result.autoConnect;
    NSArray<NSString *> *invalidParameters = result.invalidParameters;
    BOOL parsed = result.success;

    if (!parsed) {
        if ([invalidParameters count] > 0) {
            NSArray<NSString *> *validParameters = [ConnectionStringParser validQueryParameters];
            NSBeep();
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error")
                                         message:[NSString stringWithFormat:@"%@:\n\n%@: %@\n\n%@: %@",
                                                  NSLocalizedString(@"Error for", @"error for message"),
                                                  NSLocalizedString(@"Invalid query parameters given", @"Invalid query parameters given"),
                                                  [invalidParameters componentsJoinedByString:@", "],
                                                  NSLocalizedString(@"Allowed query parameters are", @"Allowed query parameters are"),
                                                  [validParameters componentsJoinedByString:@", "]]
                                        callback:nil];
        } else {
            SPLog(@"unsupported url scheme: %@", url);
        }
        return;
    }

    SPWindowController *windowController = [self.tabManager newWindowForWindow];
    if ([windowController applyLightweightConnectionDictionary:details autoConnect:connect]) {
        return;
    }

    [[windowController legacyDatabaseDocumentForExplicitFallbackWithReason:@"URL scheme connection required legacy database view"] setState:@{@"connection":details,@"auto_connect": @(connect)} fromFile:NO];
}

- (void)handleEventWithURL:(NSURL*)url
{
    NSString *command = [url host];
    NSString *passedProcessID = [url user];
    NSArray *parameter;
    NSArray *pathComponents;
    if([[url absoluteString] hasSuffix:@"/"])
        pathComponents = [[[url absoluteString] substringToIndex:[[url absoluteString] length]-1] pathComponents];
    else
        pathComponents = [[url absoluteString] pathComponents];

    // remove percent encoding
    NSMutableArray *decodedPathComponents = [NSMutableArray arrayWithCapacity:pathComponents.count];
    for (NSString *component in pathComponents) {
        NSString *decoded;

        if(component.isPercentEncoded){
            decoded = component.stringByRemovingPercentEncoding;
        }
        else {
            decoded = component;
        }
        [decodedPathComponents addObject:decoded];
    }
    pathComponents = decodedPathComponents.copy;

    if([pathComponents count] > 2)
        parameter = [pathComponents subarrayWithRange:NSMakeRange(2, [pathComponents count]-2)];
    else
        parameter = @[];

    // Handle commands which don't need a connection window
    if([command isEqualToString:@"chooseItemFromList"]) {
        NSString *statusFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], (passedProcessID && [passedProcessID length]) ? passedProcessID : @""];
        NSString *resultFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], (passedProcessID && [passedProcessID length]) ? passedProcessID : @""];
        [fileManager removeItemAtPath:statusFileName error:nil];
        [fileManager removeItemAtPath:resultFileName error:nil];
        NSString *result = @"";
        NSString *status = @"0";
        if([parameter count]) {
            NSInteger idx = [SPChooseMenuItemDialog withItems:parameter atPosition:[NSEvent mouseLocation]];
            if(idx > -1) {
                result = [parameter objectAtIndex:idx];
            }
        }
        if(![status writeToFile:statusFileName atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
            NSBeep();
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"BASH Error", @"bash error") message:NSLocalizedString(@"Status file for sequelace url scheme command couldn't be written!", @"status file for sequelace url scheme command couldn't be written error message") callback:nil];
        }
        [result writeToFile:resultFileName atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    
    if ([command isEqualToString:@"LaunchFavorite"]) {
        NSString *targetBookmarkName = nil;
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *queryItem in components.queryItems) {
            if ([queryItem.name isEqualToString:@"name"]) {
                targetBookmarkName = queryItem.value;
                break;
            }
        }
        
        if (targetBookmarkName && [targetBookmarkName length]) {
            SPTreeNode *targetFavoriteNode = nil;
            SPTreeNode *favoritesTree = [SPFavoritesController sharedFavoritesController].favoritesTree;
            for (SPTreeNode *favoriteNode in [favoritesTree allChildLeafs]) {
                if ([favoriteNode.dictionaryRepresentation[SPFavoriteNameKey] isEqualToString:targetBookmarkName]) {
                    targetFavoriteNode = favoriteNode;
                    break;
                }
            }
            
            if (targetFavoriteNode) {
                SPWindowController *windowController = [self.tabManager newWindowForWindow];
                if ([windowController applyLightweightFavoriteDictionary:targetFavoriteNode.dictionaryRepresentation autoConnect:YES]) {
                    return;
                }

                SPDatabaseDocument *document = [windowController legacyDatabaseDocumentForExplicitFallbackWithReason:@"LaunchFavorite URL scheme required legacy database view"];
                SPConnectionController *connectionController = document.connectionController;
                SPFavoritesOutlineView *favoritesOutlineView = connectionController.favoritesOutlineView;
                [favoritesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[favoritesOutlineView rowForItem:targetFavoriteNode]] byExtendingSelection:NO];
                [connectionController initiateConnection:connectionController];
                return;
            }
        }
        
        NSBeep();
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"LaunchFavorite URL Scheme Error", @"LaunchFavorite URL Scheme Error") message: [NSString stringWithFormat:@"%@ %@: “%@”", NSLocalizedString(@"The variable in the ?name= query parameter could not be matched with any of your favorites.", @"The variable in the ?name= query parameter could not be matched with any of your favorites."), NSLocalizedString(@"Variable", @"Variable"), targetBookmarkName] callback:nil];
        
        return;
    }

    if([command isEqualToString:@"SyntaxHighlighting"]) {

        BOOL isDir;

        NSString *anUUID = (passedProcessID && [passedProcessID length]) ? passedProcessID : @"";
        NSString *queryFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], anUUID];
        NSString *resultFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], anUUID];
        NSString *metaFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultMetaPathHeader stringByExpandingTildeInPath], anUUID];
        NSString *statusFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], anUUID];

        NSError *inError = nil;
        NSString *query = [NSString stringWithContentsOfFile:queryFileName encoding:NSUTF8StringEncoding error:&inError];
        NSString *result = @"";
        NSString *status = @"0";

        if([fileManager fileExistsAtPath:queryFileName isDirectory:&isDir] && !isDir) {

            if(inError == nil && query && [query length]) {
                if([parameter count] > 0) {
                    if([[parameter lastObject] isEqualToString:@"html"])
                        result = [NSString stringWithString:[self doSQLSyntaxHighlightForString:query cssLike:NO]];
                    else if([[parameter lastObject] isEqualToString:@"htmlcss"])
                        result = [NSString stringWithString:[self doSQLSyntaxHighlightForString:query cssLike:YES]];
                }
            }
        }

        [fileManager removeItemAtPath:queryFileName error:nil];
        [fileManager removeItemAtPath:resultFileName error:nil];
        [fileManager removeItemAtPath:metaFileName error:nil];
        [fileManager removeItemAtPath:statusFileName error:nil];

        if(![result writeToFile:resultFileName atomically:YES encoding:NSUTF8StringEncoding error:nil])
            status = @"1";

        // write status file as notification that query was finished
        BOOL succeed = [status writeToFile:statusFileName atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if(!succeed) {
            NSBeep();
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"BASH Error", @"bash error") message:NSLocalizedString(@"Status file for sequelace url scheme command couldn't be written!", @"status file for sequelace url scheme command couldn't be written error message") callback:nil];
        }
        return;
    }

    SPWindowController *processWindowController = nil;
    SPDatabaseDocument *processDocument = nil;

    // Try to find the SPDatabaseDocument which sent the the url scheme command
    // For speed check the front most first otherwise iterate through all
    if (passedProcessID && [passedProcessID length]) {
        processWindowController = [self windowControllerForBundleProcessID:passedProcessID];
        processDocument = [self connectedDatabaseDocumentForWindowController:processWindowController];
    }

    // if no processDoc found and no passedProcessID was passed execute
    // command at front most active window
    if(!processWindowController && !passedProcessID) {
        processWindowController = [self bundleEnvironmentWindowController];
        processDocument = [self connectedDatabaseDocumentForWindowController:processWindowController];
    }

    if(processDocument && command) {
        if([command isEqualToString:@"passToDoc"]) {
            NSMutableDictionary *cmdDict = [NSMutableDictionary dictionary];
            [cmdDict setObject:parameter forKey:@"parameter"];
            [cmdDict setObject:(passedProcessID)?:@"" forKey:@"id"];
            [processDocument handleSchemeCommand:cmdDict];
        } else {
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error") message:[NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [command description], NSLocalizedString(@"sequelace URL scheme command not supported.", @"sequelace URL scheme command not supported.")] callback:nil];

            // If command failed notify the file handle hand shake mechanism
            NSString *out = @"1";
            NSString *anUUID = @"";
            if(command && passedProcessID && [passedProcessID length])
                anUUID = passedProcessID;
            else
                anUUID = command;

            [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], anUUID]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];

            out = @"Error";
            [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], anUUID]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];

        }

        return;

    }

    if(processWindowController && [processWindowController hasActiveLightweightConnection] && command) {
        if([command isEqualToString:@"passToDoc"]) {
            NSMutableDictionary *cmdDict = [NSMutableDictionary dictionary];
            [cmdDict setObject:parameter forKey:@"parameter"];
            [cmdDict setObject:(passedProcessID)?:@"" forKey:@"id"];
            if ([processWindowController handleLightweightSchemeCommand:cmdDict]) {
                return;
            }
        } else {
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error") message:[NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [command description], NSLocalizedString(@"sequelace URL scheme command not supported.", @"sequelace URL scheme command not supported.")] callback:nil];

            // If command failed notify the file handle hand shake mechanism
            NSString *out = @"1";
            NSString *anUUID = @"";
            if(command && passedProcessID && [passedProcessID length])
                anUUID = passedProcessID;
            else
                anUUID = command;

            [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], anUUID]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];

            out = @"Error";
            [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], anUUID]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];
        }

        return;
    }

    if(passedProcessID && [passedProcessID length]) {
        // If command failed notify the file handle hand shake mechanism
        NSString *out = @"1";
        [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], passedProcessID]
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
        out = NSLocalizedString(@"An error for sequelace URL scheme command occurred. Probably no corresponding connection window found.", @"An error for sequelace URL scheme command occurred. Probably no corresponding connection window found.");
        [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], passedProcessID]
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];

        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error") message:[NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [command description], NSLocalizedString(@"An error for sequelace URL scheme command occurred. Probably no corresponding connection window found.", @"An error for sequelace URL scheme command occurred. Probably no corresponding connection window found.")] callback:nil];

        usleep(5000);
        [fileManager removeItemAtPath:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], passedProcessID] error:nil];
        [fileManager removeItemAtPath:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], passedProcessID] error:nil];
        [fileManager removeItemAtPath:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultMetaPathHeader stringByExpandingTildeInPath], passedProcessID] error:nil];
        [fileManager removeItemAtPath:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], passedProcessID] error:nil];
    } else {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error") message: [NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [command description], NSLocalizedString(@"An error occur while executing a scheme command. If the scheme command was invoked by a Bundle command, it could be that the command still runs. You can try to terminate it by pressing ⌘+. or via the Activities pane.", @"an error occur while executing a scheme command. if the scheme command was invoked by a bundle command, it could be that the command still runs. you can try to terminate it by pressing ⌘+. or via the activities pane.")] callback:nil];
    }

    if(processDocument)
        SPLog(@"process doc ID: %@\n%@", [processDocument processID], [processDocument tabTitleForTooltip]);
    else if(processWindowController)
        SPLog(@"process lightweight ID: %@", [processWindowController lightweightBundleProcessIDValue]);
    else
        SPLog(@"No corresponding doc found");
    SPLog(@"param: %@", parameter);
    SPLog(@"command: %@", command);
    SPLog(@"command id: %@", passedProcessID);

}

/**
 * Return an HTML formatted string representing the passed SQL string syntax highlighted
 */
- (NSString*)doSQLSyntaxHighlightForString:(NSString*)sqlText cssLike:(BOOL)cssLike
{
    NSMutableString *sqlHTML = [[NSMutableString alloc] initWithCapacity:[sqlText length]];

    NSString *tokenColor;
    NSString *cssId;
    size_t token;
    NSRange tokenRange;

    // initialise flex
    yyuoffset = 0; yyuleng = 0;
    yy_switch_to_buffer(yy_scan_string([sqlText UTF8String]));
    BOOL skipFontTag;

    while ((token=yylex())) {
        skipFontTag = NO;
        switch (token) {
            case SPT_SINGLE_QUOTED_TEXT:
            case SPT_DOUBLE_QUOTED_TEXT:
                tokenColor = @"#A7221C";
                cssId = @"sp_sql_quoted";
                break;
            case SPT_BACKTICK_QUOTED_TEXT:
                tokenColor = @"#001892";
                cssId = @"sp_sql_backtick";
                break;
            case SPT_RESERVED_WORD:
                tokenColor = @"#0041F6";
                cssId = @"sp_sql_keyword";
                break;
            case SPT_NUMERIC:
                tokenColor = @"#67350F";
                cssId = @"sp_sql_numeric";
                break;
            case SPT_COMMENT:
                tokenColor = @"#265C10";
                cssId = @"sp_sql_comment";
                break;
            case SPT_VARIABLE:
                tokenColor = @"#6C6C6C";
                cssId = @"sp_sql_variable";
                break;
            case SPT_WHITESPACE:
                skipFontTag = YES;
                cssId = @"";
                break;
            default:
                skipFontTag = YES;
                cssId = @"";
        }

        tokenRange = NSMakeRange(yyuoffset, yyuleng);

        if(skipFontTag)
            [sqlHTML appendString:[[sqlText substringWithRange:tokenRange] HTMLEscapeString]];
        else {
            if(cssLike)
                [sqlHTML appendFormat:@"<span class=\"%@\">%@</span>", cssId, [[sqlText substringWithRange:tokenRange] HTMLEscapeString]];
            else
                [sqlHTML appendFormat:@"<font color=%@>%@</font>", tokenColor, [[sqlText substringWithRange:tokenRange] HTMLEscapeString]];
        }

    }

    // Wrap lines, and replace tabs with spaces
    [sqlHTML replaceOccurrencesOfString:@"\n" withString:@"<br>" options:NSLiteralSearch range:NSMakeRange(0, [sqlHTML length])];
    [sqlHTML replaceOccurrencesOfString:@"\t" withString:@"&nbsp;&nbsp;&nbsp;&nbsp;" options:NSLiteralSearch range:NSMakeRange(0, [sqlHTML length])];

    return (sqlHTML) ? sqlHTML : @"";
}



/**
 * Return of certain shell variables mainly for usage in JavaScript support inside the
 * HTML output window to allow to ask on run-time
 */
- (SPDatabaseDocument *)connectedDatabaseDocumentForWindowController:(SPWindowController *)windowController
{
    SPDatabaseDocument *databaseDocument = [windowController loadedDatabaseDocumentIfAvailable];
    return ([databaseDocument getConnection]) ? databaseDocument : nil;
}

- (BOOL)windowControllerHasActiveConnectionTarget:(SPWindowController *)windowController
{
    return ([self connectedDatabaseDocumentForWindowController:windowController] != nil || [windowController hasActiveLightweightConnection]);
}

- (SPWindowController *)keyWindowControllerWithActiveConnectionTarget
{
    SPWindowController *windowController = (SPWindowController *)[[NSApp keyWindow] windowController];
    if (![windowController isKindOfClass:[SPWindowController class]]) {
        return nil;
    }

    return [self windowControllerHasActiveConnectionTarget:windowController] ? windowController : nil;
}

- (SPWindowController *)bundleEnvironmentWindowController
{
    SPWindowController *keyWindowController = [self keyWindowControllerWithActiveConnectionTarget];
    if (keyWindowController) {
        return keyWindowController;
    }

    SPWindowController *activeWindowController = [self.tabManager activeWindowController];
    if ([self windowControllerHasActiveConnectionTarget:activeWindowController]) {
        return activeWindowController;
    }

    for (NSWindow *window in [NSApp orderedWindows]) {
        SPWindowController *windowController = (SPWindowController *)[window windowController];
        if (![windowController isKindOfClass:[SPWindowController class]]) {
            continue;
        }

        if ([self windowControllerHasActiveConnectionTarget:windowController]) {
            return windowController;
        }
    }

    for (SPWindowController *windowController in [self.tabManager windowControllers]) {
        if ([self windowControllerHasActiveConnectionTarget:windowController]) {
            return windowController;
        }
    }

    return activeWindowController;
}

- (SPWindowController *)windowControllerForBundleProcessID:(NSString *)processID
{
    if (![processID length]) {
        return nil;
    }

    SPWindowController *activeWindowController = [self.tabManager activeWindowController];
    SPDatabaseDocument *activeDocument = [self connectedDatabaseDocumentForWindowController:activeWindowController];
    if ([[activeDocument processID] isEqualToString:processID] || [[activeWindowController lightweightBundleProcessIDValue] isEqualToString:processID]) {
        return activeWindowController;
    }

    for (SPWindowController *windowController in [self.tabManager windowControllers]) {
        SPDatabaseDocument *databaseDocument = [self connectedDatabaseDocumentForWindowController:windowController];
        if ([[databaseDocument processID] isEqualToString:processID] || [[windowController lightweightBundleProcessIDValue] isEqualToString:processID]) {
            return windowController;
        }
    }

    return nil;
}

- (void)addBundleCallbackEnvironmentToDictionary:(NSMutableDictionary *)environment processID:(NSString *)processID
{
    if (![processID length]) {
        return;
    }

    [environment setObject:processID forKey:SPBundleShellVariableProcessID];
    [environment setObject:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], processID] forKey:SPBundleShellVariableQueryFile];
    [environment setObject:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], processID] forKey:SPBundleShellVariableQueryResultFile];
    [environment setObject:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], processID] forKey:SPBundleShellVariableQueryResultStatusFile];
    [environment setObject:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultMetaPathHeader stringByExpandingTildeInPath], processID] forKey:SPBundleShellVariableQueryResultMetaFile];
}

- (NSDictionary *)shellEnvironmentForWindowController:(SPWindowController *)windowController
{
    if (!windowController) {
        return @{};
    }

    SPDatabaseDocument *databaseDocument = [self connectedDatabaseDocumentForWindowController:windowController];
    if (databaseDocument) {
        return [databaseDocument shellVariables] ?: @{};
    }

    if ([windowController hasActiveLightweightConnection]) {
        return [windowController lightweightShellVariables] ?: @{};
    }

    return @{};
}

- (void)prepareBundleEnvironment:(NSMutableDictionary *)environment withProcessID:(NSString *)processID
{
    if (!environment || ![processID length]) {
        return;
    }

    SPWindowController *windowController = [self bundleEnvironmentWindowController];
    SPDatabaseDocument *databaseDocument = [self connectedDatabaseDocumentForWindowController:windowController];
    if (databaseDocument) {
        [databaseDocument setProcessID:processID];
        [self addBundleCallbackEnvironmentToDictionary:environment processID:processID];
        [environment addEntriesFromDictionary:[databaseDocument shellVariables] ?: @{}];
    }
    else if ([windowController hasActiveLightweightConnection]) {
        [windowController assignLightweightBundleProcessID:processID];
        [self addBundleCallbackEnvironmentToDictionary:environment processID:processID];
        [environment addEntriesFromDictionary:[windowController lightweightShellVariables] ?: @{}];
    }

    if([environment objectForKey:SPBundleShellVariableCurrentEditedColumnName] && [[environment objectForKey:SPBundleShellVariableDataTableSource] isEqualToString:@"content"])
        [environment setObject:[environment objectForKey:SPBundleShellVariableSelectedTable] forKey:SPBundleShellVariableCurrentEditedTable];
}

- (id)activeBundleCommandCaller
{
    SPWindowController *windowController = [self bundleEnvironmentWindowController];
    SPDatabaseDocument *databaseDocument = [self connectedDatabaseDocumentForWindowController:windowController];
    if (databaseDocument) {
        return databaseDocument;
    }

    if ([windowController hasActiveLightweightConnection]) {
        return windowController;
    }

    return nil;
}

- (NSDictionary*)shellEnvironmentForDocument:(NSString*)docUUID {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    if (docUUID == nil) {
        [env addEntriesFromDictionary:[self shellEnvironmentForWindowController:[self bundleEnvironmentWindowController]]];
    } else {
        SPWindowController *windowController = [self windowControllerForBundleProcessID:docUUID];
        if (windowController) {
            [env addEntriesFromDictionary:[self shellEnvironmentForWindowController:windowController]];
        }
    }

    id firstResponder = [[NSApp keyWindow] firstResponder];
    if([firstResponder respondsToSelector:@selector(executeBundleItemForInputField:)]) {
        BOOL selfIsQueryEditor = ([[[firstResponder class] description] isEqualToString:@"SPTextView"] && [[firstResponder delegate] respondsToSelector:@selector(currentQueryRange)]);
        NSRange currentWordRange, currentSelectionRange, currentLineRange, currentQueryRange;
        currentSelectionRange = [firstResponder selectedRange];
        currentWordRange = [firstResponder getRangeForCurrentWord];
        currentLineRange = [[firstResponder string] lineRangeForRange:NSMakeRange([firstResponder selectedRange].location, 0)];

        if(selfIsQueryEditor) {
            currentQueryRange = [(SPCustomQuery *)[firstResponder delegate] currentQueryRange];
        } else {
            currentQueryRange = currentLineRange;
        }
        if(!currentQueryRange.length)
            currentQueryRange = currentSelectionRange;

        [env setObject:SPBundleScopeInputField forKey:SPBundleShellVariableBundleScope];

        if(selfIsQueryEditor && [(SPCustomQuery *)[firstResponder delegate] currentQueryRange].length)
            [env setObject:[[firstResponder string] substringWithRange:[(SPCustomQuery *)[firstResponder delegate] currentQueryRange]] forKey:SPBundleShellVariableCurrentQuery];

        if(currentSelectionRange.length)
            [env setObject:[[firstResponder string] substringWithRange:currentSelectionRange] forKey:SPBundleShellVariableSelectedText];

        if(currentWordRange.length)
            [env setObject:[[firstResponder string] substringWithRange:currentWordRange] forKey:SPBundleShellVariableCurrentWord];

        if(currentLineRange.length)
            [env setObject:[[firstResponder string] substringWithRange:currentLineRange] forKey:SPBundleShellVariableCurrentLine];
    }
    else if([firstResponder respondsToSelector:@selector(executeBundleItemForDataTable:)]) {

        if([[firstResponder delegate] respondsToSelector:@selector(usedQuery)] && [[firstResponder delegate] usedQuery])
            [env setObject:[[firstResponder delegate] usedQuery] forKey:SPBundleShellVariableUsedQueryForTable];

        if([firstResponder numberOfSelectedRows]) {
            NSMutableArray *sel = [NSMutableArray array];
            NSIndexSet *selectedRows = [firstResponder selectedRowIndexes];
            [selectedRows enumerateIndexesUsingBlock:^(NSUInteger rowIndex, BOOL * _Nonnull stop) {
                [sel addObject:[NSString stringWithFormat:@"%ld", (long)rowIndex]];
            }];
            [env setObject:[sel componentsJoinedByString:@"\t"] forKey:SPBundleShellVariableSelectedRowIndices];
        }

        [env setObject:SPBundleScopeDataTable forKey:SPBundleShellVariableBundleScope];

    } else {
        [env setObject:SPBundleScopeGeneral forKey:SPBundleShellVariableBundleScope];
    }
    return env;
}

- (void)registerActivity:(NSDictionary*)commandDict
{
    [runningActivitiesArray addObject:commandDict];
    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPActivitiesUpdateNotification object:nil];

    SPDatabaseDocument* frontMostDoc = [self frontDocument];
    if(frontMostDoc) {
        if([runningActivitiesArray count] || [[frontMostDoc runningActivities] count])
            [frontMostDoc performSelector:@selector(setActivityPaneHidden:) withObject:@0 afterDelay:1.0];
        else {
            [NSObject cancelPreviousPerformRequestsWithTarget:frontMostDoc
                                                     selector:@selector(setActivityPaneHidden:)
                                                       object:@0];
            [frontMostDoc setActivityPaneHidden:@1];
        }
    }

}

- (void)removeRegisteredActivity:(NSInteger)pid
{
    for(id cmd in runningActivitiesArray) {
        if([[cmd objectForKey:@"pid"] integerValue] == pid) {
            [runningActivitiesArray removeObject:cmd];
            break;
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPActivitiesUpdateNotification object:nil];

    SPDatabaseDocument* frontMostDoc = [self frontDocument];
    if(frontMostDoc) {
        if([runningActivitiesArray count] || [[frontMostDoc runningActivities] count])
            [frontMostDoc performSelector:@selector(setActivityPaneHidden:) withObject:@0 afterDelay:1.0];
        else {
            [NSObject cancelPreviousPerformRequestsWithTarget:frontMostDoc
                                                     selector:@selector(setActivityPaneHidden:)
                                                       object:@0];
            [frontMostDoc setActivityPaneHidden:@1];
        }
    }
}

- (NSArray*)runningActivities
{
    return (NSArray*)runningActivitiesArray;
}

#pragma mark -
#pragma mark IBAction methods

/**
 * Opens the about panel.
 */
- (IBAction)openAboutPanel:(id)sender
{
    if (!aboutController) {
        aboutController = [[SAAboutWindowController alloc] initWithDelegate:self];
    }

    [aboutController showWindow:self];
}

/**
 * Opens the preferences window.
 */
- (IBAction)openPreferences:(id)sender
{
    [prefsController showWindow:self];
}

#pragma mark -
#pragma mark Accessors

/**
 * Provide a method to retrieve the prefs controller
 */
- (SPPreferenceController *)preferenceController
{
    return prefsController;
}

/**
 * Retrieve the frontmost document; returns nil if not found.
 */
- (SPDatabaseDocument *)frontDocument {
    return [[self.tabManager activeWindowController] loadedDatabaseDocumentIfAvailable];
}

- (NSDictionary *)spfSessionDocData
{
    return _spfSessionDocData;
}

- (void)setSpfSessionDocData:(NSDictionary *)data {
    if (data) {
        _spfSessionDocData = [data mutableCopy];
    } else {
        _spfSessionDocData = [NSMutableDictionary new];
    }
}

#pragma mark -
#pragma mark Services menu methods

/**
 * Passes the query to the frontmost document
 */
- (void)doPerformQueryService:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error
{
    NSString *pboardString;

    NSArray *types = [pboard types];

    if ((![types containsObject:NSPasteboardTypeString]) || (!(pboardString = [pboard stringForType:NSPasteboardTypeString]))) {
        *error = @"Pasteboard couldn't give string.";

        return;
    }

    SPWindowController *windowController = [self bundleEnvironmentWindowController];
    SPDatabaseDocument *databaseDocument = [self connectedDatabaseDocumentForWindowController:windowController];

    // Check if at least one connection target exists
    if (!databaseDocument && ![windowController hasActiveLightweightConnection]) {
        *error = @"No Documents open!";

        return;
    }

    // Pass query to front connection target
    if (databaseDocument) {
        [databaseDocument doPerformQueryService:pboardString];
    }
    else {
        [windowController doPerformLightweightQueryService:pboardString];
    }

    return;
}

#pragma mark -
#pragma mark Sequel Ace menu methods

/**
 * Opens website link in default browser
 */
- (IBAction)visitWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_HOMEPAGE]];
}

/**
 * Opens help link in default browser
 */
- (IBAction)visitHelpWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_DOCUMENTATION]];
}

/**
 * Opens FAQ help link in default browser
 */
- (IBAction)visitFAQWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_FAQ]];
}

/**
 * Opens the 'Keyboard Shortcuts' page in the default browser.
 */
- (IBAction)viewKeyboardShortcuts:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_KEYBOARDSHORTCUTS]];
}

#pragma mark -
#pragma mark Other methods

/**
 * Implement this method to prevent the above being called in the case of a reopen (for example, clicking
 * the dock icon) where we don't want the auto-connect to kick in.
 */
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    // Only create a new document (without auto-connect) when there are already no documents open.
    if ([self.tabManager windowControllers].count == 0) {
        [self.tabManager newWindowForWindow];
        return NO;
    }
    // Return YES to the automatic opening
    return YES;
}

/**
 * If Sequel Ace is terminating kill all running BASH scripts and release all HTML output controller.
 *
 * TODO: Remove a lot of this duplicate code.
 */
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    BOOL fastQuitConfirmationApproved = self.fastQuitConfirmationApproved;
    self.fastQuitConfirmationApproved = NO;

    if ([self hasVisibleWindowForQuitPrompt] && [[NSUserDefaults standardUserDefaults] boolForKey:SPApplicationPromptOnQuit] && !fastQuitConfirmationApproved) {
        BOOL answer = [self dialogOKCancelWithQuestion:NSLocalizedString(@"Close the app?", @"quitting app informal alert title") text:NSLocalizedString(@"Are you sure you want to quit the app?", @"quitting app informal alert body")];
        if (answer == NO) {
            return NSTerminateCancel;
        }
    }

    BOOL shouldSaveFavorites = NO;

    // removing vacuum here. See: https://www.sqlite.org/lang_vacuum.html
    // The VACUUM command may change the ROWIDs of entries in any tables that do not have an explicit INTEGER PRIMARY KEY.

    if (lastBundleBlobFilesDirectory != nil) {
        [fileManager removeItemAtPath:lastBundleBlobFilesDirectory error:nil];
    }

    self.lightweightResumeStateDirty = YES;
    [self savePendingLightweightResumeStateIfNeeded];

    // Iterate through each open window
    for (SPWindowController *windowController in [self.tabManager windowControllers]) {
        SPDatabaseDocument *databaseDocument = [windowController loadedDatabaseDocumentIfAvailable];
        if (!databaseDocument) {
            continue;
        }

        // Kill any BASH commands which are currently active
        for (NSDictionary *cmd in [databaseDocument runningActivities]) {
            NSInteger pid = [[cmd objectForKey:@"pid"] integerValue];
            NSTask *killTask = [[NSTask alloc] init];

            [killTask setLaunchPath:@"/bin/sh"];
            [killTask setArguments:[NSArray arrayWithObjects:@"-c", [NSString stringWithFormat:@"kill -9 -%ld", (long)pid], nil]];
            [killTask launch];
            [killTask waitUntilExit];
        }

        // If the connection view is active, mark the favourites for saving
        if (![databaseDocument getConnection]) {
            shouldSaveFavorites = YES;
        }
    }

    for (NSDictionary* cmd in [self runningActivities]) {
        NSInteger pid = [[cmd objectForKey:@"pid"] integerValue];
        NSTask *killTask = [[NSTask alloc] init];

        [killTask setLaunchPath:@"/bin/sh"];
        [killTask setArguments:[NSArray arrayWithObjects:@"-c", [NSString stringWithFormat:@"kill -9 -%ld", (long)pid], nil]];
        [killTask launch];
        [killTask waitUntilExit];
    }

    // this might catch some stray ssh pids, but probably not.
    NSTask *killTask = [[NSTask alloc] init];
    [killTask setLaunchPath:@"/bin/sh"];
    [killTask setArguments:@[@"-c",[NSString stringWithFormat:@"kill -9 %@", [NSString stringWithString:[sshProcessIDs componentsJoinedByString:@" "]]]]];
    [killTask launch];
    [killTask waitUntilExit];

    // If required, make sure we save any changes made to the connection outline view's state
    if (shouldSaveFavorites) {
        [[SPFavoritesController sharedFavoritesController] saveFavoritesSynchronously];
    }

    // Close any open font panels to prevent them reopening on next launch
    [self closeFontPanelIfOpen];

    return NSTerminateNow;
}

- (BOOL)hasVisibleWindowForQuitPrompt
{
    for (NSWindow *window in [NSApp windows]) {
        if ([window isVisible] && ![window isMiniaturized] && ![window isKindOfClass:[NSPanel class]]) {
            return YES;
        }
    }

    return NO;
}

#pragma mark -
#pragma mark Private API

/**
 * Copy default themes, when we start the app.
 */
- (void)_copyDefaultThemes
{
    NSError *appPathError = nil;

    NSString *defaultThemesPath = [NSString stringWithFormat:@"%@/Default Themes", NSBundle.mainBundle.sharedSupportPath];
    NSString *appSupportThemesPath = [fileManager applicationSupportDirectoryForSubDirectory:SPThemesSupportFolder createIfNotExists:YES error:&appPathError];

    // If ~/Library/Application Path/Sequel Ace/Themes couldn't be created bail
    if (appPathError != nil) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Themes Installation Error", @"themes installation error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't create Application Support Theme folder!\nError: %@", @"Couldn't create Application Support Theme folder!\nError: %@"), [appPathError localizedDescription]] callback:nil];
        return;
    }

    NSError *error = nil;
    NSError *copyError = nil;
    NSArray *defaultThemes = [fileManager contentsOfDirectoryAtPath:defaultThemesPath error:&error];

    if (defaultThemes && [defaultThemes count] && error == nil) {
        for (NSString *defaultTheme in defaultThemes)
        {
            if (![[[defaultTheme pathExtension] lowercaseString] isEqualToString:[SPColorThemeFileExtension lowercaseString]]) continue;

            NSString *defaultThemeFullPath = [NSString stringWithFormat:@"%@/%@", defaultThemesPath, defaultTheme];
            NSString *appSupportThemeFullPath = [NSString stringWithFormat:@"%@/%@", appSupportThemesPath, defaultTheme];

            if ([fileManager fileExistsAtPath:appSupportThemeFullPath]) continue;

            [fileManager copyItemAtPath:defaultThemeFullPath toPath:appSupportThemeFullPath error:&copyError];
        }
    }

    // If Themes could not be copied, show error message
    if (copyError != nil) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Themes Installation Error", @"themes installation error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't copy default themes to Application Support Theme folder!\nError: %@", @"Couldn't copy default themes to Application Support Theme folder!\nError: %@"), [copyError localizedDescription]] callback:nil];
        return;
    }
}

#pragma mark - SPAppleScriptSupport

/**
 * AppleScript call to get the available documents.
 */
- (NSArray *)orderedDocuments
{
    NSMutableArray *orderedDocuments = [NSMutableArray array];

    for (NSWindow *aWindow in [self orderedWindows]) {
        if ([[aWindow windowController] isMemberOfClass:[SPWindowController class]]) {
            SPWindowController *windowController = (SPWindowController *)[aWindow windowController];
            SPDatabaseDocument *databaseDocument = [windowController loadedDatabaseDocumentIfAvailable];
            if (databaseDocument) {
                [orderedDocuments addObject:databaseDocument];
            } else if ([windowController hasActiveLightweightConnection]) {
                id lightweightDocument = [windowController lightweightAppleScriptDocumentProxy];
                if (lightweightDocument) {
                    [orderedDocuments addObject:lightweightDocument];
                }
            }
        }
    }
    return orderedDocuments;
}

/**
 * AppleScript call to get the available windows.
 */
- (NSArray *)orderedWindows
{
    return [NSApp orderedWindows];
}

/**
 * AppleScript handler to quit Sequel Ace
 *
 * This handler is required to allow termination via the Dock or AppleScript event after activating it using AppleScript
 */
- (id)handleQuitScriptCommand:(NSScriptCommand *)command
{
    [NSApp terminate:self];

    return nil;
}

/**
 * AppleScript open handler
 *
 * This handler is required to catch the 'open' command if no argument was passed which would cause a crash.
 */
- (id)handleOpenScriptCommand:(NSScriptCommand *)command
{
    return nil;
}

/**
 * AppleScript print handler
 *
 * This handler prints the active view.
 */
- (id)handlePrintScriptCommand:(NSScriptCommand *)command
{
    SPWindowController *activeWindowController = [self.tabManager activeWindowController];
    SPDatabaseDocument *frontDoc = [activeWindowController loadedDatabaseDocumentIfAvailable];

    if (frontDoc && ![frontDoc isWorking] && ![[frontDoc connectionID] isEqualToString:@"_"]) {
        [frontDoc startPrintDocumentOperation];
    }
    else if ([activeWindowController canPrintLightweightDocument]) {
        [activeWindowController printLightweightDocument:nil];
    }

    return nil;
}

#pragma mark - SPWindowManagement

- (IBAction)newWindowForTab:(id)sender {
    [self.tabManager newWindowForTab];
}

/**
 * Duplicate the current connection tab
 */
- (IBAction)duplicateTab:(id)sender {

    // Get the state of the previously-frontmost document
    SPWindowController *activeWindowController = self.tabManager.activeWindowController;
    NSDictionary *lightweightState = [activeWindowController lightweightConnectionStateDictionaryWithIncludePasswords:YES includeSession:YES includeQuery:YES];
    if ([lightweightState count]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDocumentDuplicateTabNotification object:nil userInfo:@{
            @"isLightweight"    : @YES,
            @"lightweightState" : lightweightState
        }];
        return;
    }

    SPDatabaseDocument *databaseDocument = [activeWindowController loadedDatabaseDocumentIfAvailable];
    if (!databaseDocument) {
        return;
    }

    NSDictionary *allStateDetails = @{
        @"connection" : @YES,
        @"history"    : @YES,
        @"session"    : @YES,
        @"query"      : @YES,
        @"password"   : @YES
    };

    NSMutableDictionary *frontState = [NSMutableDictionary dictionaryWithDictionary:[databaseDocument stateIncludingDetails:allStateDetails]];

    // Ensure it's set to autoconnect
    [frontState setObject:@YES forKey:@"auto_connect"];

    [[NSNotificationCenter defaultCenter] postNotificationName:SPDocumentDuplicateTabNotification object:nil userInfo:frontState];
}

#pragma mark -

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeObserver:self forKeyPath:SPShowUpdateAvailable];
    if(SecureBookmarkManager.sharedInstance != nil) {
        [SecureBookmarkManager.sharedInstance stopAllSecurityScopedAccess];
    }

}

- (IBAction)reloadBundles:(id)sender{
    [SPBundleManager.shared reloadBundles:sender];
}

- (IBAction)openBundleEditor:(id)sender{
    [SPBundleManager.shared openBundleEditor:sender];
}

- (IBAction)bundleCommandDispatcher:(id)sender{
    [SPBundleManager.shared bundleCommandDispatcher:sender];
}

- (void)rebuildMenus{
    // === Rebuild Bundles main menu item ===

    // Get main menu "Bundles"'s submenu
    NSMenu *menu = [[[NSApp mainMenu] itemWithTag:SPMainMenuBundles] submenu];

    // Clean menu
    [menu removeAllItems];

    // Add default menu items
    NSMenuItem *anItem;
    anItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Bundle Editor", @"bundle editor menu item label") action:@selector(openBundleEditor:) keyEquivalent:@"b"];
    [anItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand|NSEventModifierFlagOption|NSEventModifierFlagControl)];
    [menu addItem:anItem];
    anItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Reload Bundles", @"reload bundles menu item label") action:@selector(reloadBundles:) keyEquivalent:@""];
    [menu addItem:anItem];

    // Bail out if no Bundle was installed
    if (!SPBundleManager.shared.foundInstalledBundles) return;

    // Add installed Bundles
    // For each scope add a submenu but not for the last one (should be General always)
    [menu addItem:[NSMenuItem separatorItem]];
    [menu setAutoenablesItems:YES];
    NSArray *scopes = @[SPBundleScopeInputField, SPBundleScopeDataTable, SPBundleScopeGeneral];
    NSArray *scopeTitles = @[
        NSLocalizedString(@"Input Field", @"input field menu item label"),
        NSLocalizedString(@"Data Table", @"data table menu item label"),
        NSLocalizedString(@"General", @"general menu item label")
    ];

    NSUInteger k = 0;
    BOOL bundleOtherThanGeneralFound = NO;
    for(NSString* scope in scopes) {

        NSArray *scopeBundleCategories = [SPBundleManager.shared bundleCategoriesForScope:scope];
        NSArray *scopeBundleItems = [SPBundleManager.shared bundleItemsForScope:scope];

        if(![scopeBundleItems count]) {
            k++;
            continue;
        }

        NSMenu *bundleMenu = nil;
        NSMenuItem *bundleSubMenuItem = nil;

        // Add last scope (General) not as submenu
        if(k < [scopes count]-1) {
            bundleMenu = [[NSMenu alloc] init];
            [bundleMenu setAutoenablesItems:YES];
            bundleSubMenuItem = [[NSMenuItem alloc] initWithTitle:[scopeTitles objectAtIndex:k] action:nil keyEquivalent:@""];
            [bundleSubMenuItem setTag:10000000];

            [menu addItem:bundleSubMenuItem];
            [menu setSubmenu:bundleMenu forItem:bundleSubMenuItem];

        } else {
            bundleMenu = menu;
            if(bundleOtherThanGeneralFound)
                [menu addItem:[NSMenuItem separatorItem]];
        }

        // Add found Category submenus
        NSMutableArray *categorySubMenus = [NSMutableArray array];
        NSMutableArray *categoryMenus = [NSMutableArray array];
        if([scopeBundleCategories count]) {
            for(NSString* title in scopeBundleCategories) {
                [categorySubMenus addObject:[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]];
                [categoryMenus addObject:[[NSMenu alloc] init]];
                [bundleMenu addItem:[categorySubMenus lastObject]];
                [bundleMenu setSubmenu:[categoryMenus lastObject] forItem:[categorySubMenus lastObject]];
            }
        }

        NSInteger i = 0;
        for(NSDictionary *item in scopeBundleItems) {

            NSString *keyEq;
            if([item objectForKey:SPBundleFileKeyEquivalentKey])
                keyEq = [[item objectForKey:SPBundleFileKeyEquivalentKey] objectAtIndex:0];
            else
                keyEq = @"";

            NSMenuItem *mItem = [[NSMenuItem alloc] initWithTitle:[item objectForKey:SPBundleInternLabelKey] action:@selector(bundleCommandDispatcher:) keyEquivalent:keyEq];
            bundleOtherThanGeneralFound = YES;
            if([keyEq length])
                [mItem setKeyEquivalentModifierMask:[[[item objectForKey:SPBundleFileKeyEquivalentKey] objectAtIndex:1] intValue]];

            if([item objectForKey:SPBundleFileTooltipKey])
                [mItem setToolTip:[item objectForKey:SPBundleFileTooltipKey]];

            [mItem setTag:1000000 + i++];
            [mItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                         scope, @"scope",
                                         ([item objectForKey:@"key"])?:@"", @"key", nil]];

            if([item objectForKey:SPBundleFileCategoryKey]) {
                [[categoryMenus objectAtIndex:[scopeBundleCategories indexOfObject:[item objectForKey:SPBundleFileCategoryKey]]] addItem:mItem];
            } else {
                [bundleMenu addItem:mItem];
            }
        }

        k++;
    }
}

@end
