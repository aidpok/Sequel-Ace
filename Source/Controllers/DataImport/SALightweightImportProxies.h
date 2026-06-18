//
//  SALightweightImportProxies.h
//  sequel-ace
//

#import <Foundation/Foundation.h>

#import "SPConstants.h"

@class SPMySQLConnection;

NS_ASSUME_NONNULL_BEGIN

@interface SALightweightDatabaseDataProxy : NSObject

@property (nonatomic, strong, nullable) SPMySQLConnection *connection;

- (instancetype)initWithConnection:(nullable SPMySQLConnection *)connection NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

- (NSArray<NSDictionary<NSString *, id> *> *)getDatabaseStorageEngines;
- (NSArray<NSDictionary<NSString *, id> *> *)getDatabaseCharacterSetEncodings;

@end

@interface SALightweightImportTablesListProxy : NSObject

@property (nonatomic, strong, nullable) SPMySQLConnection *connection;
@property (nonatomic, strong, readonly) SALightweightDatabaseDataProxy *databaseDataInstance;
@property (nonatomic, copy, nullable) NSString *databaseName;
@property (nonatomic, copy, nullable) NSString *selectedTableName;
@property (nonatomic, copy) NSArray<NSString *> *tableNames;

- (instancetype)initWithConnection:(nullable SPMySQLConnection *)connection
					  databaseName:(nullable NSString *)databaseName
						 tableName:(nullable NSString *)tableName
						tableNames:(nullable NSArray<NSString *> *)tableNames NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithConnection:(nullable SPMySQLConnection *)connection;
- (instancetype)init;

- (IBAction)updateTables:(nullable id)sender;

- (NSArray<NSString *> *)allTableNames;
- (NSArray<NSString *> *)selectedTableAndViewNames;
- (NSArray<NSString *> *)tables;
- (nullable NSString *)tableName;

- (BOOL)selectItemWithName:(nullable NSString *)theName;
- (BOOL)isTableNameValid:(nullable NSString *)tableName forType:(SPTableType)tableType;
- (BOOL)isTableNameValid:(nullable NSString *)tableName forType:(SPTableType)tableType ignoringSelectedTable:(BOOL)ignoreSelectedTable;

@end

NS_ASSUME_NONNULL_END
