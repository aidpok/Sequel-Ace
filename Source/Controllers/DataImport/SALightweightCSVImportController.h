//
//  SALightweightCSVImportController.h
//  Sequel Ace
//

#import <Cocoa/Cocoa.h>

@class SALightweightImportTablesListProxy;
@class SPFieldMapperController;
@class SPMySQLConnection;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SALightweightCSVImportControllerErrorDomain;

typedef NS_ENUM(NSInteger, SALightweightCSVImportControllerErrorCode) {
	SALightweightCSVImportControllerErrorMissingSource = 1,
	SALightweightCSVImportControllerErrorUnsupportedFileType,
	SALightweightCSVImportControllerErrorMissingConnection,
	SALightweightCSVImportControllerErrorFieldMapperUnavailable,
	SALightweightCSVImportControllerErrorImportEngineUnavailable,
	SALightweightCSVImportControllerErrorSourceUnreadable,
	SALightweightCSVImportControllerErrorSourceEncoding,
	SALightweightCSVImportControllerErrorSourceParse,
	SALightweightCSVImportControllerErrorFieldMappingCancelled,
	SALightweightCSVImportControllerErrorMissingParentWindow,
	SALightweightCSVImportControllerErrorImportAlreadyRunning,
	SALightweightCSVImportControllerErrorTargetMetadataUnavailable
};

typedef NS_ENUM(NSInteger, SALightweightCSVImportSourceReturnRequest) {
	SALightweightCSVImportSourceReturnRequestNone = 0,
	SALightweightCSVImportSourceReturnRequestFile,
	SALightweightCSVImportSourceReturnRequestClipboard
};

@interface SALightweightCSVImportResult : NSObject

@property (nonatomic, assign, readonly) NSInteger rowsImported;
@property (nonatomic, copy, readonly) NSArray<NSString *> *errors;
@property (nonatomic, copy, readonly) NSString *errorString;
@property (nonatomic, assign, readonly, getter=isCancelled) BOOL cancelled;
@property (nonatomic, strong, readonly, nullable) NSError *error;

- (instancetype)initWithRowsImported:(NSInteger)rowsImported
							   errors:(nullable NSArray<NSString *> *)errors
							cancelled:(BOOL)cancelled
								error:(nullable NSError *)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

typedef void (^SALightweightCSVFieldMappingCompletion)(BOOL accepted, NSError * _Nullable error);
typedef void (^SALightweightCSVImportCompletion)(BOOL didStart, NSError * _Nullable error);
typedef void (^SALightweightCSVImportProgress)(NSInteger rowsImported, unsigned long long bytesRead, unsigned long long totalBytes);
typedef void (^SALightweightCSVImportResultCompletion)(SALightweightCSVImportResult *result);

@interface SALightweightCSVImportController : NSObject

@property (nonatomic, strong, nullable) SPMySQLConnection *connection;
@property (nonatomic, copy, nullable) NSString *databaseName;
@property (nonatomic, copy, nullable) NSString *selectedTableName;
@property (nonatomic, copy) NSArray<NSString *> *tableNames;

@property (nonatomic, copy, nullable) NSURL *fileURL;
@property (nonatomic, copy, nullable) NSString *filePath;
@property (nonatomic, assign) NSStringEncoding sourceEncoding;

@property (nonatomic, copy) NSString *fieldTerminator;
@property (nonatomic, copy) NSString *lineTerminator;
@property (nonatomic, copy) NSString *fieldEnclosedBy;
@property (nonatomic, copy) NSString *escapeCharacter;
@property (nonatomic, assign) BOOL firstLineIsHeader;

@property (nonatomic, strong, readonly) SALightweightImportTablesListProxy *tablesListInstance;
@property (nonatomic, copy, readonly, nullable) NSString *sourcePath;
@property (nonatomic, assign, readonly) BOOL sourcePathIsTemporary;

@property (nonatomic, copy, readonly, nullable) NSString *selectedTableTarget;
@property (nonatomic, copy, readonly, nullable) NSString *selectedImportMethod;
@property (nonatomic, copy, readonly) NSArray *fieldMapperOperator;
@property (nonatomic, copy, readonly) NSArray *fieldMappingArray;
@property (nonatomic, copy, readonly) NSArray *fieldMappingTableColumnNames;
@property (nonatomic, copy, readonly) NSArray *fieldMappingGlobalValueArray;
@property (nonatomic, copy, readonly) NSArray *fieldMappingTableDefaultValues;
@property (nonatomic, copy, readonly, nullable) NSString *csvImportHeaderString;
@property (nonatomic, copy, readonly, nullable) NSString *csvImportTailString;
@property (nonatomic, assign, readonly) BOOL importIntoNewTable;
@property (nonatomic, assign, readonly) BOOL insertRemainingRowsAfterUpdate;
@property (nonatomic, assign, readonly) BOOL fieldMappingArrayHasGlobalVariables;
@property (nonatomic, assign, readonly) BOOL importMethodIsUpdate;
@property (nonatomic, strong, readonly, nullable) NSError *fieldMappingError;
@property (nonatomic, assign, readonly) SALightweightCSVImportSourceReturnRequest fieldMappingSourceReturnRequest;
@property (nonatomic, assign, readonly, getter=isImportRunning) BOOL importRunning;

- (instancetype)initWithConnection:(nullable SPMySQLConnection *)connection
					  databaseName:(nullable NSString *)databaseName
				 selectedTableName:(nullable NSString *)selectedTableName
						tableNames:(nullable NSArray<NSString *> *)tableNames
						   fileURL:(nullable NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

+ (NSArray<NSString *> *)supportedFileExtensions;
+ (BOOL)isSupportedFileURL:(nullable NSURL *)fileURL;
+ (BOOL)isSupportedFilePath:(nullable NSString *)filePath;
+ (BOOL)isTabSeparatedFileURL:(nullable NSURL *)fileURL;
+ (BOOL)isTabSeparatedFilePath:(nullable NSString *)filePath;

- (void)captureSettingsWithFieldTerminator:(nullable NSString *)fieldTerminator
							lineTerminator:(nullable NSString *)lineTerminator
						   fieldEnclosedBy:(nullable NSString *)fieldEnclosedBy
						   escapeCharacter:(nullable NSString *)escapeCharacter
						 firstLineIsHeader:(BOOL)firstLineIsHeader;
- (void)captureSettingsFromUserDefaults:(NSUserDefaults *)userDefaults;
- (NSDictionary<NSString *, id> *)capturedSettings;
- (void)applyFileTypeSettingsInference;

- (BOOL)validateSupportedFileTypeWithError:(NSError **)error;
- (BOOL)validateSessionInputsWithError:(NSError **)error;

- (nullable NSArray<NSArray<id> *> *)previewRowsWithError:(NSError **)error;
- (nullable NSArray<NSArray<id> *> *)previewRowsWithLimit:(NSUInteger)rowLimit error:(NSError **)error;
- (nullable SPFieldMapperController *)prepareFieldMapperWithPreviewRows:(nullable NSArray<NSArray<id> *> *)previewRows
																   error:(NSError **)error;
- (nullable SPFieldMapperController *)prepareFieldMapperWithParsedPreviewRowsWithError:(NSError **)error;
- (void)beginFieldMappingWithWindow:(nullable NSWindow *)window completion:(nullable SALightweightCSVFieldMappingCompletion)completion;
- (void)beginImportWithWindow:(nullable NSWindow *)window completion:(nullable SALightweightCSVImportCompletion)completion;
- (void)beginImportWithWindow:(nullable NSWindow *)window
						 progress:(nullable SALightweightCSVImportProgress)progress
					   completion:(nullable SALightweightCSVImportResultCompletion)completion;
- (void)cancelImport;
- (void)cancelAndClearTemporaryState;
- (void)importFile;
- (void)importFromClipboard;
- (void)clearTemporaryState;

@end

NS_ASSUME_NONNULL_END
