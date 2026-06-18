//
//  SALightweightImportProxies.m
//  sequel-ace
//

#import "SALightweightImportProxies.h"

#import <SPMySQL/SPMySQL.h>

static NSString *SAStringFromObject(id object)
{
	if (!object || object == [NSNull null]) return nil;
	if ([object isKindOfClass:[NSString class]]) return object;
	if ([object respondsToSelector:@selector(stringValue)]) return [object stringValue];
	return nil;
}

static id SAObjectForKeyVariants(NSDictionary *row, NSArray<NSString *> *keys)
{
	for (NSString *key in keys) {
		id object = [row objectForKey:key];
		if (object && object != [NSNull null]) return object;
	}

	for (NSString *rowKey in row) {
		for (NSString *key in keys) {
			if ([rowKey caseInsensitiveCompare:key] == NSOrderedSame) {
				id object = [row objectForKey:rowKey];
				if (object && object != [NSNull null]) return object;
			}
		}
	}

	return nil;
}

static NSArray<NSDictionary<NSString *, id> *> *SARowsForQuery(SPMySQLConnection *connection, NSString *query)
{
	if (!connection || ![query length]) return @[];

	SPMySQLResult *result = [connection queryString:query];
	if (!result || [connection queryErrored]) return @[];

	[result setDefaultRowReturnType:SPMySQLResultRowAsDictionary];
	[result setReturnDataAsStrings:YES];

	NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray arrayWithCapacity:(NSUInteger)[result numberOfRows]];
	for (id row in result) {
		if ([row isKindOfClass:[NSDictionary class]]) {
			[rows addObject:row];
		}
	}

	return rows;
}

static NSComparisonResult SACompareStrings(NSString *left, NSString *right)
{
	return [(left ?: @"") compare:(right ?: @"") options:NSCaseInsensitiveSearch|NSLiteralSearch];
}

@implementation SALightweightDatabaseDataProxy

- (instancetype)init
{
	return [self initWithConnection:nil];
}

- (instancetype)initWithConnection:(SPMySQLConnection *)connection
{
	if ((self = [super init])) {
		_connection = connection;
	}

	return self;
}

- (NSArray<NSDictionary<NSString *, id> *> *)getDatabaseStorageEngines
{
	NSArray<NSDictionary<NSString *, id> *> *rows = SARowsForQuery(self.connection, @"SELECT Engine, Support FROM `information_schema`.`engines` WHERE SUPPORT IN ('DEFAULT', 'YES') AND Engine != 'PERFORMANCE_SCHEMA'");

	if (![rows count]) {
		rows = SARowsForQuery(self.connection, @"SHOW ENGINES");
	}

	NSMutableArray<NSDictionary<NSString *, id> *> *engines = [NSMutableArray array];
	for (NSDictionary *row in rows) {
		NSString *engine = SAStringFromObject(SAObjectForKeyVariants(row, @[@"Engine"]));
		if (![engine length] || [engine caseInsensitiveCompare:@"PERFORMANCE_SCHEMA"] == NSOrderedSame) continue;

		NSString *support = SAStringFromObject(SAObjectForKeyVariants(row, @[@"Support"]));
		if ([support length]
				&& [support caseInsensitiveCompare:@"YES"] != NSOrderedSame
				&& [support caseInsensitiveCompare:@"DEFAULT"] != NSOrderedSame) {
			continue;
		}

		[engines addObject:@{@"Engine": engine}];
	}

	return [engines sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
		return SACompareStrings(SAStringFromObject([left objectForKey:@"Engine"]), SAStringFromObject([right objectForKey:@"Engine"]));
	}];
}

- (NSArray<NSDictionary<NSString *, id> *> *)getDatabaseCharacterSetEncodings
{
	NSArray<NSDictionary<NSString *, id> *> *rows = SARowsForQuery(self.connection, @"SELECT CHARACTER_SET_NAME, DESCRIPTION, DEFAULT_COLLATE_NAME, MAXLEN FROM `information_schema`.`character_sets` ORDER BY `character_set_name` ASC");

	if (![rows count]) {
		rows = SARowsForQuery(self.connection, @"SHOW CHARACTER SET");
	}

	NSMutableArray<NSDictionary<NSString *, id> *> *encodings = [NSMutableArray array];
	for (NSDictionary *row in rows) {
		NSString *name = SAStringFromObject(SAObjectForKeyVariants(row, @[@"CHARACTER_SET_NAME", @"Charset"]));
		if (![name length]) continue;

		NSString *description = SAStringFromObject(SAObjectForKeyVariants(row, @[@"DESCRIPTION", @"Description"]));
		NSString *defaultCollation = SAStringFromObject(SAObjectForKeyVariants(row, @[@"DEFAULT_COLLATE_NAME", @"Default collation"]));
		id maxLength = SAObjectForKeyVariants(row, @[@"MAXLEN", @"Maxlen"]);

		NSMutableDictionary<NSString *, id> *encoding = [NSMutableDictionary dictionary];
		[encoding setObject:name forKey:@"CHARACTER_SET_NAME"];
		[encoding setObject:([description length] ? description : name) forKey:@"DESCRIPTION"];
		if ([defaultCollation length]) [encoding setObject:defaultCollation forKey:@"DEFAULT_COLLATE_NAME"];
		if (maxLength) [encoding setObject:maxLength forKey:@"MAXLEN"];

		[encodings addObject:encoding];
	}

	if (![encodings count]) {
		[encodings addObjectsFromArray:@[
			@{@"CHARACTER_SET_NAME": @"utf8mb4", @"DESCRIPTION": @"UTF-8 Unicode", @"DEFAULT_COLLATE_NAME": @"utf8mb4_unicode_ci", @"MAXLEN": @4},
			@{@"CHARACTER_SET_NAME": @"utf8", @"DESCRIPTION": @"UTF-8 Unicode", @"DEFAULT_COLLATE_NAME": @"utf8_general_ci", @"MAXLEN": @3},
			@{@"CHARACTER_SET_NAME": @"latin1", @"DESCRIPTION": @"cp1252 West European", @"DEFAULT_COLLATE_NAME": @"latin1_swedish_ci", @"MAXLEN": @1}
		]];
	}

	return [encodings sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
		return SACompareStrings(SAStringFromObject([left objectForKey:@"CHARACTER_SET_NAME"]), SAStringFromObject([right objectForKey:@"CHARACTER_SET_NAME"]));
	}];
}

@end

@implementation SALightweightImportTablesListProxy

- (instancetype)init
{
	return [self initWithConnection:nil databaseName:nil tableName:nil tableNames:nil];
}

- (instancetype)initWithConnection:(SPMySQLConnection *)connection
{
	return [self initWithConnection:connection databaseName:nil tableName:nil tableNames:nil];
}

- (instancetype)initWithConnection:(SPMySQLConnection *)connection
					  databaseName:(NSString *)databaseName
						 tableName:(NSString *)tableName
						tableNames:(NSArray<NSString *> *)tableNames
{
	if ((self = [super init])) {
		_connection = connection;
		_databaseDataInstance = [[SALightweightDatabaseDataProxy alloc] initWithConnection:connection];
		_databaseName = [databaseName copy];
		_selectedTableName = [tableName copy];
		_tableNames = [self.class _normalizedTableNames:tableNames];

		if (![_tableNames count]) {
			[self updateTables:nil];
		}
	}

	return self;
}

- (void)setConnection:(SPMySQLConnection *)connection
{
	_connection = connection;
	self.databaseDataInstance.connection = connection;
}

- (void)setTableNames:(NSArray<NSString *> *)tableNames
{
	_tableNames = [self.class _normalizedTableNames:tableNames];
}

- (IBAction)updateTables:(id)sender
{
	if (!self.connection) {
		if (!self.tableNames) self.tableNames = @[];
		return;
	}

	NSArray *tables = [self.connection tablesFromDatabase:self.databaseName];
	if (tables) {
		self.tableNames = tables;
	}
}

- (NSArray<NSString *> *)allTableNames
{
	return self.tableNames ?: @[];
}

- (NSArray<NSString *> *)selectedTableAndViewNames
{
	NSString *selectedName = self.selectedTableName;
	if (![selectedName length]) return @[];

	for (NSString *table in [self allTableNames]) {
		if ([table isEqualToString:selectedName]) return @[selectedName];
		if ([table compare:selectedName options:NSCaseInsensitiveSearch|NSLiteralSearch] == NSOrderedSame) return @[table];
	}

	return @[];
}

- (NSArray<NSString *> *)tables
{
	return [self allTableNames];
}

- (NSString *)tableName
{
	return self.selectedTableName;
}

- (BOOL)selectItemWithName:(NSString *)theName
{
	if (![theName length]) {
		self.selectedTableName = nil;
		return NO;
	}

	for (NSString *table in [self allTableNames]) {
		if ([table isEqualToString:theName] || [table compare:theName options:NSCaseInsensitiveSearch|NSLiteralSearch] == NSOrderedSame) {
			self.selectedTableName = table;
			return YES;
		}
	}

	return NO;
}

- (BOOL)isTableNameValid:(NSString *)tableName forType:(SPTableType)tableType
{
	return [self isTableNameValid:tableName forType:tableType ignoringSelectedTable:NO];
}

- (BOOL)isTableNameValid:(NSString *)tableName forType:(SPTableType)tableType ignoringSelectedTable:(BOOL)ignoreSelectedTable
{
	if (tableType != SPTableTypeTable && tableType != SPTableTypeView) return YES;
	if (![tableName length]) return NO;

	NSCharacterSet *whitespaceAndNewline = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	if ([tableName rangeOfCharacterFromSet:whitespaceAndNewline options:NSBackwardsSearch].location == [tableName length] - 1) return NO;

	NSString *lowercaseTableName = [tableName lowercaseString];
	for (NSString *existingTableName in [self allTableNames]) {
		if (![lowercaseTableName isEqualToString:[existingTableName lowercaseString]]) continue;
		if (ignoreSelectedTable && [existingTableName isEqualToString:self.selectedTableName]) continue;
		return NO;
	}

	return YES;
}

+ (NSArray<NSString *> *)_normalizedTableNames:(NSArray<NSString *> *)tableNames
{
	if (![tableNames count]) return @[];

	NSMutableArray<NSString *> *normalizedNames = [NSMutableArray arrayWithCapacity:[tableNames count]];
	for (id tableName in tableNames) {
		NSString *name = SAStringFromObject(tableName);
		if ([name length]) [normalizedNames addObject:name];
	}

	return normalizedNames;
}

@end
