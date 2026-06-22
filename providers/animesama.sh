play_animesama_episode() {
    vidmoly_url="$1"
    sibnet_url="$2"
    if [ -n "$vidmoly_url" ]; then
        echo "Lecteur 1 en cours..."
        if play_vidmoly "$vidmoly_url"; then return 0 ; fi
        echo "Echec lecteur 1."
    fi
    if [ -n "$sibnet_url" ]; then
        echo "Lecteur 2 en cours..."
        if play_ytdlp "$sibnet_url" "https://video.sibnet.ru/"; then return 0 ; fi
        echo "Echec lecteur 2."
    fi
    echo "Aucun lecteur disponible pour cet episode."
    return 1
}

animesama_play_loop() {
    vidmoly_list="$1"
    sibnet_list="$2"
    ep_count="$3"
    ep_num="$4"
    id_prefix="$5"
    selected="$6"
    while true; do
        vidmoly_url=$(echo "$vidmoly_list" | sed -n "${ep_num}p")
        sibnet_url=$(echo "$sibnet_list" | sed -n "${ep_num}p")
        echo "Lecture de l'episode $ep_num..."
        #play_animesama_episode "$vidmoly_url" "$sibnet_url"
        #mark_as_watched "${id_prefix}|${ep_num}" "$selected"

        if play_animesama_episode "$vidmoly_url" "$sibnet_url"; then
            mark_as_watched "${id_prefix}|${ep_num}" "$selected"
        fi

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

search_animesama() {
    title="$1"
    lang="$2"
    html=$(curl -s "https://anime-sama.to/catalogue/?search=$(encode_title "$title")")
    results=$(echo "$html" | grep "card-title" | sed 's/<h2 class="card-title">//g' | sed 's/<\/h2>//g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [ -z "$results" ]; then echo "Aucun resultat sur anime-sama." ; return 1 ; fi
    selected=$(echo "$results" | fzf_select "Selectionnez un anime : ")
    if [ -z "$selected" ]; then return 2 ; fi
    search_urls=$(echo "$html" | grep "catalogue/" | sed 's/<a href="//g' | sed 's/">//g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    anime_slug=$(echo "$selected" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    anime_url=$(echo "$search_urls" | grep "/${anime_slug}[/\"]")
    anime_html=$(curl -s "$anime_url")
    saisons_noms=$(echo "$anime_html" | grep "panneauAnime" | grep -v "fonction\|nom\|url" | sed 's/panneauAnime("//g' | sed 's/", ".*$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    saisons_slug=$(echo "$anime_html" | grep "panneauAnime" | grep -v "fonction\|nom\|url" | sed 's/.*", "//g' | sed 's/".*$//g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    saisons_selected=$(echo "$saisons_noms" | fzf_select "Selectionnez une saison : ")
    if [ -z "$saisons_selected" ]; then return 2 ; fi
    saison_line=$(echo "$saisons_noms" | grep -n "^${saisons_selected}$" | cut -d ':' -f1)
    saison_url=$(echo "$saisons_slug" | sed -n "${saison_line}p" | sed "s/vostfr/$lang/g")
    episodes_js=$(curl -sL "$anime_url$saison_url/episodes.js")
    vidmoly_list=$(echo "$episodes_js" | grep -o "https://vidmoly[^']*")
    sibnet_list=$(echo "$episodes_js" | grep -o "https://video\.sibnet\.ru[^']*")
    ep_count=$(echo "$vidmoly_list" | grep -c "vidmoly")
    if [ "$ep_count" -eq 0 ]; then ep_count=$(echo "$sibnet_list" | grep -c "sibnet") ; fi
    if [ "$ep_count" -eq 0 ]; then echo "Aucun episode trouve sur anime-sama." ; return 1 ; fi

    # Identifiant unique pour l'historique
    id_prefix="animesama|${anime_slug}|${saison_url}"

    ep_selected=$(build_episode_list "$ep_count" "$id_prefix" | fzf_select_ansi "Selectionnez un episode : ")
    if [ -z "$ep_selected" ]; then return 2 ; fi
    ep_num=$(extract_ep_num "$ep_selected")

    animesama_play_loop "$vidmoly_list" "$sibnet_list" "$ep_count" "$ep_num" "$id_prefix" "$selected"
}

resume_animesama() {
    # $1 = ligne historique : animesama|slug|saison_url|ep|titre
    slug=$(echo "$1" | cut -d'|' -f2)
    saison_url=$(echo "$1" | cut -d'|' -f3)
    selected=$(echo "$1" | cut -d'|' -f5)
    anime_url="https://anime-sama.to/catalogue/$slug/"
    episodes_js=$(curl -sL "${anime_url}${saison_url}/episodes.js")
    vidmoly_list=$(echo "$episodes_js" | grep -o "https://vidmoly[^']*")
    sibnet_list=$(echo "$episodes_js" | grep -o "https://video\.sibnet\.ru[^']*")
    ep_count=$(echo "$vidmoly_list" | grep -c "vidmoly")
    if [ "$ep_count" -eq 0 ]; then ep_count=$(echo "$sibnet_list" | grep -c "sibnet") ; fi
    if [ "$ep_count" -eq 0 ]; then echo "Impossible de reprendre (episodes introuvables)." ; return 1 ; fi

    id_prefix="animesama|${slug}|${saison_url}"
    ep_selected=$(build_episode_list "$ep_count" "$id_prefix" | fzf_select_ansi "Selectionnez un episode : ")
    if [ -z "$ep_selected" ]; then return 2 ; fi
    ep_num=$(extract_ep_num "$ep_selected")

    animesama_play_loop "$vidmoly_list" "$sibnet_list" "$ep_count" "$ep_num" "$id_prefix" "$selected"
}