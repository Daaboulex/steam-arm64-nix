{
  lib,
  libdbusmenu,
  gtk2,
}:
(libdbusmenu.override {
  gtk3 = gtk2;
  withGtk3 = true;
}).overrideAttrs
  (old: {
    pname = "libdbusmenu-gtk2";
    configureFlags = map (f: if f == "--with-gtk=3" then "--with-gtk=2" else f) old.configureFlags;
    meta = old.meta // {
      description = "The GTK 2 build of libdbusmenu, which Valve's client needs through libappindicator";
      pkgConfigModules = lib.remove "dbusmenu-gtk3-0.4" (old.meta.pkgConfigModules or [ ]);
    };
  })
