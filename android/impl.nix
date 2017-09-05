env: with env;
{
  buildApp = args: with args; nixpkgs.androidenv.buildGradleApp {
    acceptAndroidSdkLicenses = true;
    buildDirectory = "./.";
    # Can be "assembleRelease" or "assembleDebug" (to build release or debug) or "assemble" (to build both)
    gradleTask = "assembleDebug";
    keyAlias = null;
    keyAliasPassword = null;
    keyStore = null;
    keyStorePassword = null;
    mavenDeps = import ./defaults/deps.nix;
    name = applicationId;
    platformVersions = [ "25" ];
    release = false;
    src =
      let inherit (nixpkgs.lib) splitString escapeShellArg mapAttrs attrNames concatStrings optionalString;
          splitApplicationId = splitString "." applicationId;
          appSOs = mapAttrs (abiVersion: { myNixpkgs, myHaskellPackages }: {
            inherit (myNixpkgs) libiconv;
            hsApp = package myHaskellPackages;
          }) {
            "arm64-v8a" = {
              myNixpkgs = nixpkgsCross.android.arm64Impure;
              myHaskellPackages = ghcAndroidArm64;
            };
            "armeabi-v7a" = {
              myNixpkgs = nixpkgsCross.android.armv7aImpure;
              myHaskellPackages = ghcAndroidArmv7a;
            };
          };
          abiVersions = attrNames appSOs;
      in nixpkgs.runCommand "android-app" {
        buildGradle = builtins.toFile "build.gradle" (import ./build.gradle.nix {
          inherit applicationId version additionalDependencies releaseKey;
          googleServicesClasspath = optionalString (googleServicesJson != null)
            "classpath 'com.google.gms:google-services:3.0.0'";
          googleServicesPlugin = optionalString (googleServicesJson != null)
            "apply plugin: 'com.google.gms.google-services'";
        });
        androidManifestXml = builtins.toFile "AndroidManifest.xml" (import ./AndroidManifest.xml.nix {
          inherit applicationId version iconPath intentFilters services permissions;
        });
        stringsXml = builtins.toFile "strings.xml" (import ./strings.xml.nix {
          inherit displayName;
        });
        applicationMk = builtins.toFile "Application.mk" (import ./Application.mk.nix {
          inherit nixpkgs abiVersions;
        });
        src = ./src;
        nativeBuildInputs = [ nixpkgs.rsync ];
        unpackPhase = "";
      } (''
          set -x

          cp -r --no-preserve=mode "$src" "$out"
          ln -s "$buildGradle" "$out/build.gradle"
          ln -s "$androidManifestXml" "$out/AndroidManifest.xml"
          mkdir -p "$out/res/values"
          ln -s "$stringsXml" "$out/res/values/strings.xml"
          mkdir -p "$out/jni"
          ln -s "$applicationMk" "$out/jni/Application.mk"

        '' + concatStrings (builtins.map (arch:
          let inherit (appSOs.${arch}) libiconv hsApp;
          in ''
            {
              ARCH_LIB=$out/lib/${arch}
              mkdir -p $ARCH_LIB

              # Move libiconv (per arch) to the correct place
              cp --no-preserve=mode "${libiconv}/lib/libiconv.so" "$ARCH_LIB"
              cp --no-preserve=mode "${libiconv}/lib/libcharset.so" "$ARCH_LIB"

              cp --no-preserve=mode "${hsApp}/bin/lib${executableName}.so" "$ARCH_LIB/libHaskellActivity.so"
            }
        '') abiVersions) + ''
          rsync -r --chmod=+w "${resources}"/ "$out/res/"
          [ -d "$out/assets" ]
          [ -d "$out/res" ]
        '');
    useExtraSupportLibs = true; #TODO: Should this be enabled by default?
    useGoogleAPIs = true; #TODO: Should this be enabled by default?

    # We use the NDK build process
    useNDK = true;
  };

  intentFilterXml = args: with args; ''
    <intent-filter android:autoVerify="true">
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data android:scheme="${scheme}"
            android:host="${host}"
            ${ optionalString (port != null) ''android:port="${toString port}"'' }
            android:pathPrefix="${pathPrefix}" />
    </intent-filter>
  '';
}