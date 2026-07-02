#!/bin/sh

play_voiranime_episode() {
    page=$(curl -sL "$1")
    echo "Lecteur 1 en cours..."
    embed_url=$(echo "$page" | grep -o "https://vidmoly\.biz/embed-[^\\\"]*" | head -1)
    if [ -n "$embed_url" ] && play_vidmoly "$embed_url"; then return 0 ; fi
    echo "Echec lecteur 1."
    echo "Lecteur 2 en cours..."
    mailru_url=$(echo "$page" | grep -o "https:\\\\/\\\\/my\.mail\.ru\\\\/video\\\\/embed\\\\/[0-9]*" | head -1 | sed 's/\\\//\//g')
    if [ -n "$mailru_url" ] && play_ytdlp "$mailru_url"; then return 0 ; fi
    echo "Echec lecteur 2."
    echo "Lecteur 3 en cours..."
    stape_url=$(echo "$page" | grep -o "https:\\\\/\\\\/streamtape\.com\\\\/e\\\\/[^\\\\\"]*" | head -1 | sed 's/\\\//\//g')
    if [ -n "$stape_url" ] && play_ytdlp "$stape_url"; then return 0 ; fi
    echo "Echec lecteur 3."
    echo "Aucun lecteur disponible pour cet episode."
    return 1
}

voiranime_play_loop() {
    ep_urls="$1"
    ep_count="$2"
    ep_num="$3"
    id_prefix="$4"
    selected="$5"
    while true; do
        ep_url=$(echo "$ep_urls" | sed -n "${ep_num}p" | awk '{print $2}')
        echo "Lecture de l'episode $ep_num..."

        play_voiranime_episode "$ep_url"
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

search_voiranime() {
    title="$1"
    lang="$2"
    encoded_title=$(encode_title "$title")
    all_html=""
    page=1
    while [ $page -le 5 ]; do
        page_html=$(curl -s "https://voir-anime.to/?s=$encoded_title&post_type=wp-manga&paged=$page")
        page_results=$(echo "$page_html" | grep -o '<h3 class="h4"><a href="[^"]*">[^<]*</a>')
        [ -z "$page_results" ] && break
        all_html="$all_html$page_html"
        page=$((page + 1))
    done
    results=$(echo "$all_html" | grep -o '<h3 class="h4"><a href="[^"]*">[^<]*</a>' | sed 's/.*">//' | sed 's/<\/a>//')
    if [ "$lang" = "vf" ]; then
        results=$(echo "$results" | grep "(VF)")
    else
        results=$(echo "$results" | grep -v "(VF)")
    fi
    if [ -z "$results" ]; then echo "Aucun resultat sur voir-anime." ; return 1 ; fi
    selected=$(echo "$results" | fzf_select "Selectionnez un anime : ")
    if [ -z "$selected" ]; then return 2 ; fi
    anime_url=$(echo "$all_html" | grep -o '<h3 class="h4"><a href="[^"]*">[^<]*</a>' | grep -F "$selected</a>" | head -1 | grep -o 'href="[^"]*"' | sed 's/href="//' | sed 's/"//')
    anime_slug=$(echo "$anime_url" | sed 's#https://voir-anime.to/anime/##' | sed 's#/##g')
    anime_html=$(curl -s "$anime_url")
    ep_urls=$(echo "$anime_html" | grep -A2 "wp-manga-chapter" | grep -o 'href="[^"]*"' | sed 's/href="//' | sed 's/"//' | nl -ba)
    if [ -z "$ep_urls" ]; then echo "Aucun episode trouve sur voir-anime." ; return 1 ; fi
    ep_count=$(echo "$ep_urls" | wc -l)

    id_prefix="voiranime|${anime_slug}"

    ep_selected=$(build_episode_list "$ep_count" "$id_prefix" | fzf_select_ansi "Selectionnez un episode : ")
    if [ -z "$ep_selected" ]; then return 2 ; fi
    ep_num=$(extract_ep_num "$ep_selected")

    voiranime_play_loop "$ep_urls" "$ep_count" "$ep_num" "$id_prefix" "$selected"
}

resume_voiranime() {
    # $1 = ligne historique : voiranime|slug|ep|titre
    slug=$(echo "$1" | cut -d'|' -f2)
    selected=$(echo "$1" | cut -d'|' -f4)
    anime_url="https://voir-anime.to/anime/$slug/"
    anime_html=$(curl -s "$anime_url")
    ep_urls=$(echo "$anime_html" | grep -A2 "wp-manga-chapter" | grep -o 'href="[^"]*"' | sed 's/href="//' | sed 's/"//' | nl -ba)
    if [ -z "$ep_urls" ]; then echo "Impossible de reprendre (episodes introuvables)." ; return 1 ; fi
    ep_count=$(echo "$ep_urls" | wc -l)

    id_prefix="voiranime|${slug}"
    ep_selected=$(build_episode_list "$ep_count" "$id_prefix" | fzf_select_ansi "Selectionnez un episode : ")
    if [ -z "$ep_selected" ]; then return 2 ; fi
    ep_num=$(extract_ep_num "$ep_selected")

    voiranime_play_loop "$ep_urls" "$ep_count" "$ep_num" "$id_prefix" "$selected"
}