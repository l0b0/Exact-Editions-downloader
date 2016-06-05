#!/usr/bin/env bash

set -o errexit -o noclobber -o nounset -o pipefail

usage() {
    cat >&2 <<EOF
Usage: $0 MAGAZINE_NUMBER EMAIL PASSWORD
Example: $0 1234 me@example.org my_password
EOF
    exit 2
}

if [ $# -ne 3 ]
then
    usage
fi
magazine="$1"
username="$2"
password="$3"

base_directory="$magazine"

cookie_file="cookies.txt"
issues_file="issues.html"

init_all() {
    mkdir --parents "$base_directory"
    cd "$base_directory"
}

log_in() {
    trap 'rm --force "$cookie_file"' EXIT
    wget --keep-session-cookies --output-document=/dev/null --post-data="username=${username}&password=${password}" --save-cookies="${cookie_file}" 'https://login.exacteditions.com/login'
}

get_issue_index() {
    wget --load-cookies="${cookie_file}" --max-redirect=0 --output-document="${issues_file}" "https://reader.exacteditions.com/magazines/${magazine}/issues"
}

get_issue_publication_date() {
    grep --only-matching --perl-regexp '(?<=data-publication-date=")[^"]+' <<< "$1"
}

get_issue_name() {
    grep --only-matching --perl-regexp '(?<=data-name=")[^"]+' <<< "$1" | sed 's#\( \)\?/#,#g'
}

get_issue_pdf_path() {
    printf '%s %s.pdf' "$(get_issue_publication_date "$1")" "$(get_issue_name "$1")"
}

get_issue_path() {
    grep --only-matching --perl-regexp '(?<=href="/)issues/[^/"]+' <<< "$1"
}

join_pdf_files() {
    pdfunite $(find "$1" -mindepth 1 | sort --field-separator=/ --key=4 --numeric-sort) "$2"
}

clean_issue() {
    rm --force --recursive "$1"
}

download_issues() {
    while IFS= read -r -u 3 line
    do
        issue_pdf_path="$(get_issue_pdf_path "$line")"

        # Skip if already done
        if [ -e "${issue_pdf_path}" ]
        then
            continue
        fi

        issue_path="$(get_issue_path "$line")"
        spread_directory="${issue_path}/spread"
        mkdir --parents "${spread_directory}"

        # Get issue thumbnails
        thumbs_file="${issue_path}/thumbs.html"
        wget --load-cookies="${cookie_file}" --max-redirect=0 --output-document="${thumbs_file}" "https://reader.exacteditions.com/${issue_path}/thumbs"

        while read -r -u 4 spread_path
        do
            # Get spreads
            spread_pdf_path="${spread_path}.pdf"
            local_spread_pdf_path="${spread_pdf_path}"
            if [ ! -e "${local_spread_pdf_path}" ]
            then
                wget --load-cookies="${cookie_file}" --max-redirect=0 --output-document="${local_spread_pdf_path}" "https://reader.exacteditions.com/${spread_pdf_path}"
                sleep 10
            fi
        done 4< <(grep --only-matching --perl-regexp '(?<=href="/)issues/[^/"]+/spread/[^/"]+' "${thumbs_file}")

        join_pdf_files "${spread_directory}" "${issue_pdf_path}"

        clean_issue "${issue_path}"
    done 3< <(grep 'href="/issues/[^/"]\+' "${issues_file}")
}

clean_all() {
    rmdir issues
    rm --force "${issues_file}"
}

init_all
log_in
get_issue_index
download_issues
clean_all
