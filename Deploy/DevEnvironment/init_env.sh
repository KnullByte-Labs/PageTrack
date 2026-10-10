docker run -d \
  --name pagetrack-backend-dev \
  --network database_pagetrack \
  -u $(id -u):$(id -g) \
  -e HOME=/tmp \
  -p 8082:8080 \
  -v ../../Backend:/Backend \
  -w /Backend \
  golang:alpine tail -f /dev/null
