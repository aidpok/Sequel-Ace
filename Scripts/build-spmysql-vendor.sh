#!/bin/bash
#
# Build the vendored SPMySQL client package from source.
#
# This intentionally does not copy Homebrew bottles. Homebrew-built bottles can
# target newer macOS releases than Sequel Ace supports, which makes Xcode warn
# when the app target stays lower.

set -euo pipefail

OPENSSL_VERSION="3.6.2"
OPENSSL_SHA256="aaf51a1fe064384f811daeaeb4ec4dce7340ec8bd893027eee676af31e83a04f"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"

MARIADB_CONNECTOR_C_VERSION="3.4.8"
MARIADB_CONNECTOR_C_SHA256="156aed3b49f857d0ac74fb76f1982968bcbfd8382da3f5b6ae71f616729920d7"
MARIADB_CONNECTOR_C_URL="https://archive.mariadb.org/connector-c-${MARIADB_CONNECTOR_C_VERSION}/mariadb-connector-c-${MARIADB_CONNECTOR_C_VERSION}-src.tar.gz"

MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
ARCH="${ARCH:-arm64}"
case "$ARCH" in
	arm64)
		OPENSSL_TARGET="darwin64-arm64-cc"
		;;
	x86_64)
		OPENSSL_TARGET="darwin64-x86_64-cc"
		;;
	*)
		echo "Unsupported ARCH: $ARCH" >&2
		exit 1
		;;
esac
WORK_DIR="${WORK_DIR:-/tmp/sequel-ace-spmysql-vendor}"
ROOT_DIR="${ROOT_DIR:-$WORK_DIR/root}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"
SOURCE_DIR="${SOURCE_DIR:-$WORK_DIR/src}"
CONNECTOR_ROOT="${CONNECTOR_ROOT:-Frameworks/SPMySQLFramework/Vendor/MariaDBConnectorC}"
CLIENT_LIB_ROOT="${CLIENT_LIB_ROOT:-Frameworks/SPMySQLFramework/MySQL Client Libraries/lib}"

download() {
	local url="$1"
	local output="$2"
	local sha256="$3"

	mkdir -p "$(dirname "$output")"
	if [ ! -f "$output" ]; then
		curl -fL "$url" -o "$output"
	fi

	echo "$sha256  $output" | shasum -a 256 -c -
}

extract() {
	local tarball="$1"
	local destination="$2"

	rm -rf "$destination"
	mkdir -p "$destination"
	tar -xzf "$tarball" -C "$destination" --strip-components 1
}

build_openssl() {
	local openssl_src="$SOURCE_DIR/openssl"

	extract "$WORK_DIR/openssl-${OPENSSL_VERSION}.tar.gz" "$openssl_src"
	(
		cd "$openssl_src"
		MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" ./Configure \
			"$OPENSSL_TARGET" \
			shared \
			no-tests \
			no-docs \
			--prefix="$ROOT_DIR/openssl" \
			--openssldir="$ROOT_DIR/openssl/ssl" \
			"-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
		MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" make -j"$(sysctl -n hw.ncpu)"
		make install_sw
	)
}

build_mariadb_connector() {
	local mariadb_src="$SOURCE_DIR/mariadb-connector-c"
	local mariadb_build="$BUILD_DIR/mariadb-connector-c"

	extract "$WORK_DIR/mariadb-connector-c-${MARIADB_CONNECTOR_C_VERSION}.tar.gz" "$mariadb_src"
	rm -rf "$mariadb_build"

	cmake -S "$mariadb_src" -B "$mariadb_build" \
		-G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$ROOT_DIR/mariadb" \
		-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
		-DCMAKE_OSX_ARCHITECTURES="$ARCH" \
		-DCMAKE_PREFIX_PATH="$ROOT_DIR/openssl" \
		-DOPENSSL_ROOT_DIR="$ROOT_DIR/openssl" \
		-DOPENSSL_INCLUDE_DIR="$ROOT_DIR/openssl/include" \
		-DOPENSSL_SSL_LIBRARY="$ROOT_DIR/openssl/lib/libssl.3.dylib" \
		-DOPENSSL_CRYPTO_LIBRARY="$ROOT_DIR/openssl/lib/libcrypto.3.dylib" \
		-DWITH_SSL=OPENSSL \
		-DDEFAULT_SSL_VERIFY_SERVER_CERT=OFF \
		-DWITH_UNIT_TESTS=OFF \
		-DWITH_CURL=OFF \
		-DWITH_EXTERNAL_ZLIB=ON \
		-DZSTD_FOUND=FALSE

	cmake --build "$mariadb_build" --parallel "$(sysctl -n hw.ncpu)"
	cmake --install "$mariadb_build"
}

install_vendored_package() {
	rm -rf "$CONNECTOR_ROOT/include"
	mkdir -p "$CONNECTOR_ROOT/include" "$CLIENT_LIB_ROOT"

	rsync -a --delete "$ROOT_DIR/mariadb/include/mariadb/" "$CONNECTOR_ROOT/include/"
	cp "$ROOT_DIR/mariadb/lib/mariadb/libmariadb.3.dylib" "$CLIENT_LIB_ROOT/libmysqlclient.24.dylib"
	cp "$ROOT_DIR/openssl/lib/libssl.3.dylib" "$CLIENT_LIB_ROOT/libssl.3.dylib"
	cp "$ROOT_DIR/openssl/lib/libcrypto.3.dylib" "$CLIENT_LIB_ROOT/libcrypto.3.dylib"

	install_name_tool -id @loader_path/libmysqlclient.24.dylib "$CLIENT_LIB_ROOT/libmysqlclient.24.dylib"
	install_name_tool -change "$ROOT_DIR/openssl/lib/libssl.3.dylib" @loader_path/libssl.3.dylib "$CLIENT_LIB_ROOT/libmysqlclient.24.dylib"
	install_name_tool -change "$ROOT_DIR/openssl/lib/libcrypto.3.dylib" @loader_path/libcrypto.3.dylib "$CLIENT_LIB_ROOT/libmysqlclient.24.dylib"

	install_name_tool -id @loader_path/libssl.3.dylib "$CLIENT_LIB_ROOT/libssl.3.dylib"
	install_name_tool -change "$ROOT_DIR/openssl/lib/libcrypto.3.dylib" @loader_path/libcrypto.3.dylib "$CLIENT_LIB_ROOT/libssl.3.dylib"

	install_name_tool -id @loader_path/libcrypto.3.dylib "$CLIENT_LIB_ROOT/libcrypto.3.dylib"
}

verify_vendored_package() {
	local dylib

	for dylib in "$CLIENT_LIB_ROOT/libmysqlclient.24.dylib" "$CLIENT_LIB_ROOT/libssl.3.dylib" "$CLIENT_LIB_ROOT/libcrypto.3.dylib"; do
		vtool -show-build "$dylib" | grep -q "minos $MACOSX_DEPLOYMENT_TARGET"
		if otool -L "$dylib" | grep -v "$dylib" | grep -Eq "/(opt/homebrew|tmp)/"; then
			echo "Unexpected non-vendored dependency in $dylib" >&2
			otool -L "$dylib" >&2
			exit 1
		fi
	done
}

rm -rf "$ROOT_DIR" "$BUILD_DIR" "$SOURCE_DIR"
mkdir -p "$WORK_DIR"

download "$OPENSSL_URL" "$WORK_DIR/openssl-${OPENSSL_VERSION}.tar.gz" "$OPENSSL_SHA256"
download "$MARIADB_CONNECTOR_C_URL" "$WORK_DIR/mariadb-connector-c-${MARIADB_CONNECTOR_C_VERSION}.tar.gz" "$MARIADB_CONNECTOR_C_SHA256"

build_openssl
build_mariadb_connector
install_vendored_package
verify_vendored_package

echo "Updated MariaDB Connector/C headers in: $CONNECTOR_ROOT/include"
echo "Updated SPMySQL client dylibs in: $CLIENT_LIB_ROOT"
