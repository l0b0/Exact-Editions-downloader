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
mkdir --parents "$base_directory"
cd "$base_directory"

# Log in
trap 'rm --force "$cookie_file"' EXIT
cookie_file="cookies.txt"
wget --keep-session-cookies --output-document=/dev/null --post-data="username=${username}&password=${password}" --save-cookies="${cookie_file}" 'https://login.exacteditions.com/login'

# Get issues
issues_file="issues.html"
wget --load-cookies="${cookie_file}" --max-redirect=0 --output-document="${issues_file}" "https://reader.exacteditions.com/magazines/${magazine}/issues"

for issue_path in $(grep --only-matching --perl-regexp '(?<=href="/)issues/[^/"]+' "${issues_file}")
do
    spread_directory="${issue_path}/spread"
    mkdir --parents "${spread_directory}"

    # Get issue thumbnails
    thumbs_file="${issue_path}/thumbs.html"
    wget --load-cookies="${cookie_file}" --max-redirect=0 --output-document="${thumbs_file}" "https://reader.exacteditions.com/${issue_path}/thumbs"

    for spread_path in $(grep --only-matching --perl-regexp '(?<=href="/)issues/[^/"]+/spread/[^/"]+' "${thumbs_file}")
    do
        # Get spreads
        spread_pdf_path="${spread_path}.pdf"
        local_spread_pdf_path="${spread_pdf_path}"
        if [ ! -e "${local_spread_pdf_path}" ]
        then
            wget --load-cookies="${cookie_file}" --max-redirect=0 --output-document="${local_spread_pdf_path}" "https://reader.exacteditions.com/${spread_pdf_path}"
            sleep 10
        fi
    done

    # Convert to single PDF file
    local_issue_pdf_path="${issue_path}/issue.pdf"
    if [ ! -e "${local_issue_pdf_path}" ]
    then
        pdfunite $(find "${spread_directory}" -mindepth 1 | sort --field-separator=/ --key=4 --numeric-sort) "${local_issue_pdf_path}"
    fi
done
