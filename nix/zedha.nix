{ lib, stable, zedPackage }:
let
  replaceRequired = from: to: text:
    assert lib.assertMsg (lib.hasInfix from text)
      "official Zed Nix hook no longer contains ${from}";
    builtins.replaceStrings [ from ] [ to ] text;
in
zedPackage.overrideAttrs (old: rec {
  pname = "zedha";
  version = "${lib.removePrefix "v" stable.tag}-zedha";
  __intentionallyOverridingVersion = true;
  env = old.env // {
    RELEASE_VERSION = version;
    ZED_COMMIT_SHA = stable.commit;
  };
  patches = (old.patches or [ ]) ++ [
    ../patches/0001-terminal-launcher.patch
    ../patches/0002-brand-as-zedha.patch
    ../patches/0003-brand-linux-as-zedha.patch
  ];
  preBuild = replaceRequired "echo nightly" "echo stable" old.preBuild;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec
    cp $TARGET_DIR/zedha $out/libexec/zedha-editor
    cp $TARGET_DIR/cli $out/bin/zedha
    install -D crates/zed/resources/app-icon@2x.png $out/share/icons/hicolor/1024x1024@2x/apps/zedha.png
    install -D crates/zed/resources/app-icon.png $out/share/icons/hicolor/512x512/apps/zedha.png
    (
      export DO_STARTUP_NOTIFY=true APP_CLI=zedha APP_ICON=zedha APP_NAME=Zedha APP_ARGS=%U
      mkdir -p $out/share/applications
      envsubst < crates/zed/resources/zed.desktop.in > $out/share/applications/me.ghostwriternr.Zedha.desktop
      chmod +x $out/share/applications/me.ghostwriternr.Zedha.desktop
    )
    runHook postInstall
  '';
  postFixup = replaceRequired "zed-editor" "zedha-editor" old.postFixup;
  meta = old.meta // {
    description = "Zedha downstream distribution of Zed";
    mainProgram = "zedha";
  };
})
