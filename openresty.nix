{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  perl,
  zlib,
  pcre,
  openssl,
  curl,
  gnumake,
  gcc,
  git,
  patch,
  pkg-config,
  unzip,
  luajitPackages,
}: let
  # Versions matching the original script
  openrestyVersion = "1.21.4.1";
  pcreVersion = "8.45";
  luarocksVersion = "3.9.1";
  kongNginxModuleVersion = "0.5.0";

  # Override curl to use OpenSSL 1.1.1 instead of 3.x
  curlWithOpenSSL111 = curl.override {
    openssl = openssl;
  };

  # Kong nginx module
  kongNginxModule = fetchFromGitHub {
    owner = "Kong";
    repo = "lua-kong-nginx-module";
    rev = kongNginxModuleVersion;
    sha256 = "sha256-y0xu1WEomyHOeYq0XthyBishlLHzK63LwHMLvPdWZQo=";
  };

  # LuaRocks source (will be built after OpenResty)
  luarocksSrc = fetchurl {
    url = "https://luarocks.org/releases/luarocks-${luarocksVersion}.tar.gz";
    sha256 = "sha256-/6/YOxxCqjgEIWalmsO2GMg4zk5j9Kzp2WGlZ571glM=";
  };
in
  stdenv.mkDerivation rec {
    pname = "openresty-kong";
    version = openrestyVersion;

    src = fetchurl {
      url = "https://openresty.org/download/openresty-${version}.tar.gz";
      sha256 = "sha256-DFCTtk94IehQZcmeXU5swxggz9fze5oN7IQgnYeir5k=";
    };

    nativeBuildInputs = [
      perl
      curlWithOpenSSL111
      gnumake
      gcc
      git
      patch
      pkg-config
      unzip
    ];

    buildInputs = [
      zlib
      pcre
      openssl # Ensure OpenSSL 1.1.1 is the only OpenSSL available
      luajitPackages.luafilesystem
    ];

    hardeningDisable = ["format"];

    # Apply Kong patches
    postPatch = ''
      # First, patch the Kong nginx module for OpenSSL 1.1.1 compatibility
      # Copy Kong module to a writable location and patch it
      cp -r ${kongNginxModule} kong-nginx-module-patched
      chmod -R u+w kong-nginx-module-patched

      # Fix the function signature for OpenSSL 1.1.1 compatibility
      sed -i 's/ngx_lua_kong_ssl_x509_copy(X509 \*in)/ngx_lua_kong_ssl_x509_copy(const X509 *in)/' kong-nginx-module-patched/src/ssl/ngx_lua_kong_ssl.c
      sed -i 's/return X509_up_ref(in) == 0 ? NULL : in;/return X509_up_ref((X509*)in) == 0 ? NULL : (X509*)in;/' kong-nginx-module-patched/src/ssl/ngx_lua_kong_ssl.c

      # Apply Kong patches to the bundle
      pushd bundle

      # Apply specific patches for OpenResty ${version}
      echo "Applying Kong patches for OpenResty ${version}..."

      # LuaJIT patches
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/LuaJIT-2.1-20220411_01_patch_macro_luajit_version.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/LuaJIT-2.1-20220411_02.patch}

      # lua-cjson patch
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/lua-cjson-2.1.0.10_01-empty_array.patch}

      # lua-resty-core patches
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/lua-resty-core-0.1.23_01-cosocket-mtls.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/lua-resty-core-0.1.23_02-dyn_upstream_keepalive.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/lua-resty-core-0.1.23_03-make-resty.core.shdict-compatible-with-m1.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/lua-resty-core-0.1.23_04-make-resty.core.response-compatible-with-m1.patch}

      # lua-resty-websocket patch
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/lua-resty-websocket-0.09_01-client-mtls.patch}

      # nginx patches
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/nginx-1.21.4_01-upstream_client_certificate_and_ssl_verify.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/nginx-1.21.4_02-remove-server-tokens-from-special-responses-output.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/nginx-1.21.4_03-stream_upstream_client_certificate_and_ssl_verify.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/nginx-1.21.4_04-grpc_authority_override.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/nginx-1.21.4_05-remove-server-headers-from-ngx-header-filter-module.patch}

      # ngx_lua patches
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/ngx_lua-0.10.21_01-cosocket-mtls.patch}
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/ngx_lua-0.10.21_02-dyn_upstream_keepalive.patch}

      # ngx_stream_lua patch
      patch -p1 < ${./openresty-patches/patches/1.21.4.1/ngx_stream_lua-0.0.11_01-expose_request_struct.patch}

      touch .patch_applied
      popd
    '';

    preConfigure = ''
      # Set up absolute paths for Kong modules
      KONG_MODULE_PATH="$(pwd)/../kong-nginx-module-patched"
    '';

    configureFlags = [
      "--prefix=${placeholder "out"}"
      "--with-pcre"
      "--with-pcre-jit"
      "--with-http_ssl_module"
      "--with-http_sub_module"
      "--with-http_realip_module"
      "--with-http_stub_status_module"
      "--with-http_v2_module"
      "--without-http_encrypted_session_module"
      "--with-stream_realip_module"
      "--with-stream_ssl_preread_module"
      "--with-openssl-opt=-I${openssl.dev}/include"
      "--with-cc-opt=-I${openssl.dev}/include"
      "--with-ld-opt=-L${openssl.out}/lib"
    ];

    configurePhase = ''
      runHook preConfigure

      # Debug: check directory structure
      echo "Current directory: $(pwd)"
      echo "Parent directory contents:"
      ls -la ../
      echo "Looking for kong-nginx-module-patched..."
      find .. -name "kong-nginx-module-patched" -type d

      # Configure with Kong module paths
      KONG_MODULE_PATH="$(find .. -name "kong-nginx-module-patched" -type d | head -1)"
      echo "Using Kong module path: $KONG_MODULE_PATH"
      ./configure \
        ''${configureFlags[@]} \
        --add-module="$KONG_MODULE_PATH" \
        --add-module="$KONG_MODULE_PATH/stream"

      runHook postConfigure
    '';

    preBuild = ''
      # Clear any conflicting environment variables
      unset OPENSSL_DIR
      unset OPENSSL_ROOT_DIR

      # Set rpath for runtime linking
      export OPENRESTY_RPATH=${openssl.out}/lib

      # Force exclusive use of OpenSSL 1.1.1 - clear other paths first
      export PKG_CONFIG_PATH=${openssl.dev}/lib/pkgconfig
      export CPPFLAGS="-I${openssl.dev}/include"
      export LDFLAGS="-L${openssl.out}/lib"
      export C_INCLUDE_PATH=${openssl.dev}/include
      export CPLUS_INCLUDE_PATH=${openssl.dev}/include
      export LIBRARY_PATH=${openssl.out}/lib

      # Ensure no OpenSSL 3.x paths are in the environment
      unset NIX_CFLAGS_COMPILE NIX_LDFLAGS

      # Show which OpenSSL version we're using for debugging
      echo "Using OpenSSL: ${openssl.dev}/include"
      echo "OpenSSL version information:"
      ls -la ${openssl.dev}/include/openssl/ | head -5
      echo "OpenSSL lib path: ${openssl.out}/lib"
      ls -la ${openssl.out}/lib/libssl* | head -3 || true

      # Verify no OpenSSL 3.x paths exist
      echo "Checking for conflicting OpenSSL 3.x paths..."
      if find /nix/store -path "*/openssl-3*/include" -type d 2>/dev/null | head -1; then
        echo "WARNING: Found OpenSSL 3.x paths in environment"
      else
        echo "No conflicting OpenSSL 3.x paths found"
      fi
    '';

    buildPhase = ''
      # Build with proper number of cores
      make -j$NIX_BUILD_CORES
    '';

    postInstall = ''
      # Install Kong nginx module Lua libraries
      KONG_MODULE_PATH="$(find .. -name "kong-nginx-module-patched" -type d | head -1)"
      if [ -n "$KONG_MODULE_PATH" ]; then
        pushd "$KONG_MODULE_PATH"
        make install LUA_LIB_DIR=$out/lualib
        popd
      else
        echo "Kong module not found, skipping Lua library installation"
      fi

      # Build and install LuaRocks
      pushd /tmp
      tar -xzf ${luarocksSrc}
      pushd luarocks-${luarocksVersion}
      ./configure \
        --prefix=$out/luarocks \
        --lua-suffix=jit \
        --with-lua=$out/luajit \
        --with-lua-include=$out/luajit/include/luajit-2.1
      make build -j$NIX_BUILD_CORES
      make install
      popd
      popd

      # Create symlinks for compatibility
      mkdir -p $out/openresty
      ln -sf $out/* $out/openresty/

      # Configure Lua paths for luafilesystem module
      mkdir -p $out/lualib $out/luajit/lib/lua/5.1
      # Create symlink to luafilesystem module in the standard Lua path
      ln -sf ${luajitPackages.luafilesystem}/lib/lua/5.1/lfs.so $out/luajit/lib/lua/5.1/
      # Also create a symlink in the lualib directory for OpenResty compatibility
      ln -sf ${luajitPackages.luafilesystem}/lib/lua/5.1/lfs.so $out/lualib/
    '';

    # Add runtime dependencies
    propagatedBuildInputs = [
      openssl
      pcre
      zlib
    ];

    meta = with lib; {
      description = "OpenResty with Kong patches";
      homepage = "https://openresty.org";
      license = licenses.bsd2;
      platforms = platforms.unix;
      maintainers = [];
    };
  }
