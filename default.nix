# For non-flake users
{ pkgs ? import <nixpkgs> {} }:

pkgs.callPackage ./openresty.nix { }