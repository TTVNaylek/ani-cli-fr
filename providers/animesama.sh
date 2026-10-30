#!/bin/sh

AS_BASE="https://anime-sama.to"

# Liste les lecteurs d'une saison. $1 = url de la saison (avec / final).
# Sortie : une ligne "numero_episode<TAB>url_embed" par lecteur.
animesama_episodes() {
    # Sans Referer, Cloudflare bloque episodes.js.
    http_get "${1}episodes.js" "$1" | awk -v q="'" '
        /var eps[0-9]+/ { n = 0 }
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (substr(line, 1, 2) == "//") next
            while (match(line, q "https?://[^" q "]+" q)) {
                n++
                print n "\t" substr(line, RSTART + 1, RLENGTH - 2)
                line = substr(line, RSTART + RLENGTH)
            }
        }'
}

# Page de recherche (stdin) -> une ligne "nom<TAB>/catalogue/slug/" par resultat.
animesama_parse_search() {
    grep -o 'data-url="[^"]*" data-cat="[^"]*" data-nom="[^"]*"' | awk -F'"' '{
        nom = $6
        gsub(/^ +| +$/, "", nom)
        gsub(/&#0?39;/, "\047", nom); gsub(/&quot;/, "\"", nom); gsub(/&amp;/, "\\&", nom)
        print nom "\t" $2
    }'
}

# Page d'un anime (stdin) -> une ligne "nom<TAB>chemin" par saison,
# sans les exemples commentes du site.
animesama_parse_saisons() {
    grep -o 'panneauAnime("[^"]*", *"[^"]*")' | grep -v -e '("nom"' -e '"url")' | awk -F'"' '{ print $2 "\t" $4 }'
}

animesama_play_loop() {
    eps_table="$1"
    ep_count="$2"
    ep_num="$3"
    id_prefix="$4"
    selected="$5"
    while true; do
        sources=$(echo "$eps_table" | awk -F'\t' -v n="$ep_num" '$1 == n { print $2 }')
        echo "Lecture de l'episode $ep_num..."

        play_sources "$sources" "$selected - Episode $ep_num"
        handle_play_result "$?" "$id_prefix" "$ep_num" "$selected"
        if [ "$?" -eq 1 ]; then return 1; fi

        action=$(post_play_menu "$ep_num" "$ep_count")
        case "$action" in
            suivant) ep_num=$((ep_num + 1)) ;;
            precedent) ep_num=$((ep_num - 1)) ;;
            rejouer) ;;
            retour) return 0 ;;
            quitter) exit 0 ;;
        esac
    done
}

# $1 = slug, $2 = chemin saison (ex: saison1/vostfr), $3 = titre
animesama_pick_episode() {
    eps_table=$(animesama_episodes "$AS_BASE/catalogue/$1/$2/")
    ep_count=$(echo "$eps_table" | awk -F'\t' '$1 > m { m = $1 } END { print m + 0 }')
    if [ "$ep_count" -eq 0 ]; then echo "Aucun episode trouve sur anime-sama ($2)." ; return 1 ; fi

    id_prefix="animesama|$1|$2"
    ep_selected=$(build_episode_list "$ep_count" "$id_prefix" | fzf_select_ansi "Selectionnez un episode : ")
    if [ -z "$ep_selected" ]; then return 2 ; fi
    ep_num=$(extract_ep_num "$ep_selected")

    animesama_play_loop "$eps_table" "$ep_count" "$ep_num" "$id_prefix" "$3"
}

search_animesama() {
    title="$1"
    lang="$2"
    results=$(curl -sL --connect-timeout 10 -m 30 -A "$UA" -G --data-urlencode "search=$title" "$AS_BASE/catalogue/" | animesama_parse_search)
    if [ -z "$results" ]; then echo "Aucun resultat sur anime-sama." ; return 1 ; fi
    selected=$(echo "$results" | cut -f1 | fzf_select "Selectionnez un anime : ")
    if [ -z "$selected" ]; then return 2 ; fi
    anime_path=$(echo "$results" | awk -F'\t' -v s="$selected" '$1 == s { print $2; exit }')
    anime_slug=$(echo "$anime_path" | sed 's#/*$##; s#.*/##')

    saisons=$(http_get "$AS_BASE/catalogue/$anime_slug/" | animesama_parse_saisons)
    if [ -z "$saisons" ]; then echo "Aucune saison trouvee sur anime-sama." ; return 1 ; fi
    saison_nom=$(echo "$saisons" | cut -f1 | fzf_select "Selectionnez une saison : ")
    if [ -z "$saison_nom" ]; then return 2 ; fi
    saison_path=$(echo "$saisons" | awk -F'\t' -v s="$saison_nom" '$1 == s { print $2; exit }' | sed "s#vostfr#$lang#")

    animesama_pick_episode "$anime_slug" "$saison_path" "$selected"
}

resume_animesama() {
    # $1 = ligne historique : animesama|slug|saison_path|ep|titre
    slug=$(echo "$1" | cut -d'|' -f2)
    saison_path=$(echo "$1" | cut -d'|' -f3)
    selected=$(echo "$1" | cut -d'|' -f5)
    animesama_pick_episode "$slug" "$saison_path" "$selected"
}
