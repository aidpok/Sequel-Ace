//
//  SALightweightCSVImportController.m
//  Sequel Ace
//

#import "SALightweightCSVImportController.h"

#import "SALightweightImportProxies.h"
#import "RegexKitLite.h"
#import "SPCSVParser.h"
#import "SPConstants.h"
#import "SPFieldMapperController.h"
#import "SPFileHandle.h"
#import "SPFileManagerAdditions.h"

#import <SPMySQL/SPMySQL.h>

NSString * const SALightweightCSVImportControllerErrorDomain = @"SALightweightCSVImportControllerErrorDomain";

static NSString * const SALightweightCSVImportDefaultFieldTerminator = @",";
static NSString * const SALightweightCSVImportDefaultLineTerminator = @"\\n";
static NSString * const SALightweightCSVImportDefaultFieldEnclosedBy = @"\"";
static NSString * const SALightweightCSVImportDefaultEscapeCharacter = @"\\ or \"";
static NSUInteger const SALightweightCSVImportDefaultPreviewRowLimit = 100;
static NSUInteger const SALightweightCSVImportPreviewChunkLength = 256 * 1024;
static NSUInteger const SALightweightCSVImportPreviewPendingByteLimit = 4 * 1024 * 1024;
static NSUInteger const SALightweightCSVImportExecutionChunkLength = 256 * 1024;
static NSUInteger const SALightweightCSVImportRowsPerQuery = 100;
static NSUInteger const SALightweightCSVImportMaxQueryLength = 250000;

@interface SALightweightCSVImportResult ()

@property (nonatomic, assign, readwrite) NSInteger rowsImported;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *errors;
@property (nonatomic, copy, readwrite) NSString *errorString;
@property (nonatomic, assign, readwrite, getter=isCancelled) BOOL cancelled;
@property (nonatomic, strong, readwrite, nullable) NSError *error;

@end

@implementation SALightweightCSVImportResult

- (instancetype)initWithRowsImported:(NSInteger)rowsImported
							   errors:(NSArray<NSString *> *)errors
							cancelled:(BOOL)cancelled
								error:(NSError *)error
{
	if ((self = [super init])) {
		_rowsImported = rowsImported;
		_errors = [errors copy] ?: @[];
		_errorString = [_errors componentsJoinedByString:@"\n"];
		_cancelled = cancelled;
		_error = error;
	}

	return self;
}

@end

@interface SALightweightCSVImportController ()

@property (nonatomic, strong, readwrite) SALightweightImportTablesListProxy *tablesListInstance;
@property (nonatomic, strong, nullable) SPFieldMapperController *fieldMapperController;
@property (nonatomic, copy, readwrite, nullable) NSString *selectedTableTarget;
@property (nonatomic, copy, readwrite, nullable) NSString *selectedImportMethod;
@property (nonatomic, copy, readwrite) NSArray *fieldMapperOperator;
@property (nonatomic, copy, readwrite) NSArray *fieldMappingArray;
@property (nonatomic, copy, readwrite) NSArray *fieldMappingTableColumnNames;
@property (nonatomic, copy, readwrite) NSArray *fieldMappingGlobalValueArray;
@property (nonatomic, copy, readwrite) NSArray *fieldMappingTableDefaultValues;
@property (nonatomic, copy, readwrite, nullable) NSString *csvImportHeaderString;
@property (nonatomic, copy, readwrite, nullable) NSString *csvImportTailString;
@property (nonatomic, assign, readwrite) BOOL importIntoNewTable;
@property (nonatomic, assign, readwrite) BOOL insertRemainingRowsAfterUpdate;
@property (nonatomic, assign, readwrite) BOOL fieldMappingArrayHasGlobalVariables;
@property (nonatomic, assign, readwrite) BOOL importMethodIsUpdate;
@property (nonatomic, strong, readwrite, nullable) NSError *fieldMappingError;
@property (nonatomic, assign, readwrite) SALightweightCSVImportSourceReturnRequest fieldMappingSourceReturnRequest;
@property (nonatomic, assign) NSUInteger numberOfImportDataColumns;
@property (nonatomic, assign, readwrite, getter=isImportRunning) BOOL importRunning;
@property (nonatomic, assign) BOOL importCancelled;
@property (nonatomic, strong) NSMutableArray<NSString *> *geometryFields;
@property (nonatomic, strong) NSMutableIndexSet *geometryFieldsMapIndex;
@property (nonatomic, strong) NSMutableArray<NSString *> *bitFields;
@property (nonatomic, strong) NSMutableIndexSet *bitFieldsMapIndex;
@property (nonatomic, strong) NSMutableArray<NSString *> *nullableNumericFields;
@property (nonatomic, strong) NSMutableIndexSet *nullableNumericFieldsMapIndex;

+ (BOOL)_isGeometryDataType:(NSString *)dataType;
+ (BOOL)_isNumericDataType:(NSString *)dataType;

- (NSString *)mappedUpdateSetStatementStringForRowArray:(NSArray *)csvRowArray;
- (NSString *)mappedValueStringForRowArray:(NSArray *)csvRowArray;
- (void)_captureCurrentFieldMapperSettingsIfAvailable;
- (NSString *)_fieldMapperSourcePath;
- (NSStringEncoding)_resolvedSourceEncodingForPath:(NSString *)sourcePath;

@end

@implementation SALightweightCSVImportController

- (instancetype)init
{
	return [self initWithConnection:nil databaseName:nil selectedTableName:nil tableNames:nil fileURL:nil];
}

- (instancetype)initWithConnection:(SPMySQLConnection *)connection
					  databaseName:(NSString *)databaseName
				 selectedTableName:(NSString *)selectedTableName
						tableNames:(NSArray<NSString *> *)tableNames
						   fileURL:(NSURL *)fileURL
{
	if ((self = [super init])) {
		_connection = connection;
		_databaseName = [databaseName copy];
		_selectedTableName = [selectedTableName copy];
		_tableNames = [self.class _normalizedTableNames:tableNames];
		_fileURL = [fileURL copy];
		_filePath = [self.class _filePathForURL:fileURL];

		_tablesListInstance = [[SALightweightImportTablesListProxy alloc] initWithConnection:connection
																				databaseName:_databaseName
																				   tableName:_selectedTableName
																				  tableNames:_tableNames];
		_geometryFields = [[NSMutableArray alloc] init];
		_geometryFieldsMapIndex = [[NSMutableIndexSet alloc] init];
		_bitFields = [[NSMutableArray alloc] init];
		_bitFieldsMapIndex = [[NSMutableIndexSet alloc] init];
		_nullableNumericFields = [[NSMutableArray alloc] init];
		_nullableNumericFieldsMapIndex = [[NSMutableIndexSet alloc] init];
		[self _resetAcceptedFieldMappingState];

		[self captureSettingsFromUserDefaults:[NSUserDefaults standardUserDefaults]];
		[self applyFileTypeSettingsInference];
	}

	return self;
}

#pragma mark - Session input synchronization

- (void)setConnection:(SPMySQLConnection *)connection
{
	_connection = connection;
	self.tablesListInstance.connection = connection;
}

- (void)setDatabaseName:(NSString *)databaseName
{
	_databaseName = [databaseName copy];
	self.tablesListInstance.databaseName = _databaseName;
}

- (void)setSelectedTableName:(NSString *)selectedTableName
{
	_selectedTableName = [selectedTableName copy];
	self.tablesListInstance.selectedTableName = _selectedTableName;
}

- (void)setTableNames:(NSArray<NSString *> *)tableNames
{
	_tableNames = [self.class _normalizedTableNames:tableNames];
	self.tablesListInstance.tableNames = _tableNames;
}

- (void)setFileURL:(NSURL *)fileURL
{
	_fileURL = [fileURL copy];
	_filePath = [self.class _filePathForURL:fileURL];
	[self applyFileTypeSettingsInference];
}

- (void)setFilePath:(NSString *)filePath
{
	_filePath = [filePath copy];
	_fileURL = [filePath length] ? [NSURL fileURLWithPath:filePath] : nil;
	[self applyFileTypeSettingsInference];
}

- (NSString *)sourcePath
{
	return self.filePath;
}

- (BOOL)sourcePathIsTemporary
{
	NSString *sourcePath = [self.filePath stringByExpandingTildeInPath];
	NSString *temporaryPrefix = [SPImportClipboardTempFileNamePrefix stringByExpandingTildeInPath];
	return [sourcePath hasPrefix:temporaryPrefix];
}

- (NSString *)_fieldMapperSourcePath
{
	NSString *sourcePath = self.sourcePath;
	if (![sourcePath length] || !self.sourcePathIsTemporary) return sourcePath;

	NSString *expandedTemporaryPrefix = [SPImportClipboardTempFileNamePrefix stringByExpandingTildeInPath];
	if (![sourcePath hasPrefix:expandedTemporaryPrefix]) return sourcePath;

	NSString *temporarySuffix = [sourcePath substringFromIndex:[expandedTemporaryPrefix length]];
	return [SPImportClipboardTempFileNamePrefix stringByAppendingString:temporarySuffix];
}

#pragma mark - Supported file types

+ (NSArray<NSString *> *)supportedFileExtensions
{
	return @[@"csv", @"csv.gz", @"csv.bz2", @"tsv", @"tsv.gz", @"tsv.bz2"];
}

+ (BOOL)isSupportedFileURL:(NSURL *)fileURL
{
	return [self isSupportedFilePath:[self _filePathForURL:fileURL]];
}

+ (BOOL)isSupportedFilePath:(NSString *)filePath
{
	NSString *lowercaseName = [[filePath lastPathComponent] lowercaseString];
	if (![lowercaseName length]) return NO;

	return [lowercaseName hasSuffix:@".csv"]
		|| [lowercaseName hasSuffix:@".csv.gz"]
		|| [lowercaseName hasSuffix:@".csv.bz2"]
		|| [lowercaseName hasSuffix:@".tsv"]
		|| [lowercaseName hasSuffix:@".tsv.gz"]
		|| [lowercaseName hasSuffix:@".tsv.bz2"];
}

+ (BOOL)isTabSeparatedFileURL:(NSURL *)fileURL
{
	return [self isTabSeparatedFilePath:[self _filePathForURL:fileURL]];
}

+ (BOOL)isTabSeparatedFilePath:(NSString *)filePath
{
	NSString *lowercaseName = [[filePath lastPathComponent] lowercaseString];
	return [lowercaseName hasSuffix:@".tsv"] || [lowercaseName hasSuffix:@".tsv.gz"] || [lowercaseName hasSuffix:@".tsv.bz2"];
}

#pragma mark - Settings capture

- (void)captureSettingsWithFieldTerminator:(NSString *)fieldTerminator
							lineTerminator:(NSString *)lineTerminator
						   fieldEnclosedBy:(NSString *)fieldEnclosedBy
						   escapeCharacter:(NSString *)escapeCharacter
						 firstLineIsHeader:(BOOL)firstLineIsHeader
{
	self.fieldTerminator = [fieldTerminator length] ? fieldTerminator : SALightweightCSVImportDefaultFieldTerminator;
	self.lineTerminator = [lineTerminator length] ? lineTerminator : SALightweightCSVImportDefaultLineTerminator;
	self.fieldEnclosedBy = fieldEnclosedBy ?: SALightweightCSVImportDefaultFieldEnclosedBy;
	self.escapeCharacter = escapeCharacter ?: SALightweightCSVImportDefaultEscapeCharacter;
	self.firstLineIsHeader = firstLineIsHeader;
}

- (void)captureSettingsFromUserDefaults:(NSUserDefaults *)userDefaults
{
	[self captureSettingsWithFieldTerminator:[self.class _stringFromUserDefaults:userDefaults forKey:SPCSVImportFieldTerminator defaultValue:SALightweightCSVImportDefaultFieldTerminator]
							  lineTerminator:[self.class _stringFromUserDefaults:userDefaults forKey:SPCSVImportLineTerminator defaultValue:SALightweightCSVImportDefaultLineTerminator]
							 fieldEnclosedBy:[self.class _stringFromUserDefaults:userDefaults forKey:SPCSVImportFieldEnclosedBy defaultValue:SALightweightCSVImportDefaultFieldEnclosedBy]
							 escapeCharacter:[self.class _stringFromUserDefaults:userDefaults forKey:SPCSVImportFieldEscapeCharacter defaultValue:SALightweightCSVImportDefaultEscapeCharacter]
						   firstLineIsHeader:[self.class _boolFromUserDefaults:userDefaults forKey:SPCSVImportFirstLineIsHeader defaultValue:YES]];
}

- (NSDictionary<NSString *, id> *)capturedSettings
{
	return @{
		@"fieldTerminator": self.fieldTerminator ?: @"",
		@"lineTerminator": self.lineTerminator ?: @"",
		@"fieldEnclosedBy": self.fieldEnclosedBy ?: @"",
		@"escapeCharacter": self.escapeCharacter ?: @"",
		@"firstLineIsHeader": @(self.firstLineIsHeader)
	};
}

- (void)applyFileTypeSettingsInference
{
	if ([self.class isTabSeparatedFilePath:self.filePath]) {
		self.fieldTerminator = @"\t";
	}
}

#pragma mark - Validation

- (BOOL)validateSupportedFileTypeWithError:(NSError **)error
{
	if (![self.filePath length]) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorMissingSource message:NSLocalizedString(@"Choose a CSV or TSV file before importing.", @"lightweight CSV import missing source error")];
		return NO;
	}

	if (![self.class isSupportedFilePath:self.filePath]) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorUnsupportedFileType message:NSLocalizedString(@"Lightweight import currently supports .csv, .csv.gz, .csv.bz2, .tsv, .tsv.gz, and .tsv.bz2 files only.", @"lightweight CSV import unsupported source error")];
		return NO;
	}

	return YES;
}

- (BOOL)validateSessionInputsWithError:(NSError **)error
{
	if (![self validateSupportedFileTypeWithError:error]) {
		return NO;
	}

	if (!self.connection) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorMissingConnection message:NSLocalizedString(@"Connect to a database before starting a lightweight CSV import.", @"lightweight CSV import missing connection error")];
		return NO;
	}

	return YES;
}

#pragma mark - CSV preview parsing

- (NSArray<NSArray<id> *> *)previewRowsWithError:(NSError **)error
{
	return [self previewRowsWithLimit:SALightweightCSVImportDefaultPreviewRowLimit error:error];
}

- (NSArray<NSArray<id> *> *)previewRowsWithLimit:(NSUInteger)rowLimit error:(NSError **)error
{
	if (![self validateSupportedFileTypeWithError:error]) {
		return nil;
	}

	if (!rowLimit) {
		rowLimit = SALightweightCSVImportDefaultPreviewRowLimit;
	}

	NSString *sourcePath = self.sourcePath;
	SPFileHandle *csvFileHandle = [SPFileHandle fileHandleForReadingAtPath:sourcePath];
	if (!csvFileHandle) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceUnreadable message:NSLocalizedString(@"The CSV file could not be opened for preview.", @"lightweight CSV preview open error")];
		return nil;
	}

	NSStringEncoding csvEncoding = [self _resolvedSourceEncodingForPath:sourcePath];
	SPCSVParser *csvParser = [[SPCSVParser alloc] init];
	[self _configureCSVParser:csvParser];

	NSMutableArray<NSArray<id> *> *previewRows = [NSMutableArray arrayWithCapacity:rowLimit];
	NSMutableData *csvDataBuffer = [[NSMutableData alloc] init];
	BOOL allDataRead = NO;

	@try {
		while ([previewRows count] < rowLimit && !allDataRead) {
			NSData *fileChunk = [csvFileHandle readDataOfLength:SALightweightCSVImportPreviewChunkLength];
			if (![fileChunk length]) {
				allDataRead = YES;
			}
			else {
				[csvDataBuffer appendData:fileChunk];
			}

			if ([csvDataBuffer length]) {
				NSString *csvString = [[NSString alloc] initWithData:csvDataBuffer encoding:csvEncoding];
				if (!csvString) {
					if (allDataRead || [csvDataBuffer length] >= SALightweightCSVImportPreviewPendingByteLimit) {
						NSString *encodingName = [NSString localizedNameOfStringEncoding:csvEncoding] ?: NSLocalizedString(@"the detected encoding", @"lightweight CSV preview fallback encoding name");
						[csvFileHandle closeFile];
						[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceEncoding message:[NSString stringWithFormat:NSLocalizedString(@"The CSV preview could not be read using %@.", @"lightweight CSV preview encoding error"), encodingName]];
						return nil;
					}

					continue;
				}

				[csvParser appendString:csvString];
				[csvDataBuffer setLength:0];
			}

			NSArray *csvRowArray;
			while ([previewRows count] < rowLimit && (csvRowArray = [csvParser getRowAsArrayAndTrimString:YES stringIsComplete:allDataRead])) {
				[previewRows addObject:csvRowArray];
			}

			if ([csvParser length] > SALightweightCSVImportPreviewPendingByteLimit) {
				[csvFileHandle closeFile];
				[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceParse message:NSLocalizedString(@"The CSV preview could not find enough row terminators before the preview size limit. Check the line terminator setting.", @"lightweight CSV preview row terminator error")];
				return nil;
			}
		}

		if (allDataRead) {
			NSArray *csvRowArray;
			while ([previewRows count] < rowLimit && (csvRowArray = [csvParser getRowAsArrayAndTrimString:YES stringIsComplete:YES])) {
				[previewRows addObject:csvRowArray];
			}
		}
	}
	@catch (NSException *exception) {
		[csvFileHandle closeFile];
		NSString *reason = [exception reason] ?: NSLocalizedString(@"Unknown file read error.", @"lightweight CSV preview unknown file read error");
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceUnreadable message:[NSString stringWithFormat:NSLocalizedString(@"The CSV preview could not be read. %@", @"lightweight CSV preview file read error"), reason]];
		return nil;
	}

	[csvFileHandle closeFile];
	return previewRows;
}

#pragma mark - Future flow stubs

- (SPFieldMapperController *)prepareFieldMapperWithPreviewRows:(NSArray<NSArray<id> *> *)previewRows error:(NSError **)error
{
	if (![self validateSessionInputsWithError:error]) {
		return nil;
	}

	if ([previewRows count] && [[previewRows objectAtIndex:0] count] > 512) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceParse message:NSLocalizedString(@"The CSV was read as containing more than 512 columns. This usually means the line terminator or escape settings are wrong.", @"lightweight CSV preview too many columns error")];
		return nil;
	}

	SPFieldMapperController *fieldMapperController = [[SPFieldMapperController alloc] initWithDelegate:self];
	if (!fieldMapperController) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorFieldMapperUnavailable message:NSLocalizedString(@"The CSV field mapper could not be prepared.", @"lightweight CSV import field mapper unavailable error")];
		return nil;
	}

	[fieldMapperController setConnection:self.connection];
	fieldMapperController.sourcePath = [self _fieldMapperSourcePath] ?: @"";
	[fieldMapperController setImportDataArray:(previewRows ?: @[]) hasHeader:self.firstLineIsHeader isPreview:YES];
	self.numberOfImportDataColumns = [[previewRows firstObject] count];

	self.fieldMapperController = fieldMapperController;
	return fieldMapperController;
}

- (SPFieldMapperController *)prepareFieldMapperWithParsedPreviewRowsWithError:(NSError **)error
{
	if (![self validateSessionInputsWithError:error]) {
		return nil;
	}

	NSArray<NSArray<id> *> *previewRows = [self previewRowsWithError:error];
	if (!previewRows) {
		return nil;
	}

	if (![previewRows count]) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceParse message:NSLocalizedString(@"The CSV preview did not contain any rows.", @"lightweight CSV preview empty file error")];
		return nil;
	}

	return [self prepareFieldMapperWithPreviewRows:previewRows error:error];
}

- (void)beginFieldMappingWithWindow:(NSWindow *)window completion:(SALightweightCSVFieldMappingCompletion)completion
{
	if (![NSThread isMainThread]) {
		__weak SALightweightCSVImportController *weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf beginFieldMappingWithWindow:window completion:completion];
		});
		return;
	}

	[self _resetAcceptedFieldMappingState];

	NSError *mappingError = nil;
	if (![self _selectTargetDatabaseWithError:&mappingError]) {
		self.fieldMappingError = mappingError;
		if (completion) completion(NO, mappingError);
		return;
	}

	SPFieldMapperController *fieldMapperController = [self prepareFieldMapperWithParsedPreviewRowsWithError:&mappingError];
	if (!fieldMapperController) {
		self.fieldMappingError = mappingError;
		if (completion) completion(NO, mappingError);
		return;
	}

	NSWindow *fieldMapperWindow = [fieldMapperController window];
	if (!fieldMapperWindow) {
		mappingError = [self.class _errorWithCode:SALightweightCSVImportControllerErrorFieldMapperUnavailable
										  message:NSLocalizedString(@"The CSV field mapper window could not be loaded.", @"lightweight CSV import field mapper window unavailable error")];
		self.fieldMappingError = mappingError;
		if (completion) completion(NO, mappingError);
		return;
	}

	NSWindow *parentWindow = window ?: [NSApp keyWindow] ?: [NSApp mainWindow];
	if (!parentWindow || parentWindow == fieldMapperWindow) {
		mappingError = [self.class _errorWithCode:SALightweightCSVImportControllerErrorFieldMapperUnavailable
										  message:NSLocalizedString(@"The CSV field mapper requires a parent window in lightweight mode.", @"lightweight CSV import field mapper parent window unavailable error")];
		self.fieldMappingError = mappingError;
		if (completion) completion(NO, mappingError);
		return;
	}

	__weak SALightweightCSVImportController *weakSelf = self;
	void (^finishMapping)(NSModalResponse) = ^(NSModalResponse returnCode) {
		SALightweightCSVImportController *strongSelf = weakSelf;
		if (!strongSelf) return;

		if (returnCode && strongSelf.fieldMappingSourceReturnRequest == SALightweightCSVImportSourceReturnRequestNone) {
			[strongSelf _captureAcceptedFieldMappingStateFromController:fieldMapperController];
			if (completion) completion(YES, nil);
			return;
		}

		if (strongSelf.fieldMappingSourceReturnRequest != SALightweightCSVImportSourceReturnRequestNone) {
			if (completion) completion(NO, nil);
			return;
		}

		NSError *cancellationError = strongSelf.fieldMappingError ?: [strongSelf.class _errorWithCode:SALightweightCSVImportControllerErrorFieldMappingCancelled
																							   message:NSLocalizedString(@"The CSV field mapping was cancelled.", @"lightweight CSV import field mapping cancelled error")];
		strongSelf.fieldMappingError = cancellationError;
		if (completion) completion(NO, cancellationError);
	};

	[parentWindow beginSheet:fieldMapperWindow completionHandler:finishMapping];
}

- (void)beginImportWithWindow:(NSWindow *)window completion:(SALightweightCSVImportCompletion)completion
{
	[self beginImportWithWindow:window progress:nil completion:^(SALightweightCSVImportResult *result) {
		if (!completion) return;
		BOOL didStart = ((result.error == nil && !result.isCancelled) || result.rowsImported > 0 || [result.errors count]);
		completion(didStart, result.error);
	}];
}

- (void)beginImportWithWindow:(NSWindow *)window
					 progress:(SALightweightCSVImportProgress)progress
				   completion:(SALightweightCSVImportResultCompletion)completion
{
	if (![NSThread isMainThread]) {
		__weak SALightweightCSVImportController *weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf beginImportWithWindow:window progress:progress completion:completion];
		});
		return;
	}

	NSWindow *parentWindow = window ?: [NSApp keyWindow] ?: [NSApp mainWindow];
	if (!parentWindow) {
		NSError *parentError = [self.class _errorWithCode:SALightweightCSVImportControllerErrorMissingParentWindow
												  message:NSLocalizedString(@"The lightweight CSV importer requires a parent window.", @"lightweight CSV import missing parent window error")];
		[self _finishImportWithRowsImported:0 errors:@[] cancelled:NO error:parentError completion:completion];
		return;
	}

	NSError *validationError = nil;
	if (![self validateSessionInputsWithError:&validationError]) {
		[self _finishImportWithRowsImported:0 errors:@[] cancelled:NO error:validationError completion:completion];
		return;
	}

	if (self.isImportRunning) {
		NSError *runningError = [self.class _errorWithCode:SALightweightCSVImportControllerErrorImportAlreadyRunning
												   message:NSLocalizedString(@"A lightweight CSV import is already running.", @"lightweight CSV import already running error")];
		[self _finishImportWithRowsImported:0 errors:@[] cancelled:NO error:runningError completion:completion];
		return;
	}

	__weak SALightweightCSVImportController *weakSelf = self;
	void (^startImport)(void) = ^{
		SALightweightCSVImportController *strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf _startStreamingImportWithProgress:progress completion:completion];
	};

	if ([self _hasAcceptedFieldMappingState]) {
		startImport();
		return;
	}

	[self beginFieldMappingWithWindow:parentWindow completion:^(BOOL accepted, NSError *error) {
		if (!accepted) {
			[self _finishImportWithRowsImported:0 errors:@[] cancelled:YES error:error completion:completion];
			return;
		}

		startImport();
	}];
}

- (void)cancelImport
{
	self.importCancelled = YES;
	[self.connection cancelCurrentQuery];
}

- (void)cancelAndClearTemporaryState
{
	[self cancelImport];

	NSWindow *fieldMapperWindow = [self.fieldMapperController window];
	if (fieldMapperWindow) {
		self.fieldMappingError = [self.class _errorWithCode:SALightweightCSVImportControllerErrorFieldMappingCancelled
													message:NSLocalizedString(@"The CSV field mapping was cancelled.", @"lightweight CSV import field mapping cancelled error")];
		self.fieldMappingSourceReturnRequest = SALightweightCSVImportSourceReturnRequestNone;

		if ([fieldMapperWindow sheetParent]) {
			[[fieldMapperWindow sheetParent] endSheet:fieldMapperWindow returnCode:NSModalResponseCancel];
		}
		else {
			[fieldMapperWindow close];
		}
	}

	[self clearTemporaryState];
}

- (void)importFile
{
	[self _captureCurrentFieldMapperSettingsIfAvailable];
	self.fieldMappingSourceReturnRequest = SALightweightCSVImportSourceReturnRequestFile;
	self.fieldMappingError = nil;
}

- (void)importFromClipboard
{
	[self _captureCurrentFieldMapperSettingsIfAvailable];
	self.fieldMappingSourceReturnRequest = SALightweightCSVImportSourceReturnRequestClipboard;
	self.fieldMappingError = nil;
}

- (void)clearTemporaryState
{
	if (self.sourcePathIsTemporary && [self.sourcePath length]) {
		[[NSFileManager defaultManager] removeItemAtPath:self.sourcePath error:nil];
	}
	self.fieldMapperController = nil;
	self.fieldMappingError = nil;
	self.fieldMappingSourceReturnRequest = SALightweightCSVImportSourceReturnRequestNone;
}

#pragma mark - Private helpers

- (void)_configureCSVParser:(SPCSVParser *)csvParser
{
	[csvParser setFieldTerminatorString:(self.fieldTerminator ?: SALightweightCSVImportDefaultFieldTerminator) convertDisplayStrings:YES];
	[csvParser setLineTerminatorString:(self.lineTerminator ?: SALightweightCSVImportDefaultLineTerminator) convertDisplayStrings:YES];
	[csvParser setFieldQuoteString:(self.fieldEnclosedBy ?: SALightweightCSVImportDefaultFieldEnclosedBy) convertDisplayStrings:YES];

	if ([(self.escapeCharacter ?: SALightweightCSVImportDefaultEscapeCharacter) isEqualToString:SALightweightCSVImportDefaultEscapeCharacter]) {
		[csvParser setEscapeString:@"\\" convertDisplayStrings:NO];
	}
	else {
		[csvParser setEscapeString:self.escapeCharacter convertDisplayStrings:YES];
		[csvParser setEscapeStringsAreMatchedStrictly:YES];
	}

	[csvParser setNullReplacementString:[[NSUserDefaults standardUserDefaults] objectForKey:SPNullValue]];
}

- (NSStringEncoding)_resolvedSourceEncodingForPath:(NSString *)sourcePath
{
	if (self.sourceEncoding) {
		return self.sourceEncoding;
	}

	return [[NSFileManager defaultManager] detectEncodingforFileAtPath:sourcePath];
}

- (void)_resetAcceptedFieldMappingState
{
	self.selectedTableTarget = nil;
	self.selectedImportMethod = nil;
	self.fieldMapperOperator = @[];
	self.fieldMappingArray = @[];
	self.fieldMappingTableColumnNames = @[];
	self.fieldMappingGlobalValueArray = @[];
	self.fieldMappingTableDefaultValues = @[];
	self.csvImportHeaderString = nil;
	self.csvImportTailString = nil;
	self.importIntoNewTable = NO;
	self.insertRemainingRowsAfterUpdate = NO;
	self.fieldMappingArrayHasGlobalVariables = NO;
	self.importMethodIsUpdate = NO;
	self.fieldMappingError = nil;
	self.fieldMappingSourceReturnRequest = SALightweightCSVImportSourceReturnRequestNone;
	self.numberOfImportDataColumns = 0;
}

- (void)_captureCurrentFieldMapperSettingsIfAvailable
{
	if (!self.fieldMapperController) return;

	self.firstLineIsHeader = [self.fieldMapperController importFieldNamesHeader];
}

- (void)_captureAcceptedFieldMappingStateFromController:(SPFieldMapperController *)fieldMapperController
{
	self.fieldMapperOperator = [[fieldMapperController fieldMapperOperator] copy] ?: @[];
	self.fieldMappingArray = [[fieldMapperController fieldMappingArray] copy] ?: @[];
	self.selectedTableTarget = [[fieldMapperController selectedTableTarget] copy];
	self.selectedImportMethod = [[fieldMapperController selectedImportMethod] copy];
	self.fieldMappingTableColumnNames = [[fieldMapperController fieldMappingTableColumnNames] copy] ?: @[];
	self.fieldMappingGlobalValueArray = [[fieldMapperController fieldMappingGlobalValueArray] copy] ?: @[];
	self.fieldMappingTableDefaultValues = [[fieldMapperController fieldMappingTableDefaultValues] copy] ?: @[];
	self.csvImportHeaderString = [[fieldMapperController importHeaderString] copy];
	self.csvImportTailString = [[fieldMapperController onupdateString] copy];
	self.importIntoNewTable = [fieldMapperController importIntoNewTable];
	self.fieldMappingArrayHasGlobalVariables = [fieldMapperController globalValuesInUsage];
	self.insertRemainingRowsAfterUpdate = [fieldMapperController insertRemainingRowsAfterUpdate];
	self.importMethodIsUpdate = [self.selectedImportMethod isEqualToString:@"UPDATE"];
	self.fieldMappingError = nil;

	self.firstLineIsHeader = [fieldMapperController importFieldNamesHeader];
	[[NSUserDefaults standardUserDefaults] setBool:self.firstLineIsHeader forKey:SPCSVImportFirstLineIsHeader];
}

- (BOOL)_hasAcceptedFieldMappingState
{
	return [self.fieldMapperOperator count]
		&& [self.fieldMappingArray count]
		&& [self.selectedImportMethod length]
		&& [self.selectedTableTarget length]
		&& [self.csvImportHeaderString length];
}

- (void)_startStreamingImportWithProgress:(SALightweightCSVImportProgress)progress
							   completion:(SALightweightCSVImportResultCompletion)completion
{
	self.importRunning = YES;
	self.importCancelled = NO;

	__weak SALightweightCSVImportController *weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		SALightweightCSVImportController *strongSelf = weakSelf;
		if (!strongSelf) return;

		NSInteger rowsImported = 0;
		NSMutableArray<NSString *> *rowErrors = [NSMutableArray array];
		NSError *fatalError = nil;
		BOOL cancelled = NO;

		@autoreleasepool {
			BOOL completed = [strongSelf _performStreamingImportRowsImported:&rowsImported
																	  errors:rowErrors
																	progress:progress
																	   error:&fatalError];
			cancelled = (!completed && !fatalError) || strongSelf.importCancelled;
		}

		[strongSelf _finishImportWithRowsImported:rowsImported
										   errors:rowErrors
										cancelled:cancelled
											error:fatalError
									  completion:completion];
	});
}

- (BOOL)_performStreamingImportRowsImported:(NSInteger *)rowsImported
									 errors:(NSMutableArray<NSString *> *)errors
								   progress:(SALightweightCSVImportProgress)progress
									  error:(NSError **)error
{
	if (![self _hasAcceptedFieldMappingState]) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorImportEngineUnavailable message:NSLocalizedString(@"The CSV field mapping is incomplete.", @"lightweight CSV import incomplete mapping error")];
		return NO;
	}

	if (![self _selectTargetDatabaseWithError:error]) {
		return NO;
	}

	if (![self _prepareTargetMetadataWithError:error]) {
		return NO;
	}

	[self _refreshMappedSpecialFieldIndexes];

	NSMutableString *insertBaseString = [self _insertBaseStringWithError:error];
	if (!insertBaseString) {
		return NO;
	}
	NSString *insertRemainingBaseString = self.importMethodIsUpdate && self.insertRemainingRowsAfterUpdate ? [self _insertRemainingBaseString] : nil;

	NSString *sourcePath = self.sourcePath;
	SPFileHandle *csvFileHandle = [SPFileHandle fileHandleForReadingAtPath:sourcePath];
	if (!csvFileHandle) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceUnreadable message:NSLocalizedString(@"The CSV file could not be opened for import.", @"lightweight CSV import open error")];
		return NO;
	}

	unsigned long long fileTotalLength = (unsigned long long)[[[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:NULL][NSFileSize] unsignedLongLongValue];
	if (!fileTotalLength) fileTotalLength = 1;
	NSStringEncoding csvEncoding = [self _resolvedSourceEncodingForPath:sourcePath];

	SPCSVParser *csvParser = [[SPCSVParser alloc] init];
	[self _configureCSVParser:csvParser];

	NSMutableData *csvDataBuffer = [[NSMutableData alloc] init];
	NSMutableArray<NSArray<id> *> *insertRows = [NSMutableArray arrayWithCapacity:SALightweightCSVImportRowsPerQuery];
	BOOL allDataRead = NO;
	BOOL skippedHeaderRow = !self.firstLineIsHeader;
	NSInteger sourceDataRowNumber = 0;

	@try {
		while (!allDataRead) {
			if (self.importCancelled) break;

			NSData *fileChunk = [csvFileHandle readDataOfLength:SALightweightCSVImportExecutionChunkLength];
			if (![fileChunk length]) {
				allDataRead = YES;
			}
			else {
				[csvDataBuffer appendData:fileChunk];
			}

			if ([csvDataBuffer length]) {
				NSString *csvString = [[NSString alloc] initWithData:csvDataBuffer encoding:csvEncoding];
				if (!csvString) {
					if (allDataRead || [csvDataBuffer length] >= SALightweightCSVImportPreviewPendingByteLimit) {
						NSString *encodingName = [NSString localizedNameOfStringEncoding:csvEncoding] ?: NSLocalizedString(@"the detected encoding", @"lightweight CSV import fallback encoding name");
						[csvFileHandle closeFile];
						[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceEncoding message:[NSString stringWithFormat:NSLocalizedString(@"The CSV import could not be read using %@.", @"lightweight CSV import encoding error"), encodingName]];
						return NO;
					}

					continue;
				}

				[csvParser appendString:csvString];
				[csvDataBuffer setLength:0];
			}

			NSArray *csvRowArray = nil;
			while (!self.importCancelled && (csvRowArray = [csvParser getRowAsArrayAndTrimString:YES stringIsComplete:allDataRead])) {
				if (!skippedHeaderRow) {
					skippedHeaderRow = YES;
					continue;
				}

				sourceDataRowNumber++;

				if (self.importMethodIsUpdate) {
					BOOL imported = [self _executeUpdateRow:csvRowArray
												  rowNumber:sourceDataRowNumber
										 insertBaseString:insertBaseString
								 insertRemainingBaseString:insertRemainingBaseString
													 errors:errors];
					if (imported) (*rowsImported)++;
					[self _publishImportProgress:progress rowsImported:*rowsImported bytesRead:[csvFileHandle realDataReadLength] totalBytes:fileTotalLength];
				}
				else {
					[insertRows addObject:csvRowArray];
					if ([insertRows count] >= SALightweightCSVImportRowsPerQuery) {
						NSInteger imported = [self _executeInsertRows:insertRows
													   firstRowNumber:(sourceDataRowNumber - (NSInteger)[insertRows count] + 1)
													 insertBaseString:insertBaseString
															  errors:errors];
						*rowsImported += imported;
						[insertRows removeAllObjects];
						[self _publishImportProgress:progress rowsImported:*rowsImported bytesRead:[csvFileHandle realDataReadLength] totalBytes:fileTotalLength];
					}
				}
			}

			if ([csvParser length] > SALightweightCSVImportPreviewPendingByteLimit) {
				[csvFileHandle closeFile];
				[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceParse message:NSLocalizedString(@"The CSV import could not find row terminators before the parser safety limit. Check the line terminator setting.", @"lightweight CSV import row terminator error")];
				return NO;
			}
		}
	}
	@catch (NSException *exception) {
		[csvFileHandle closeFile];
		NSString *reason = [exception reason] ?: NSLocalizedString(@"Unknown file read error.", @"lightweight CSV import unknown file read error");
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorSourceUnreadable message:[NSString stringWithFormat:NSLocalizedString(@"The CSV import could not be read. %@", @"lightweight CSV import file read error"), reason]];
		return NO;
	}

	if (!self.importCancelled && [insertRows count]) {
		NSInteger imported = [self _executeInsertRows:insertRows
									   firstRowNumber:(sourceDataRowNumber - (NSInteger)[insertRows count] + 1)
									 insertBaseString:insertBaseString
											  errors:errors];
		*rowsImported += imported;
		[self _publishImportProgress:progress rowsImported:*rowsImported bytesRead:[csvFileHandle realDataReadLength] totalBytes:fileTotalLength];
	}

	[csvFileHandle closeFile];
	return !self.importCancelled;
}

- (BOOL)_prepareTargetMetadataWithError:(NSError **)error
{
	[self.geometryFields removeAllObjects];
	[self.geometryFieldsMapIndex removeAllIndexes];
	[self.bitFields removeAllObjects];
	[self.bitFieldsMapIndex removeAllIndexes];
	[self.nullableNumericFields removeAllObjects];
	[self.nullableNumericFieldsMapIndex removeAllIndexes];

	NSString *databaseName = self.databaseName ?: self.connection.database;
	if (![databaseName length] || ![self.selectedTableTarget length]) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorTargetMetadataUnavailable message:NSLocalizedString(@"The target table metadata could not be loaded because the database or table name is missing.", @"lightweight CSV import metadata missing target error")];
		return NO;
	}

	NSString *query = [NSString stringWithFormat:@"SELECT COLUMN_NAME AS name, DATA_TYPE AS data_type, IS_NULLABLE AS is_nullable FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = %@ AND TABLE_NAME = %@ ORDER BY ORDINAL_POSITION",
					   [self.connection escapeAndQuoteString:databaseName],
					   [self.connection escapeAndQuoteString:self.selectedTableTarget]];
	SPMySQLResult *result = [self.connection queryString:query];
	if ([self.connection queryErrored]) {
		// Match legacy import behaviour: target metadata only drives special field coercion.
		// The import SQL itself should decide whether the target is valid.
		return YES;
	}

	if (!result) {
		// See note above; continue without geometry/bit/nullable numeric maps.
		return YES;
	}

	[result setDefaultRowReturnType:SPMySQLResultRowAsDictionary];
	[result setReturnDataAsStrings:YES];

	if (![result numberOfRows]) {
		// See note above; this can happen immediately after field mapper creates a new table.
		return YES;
	}

	for (id row in result) {
		if (![row isKindOfClass:[NSDictionary class]]) continue;
		NSDictionary *field = row;
		NSString *fieldName = [field objectForKey:@"name"];
		NSString *dataType = [[field objectForKey:@"data_type"] lowercaseString];
		NSString *nullable = [field objectForKey:@"is_nullable"];
		if (![fieldName length] || ![dataType length]) continue;

		if ([self.class _isGeometryDataType:dataType]) {
			[self.geometryFields addObject:fieldName];
		}
		if ([dataType isEqualToString:@"bit"]) {
			[self.bitFields addObject:fieldName];
		}
		if ([self.class _isNumericDataType:dataType] && [[nullable uppercaseString] isEqualToString:@"YES"]) {
			[self.nullableNumericFields addObject:fieldName];
		}
	}

	return YES;
}

- (void)_refreshMappedSpecialFieldIndexes
{
	for (NSUInteger i = 0; i < [self.fieldMappingArray count]; i++) {
		if ([[self.fieldMapperOperator safeObjectAtIndex:i] integerValue] != 0) continue;

		NSString *fieldName = [self.fieldMappingTableColumnNames safeObjectAtIndex:i];
		if ([self.nullableNumericFields containsObject:fieldName]) {
			[self.nullableNumericFieldsMapIndex addIndex:i];
		}
		if ([self.geometryFields containsObject:fieldName]) {
			[self.geometryFieldsMapIndex addIndex:i];
		}
		if ([self.bitFields containsObject:fieldName]) {
			[self.bitFieldsMapIndex addIndex:i];
		}
	}
}

- (NSMutableString *)_insertBaseStringWithError:(NSError **)error
{
	if (![self.csvImportHeaderString length] || ![self.selectedTableTarget length]) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorImportEngineUnavailable message:NSLocalizedString(@"The CSV import SQL header is incomplete.", @"lightweight CSV import missing SQL header error")];
		return nil;
	}

	NSMutableString *insertBaseString = [NSMutableString stringWithString:self.csvImportHeaderString];
	if (self.importMethodIsUpdate) {
		return insertBaseString;
	}

	[insertBaseString appendFormat:@"%@ (", [self.selectedTableTarget backtickQuotedString]];
	BOOL hasEntries = NO;
	for (NSUInteger i = 0; i < [self.fieldMappingArray count]; i++) {
		if ([[self.fieldMapperOperator safeObjectAtIndex:i] integerValue] != 0) continue;

		if (hasEntries) [insertBaseString appendString:@","];
		else hasEntries = YES;

		[insertBaseString appendStringOrNil:[[self.fieldMappingTableColumnNames safeObjectAtIndex:i] backtickQuotedString]];
	}
	[insertBaseString appendString:@") VALUES\n"];
	return insertBaseString;
}

- (NSString *)_insertRemainingBaseString
{
	NSMutableString *insertRemainingBaseString = [NSMutableString stringWithString:@"INSERT INTO "];
	[insertRemainingBaseString appendFormat:@"%@ (", [self.selectedTableTarget backtickQuotedString]];
	BOOL hasEntries = NO;
	for (NSUInteger i = 0; i < [self.fieldMappingArray count]; i++) {
		if ([[self.fieldMapperOperator safeObjectAtIndex:i] integerValue] != 0) continue;

		if (hasEntries) [insertRemainingBaseString appendString:@","];
		else hasEntries = YES;

		[insertRemainingBaseString appendStringOrNil:[[self.fieldMappingTableColumnNames safeObjectAtIndex:i] backtickQuotedString]];
	}
	[insertRemainingBaseString appendString:@") VALUES\n"];
	return insertRemainingBaseString;
}

- (NSInteger)_executeInsertRows:(NSArray<NSArray<id> *> *)rows
				 firstRowNumber:(NSInteger)firstRowNumber
			   insertBaseString:(NSString *)insertBaseString
						  errors:(NSMutableArray<NSString *> *)errors
{
	NSInteger importedRows = 0;
	NSUInteger rowIndex = 0;

	while (rowIndex < [rows count] && !self.importCancelled) {
		NSMutableString *query = [NSMutableString stringWithString:insertBaseString];
		NSUInteger rowsThisQuery = 0;

		for (; rowIndex + rowsThisQuery < [rows count] && rowsThisQuery < SALightweightCSVImportRowsPerQuery; rowsThisQuery++) {
			if (rowsThisQuery > 0) [query appendString:@",\n"];
			[query appendString:[self mappedValueStringForRowArray:[rows objectAtIndex:(rowIndex + rowsThisQuery)]]];
			if ([query length] > SALightweightCSVImportMaxQueryLength) {
				rowsThisQuery++;
				break;
			}
		}

		NSString *queryToRun = [self _queryByAppendingImportTailIfNeeded:query];
		[self.connection queryString:queryToRun];

		if ([self.connection queryErrored]) {
			for (NSUInteger i = 0; i < rowsThisQuery && !self.importCancelled; i++) {
				NSMutableString *singleQuery = [NSMutableString stringWithString:insertBaseString];
				[singleQuery appendString:[self mappedValueStringForRowArray:[rows objectAtIndex:(rowIndex + i)]]];
				[self.connection queryString:[self _queryByAppendingImportTailIfNeeded:singleQuery]];

				if ([self.connection queryErrored]) {
					[errors addObject:[NSString stringWithFormat:NSLocalizedString(@"[ERROR in row %ld] %@", @"lightweight CSV row import error"), (long)(firstRowNumber + (NSInteger)rowIndex + (NSInteger)i), [self.connection lastErrorMessage] ?: @""]];
				}
				else {
					importedRows++;
				}
			}
		}
		else {
			importedRows += (NSInteger)rowsThisQuery;
		}

		rowIndex += rowsThisQuery;
	}

	return importedRows;
}

- (BOOL)_executeUpdateRow:(NSArray<id> *)row
				rowNumber:(NSInteger)rowNumber
		  insertBaseString:(NSString *)insertBaseString
 insertRemainingBaseString:(NSString *)insertRemainingBaseString
					errors:(NSMutableArray<NSString *> *)errors
{
	NSMutableString *query = [NSMutableString stringWithString:insertBaseString];
	[query appendString:[self mappedUpdateSetStatementStringForRowArray:row]];
	[self.connection queryString:[self _queryByAppendingImportTailIfNeeded:query]];

	if ([self.connection queryErrored]) {
		[errors addObject:[NSString stringWithFormat:NSLocalizedString(@"[ERROR in row %ld] %@", @"lightweight CSV row import error"), (long)rowNumber, [self.connection lastErrorMessage] ?: @""]];
		return NO;
	}

	if (self.insertRemainingRowsAfterUpdate && ![self.connection rowsAffectedByLastQuery]) {
		NSMutableString *insertRemainingQuery = [NSMutableString stringWithString:insertRemainingBaseString ?: @""];
		[insertRemainingQuery appendString:[self mappedValueStringForRowArray:row]];
		[self.connection queryString:[self _queryByAppendingImportTailIfNeeded:insertRemainingQuery]];

		if ([self.connection queryErrored]) {
			[errors addObject:[NSString stringWithFormat:NSLocalizedString(@"[ERROR in row %ld] %@", @"lightweight CSV row import error"), (long)rowNumber, [self.connection lastErrorMessage] ?: @""]];
			return NO;
		}
	}

	return YES;
}

- (NSString *)_queryByAppendingImportTailIfNeeded:(NSString *)query
{
	if (![self.csvImportTailString length]) return query;
	return [NSString stringWithFormat:@"%@ %@", query, self.csvImportTailString];
}

- (void)_publishImportProgress:(SALightweightCSVImportProgress)progress
				  rowsImported:(NSInteger)rowsImported
					 bytesRead:(unsigned long long)bytesRead
					totalBytes:(unsigned long long)totalBytes
{
	if (!progress) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		progress(rowsImported, bytesRead, totalBytes);
	});
}

- (void)_finishImportWithRowsImported:(NSInteger)rowsImported
								errors:(NSArray<NSString *> *)errors
							 cancelled:(BOOL)cancelled
								 error:(NSError *)error
						   completion:(SALightweightCSVImportResultCompletion)completion
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self.importRunning = NO;
		self.importCancelled = NO;
		[self clearTemporaryState];

		if (completion) {
			SALightweightCSVImportResult *result = [[SALightweightCSVImportResult alloc] initWithRowsImported:rowsImported
																									  errors:errors
																								   cancelled:cancelled
																									   error:error];
			completion(result);
		}
	});
}

- (NSString *)mappedUpdateSetStatementStringForRowArray:(NSArray *)csvRowArray
{
	NSMutableString *setString = [NSMutableString stringWithString:@""];
	NSMutableString *whereString = [NSMutableString stringWithString:@"WHERE "];
	NSString *re = @"(?<!\\\\)\\$(\\d+)";

	for (NSUInteger i = 0; i < [self.fieldMappingArray count]; i++) {
		NSInteger importOperator = [[self.fieldMapperOperator safeObjectAtIndex:i] integerValue];
		if (importOperator == 1) continue;

		NSInteger mapColumn = [[self.fieldMappingArray safeObjectAtIndex:i] integerValue];

		if (importOperator == 0) {
			if ([setString length] > 1) [setString appendString:@","];
			NSString *fieldName = [[self.fieldMappingTableColumnNames safeObjectAtIndex:i] backtickQuotedString];
			if (fieldName) {
				[setString appendStringOrNil:fieldName];
				[setString appendString:@"="];
			}

			if (self.fieldMappingArrayHasGlobalVariables && mapColumn >= (NSInteger)self.numberOfImportDataColumns) {
				[setString appendString:[self _mappedGlobalValueStringAtIndex:mapColumn rowArray:csvRowArray regex:re]];
			}
			else {
				id cellData = [csvRowArray safeObjectAtIndex:mapColumn];
				if ([cellData isSPNotLoaded]) cellData = [self.fieldMappingTableDefaultValues safeObjectAtIndex:i];

				if (!cellData || [cellData isNSNull]) {
					[setString appendString:@"NULL"];
				}
				else {
					[setString appendStringOrNil:[self.connection escapeAndQuoteString:[cellData description]]];
				}
			}
		}
		else if (importOperator == 2) {
			if ([whereString length] > 7) [whereString appendString:@" AND "];
			[whereString appendStringOrNil:[[self.fieldMappingTableColumnNames safeObjectAtIndex:i] backtickQuotedString]];

			if (self.fieldMappingArrayHasGlobalVariables && mapColumn >= (NSInteger)self.numberOfImportDataColumns) {
				[whereString appendFormat:@"=%@", [self _mappedGlobalValueStringAtIndex:mapColumn rowArray:csvRowArray regex:re]];
			}
			else {
				id cellData = [csvRowArray safeObjectAtIndex:mapColumn];
				if ([cellData isSPNotLoaded]) cellData = [self.fieldMappingTableDefaultValues safeObjectAtIndex:i];

				if (!cellData || [cellData isNSNull]) {
					[whereString appendString:@" IS NULL"];
				}
				else {
					NSString *escaped = [self.connection escapeAndQuoteString:[cellData description]];
					if (escaped) {
						[whereString appendString:@"="];
						[whereString appendStringOrNil:escaped];
					}
				}
			}
		}
	}

	return [NSString stringWithFormat:@"%@ %@", setString, whereString];
}

- (NSString *)mappedValueStringForRowArray:(NSArray *)csvRowArray
{
	NSMutableString *valueString = [NSMutableString stringWithString:@"("];
	NSString *re = @"(?<!\\\\)\\$(\\d+)";

	for (NSUInteger i = 0; i < [self.fieldMappingArray count]; i++) {
		if ([[self.fieldMapperOperator safeObjectAtIndex:i] integerValue] > 0) continue;

		NSInteger mapColumn = [[self.fieldMappingArray safeObjectAtIndex:i] integerValue];
		if ([valueString length] > 1) [valueString appendString:@","];

		if (self.fieldMappingArrayHasGlobalVariables && mapColumn >= (NSInteger)self.numberOfImportDataColumns) {
			[valueString appendString:[self _mappedGlobalValueStringAtIndex:mapColumn rowArray:csvRowArray regex:re]];
		}
		else {
			id cellData = [csvRowArray safeObjectAtIndex:mapColumn];
			if ([cellData isSPNotLoaded]) cellData = [self.fieldMappingTableDefaultValues safeObjectAtIndex:i];

			if (!cellData || [cellData isNSNull] || ([self.nullableNumericFieldsMapIndex containsIndex:i] && [[cellData description] isEqualToString:@""])) {
				[valueString appendString:@"NULL"];
			}
			else if ([self.geometryFieldsMapIndex containsIndex:i]) {
				[valueString appendString:[[cellData description] getGeomFromTextString]];
			}
			else if ([self.bitFieldsMapIndex containsIndex:i]) {
				[valueString appendString:@"b"];
				[valueString appendStringOrNil:[self.connection escapeAndQuoteString:[cellData description]]];
			}
			else {
				[valueString appendStringOrNil:[self.connection escapeAndQuoteString:[cellData description]]];
			}
		}
	}

	[valueString appendString:@")"];
	return valueString;
}

- (NSString *)_mappedGlobalValueStringAtIndex:(NSInteger)mapColumn rowArray:(NSArray *)csvRowArray regex:(NSString *)regex
{
	NSMutableString *globalVar = [NSMutableString string];
	id insertItem = [self.fieldMappingGlobalValueArray safeObjectAtIndex:mapColumn];
	if (!insertItem || [insertItem isNSNull] || [insertItem isSPNotLoaded]) {
		[globalVar setString:@"NULL"];
	}
	else {
		[globalVar setStringOrNil:[insertItem description]];
		if ([globalVar rangeOfString:@"$"].length && [globalVar isMatchedByRegex:regex]) {
			while ([globalVar isMatchedByRegex:regex]) {
				[globalVar flushCachedRegexData];
				NSRange placeholderRange = [globalVar rangeOfRegex:regex capture:0L];
				NSInteger columnIndex = [[globalVar substringWithRange:[globalVar rangeOfRegex:regex capture:1L]] integerValue];
				if (columnIndex > 0 && columnIndex <= (NSInteger)[csvRowArray count]) {
					id columnValue = [csvRowArray safeObjectAtIndex:(NSUInteger)(columnIndex - 1)];
					if ([columnValue isNSNull]) {
						[globalVar replaceCharactersInRange:placeholderRange withString:@"NULL"];
					}
					else if ([columnValue isSPNotLoaded]) {
						[globalVar replaceCharactersInRange:placeholderRange withString:@""];
					}
					else {
						NSString *escapedColumn = [[columnValue description] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
						[globalVar replaceCharactersInRange:placeholderRange withString:[NSString stringWithFormat:@"'%@'", escapedColumn]];
					}
				}
				else {
					[globalVar replaceCharactersInRange:placeholderRange withString:@"GLOBAL_SQL_EXPRESSION_ERROR"];
				}
			}
		}
	}

	return globalVar;
}

+ (NSArray<NSString *> *)_normalizedTableNames:(NSArray<NSString *> *)tableNames
{
	if (![tableNames count]) return @[];

	NSMutableArray<NSString *> *normalizedNames = [NSMutableArray arrayWithCapacity:[tableNames count]];
	for (id tableName in tableNames) {
		if ([tableName isKindOfClass:[NSString class]] && [tableName length]) {
			[normalizedNames addObject:tableName];
		}
		else if ([tableName respondsToSelector:@selector(stringValue)]) {
			NSString *stringValue = [tableName stringValue];
			if ([stringValue length]) [normalizedNames addObject:stringValue];
		}
	}

	return normalizedNames;
}

+ (NSString *)_filePathForURL:(NSURL *)fileURL
{
	if (![fileURL isKindOfClass:[NSURL class]]) return nil;
	return [fileURL isFileURL] ? [fileURL path] : [fileURL absoluteString];
}

+ (NSString *)_stringFromUserDefaults:(NSUserDefaults *)userDefaults forKey:(NSString *)key defaultValue:(NSString *)defaultValue
{
	id value = [userDefaults objectForKey:key];
	return [value isKindOfClass:[NSString class]] ? value : defaultValue;
}

+ (BOOL)_boolFromUserDefaults:(NSUserDefaults *)userDefaults forKey:(NSString *)key defaultValue:(BOOL)defaultValue
{
	id value = [userDefaults objectForKey:key];
	if ([value respondsToSelector:@selector(boolValue)]) {
		return [value boolValue];
	}

	return defaultValue;
}

- (BOOL)_selectTargetDatabaseWithError:(NSError **)error
{
	NSString *databaseName = self.databaseName ?: self.connection.database;
	if (![databaseName length]) {
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorMissingConnection message:NSLocalizedString(@"Select a database before starting a lightweight CSV import.", @"lightweight CSV import missing database error")];
		return NO;
	}

	if (![self.connection selectDatabase:databaseName]) {
		NSString *message = [NSString stringWithFormat:NSLocalizedString(@"The target database “%@” could not be selected. %@", @"lightweight CSV import select database error"), databaseName, [self.connection lastErrorMessage] ?: @""];
		[self.class _assignError:error code:SALightweightCSVImportControllerErrorMissingConnection message:message];
		return NO;
	}

	return YES;
}

+ (BOOL)_isGeometryDataType:(NSString *)dataType
{
	static NSSet<NSString *> *geometryTypes;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		geometryTypes = [NSSet setWithArray:@[@"geometry", @"point", @"linestring", @"polygon", @"multipoint", @"multilinestring", @"multipolygon", @"geometrycollection", @"geomcollection"]];
	});

	return [geometryTypes containsObject:[dataType lowercaseString]];
}

+ (BOOL)_isNumericDataType:(NSString *)dataType
{
	static NSSet<NSString *> *numericTypes;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		numericTypes = [NSSet setWithArray:@[@"tinyint", @"smallint", @"mediumint", @"int", @"integer", @"bigint", @"decimal", @"dec", @"numeric", @"fixed", @"float", @"double", @"double precision", @"real"]];
	});

	return [numericTypes containsObject:[dataType lowercaseString]];
}

+ (NSError *)_errorWithCode:(SALightweightCSVImportControllerErrorCode)code message:(NSString *)message
{
	return [NSError errorWithDomain:SALightweightCSVImportControllerErrorDomain
							   code:code
						   userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

+ (void)_assignError:(NSError **)error code:(SALightweightCSVImportControllerErrorCode)code message:(NSString *)message
{
	if (error) {
		*error = [self _errorWithCode:code message:message];
	}
}

@end
