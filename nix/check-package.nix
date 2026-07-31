{ runCommand, zedha }:
runCommand "zedha-package-identity" { } ''
  test -x ${zedha}/bin/zedha
  test -x ${zedha}/libexec/zedha-editor
  test ! -e ${zedha}/bin/zed
  test ! -e ${zedha}/bin/zeditor
  test ! -e ${zedha}/libexec/zed-editor
  desktop=${zedha}/share/applications/me.ghostwriternr.Zedha.desktop
  grep -Fxq 'Name=Zedha' "$desktop"
  grep -Fxq 'TryExec=zedha' "$desktop"
  grep -Fxq 'Exec=zedha %U' "$desktop"
  grep -Fxq 'Icon=zedha' "$desktop"
  grep -Fq 'x-scheme-handler/zedha;' "$desktop"
  ! grep -Fq 'x-scheme-handler/zed;' "$desktop"
  test -f ${zedha}/share/icons/hicolor/512x512/apps/zedha.png
  test -f ${zedha}/share/icons/hicolor/1024x1024@2x/apps/zedha.png
  touch $out
''
