{
  description = "LFX RISC-V Mentorship development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        riscvPkgs = pkgs.pkgsCross.riscv64-embedded;
        riscvToolchainAlias = pkgs.runCommand "riscv64-unknown-elf-toolchain-alias" { } ''
          mkdir -p $out/bin

          for bin in ${riscvPkgs.buildPackages.gcc}/bin/riscv64-none-elf-*; do
            targetName=$(basename "$bin" | sed 's/riscv64-none-elf-/riscv64-unknown-elf-/')
            ln -s "$bin" "$out/bin/$targetName"
          done

          if [ -d "${riscvPkgs.buildPackages.gdb}/bin" ]; then
            for bin in ${riscvPkgs.buildPackages.gdb}/bin/riscv64-none-elf-*; do
              targetName=$(basename "$bin" | sed 's/riscv64-none-elf-/riscv64-unknown-elf-/')
              ln -s "$bin" "$out/bin/$targetName"
            done
          fi
        '';

        boost_spike = pkgs.runCommand "boost-for-spike" { } ''
          mkdir -p "$out/stage"
          ln -s "${pkgs.boost188.dev}/include/boost" "$out/boost"
          ln -s "${pkgs.boost188}/lib" "$out/stage/lib"
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          name = "lfx-dev-env";

          packages = with pkgs; [
            # Host build environment
            gcc
            gnumake
            git
            pkg-config
            python3

            # Device tree
            dtc

            # Documentation
            texliveBasic

            # Waveform
            verilator
            gtkwave
            surfer
            zlib
            lz4

            # Simulator build dependencies
            flex
            bison

            # Native RISC-V Toolchain binaries
            riscvPkgs.buildPackages.gcc
            riscvPkgs.buildPackages.gdb
            riscvToolchainAlias

            # Custom Derivation
            boost_spike
          ];

          shellHook = ''
            export CC=gcc
            export CXX=g++

            export BOOST_ROOT="${boost_spike}"
            export BOOST_CPPFLAGS="-I$BOOST_ROOT"
            export BOOST_LDFLAGS="-L$BOOST_ROOT/stage/lib"

            export CROSS_COMPILE=riscv64-unknown-elf-
          '';
        };
      }
    );
}
