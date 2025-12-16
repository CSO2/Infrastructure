#!/usr/bin/env bash

# Build all service Dockerfiles, tag with each service's git SHA, 
# load into minikube, and update kustomize overlay for local dev.

set -euo pipefail

# Script is in Infrastructure/cso2/scripts, go up to parent of Infrastructure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
cd "$INFRA_ROOT"

OVERLAY_DIR="Infrastructure/cso2/k8s/overlays/dev"

# Keep track of images we build
declare -A IMAGE_TAGS

# Find all service directories (same level as Infrastructure)
for service_dir in */; do
    # Skip Infrastructure directory
    if [[ "$service_dir" == "Infrastructure/" ]]; then
        continue
    fi
    
    # Check if directory has a Dockerfile
    if [[ -f "${service_dir}Dockerfile" ]]; then
        service_name="${service_dir%/}"
        
        # Get git SHA from this service's repo
        pushd "$service_dir" >/dev/null
        GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        popd >/dev/null
        
        IMAGE_NAME="cso2/${service_name}"
        IMAGE_TAG="dev-${GIT_SHA}"
        IMAGE_TAGS["$IMAGE_NAME"]="$IMAGE_TAG"
        (
            echo "Building ${IMAGE_NAME}:${IMAGE_TAG} from ${service_dir}"
            if [[ "$service_name" == "frontend" ]]; then
                NEXT_PUBLIC_API_URL=http://localhost
                docker build --no-cache --build-arg NEXT_PUBLIC_API_URL="$NEXT_PUBLIC_API_URL" -t "${IMAGE_NAME}:${IMAGE_TAG}" "$service_dir"
            else
                docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "$service_dir"
            fi
        ) &
    fi
done

wait

echo "Build complete. Images created:"
for img in "${!IMAGE_TAGS[@]}"; do
    docker image ls "${img}:${IMAGE_TAGS[$img]}" || true
done

echo "Loading images into Minikube..."
for img in "${!IMAGE_TAGS[@]}"; do
    echo "Loading ${img}:${IMAGE_TAGS[$img]}"
    minikube image load "${img}:${IMAGE_TAGS[$img]}"
done

# Update kustomization with new image tags
echo "Updating kustomization with new image tags..."
if [ -d "$OVERLAY_DIR" ]; then
    pushd "$OVERLAY_DIR" >/dev/null
    
    for img in "${!IMAGE_TAGS[@]}"; do
        echo "Setting image ${img}=${img}:${IMAGE_TAGS[$img]}"
        kustomize edit set image "${img}=${img}:${IMAGE_TAGS[$img]}"
    done
    
    popd >/dev/null
    echo "Done. Apply with: kubectl apply -k ${OVERLAY_DIR}"
else
    echo "Warning: overlay dir ${OVERLAY_DIR} not found"
fi
