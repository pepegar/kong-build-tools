{
  description = "Kong Build Tools - OpenResty with Kong patches";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            # Allow insecure OpenSSL 1.1.1w as required by Kong
            permittedInsecurePackages = [ "openssl-1.1.1w" ];
          };
        };
        openresty = pkgs.callPackage ./openresty.nix { 
          # Use OpenSSL 1.1.1 instead of the default OpenSSL 3.x
          openssl = pkgs.openssl_1_1;
        };
      in
      {
        packages = {
          openresty = openresty;
          default = openresty;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            curl
            git
            gcc
            gnumake
            perl
            zlib
            pkg-config
          ];
        };
      });
}