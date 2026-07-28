#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}

cache_directories=(
    "$project_directory/build/DerivedData"
    "/private/tmp/FileMailerModuleCache"
    "/private/tmp/FileMailerXcodeModuleCache"
)

size_before_kb=0
for cache_directory in "${cache_directories[@]}"; do
    if [[ -d "$cache_directory" ]]; then
        cache_size_kb=$(du -sk "$cache_directory" | awk '{print $1}')
        (( size_before_kb += cache_size_kb ))
    fi
done

for cache_directory in "${cache_directories[@]}"; do
    if [[ -d "$cache_directory" ]]; then
        find "$cache_directory" -type f -delete
        find "$cache_directory" -type l -delete
    fi
done

freed_megabytes=$(( size_before_kb / 1024 ))
echo "Caches FileMailer vidés: environ ${freed_megabytes} Mo libérés."
echo "Les sources, les dossiers et les dépendances téléchargées sont conservés."
