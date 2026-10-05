#! /bin/bash

docker run -d --name pagetrack-backend-dev --mount type=bind,source=../Backend,target=/root/Backend golang:alpine tail -f /dev/null