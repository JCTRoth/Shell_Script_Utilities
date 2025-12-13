#!/usr/bin/env bash
# Stop and remove all Docker containers safely
set -euo pipefail

# If there are no containers, `docker ps -aq` is empty — handle that
containers=$(docker ps -aq || true)
if [ -z "$containers" ]; then
	echo "No Docker containers found. Nothing to stop/remove."
	exit 0
fi

echo "Stopping containers: $containers"
docker stop $containers
echo "Removing containers: $containers"
docker rm $containers
echo "All Docker containers have been stopped and removed."