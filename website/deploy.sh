#!/bin/zsh
# Publishes the site to the server: zsh website/deploy.sh
set -e
cd "$(dirname "$0")"
rsync -az --delete --exclude server --exclude deploy.sh ./ root@120.26.52.95:/var/www/waytrace/
echo "Published to /var/www/waytrace"
