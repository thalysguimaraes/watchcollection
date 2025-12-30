#!/bin/bash
# FlareSolverr setup for Chrono24 Cloudflare bypass
# Run this before crawling to bypass Cloudflare protection

CONTAINER_NAME="flaresolverr"
PORT=8191

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "FlareSolverr already running on port $PORT"
        exit 0
    else
        echo "Starting existing FlareSolverr container..."
        docker start $CONTAINER_NAME
    fi
else
    echo "Creating and starting FlareSolverr container..."
    docker run -d \
        --name $CONTAINER_NAME \
        -p $PORT:8191 \
        -e LOG_LEVEL=info \
        --restart unless-stopped \
        ghcr.io/flaresolverr/flaresolverr:latest
fi

echo "Waiting for FlareSolverr to be ready..."
sleep 5

if curl -s http://localhost:$PORT/ > /dev/null 2>&1; then
    echo "FlareSolverr is ready at http://localhost:$PORT"
else
    echo "FlareSolverr may still be starting. Check: docker logs $CONTAINER_NAME"
fi
