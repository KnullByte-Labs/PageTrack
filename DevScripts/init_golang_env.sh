#! /bin/bash

docker run -d \
    --name pagetrack-backend-dev \
    golang:alpine tail -f /dev/null