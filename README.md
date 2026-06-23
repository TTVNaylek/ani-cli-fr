# ani-cli-fr

Un outil en ligne de commande pour rechercher et regarder des animés en **VF** et **VOSTFR**, directement depuis le terminal. Inspiré de [ani-cli](https://github.com/pystardust/ani-cli), mais pensé pour les sources francophones.

## Fonctionnalités

- **Recherche multi-sources** : interroge `anime-sama` puis `voir-anime` en secours
- **Fallback automatique** : si une source ne trouve rien, l'autre prend le relais sans intervention
- **Cascade de lecteurs** : essaie plusieurs hébergeurs (vidmoly, sibnet, mail.ru, streamtape) jusqu'à en trouver un qui fonctionne
- **VF / VOSTFR** : choix de la langue via un simple flag
- **Historique de visionnage** : les épisodes déjà vus sont marqués `✓ Vu` en couleur
- **Reprise** : reprends un animé là où tu t'étais arrêté depuis le menu d'accueil
- **Menu post-lecture** : épisode suivant, précédent, rejouer, retour au menu, quitter
- **Session continue** : le programme reste ouvert pour enchaîner les recherches

## Dépendances

L'outil repose sur quatre utilitaires :

| Outil | Rôle |
|-------|------|
| `curl` | Récupération des pages web |
| `fzf` | Menus interactifs de sélection |
| `mpv` | Lecture vidéo |
| `yt-dlp` | Extraction des flux pour certains lecteurs |

### Installation des dépendances

**Arch Linux**
```sh
sudo pacman -S curl fzf mpv yt-dlp
```

**Debian / Ubuntu**
```sh
sudo apt install curl fzf mpv yt-dlp
```

**Fedora**
```sh
sudo dnf install curl fzf mpv yt-dlp
```

**macOS** (via [Homebrew](https://brew.sh/))
```sh
brew install curl fzf mpv yt-dlp
```

## Installation

```sh
git clone https://github.com/TTVNaylek/ani-cli-fr.git
cd ani-cli-fr
chmod +x ani-cli-fr
```

Pour pouvoir lancer la commande depuis n'importe où, tu peux créer un lien symbolique dans un dossier de ton `PATH` :

```sh
sudo ln -s "$(pwd)/ani-cli-fr" /usr/local/bin/ani-cli-fr
```

## Utilisation

**Recherche directe**
```sh
ani-cli-fr naruto
```

**En version française**
```sh
ani-cli-fr --vf one piece
```

**Mode interactif** (menu d'accueil avec recherche et reprise)
```sh
ani-cli-fr
```

**Aide**
```sh
ani-cli-fr --help
```

### Options

| Option | Description |
|--------|-------------|
| `--vf`, `-vf` | Recherche en version française |
| `--vostfr`, `-vostfr` | Recherche en VOSTFR (par défaut) |
| `--help`, `-h` | Affiche l'aide |

### Navigation

Les menus se naviguent avec `fzf` : flèches ou frappe au clavier pour filtrer, `Entrée` pour valider, `Échap` pour annuler.

## Compatibilité

| Système | Support |
|---------|---------|
| **Linux** (toutes distributions) | Natif |
| **macOS** | Via Homebrew |
| **Windows** | Via [WSL](https://learn.microsoft.com/windows/wsl/) uniquement |

> Sur Windows, l'intégration de `mpv` en ligne de commande native est limitée ; l'usage via WSL est recommandé.

## Avertissement légal

Ce projet est fourni **à des fins éducatives uniquement**. Il ne fait qu'indexer et lire des liens accessibles publiquement sur des sites tiers ; il n'héberge, ne stocke et ne distribue aucun contenu vidéo.

L'utilisateur est seul responsable de l'usage qu'il fait de cet outil et doit s'assurer de respecter les lois sur le droit d'auteur en vigueur dans son pays. Les auteurs déclinent toute responsabilité quant à un usage abusif ou illégal.

## Licence

Distribué sous licence [MIT](LICENSE).

---

Développé par [Naylek](https://github.com/TTVNaylek)
