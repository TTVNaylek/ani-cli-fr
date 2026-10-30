#!/bin/sh

UA="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"

# Telecharge une page. $1 = url, $2 = referer optionnel.
http_get() {
    if [ -n "$2" ]; then
        curl -sL --connect-timeout 10 -m 30 -A "$UA" -e "$2" "$1"
    else
        curl -sL --connect-timeout 10 -m 30 -A "$UA" "$1"
    fi
}

fzf_select() {
    fzf --reverse --prompt="$1" --height=40% --border
}

# Decode le javascript "packed" (eval(function(p,a,c,k,e,d)...)) lu sur stdin.
# Utilise par uqload, ansembed/voembed, smoothpre et la plupart des lecteurs actuels.
unpack_packer() {
    awk -v q="'" '
    function enc(n, base,    s) {
        s = ""
        do { s = substr(digits, n % base + 1, 1) s; n = int(n / base) } while (n > 0)
        return s
    }
    BEGIN { digits = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" }
    { doc = doc $0 "\n" }
    END {
        start = index(doc, "}(" q)
        if (start == 0) exit
        rest = substr(doc, start + 3)
        if (!match(rest, q ",[0-9]+,[0-9]+," q)) exit
        payload = substr(rest, 1, RSTART - 1)
        split(substr(rest, RSTART + 2, RLENGTH - 4), num, ",")
        keys = substr(rest, RSTART + RLENGTH)
        keys = substr(keys, 1, index(keys, q) - 1)
        n = split(keys, k, "|")
        for (i = 0; i < num[2]; i++) {
            e = enc(i, num[1])
            w[e] = (i < n && k[i + 1] != "") ? k[i + 1] : e
        }
        out = ""
        while (match(payload, /[0-9A-Za-z_]+/)) {
            tok = substr(payload, RSTART, RLENGTH)
            out = out substr(payload, 1, RSTART - 1) ((tok in w) ? w[tok] : tok)
            payload = substr(payload, RSTART + RLENGTH)
        }
        out = out payload
        gsub(/\\\047/, q, out)
        print out
    }'
}

# Premiere URL de flux (m3u8 ou mp4) trouvee sur stdin.
extract_media_url() {
    grep -oE "https?://[^\"' <>\\\\]+\.(m3u8|mp4)[^\"' <>\\\\]*" | head -1
}

# Streamtape : l'URL reelle est reconstruite en javascript a partir de morceaux.
resolve_streamtape() {
    line=$(http_get "$1" | grep "robotlink').innerHTML" | head -1)
    [ -z "$line" ] && return 1
    prefix=$(echo "$line" | sed "s/.*innerHTML = '\([^']*\)'.*/\1/")
    chunk=$(echo "$line" | sed "s/.*+ ('\([^']*\)').*/\1/")
    skip=$(echo "$line" | grep -o 'substring([0-9]*)' | tr -dc '0-9\n' | awk '{ s += $1 } END { print s + 0 }')
    echo "https:${prefix}$(echo "$chunk" | cut -c$((skip + 1))-)&stream=1"
}

# Transforme une URL embed en URL de flux lisible par mpv.
resolve_stream() {
    case "$1" in
        *streamtape.*)
            resolve_streamtape "$1"
            return ;;
        *sibnet.ru*|*mail.ru*|*sendvid.com*)
            yt-dlp -g --referer "$1" "$1" 2>/dev/null | head -1
            return ;;
    esac
    page=$(http_get "$1")
    stream=$(printf '%s\n' "$page" | extract_media_url)
    if [ -z "$stream" ]; then
        stream=$(printf '%s\n' "$page" | unpack_packer | extract_media_url)
    fi
    if [ -z "$stream" ]; then
        stream=$(yt-dlp -g "$1" 2>/dev/null | head -1)
    fi
    echo "$stream"
}

# Trie les lecteurs du plus fiable au moins fiable (lus sur stdin, un par ligne).
rank_sources() {
    awk 'NF && !seen[$0]++ {
        r = 4
        if ($0 ~ /ansembed|voembed|vidmoly/) r = 1
        else if ($0 ~ /uqload/) r = 2
        else if ($0 ~ /streamtape/) r = 3
        else if ($0 ~ /sibnet|mail\.ru|sendvid/) r = 5
        print r "\t" NR "\t" $0
    }' | sort -n -k1,1 -k2,2 | cut -f3-
}

# Essaie chaque lecteur jusqu'a ce qu'un fonctionne. $1 = urls embed, $2 = titre.
play_sources() {
    sources=$(printf '%s\n' "$1" | rank_sources)
    i=0
    while [ -n "$sources" ]; do
        src=$(printf '%s\n' "$sources" | head -1)
        sources=$(printf '%s\n' "$sources" | sed '1d')
        i=$((i + 1))
        host=$(echo "$src" | awk -F/ '{ print $3 }')
        echo "Lecteur $i ($host) en cours..."
        stream=$(resolve_stream "$src")
        if [ -n "$stream" ]; then
            mpv --force-media-title="$2" --referrer="$src" --user-agent="$UA" "$stream"
            # 0 = fin normale, 3 = lecture partielle, 4 = quitte par l'utilisateur
            case "$?" in 0|3|4) return 0 ;; esac
        fi
        echo "Echec lecteur $i."
    done
    echo "Aucun lecteur disponible pour cet episode."
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