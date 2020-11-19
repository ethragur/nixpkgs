{ lib
, buildPackages, pkgs, targetPackages
, pkgsBuildBuild, pkgsBuildHost, pkgsBuildTarget, pkgsHostHost, pkgsTargetTarget
, stdenv, splicePackages, newScope
, preLibcCrossHeaders
}:

let
  otherSplices = {
    selfBuildBuild = pkgsBuildBuild.darwin;
    selfBuildHost = pkgsBuildHost.darwin;
    selfBuildTarget = pkgsBuildTarget.darwin;
    selfHostHost = pkgsHostHost.darwin;
    selfTargetTarget = pkgsTargetTarget.darwin or {}; # might be missing
  };

  # Prefix for binaries. Customarily ends with a dash separator.
  #
  # TODO(@Ericson2314) Make unconditional, or optional but always true by
  # default.
  targetPrefix = lib.optionalString (stdenv.targetPlatform != stdenv.hostPlatform)
                                        (stdenv.targetPlatform.config + "-");
in

lib.makeScopeWithSplicing splicePackages newScope otherSplices (_: {}) (spliced: spliced.apple_sdk.frameworks) (self: let
  inherit (self) mkDerivation callPackage;

  # Must use pkgs.callPackage to avoid infinite recursion.

  # Open source packages that are built from source
  appleSourcePackages = pkgs.callPackage ../os-specific/darwin/apple-source-releases { } self;

  impure-cmds = pkgs.callPackage ../os-specific/darwin/impure-cmds { };

  # macOS 10.12 SDK
  apple_sdk_10_12 = pkgs.callPackage ../os-specific/darwin/apple-sdk {
    inherit (buildPackages.darwin) print-reexports;
    inherit (self) darwin-stubs;
  };

  # macOS 11.0 SDK
  apple_sdk_11_0 = pkgs.callPackage ../os-specific/darwin/apple-sdk-11.0 { };

  # Pick an SDK
  apple_sdk = if stdenv.hostPlatform.isAarch64 then apple_sdk_11_0 else apple_sdk_10_12;

  # Pick the source of libraries: either Apple's open source releases, or the
  # SDK.
  useAppleSDKLibs = stdenv.hostPlatform.isAarch64;

  chooseLibs = {
    inherit (
      if useAppleSDKLibs
        then apple_sdk
        else appleSourcePackages
    ) Libsystem LibsystemCross libcharset libunwind objc4 configd IOKit;

    inherit (
      if useAppleSDKLibs
        then apple_sdk.frameworks
        else appleSourcePackages
    ) Security;
  };
in

impure-cmds // appleSourcePackages // chooseLibs // {

  inherit apple_sdk;

  stdenvNoCF = stdenv.override {
    extraBuildInputs = [];
  };

  binutils-unwrapped = callPackage ../os-specific/darwin/binutils {
    inherit (pkgs) binutils-unwrapped;
    inherit (pkgs.llvmPackages) llvm clang-unwrapped;
  };

  binutils = pkgs.wrapBintoolsWith {
    libc =
      if stdenv.targetPlatform != stdenv.hostPlatform
      then pkgs.libcCross
      else pkgs.stdenv.cc.libc;
    bintools = self.binutils-unwrapped;
  };

  binutilsNoLibc = pkgs.wrapBintoolsWith {
    libc = preLibcCrossHeaders;
    bintools = self.binutils-unwrapped;
  };

  cctools = callPackage ../os-specific/darwin/cctools/port.nix {
    stdenv = if stdenv.isDarwin then stdenv else pkgs.libcxxStdenv;
  };

  # TODO: remove alias.
  cf-private = self.apple_sdk.frameworks.CoreFoundation;

  DarwinTools = callPackage ../os-specific/darwin/DarwinTools { };

  darwin-stubs = callPackage ../os-specific/darwin/darwin-stubs { };

  print-reexports = callPackage ../os-specific/darwin/print-reexports { };

  rewrite-tbd = callPackage ../os-specific/darwin/rewrite-tbd { };

  checkReexportsHook = pkgs.makeSetupHook {
    deps = [ pkgs.darwin.print-reexports ];
  } ../os-specific/darwin/print-reexports/setup-hook.sh;

  sigtool = callPackage ../os-specific/darwin/sigtool { };

  postLinkSignHook = pkgs.writeTextFile {
    name = "post-link-sign-hook";
    executable = true;

    text = ''
      CODESIGN_ALLOCATE=${targetPrefix}codesign_allocate \
        ${self.sigtool}/bin/codesign -f -s - "$linkerOutput"
    '';
  };

  maloader = callPackage ../os-specific/darwin/maloader {
  };

  insert_dylib = callPackage ../os-specific/darwin/insert_dylib { };

  iosSdkPkgs = callPackage ../os-specific/darwin/xcode/sdk-pkgs.nix {
    buildIosSdk = buildPackages.darwin.iosSdkPkgs.sdk;
    targetIosSdkPkgs = targetPackages.darwin.iosSdkPkgs;
    inherit (pkgs.llvmPackages) clang-unwrapped;
  };

  iproute2mac = callPackage ../os-specific/darwin/iproute2mac { };

  libobjc = self.objc4;

  lsusb = callPackage ../os-specific/darwin/lsusb { };

  opencflite = callPackage ../os-specific/darwin/opencflite { };

  stubs = pkgs.callPackages ../os-specific/darwin/stubs { };

  trash = callPackage ../os-specific/darwin/trash { };

  usr-include = callPackage ../os-specific/darwin/usr-include { };

  inherit (pkgs.callPackages ../os-specific/darwin/xcode { })
    xcode_8_1 xcode_8_2
    xcode_9_1 xcode_9_2 xcode_9_4 xcode_9_4_1
    xcode_10_2 xcode_10_2_1 xcode_10_3
    xcode_11
    xcode;

  CoreSymbolication = callPackage ../os-specific/darwin/CoreSymbolication { };

  # TODO: make swift-corefoundation build with apple_sdk_11_0.Libsystem
  CF = if useAppleSDKLibs
    then apple_sdk.frameworks.CoreFoundation
    else callPackage ../os-specific/darwin/swift-corelibs/corefoundation.nix { };

  # As the name says, this is broken, but I don't want to lose it since it's a direction we want to go in
  # libdispatch-broken = callPackage ../os-specific/darwin/swift-corelibs/libdispatch.nix { };

  darling = callPackage ../os-specific/darwin/darling/default.nix { };

  libtapi = callPackage ../os-specific/darwin/libtapi {};

  ios-deploy = callPackage ../os-specific/darwin/ios-deploy {};

  discrete-scroll = callPackage ../os-specific/darwin/discrete-scroll { };

})
