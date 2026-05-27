# Build Flutter web app
FROM debian:stable-slim AS flutter-build

RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION=3.24.0
RUN git clone https://github.com/flutter/flutter.git /flutter --depth 1 --branch ${FLUTTER_VERSION}
ENV PATH="/flutter/bin:/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN flutter doctor -v
RUN flutter config --enable-web

WORKDIR /app

COPY src/packages/flutter-app/pubspec.yaml src/packages/flutter-app/pubspec.lock ./
RUN flutter pub get

COPY src/packages/flutter-app/lib/ lib/
COPY src/packages/flutter-app/web/ web/
COPY src/packages/flutter-app/analysis_options.yaml ./

RUN mkdir -p web/icons
RUN dart run build_runner build --delete-conflicting-outputs

RUN flutter build web --release \
    --web-renderer canvaskit \
    --base-href /app/ \
    --dart-define=API_BASE_URL=/api/v1

# Serve static files and proxy API via nginx
FROM nginx:alpine

COPY dockerize/deployment/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=flutter-build /app/build/web /usr/share/nginx/html/app

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
