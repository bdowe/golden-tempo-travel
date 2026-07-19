# Build stage — pinned to the build host's platform so multi-arch builds
# cross-compile (fast) instead of running the Go toolchain under QEMU.
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS builder

# Set working directory
WORKDIR /app

# Install git (needed for go mod download)
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application for the image's target platform (amd64/arm64)
ARG TARGETOS TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -a -installsuffix cgo -o main .

# Final stage
FROM alpine:latest

# Release identifier for Sentry (main.go reads SENTRY_RELEASE). CI passes the
# git SHA via --build-arg; local builds leave it empty (Sentry omits release).
ARG SENTRY_RELEASE=
ENV SENTRY_RELEASE=${SENTRY_RELEASE}

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates

# Create a non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /root/

# Copy the binary from builder stage
COPY --from=builder /app/main .

# Change ownership to non-root user
RUN chown -R appuser:appgroup /root/

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the application
CMD ["./main"]
