# Nix Build for Kong Build Tools OpenResty

This provides a Nix-based alternative to the bash script `build-kong-openresty.sh` for building OpenResty with Kong patches.

## Features

- **Reproducible builds**: Same result every time, no matter the system state
- **Automatic dependency management**: Nix handles all build dependencies  
- **Kong patches applied**: All patches from `openresty-patches/` are automatically applied
- **Kong nginx module**: Includes lua-kong-nginx-module v0.5.0 (required for TLS cert support)
- **Apple Silicon compatible**: Includes M1/M2 compatibility patches
- **Custom OpenSSL**: Builds OpenSSL 1.1.1w with Kong-specific configuration
- **No sudo required**: Everything builds in user space

## Build Configuration

Matches your original script exactly:
- **OpenResty**: 1.21.4.1
- **OpenSSL**: 1.1.1w  
- **PCRE**: 8.45
- **LuaRocks**: 3.9.1
- **Kong Nginx Module**: 0.5.0
- **No resty-lmdb**: Excluded (as per `--no-resty-lmdb`)

## Usage

### With Nix Flakes (Recommended)

```bash
# Build OpenResty
nix build .#openresty

# Build and link to specific directory
nix build .#openresty --out-link /path/to/your/openresty

# One-time build and run
nix run .#openresty -- -v
```

### Without Flakes

```bash  
# Build using default.nix
nix-build -A openresty

# Build with specific nixpkgs
nix-build --arg pkgs 'import <nixpkgs> {}'
```

### Using in Other Projects

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kong-build-tools.url = "github:your-repo/kong-build-tools";
  };

  outputs = { nixpkgs, kong-build-tools, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages.x86_64-linux.my-app = pkgs.stdenv.mkDerivation {
        name = "my-app";
        buildInputs = [ kong-build-tools.packages.x86_64-linux.openresty ];
      };
    };
}
```

## Output Structure

The build produces the same directory structure as the original script:

```
/nix/store/xxx-openresty-kong-1.21.4.1/
├── bin/           # OpenResty binaries  
├── luajit/        # LuaJIT installation
├── lualib/        # Lua libraries including Kong modules
├── nginx/         # Nginx with Kong patches
│   ├── conf/
│   ├── html/  
│   └── sbin/nginx
├── openssl/       # Custom OpenSSL build
└── site/          # Site packages directory
```

## Environment Variables

Set `OPENRESTY_INSTALL_PREFIX` to match the original script usage:

```bash
export OPENRESTY_INSTALL_PREFIX=$(nix build .#openresty --print-out-paths)
```

## Development

```bash  
# Enter development shell with all build tools
nix develop

# Check the build configuration
nix flake check --show-trace

# Build with more verbose output  
nix build .#openresty --show-trace -L
```

## Advantages over Bash Script

1. **Reproducible**: Same hash = identical build
2. **Cached**: Nix automatically caches successful builds  
3. **Parallel**: Builds dependencies in parallel when possible
4. **Isolated**: No system pollution or conflicts
5. **Declarative**: Configuration is code, not imperative steps
6. **Cross-platform**: Works on Linux, macOS, and NixOS

## Migration from Bash Script

Replace your bash script usage:

```bash
# OLD:
OPENRESTY_INSTALL_PREFIX=/openresty ./build-kong-openresty.sh

# NEW:  
nix build .#openresty --out-link /openresty
```

The result is functionally identical but with better reproducibility and dependency management.