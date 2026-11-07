{ config, pkgs, ... }:

# raiser on PATH, from its clone at ~/dev/raiser, which each host importing this
# needs, with `uv sync` run in it.
#
# Its libvirt bindings only ship as an sdist that has to compile against libvirt,
# so raiser makes them an optional extra and they come from nixpkgs here instead.
# The venv has to use Python 3.14 to load this compiled module.
let
  home = config.home.homeDirectory;
  libvirt = pkgs.python314Packages.libvirt;
in
{
  home.sessionVariables.PYTHONPATH = "${libvirt}/${pkgs.python314.sitePackages}";

  home.sessionPath = [ "${home}/.local/bin" ];
  home.file.".local/bin/raiser".source =
    config.lib.file.mkOutOfStoreSymlink "${home}/dev/raiser/.venv/bin/raiser";
}
