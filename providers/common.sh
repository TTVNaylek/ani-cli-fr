#!/bin/sh

encode_title() {
    echo "$1" | tr ' ' '+'
}

fzf_select() {
    fzf --reverse --prompt="$1" --height=40% --border
}

# Lecteur vidmoly : extrait le m3u8 depuis une URL embed et lance mpv.
play_vidmoly() {
    embed_url=$(echo "$1" | sed 's/vidmoly\.to/vidmoly.biz/g')
    stream_url=$(curl -sL "$embed_url" | grep -o "https://prx[^']*master\.m3u8[^']*" | head -1)
    if [ -n "$stream_url" ]; then
        mpv "$stream_url"
        return 0
    fi
    return 1
}

# Lecteur generique via yt-dlp. $1 = url embed, $2 = referer optionnel.
play_ytdlp() {
    stream_url=$(yt-dlp -g "$1" 2>/dev/null | head -1)
    if [ -n "$stream_url" ]; then
        if [ -n "$2" ]; then
            mpv --http-header-fields="Referer: $2" "$stream_url"
        else
            mpv "$stream_url"
        fi
        return 0
    fi
    return 1
}

# Menu apres lecture. $1 = episode courant, $2 = nombre total d'episodes.
post_play_menu() {
    current="$1"
    total="$2"
    options=""
    if [ "$current" -lt "$total" ]; then
        options="Episode suivant"
    fi
    if [ "$current" -gt 1 ]; then
        options="$options
Episode precedent"
    fi
    options="$options
Rejouer
Retour au menu
Quitter"
    choice=$(echo "$options" | sed '/^$/d' | fzf_select "Que faire ? ")
    case "$choice" in
        "Episode suivant") echo "suivant" ;;
        "Episode precedent") echo "precedent" ;;
        "Rejouer") echo "rejouer" ;;
        "Retour au menu") echo "retour" ;;
        "Quitter") echo "quitter" ;;
        *) echo "quitter" ;;
    esac
}

HISTORY_DIR="$HOME/.local/state/ani-cli-fr"
HISTORY_FILE="$HISTORY_DIR/history"

# Marque un episode comme vu.
# $1 = identifiant unique (ex: animesama|one-piece|saison1/vostfr|5)
# $2 = titre lisible (ex: One Piece)
mark_as_watched() {
    mkdir -p "$HISTORY_DIR"
    if ! grep -qxF "$1|$2" "$HISTORY_FILE" 2>/dev/null; then
        echo "$1|$2" >> "$HISTORY_FILE"
    fi
}

# Verifie si un episode est vu. $1 = identifiant (sans le titre).
is_watched() {
    # On cherche une ligne qui COMMENCE par l'identifiant suivi de |
    grep -qF "$1|" "$HISTORY_FILE" 2>/dev/null
}

# Genere une liste d'episodes numerotee avec marquage "Vu".
# $1 = nombre d'episodes, $2 = prefixe identifiant (ex: "animesama|one-piece|saison1")
build_episode_list() {
    count="$1"
    id_prefix="$2"
    i=1
    while [ "$i" -le "$count" ]; do
        if is_watched "${id_prefix}|${i}"; then
            # Gris + mention Vu (codes ANSI)
            printf '\033[90mEpisode %s ✓ Vu\033[0m\n' "$i"
        else
            printf 'Episode %s\n' "$i"
        fi
        i=$((i + 1))
    done
}

# Selection fzf avec support des couleurs ANSI.
fzf_select_ansi() {
    fzf --ansi --reverse --prompt="$1" --height=40% --border
}

# Retourne la ligne d'historique choisie, ou vide si annule/aucun historique.
resume_menu() {
    [ ! -f "$HISTORY_FILE" ] && return 1

    entries=$(awk -F'|' '
    {
        prov = $1
        if (prov == "animesama") {
            # provider|slug|contexte|ep|titre  (5 champs)
            key = $1 "|" $2 "|" $3
            ep = $4
            titre = $5
        } else {
            # provider|slug|ep|titre  (4 champs)
            key = $1 "|" $2
            ep = $3
            titre = $4
        }
        if (ep+0 > max[key]+0) {
            max[key] = ep
            title[key] = titre
            provd[key] = prov
            line[key] = $0
        }
    }
    END {
        for (k in max) {
            print title[k] " - Episode " max[k] " (" provd[k] ")\t" line[k]
        }
    }' "$HISTORY_FILE")

    [ -z "$entries" ] && return 1

    chosen=$(echo "$entries" | cut -f1 | fzf_select "Reprendre : ")
    [ -z "$chosen" ] && return 1

    echo "$entries" | awk -F'\t' -v sel="$chosen" '$1 == sel {print $2}'
}

# Met a jour ani-cli-fr si installe via git, sinon redirige vers le gestionnaire.
update_ani_cli_fr() {
    script_dir="$1"
    if [ -d "$script_dir/.git" ]; then
        echo "Recherche de mises a jour..."
        if command -v git >/dev/null 2>&1; then
            cd "$script_dir" || return 1
            git pull
        else
            echo "git n'est pas installe."
            return 1
        fi
    else
        echo "ani-cli-fr a ete installe via un gestionnaire de paquets."
        echo "Utilisez votre gestionnaire pour le mettre a jour :"
        echo "  Arch (AUR)  : yay -Syu ani-cli-fr"
        echo "  Homebrew    : brew upgrade ani-cli-fr"
    fi
}

# Portable GNU sed (Linux) et BSD sed (macOS).
extract_ep_num() {
    esc=$(printf '\033')
    echo "$1" | sed "s/${esc}\[[0-9]*m//g" | awk '{print $2}'
}

clear_history(){
    clear_menu="Oui
Non"
    clear_choice=$(echo "$clear_menu" | fzf_select "Etes-vous sur de vider votre historique ? : ")

    case "$clear_choice" in
        "Oui")
            rm -f "$HISTORY_FILE"
            echo "Historique nettoye."
            ;;
        "Non" | *)
            echo "Annulation de la suppression de l'historique."
            ;;
    esac
}

handle_play_result(){
    lect_result="$1"
    id_prefix="$2"
    ep_num="$3"
    selected="$4"

    if [ "$lect_result" -eq 0 ]; then
        mark_as_watched "${id_prefix}|${ep_num}" "$selected"
        return 0
    else
        echo "Aucun lecteur disponible."
        return 1
    fi
}