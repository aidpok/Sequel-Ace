//
//  SPMySQLClientCompatibility.h
//  SPMySQLFramework
//
//  Created by Codex on May 21, 2026
//

#import "../Vendor/MariaDBConnectorC/include/mysql.h"

#ifndef SPMySQLClientCompatibility_h
#define SPMySQLClientCompatibility_h

#if defined(SERVER_MORE_RESULTS_EXIST) && !defined(SERVER_MORE_RESULTS_EXISTS)
#define SERVER_MORE_RESULTS_EXISTS SERVER_MORE_RESULTS_EXIST
#endif

#if defined(LIBMARIADB) && !defined(CR_INSECURE_API_ERR)
#define CR_INSECURE_API_ERR 0xFFFFFFFF
#define mysql_real_escape_string_quote(connection, to, from, length, quote) mysql_real_escape_string(connection, to, from, length)
#endif

static inline void SPMySQLApplyRestrictedAuthenticationPlugins(MYSQL *connection)
{
#ifdef LIBMARIADB
	mysql_options(connection, MARIADB_OPT_RESTRICTED_AUTH, "mysql_native_password,mysql_old_password,caching_sha2_password,mysql_clear_password,client_ed25519,dialog");
#endif
}

static inline int SPMySQLRequireSSL(MYSQL *connection, const char *tlsCipherSuites)
{
#ifdef LIBMARIADB
	my_bool enforceSSL = 1;
	return mysql_options(connection, MYSQL_OPT_SSL_ENFORCE, (void *)&enforceSSL);
#else
	mysql_options(connection, MYSQL_OPT_TLS_CIPHERSUITES, (const void *)tlsCipherSuites);
	enum mysql_ssl_mode opt_ssl_mode = SSL_MODE_REQUIRED;
	return mysql_options(connection, MYSQL_OPT_SSL_MODE, (void *)&opt_ssl_mode);
#endif
}

static inline void SPMySQLPreferSSL(MYSQL *connection)
{
#ifndef LIBMARIADB
	enum mysql_ssl_mode opt_ssl_mode = SSL_MODE_PREFERRED;
	mysql_options(connection, MYSQL_OPT_SSL_MODE, (void *)&opt_ssl_mode);
#endif
}

static inline int SPMySQLDisableSSL(MYSQL *connection)
{
#ifndef LIBMARIADB
	enum mysql_ssl_mode opt_ssl_mode = SSL_MODE_DISABLED;
	mysql_options(connection, MYSQL_OPT_SSL_MODE, (void *)&opt_ssl_mode);
	return 1;
#else
	return 0;
#endif
}

static inline int SPMySQLConnectionHasNetworkBuffer(MYSQL *connection)
{
	if (!connection) return 0;
#ifdef LIBMARIADB
	return (connection->net.pvio && connection->net.buff);
#else
	return (connection->net.vio && connection->net.buff);
#endif
}

static inline void SPMySQLDisableAutomaticReconnect(MYSQL *connection)
{
#ifdef LIBMARIADB
	connection->options.reconnect = 0;
#else
	connection->reconnect = 0;
#endif
}

#endif
