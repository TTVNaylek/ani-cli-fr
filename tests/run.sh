#!/bin/sh
# Tests d'ani-cli-fr.
#   sh tests/run.sh           tests hors ligne (fixtures)
#   sh tests/run.sh --online  + tests contre les vrais sites

root="$(cd "$(dirname "$0")/.." && pwd)"
fix="$root/tests/fixtures"
. "$root/providers/common.sh"
. "$root/providers/animesama.sh"
. "$root/providers/voiranime.sh"

pass=0
fail=0
TAB=$(printf '\t')

# $1 = nom du test, $2 = attendu, $3 = obtenu
check() {
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
        echo "ok   $1"
    else
        fail=$((fail + 1))
        echo "FAIL $1"
        echo "     attendu : $2"
        echo "     obtenu  : $3"
    fi
}

echo "== Tests hors ligne"

# check_dependencies : PATH factice sans fzf, puis avec tous les stubs
stubs=$(mktemp -d)
for c in curl mpv yt-dlp; do printf '#!/bin/sh\n' > "$stubs/$c"; chmod +x "$stubs/$c"; done
out=$(PATH="$stubs" check_dependencies 2>&1); rc=$?
check "check_dependencies retourne 1 sans fzf" "1" "$rc"
case "$out" in *fzf*) r=ok ;; *) r=ko ;; esac
check "check_dependencies mentionne fzf" "ok" "$r"
printf '#!/bin/sh\n' > "$stubs/fzf"; chmod +x "$stubs/fzf"
PATH="$stubs" check_dependencies >/dev/null 2>&1; rc=$?
check "check_dependencies retourne 0 si tout est present" "0" "$rc"
rm -rf "$stubs"

check "unpack_packer decode le javascript packed" \
    "jwplayer('vplayer').setup({sources:[{file:\"https://cdn.example/hls2/master.m3u8?t=abc_DEF\"}],title:'x'});" \
    "$(unpack_packer < "$fix/packed.html")"

check "extract_media_url trouve le m3u8 apres decodage" \
    "https://cdn.example/hls2/master.m3u8?t=abc_DEF" \
    "$(unpack_packer < "$fix/packed.html" | extract_media_url)"

check "unpack_packer ne sort rien sans javascript packed" \
    "" "$(echo '<html>rien</html>' | unpack_packer)"

check "rank_sources trie et dedoublonne les lecteurs" \
    "https://ansembed.net/b
https://uqload.vc/a
https://streamtape.com/e/c
https://inconnu.com/e/d
https://video.sibnet.ru/e" \
    "$(printf '%s\n' https://video.sibnet.ru/e https://uqload.vc/a https://inconnu.com/e/d https://ansembed.net/b https://streamtape.com/e/c https://uqload.vc/a | rank_sources)"

# Les appels reseau sont remplaces par les fixtures.
http_get() {
    case "$1" in
        *streamtape*) cat "$fix/streamtape.html" ;;
        *vide/episodes.js) cat "$fix/episodes_vide.js" ;;
        *episodes.js) cat "$fix/episodes.js" ;;
        *anime-sama*/vide/) cat "$fix/animesama_empty.html" ;;
        *anime-sama*) cat "$fix/animesama_anime.html" ;;
        *voir-anime*/doublons/) cat "$fix/voiranime_anime_doublons.html" ;;
        *voir-anime*/sans-lecteur/) cat "$fix/voiranime_episode_sans_lecteur.html" ;;
        *voir-anime*/test/) cat "$fix/voiranime_anime.html" ;;
        *voir-anime*) cat "$fix/voiranime_episode.html" ;;
    esac
}

check "streamtape : reconstruit la vraie URL (pas le leurre)" \
    "https://streamtape.com/get_video?id=ABCD123&expires=1&ip=X&token=vrai&stream=1" \
    "$(resolve_stream "https://streamtape.com/e/abc")"

check "anime-sama : resultats de recherche (nom nettoye, entites decodees)" \
    "Naruto${TAB}/catalogue/naruto/
JoJo's Bizarre Adventure${TAB}/catalogue/jojo-s-bizarre-adventure/" \
    "$(animesama_parse_search < "$fix/animesama_search.html")"

check "anime-sama : saisons sans les exemples commentes" \
    "Saison 1${TAB}saison1/vostfr
Film${TAB}film/vostfr" \
    "$(animesama_parse_saisons < "$fix/animesama_anime.html")"

eps=$(animesama_episodes "https://anime-sama.to/catalogue/x/saison1/vostfr/")
check "anime-sama : episodes.js (plusieurs tableaux, ligne commentee ignoree)" \
    "1${TAB}https://uqload.vc/embed-aaa1.html
2${TAB}https://uqload.vc/embed-aaa2.html
3${TAB}https://uqload.vc/embed-aaa3.html
1${TAB}https://ansembed.net/embed-bbb1.html
2${TAB}https://ansembed.net/embed-bbb2.html" "$eps"

check "voir-anime : resultats de recherche" \
    "Frieren (VF)${TAB}https://voir-anime.to/anime/frieren-vf/" \
    "$(echo '<h3 class="h4"><a href="https://voir-anime.to/anime/frieren-vf/">Frieren (VF)</a></h3>' | voiranime_parse_search)"

check "voir-anime : episodes remis dans l'ordre 1, 2, 3" \
    "https://voir-anime.to/anime/test/test-01-vostfr/
https://voir-anime.to/anime/test/test-02-vostfr/
https://voir-anime.to/anime/test/test-03-vostfr/" \
    "$(voiranime_episode_urls "https://voir-anime.to/anime/test/")"

check "voir-anime : lecteurs extraits du JSON echappe, sans doublon" \
    "https://voembed.net/embed-xyz.html
https://streamtape.com/e/abc" \
    "$(voiranime_sources "https://voir-anime.to/anime/test/test-01-vostfr/")"

# Cas limites des parseurs (fixtures inventees, sans reseau)
check "rank_sources : entree vide ou lignes vides -> rien" \
    "" "$(printf '\n\n' | rank_sources)"

check "rank_sources : ordre ansembed/voembed/vidmoly < uqload < streamtape < inconnu < sibnet/mail.ru/sendvid" \
    "https://vidmoly.to/a
https://uqload.vc/b
https://streamtape.com/e/c
https://autre.org/d
https://sendvid.com/f
https://my.mail.ru/e" \
    "$(printf '%s\n' https://sendvid.com/f https://my.mail.ru/e https://autre.org/d https://streamtape.com/e/c https://uqload.vc/b https://vidmoly.to/a | rank_sources)"

check "rank_sources : l'ordre d'arrivee departage les lecteurs de meme rang" \
    "https://voembed.net/2
https://ansembed.net/1" \
    "$(printf '%s\n' https://voembed.net/2 https://ansembed.net/1 | rank_sources)"

check "anime-sama : recherche, entites &amp; &#39; &quot; decodees (doublons conserves)" \
    "Tom & Jerry${TAB}/catalogue/tom-et-jerry/
L'Attaque \"finale\"${TAB}/catalogue/l-attaque/
Tom & Jerry${TAB}/catalogue/tom-et-jerry/" \
    "$(animesama_parse_search < "$fix/animesama_search_edge.html")"

check "anime-sama : recherche sans resultat -> rien" \
    "" "$(animesama_parse_search < "$fix/animesama_empty.html")"

check "anime-sama : saisons, uniquement des exemples commentes -> rien" \
    "" "$(animesama_parse_saisons < "$fix/animesama_empty.html")"

check "anime-sama : episodes.js sans aucun lecteur actif -> rien" \
    "" "$(animesama_episodes "https://anime-sama.to/catalogue/x/vide/")"

check "voir-anime : recherche, entites &amp; &#039; &#8217; decodees, ordre conserve" \
    "Tom & Jerry${TAB}https://voir-anime.to/anime/tom-jerry/
L'Attaque (VF)${TAB}https://voir-anime.to/anime/l-attaque-vf/
D'Art${TAB}https://voir-anime.to/anime/d-art/" \
    "$(voiranime_parse_search < "$fix/voiranime_search.html")"

check "voir-anime : recherche sans resultat -> rien" \
    "" "$(echo '<html><body>Aucun resultat</body></html>' | voiranime_parse_search)"

check "voir-anime : episodes, doublons d'URL supprimes puis ordre inverse" \
    "https://voir-anime.to/anime/test/test-01-vostfr/
https://voir-anime.to/anime/test/test-02-vostfr/" \
    "$(voiranime_episode_urls "https://voir-anime.to/anime/doublons/")"

check "voir-anime : episode sans lecteur -> rien" \
    "" "$(voiranime_sources "https://voir-anime.to/anime/sans-lecteur/")"

# Historique dans un dossier temporaire
HISTORY_DIR=$(mktemp -d)
HISTORY_FILE="$HISTORY_DIR/history"
mark_as_watched "animesama|naruto|saison1/vostfr|1" "Naruto"
mark_as_watched "animesama|naruto|saison1/vostfr|1" "Naruto"
check "historique : pas de doublon" "1" "$(wc -l < "$HISTORY_FILE" | tr -d ' ')"
check "historique : episode 1 vu, episode 11 non" "vu-pasvu" \
    "$(is_watched "animesama|naruto|saison1/vostfr|1" && echo vu)-$(is_watched "animesama|naruto|saison1/vostfr|11" || echo pasvu)"
check "historique : numero extrait de la ligne coloree" "1" \
    "$(build_episode_list 2 "animesama|naruto|saison1/vostfr" | head -1 | while read -r l; do extract_ep_num "$l"; done)"
rm -rf "$HISTORY_DIR"

if [ "$1" = "--online" ]; then
    # Recharge les vraies fonctions reseau
    . "$root/providers/common.sh"
    echo "== Tests en ligne"

    # $1 = nom, $2 = url m3u8/mp4 -> verifie que le flux repond
    check_stream() {
        if [ -n "$2" ] && curl -sL -m 20 -A "$UA" -r 0-2000 "$2" | grep -q "#EXTM3U\|ftyp"; then
            check "$1" "flux ok" "flux ok"
        else
            check "$1" "flux ok" "pas de flux (${2:-url vide})"
        fi
    }

    res=$(curl -sL -m 30 -A "$UA" -G --data-urlencode "search=frieren" "$AS_BASE/catalogue/" | animesama_parse_search)
    check "anime-sama : la recherche repond" "oui" "$(echo "$res" | grep -q "frieren" && echo oui)"
    eps=$(animesama_episodes "$AS_BASE/catalogue/frieren/saison1/vostfr/")
    check "anime-sama : episodes.js accessible" "oui" "$(echo "$eps" | grep -q "^1$TAB" && echo oui)"

    for host in ansembed uqload; do
        src=$(echo "$eps" | grep "^1$TAB.*$host" | cut -f2 | head -1)
        if [ -n "$src" ]; then
            check_stream "lecteur $host" "$(resolve_stream "$src")"
        else
            echo "skip lecteur $host (absent de l'episode 1)"
        fi
    done

    va=$(curl -sL -m 30 -A "$UA" -G --data-urlencode "s=frieren" -d post_type=wp-manga "$VA_BASE/" | voiranime_parse_search)
    if [ -z "$va" ]; then
        echo "skip voir-anime : site injoignable (DNS bloque ?)"
    else
        check "voir-anime : la recherche repond" "oui" "$(echo "$va" | grep -q "Frieren" && echo oui)"
        # Les videos sont parfois supprimees : on essaie les 3 premiers episodes.
        srcs=""
        for ep in $(voiranime_episode_urls "$VA_BASE/anime/sousou-no-frieren/" | head -3); do
            srcs="$srcs
$(voiranime_sources "$ep")"
        done
        for host in voembed streamtape; do
            stream=""
            for src in $(echo "$srcs" | grep "$host"); do
                stream=$(resolve_stream "$src")
                [ -n "$stream" ] && break
            done
            if echo "$srcs" | grep -q "$host"; then
                check_stream "lecteur $host (voir-anime)" "$stream"
            else
                echo "skip lecteur $host (absent des episodes 1 a 3)"
            fi
        done
    fi
fi

echo "== $pass ok, $fail echec(s)"
[ "$fail" -eq 0 ]
