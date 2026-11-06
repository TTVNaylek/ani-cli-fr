# Packaging

## AUR (`aur/`)

Deux paquets : `ani-cli-fr` (release taguée) et `ani-cli-fr-git` (dernier commit).

Mise à jour d'une release :

1. Modifier `pkgver` (et remettre `pkgrel=1`) dans `aur/ani-cli-fr/PKGBUILD`.
2. `updpkgsums` pour recalculer le sha256.
3. `makepkg --printsrcinfo > .SRCINFO`.
4. Tester avec `makepkg -si`.

Le paquet `-git` calcule sa version tout seul : seul `.SRCINFO` est à régénérer.

Publication : les inscriptions AUR sont fermées pour l'instant, la publication
se fera donc à la main une fois le compte disponible :

    git clone ssh://aur@aur.archlinux.org/ani-cli-fr.git
    # copier PKGBUILD et .SRCINFO, puis
    git add PKGBUILD .SRCINFO && git commit -m "Mise à jour 0.x.y" && git push

## Homebrew (`homebrew/`)

La formule va dans un tap `TTVNaylek/homebrew-tap` (dossier `Formula/`).
À chaque release : changer `url` et `sha256`
(`curl -sL <url> | shasum -a 256`), puis `brew audit --strict ani-cli-fr`
et `brew test ani-cli-fr`. Installation : `brew install TTVNaylek/tap/ani-cli-fr`.
