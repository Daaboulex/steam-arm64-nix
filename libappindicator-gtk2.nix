{
  lib,
  libappindicator,
  libdbusmenu-gtk2,
  gtk2,
}:
(libappindicator.override {
  gtk3 = gtk2;
  libdbusmenu-gtk3 = libdbusmenu-gtk2;
}).overrideAttrs
  (old: {
    pname = "libappindicator-gtk2";
    configureFlags = map (f: if f == "--with-gtk=3" then "--with-gtk=2" else f) old.configureFlags;
    meta = old.meta // {
      description = "The GTK 2 build of libappindicator, the only tray Valve's aarch64 client knows how to use";
      pkgConfigModules = lib.remove "appindicator3-0.1" (old.meta.pkgConfigModules or [ ]);
    };
  })
