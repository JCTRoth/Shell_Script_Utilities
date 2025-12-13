#!/bin/bash
# Dangling images are untagged Docker images
docker image prune -a && docker container prune -f
echo "All dangling images and stopped containers have been removed."