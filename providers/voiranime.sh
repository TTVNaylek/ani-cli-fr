#!/bin/sh

VA_BASE="https://voir-anime.to"

# Page de recherche (stdin) -> une ligne "titre<TAB>url" par resultat.
voiranime_parse_search() {
    grep -o '<h3 class="h4"><a href="[^"]*">[^<]*</a>' \
        | sed 's#<h3 class="h4"><a href="\([^"]*\)">\([^<]*\)</a>#\2	\1#' \
        | sed "s/&#0\{0,1\}39;/'/g; s/&#8217;/'/g; s/&quot;/\"/g; s/&amp;/\&/g"
}

# Liste les lecteurs (iframes) d'une page episode. $1 = url de l'episode.
voiranime_sources() {
    http_get "$1" | sed 's#\\/#/#g' | grep -oE '<iframe src=\\?"https?://[^"\\]+' | sed 's/.*"//' | awk '!seen[$0]++'
}

# Liste les episodes d'un anime du premier au dernier. $1 = url de l'anime.
voiranime_episode_urls() {
    # Le site affiche les episodes du plus recent au plus ancien : on inverse.
    http_get "$1" | grep -A2 "wp-manga-chapter" | grep -o 'href="[^"]*"' | sed 's/href="//; s/"$//' \
        | awk '!seen[$0]++ { a[++n] = $0 } END { for (i = n; i > 0; i--) print a[i] }'
}

voiranime_play_loop() {
    ep_urls="$1"
    ep_count="$2"
    ep_num="$3"
    id_prefix="$4"
    selected="$5"
    while true; do
        ep_url=$(echo "$ep_urls" | sed -n "${ep_num}p")
        echo "Lecture de l'episode $ep_num..."

        play_sources "$(voiranime_sources "$ep_url")" "$selected - Episode $ep_num"
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

# $1 = slug, $2 = titre
voiranime_pick_episode() {
    ep_urls=$(voiranime_episode_urls "$VA_BASE/anime/$1/")
    if [ -z "$ep_urls" ]; then echo "Aucun episode trouve sur voir-anime." ; return 1 ; fi
    ep_count=$(echo "$ep_urls" | wc -l | tr -d ' ')

    id_prefix="voiranime|$1"
    ep_selected=$(build_episode_list "$ep_count" "$id_prefix" | fzf_select_ansi "Selectionnez un episode : ")
    if [ -z "$ep_selected" ]; then return 2 ; fi
    ep_num=$(extract_ep_num "$ep_selected")

    voiranime_play_loop "$ep_urls" "$ep_count" "$ep_num" "$id_prefix" "$2"
}

search_voiranime() {
    title="$1"
    lang="$2"
    # Une ligne "titre<TAB>url" par resultat, sur 5 pages maximum
    results=""
    page=1
    while [ "$page" -le 5 ]; do
        page_results=$(curl -sL --connect-timeout 10 -m 30 -A "$UA" -G --data-urlencode "s=$title" \
            -d post_type=wp-manga -d paged="$page" "$VA_BASE/" | voiranime_parse_search)
        [ -z "$page_results" ] && break
        results="$results
$page_results"
        page=$((page + 1))
    done
    results=$(echo "$results" | sed '/^$/d' | awk '!seen[$0]++')
    if [ "$lang" = "vf" ]; then
        results=$(echo "$results" | grep "(VF)")
    else
        results=$(echo "$results" | grep -v "(VF)")
    fi
    if [ -z "$results" ]; then echo "Aucun resultat sur voir-anime." ; return 1 ; fi
    selected=$(echo "$results" | cut -f1 | fzf_select "Selectionnez un anime : ")
    if [ -z "$selected" ]; then return 2 ; fi
    anime_url=$(echo "$results" | awk -F'\t' -v s="$selected" '$1 == s { print $2; exit }')
    anime_slug=$(echo "$anime_url" | sed 's#/*$##; s#.*/##')

    voiranime_pick_episode "$anime_slug" "$selected"
}

resume_voiranime() {
    # $1 = ligne historique : voiranime|slug|ep|titre
    slug=$(echo "$1" | cut -d'|' -f2)
    selected=$(echo "$1" | cut -d'|' -f4)
    voiranime_pick_episode "$slug" "$selected"
}
