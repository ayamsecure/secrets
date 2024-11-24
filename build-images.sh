#!/bin/bash

# Set environment variables
export AYAM_VW_VERSION=1.32.5
export AYAM_WEB_VAULT_VERSION=2024.6.2
export AYAM_SECRETS_TAG="$AYAM_VW_VERSION-$AYAM_WEB_VAULT_VERSION"

# Create a new builder instance if not already created
BUILDER_NAME="secrets-builder"
if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
  echo "Creating Docker buildx builder: $BUILDER_NAME"
  docker buildx create --name "$BUILDER_NAME" --use || { echo "Failed to create builder"; exit 1; }
else
  echo "Using existing Docker buildx builder: $BUILDER_NAME"
  docker buildx use "$BUILDER_NAME" || { echo "Failed to use builder"; exit 1; }
fi

# Array of architectures to build
ARCHS=("arm64" "amd64")

# Loop through each architecture and build
for arch in "${ARCHS[@]}"; do
  if [ "$arch" == "arm64" ]; then
    target_arch="arm"
  else
    target_arch="amd"
  fi

  echo "Starting build for architecture: $arch"
  if docker buildx build --platform "linux/$arch" -f ./docker/Dockerfile.ayam \
    --build-arg VW_VERSION="$AYAM_VW_VERSION" \
    --build-arg DB=postgresql,enable_mimalloc \
    --build-arg TARGETARCH="$target_arch" \
    --build-arg TARGETVARIANT=64 \
    -t "jayknyn/ayam-secure-secrets:$AYAM_SECRETS_TAG-$arch" . --push; then
    echo "Successfully built and pushed $arch image."
  else
    echo "Failed to build $arch image."
    exit 1
  fi
done

echo "All builds completed successfully and images have been pushed up."

# Create a multi-architecture image manifest
# echo "Creating multi-architecture image manifest"
# docker manifest create "jayknyn/ayam-secure-secrets:$AYAM_SECRETS_TAG" \
#     "jayknyn/ayam-secure-secrets:$AYAM_SECRETS_TAG-amd64" \
#     "jayknyn/ayam-secure-secrets:$AYAM_SECRETS_TAG-arm64"

# docker manifest push "jayknyn/ayam-secure-secrets:$AYAM_SECRETS_TAG"

# echo "All builds and manifest creation completed successfully."

# docker manifest create "jayknyn/ayam-secure-secrets:1.31.1-2024.5.1" \
#     "jayknyn/ayam-secure-secrets:1.31.1-2024.5.1-amd64" \
#     "jayknyn/ayam-secure-secrets:1.31.1-2024.5.1-arm64"