# Flutter Web — Docker

Docker setup for the Flutter web app has moved to the repository root:

**[dockerize/README.md](../../../dockerize/README.md)**

- **Development** (`make docker-dev`) — Flutter dev server with hot reload behind nginx on port 3000
- **Deployment** (`make docker-deploy`) — static build served by nginx on port 3000

The Flutter package no longer contains its own Dockerfile.
