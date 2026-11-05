{ config, lib, ... }:

# DMS and niri config, kept in ~/dotfiles and synced by Syncthing rather than
# declared here: the DMS settings UI has to be able to write it, and DMS adds
# files too often to link them one by one. See "Dotfiles sync" in CLAUDE.md.
let
  dotfiles = "${config.home.homeDirectory}/dotfiles";

  # force replaces the plain symlink left by the first-time move, or any other
  # symlink. A real directory makes `ln -Tsf` fail, so activation stops there
  # rather than deleting it.
  link = name: {
    source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${name}";
    force = true;
  };
in
{
  xdg.configFile.dms = link "dms";
  xdg.configFile.niri = link "niri";

  # Without these the links would dangle: DMS could then write its defaults into
  # ~/dotfiles and Syncthing would send them over the good settings elsewhere.
  # outputs.kdl is ignored by Syncthing, so each machine has to provide its own.
  home.activation.checkDotfiles = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    for file in dms/settings.json niri/dms/outputs.kdl; do
      if [[ ! -e "${dotfiles}/$file" ]]; then
        errorEcho "${dotfiles}/$file is missing. Finish the first sync before linking."
        exit 1
      fi
    done
  '';
}
