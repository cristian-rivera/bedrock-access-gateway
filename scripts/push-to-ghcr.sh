# Usage:
#    cd scripts
#    bash ./push-to-github.sh

set -o errexit  # exit on first error
set -o nounset  # exit on using unset variables
set -o pipefail # exit on any error in a pipeline

# Define variables
TAG="latest"
ARCHS=("arm64" "amd64")
GITHUB_OWNER="cristian-rivera"

build_and_push_images() {
    local IMAGE_NAME=$1
    local TAG=$2
    local ENABLE_MULTI_ARCH=${3:-true}  # Parameter for enabling multi-arch build, default is true
    local DOCKERFILE_PATH=${4:-"../src/Dockerfile_ecs"}  # Parameter for Dockerfile path, default is "../src/Dockerfile_ecs"

    # Create repository URI for GitHub Container Registry
    REPOSITORY_URI="ghcr.io/${GITHUB_OWNER}/${IMAGE_NAME}"

    # Get GitHub token from 1Password and log in to GitHub Container Registry
    # Using 1Password CLI to retrieve the secret
    GITHUB_TOKEN=$(op read "op://Private/GitHub Personal Access Token/token")
    echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_OWNER --password-stdin

    # Build Docker image for each architecture
    if [ "$ENABLE_MULTI_ARCH" == "true" ]; then
        for ARCH in "${ARCHS[@]}"
        do
            # Build multi-architecture Docker image
            docker buildx build --platform linux/$ARCH -t $IMAGE_NAME:$TAG-$ARCH -f $DOCKERFILE_PATH --load ../src/
        done
    else
        # Build single architecture Docker image
        docker buildx build --platform linux/${ARCHS[0]} -t $IMAGE_NAME:$TAG -f $DOCKERFILE_PATH --load ../src/
    fi

    # Push Docker image to GitHub Container Registry
    if [ "$ENABLE_MULTI_ARCH" == "true" ]; then
        for ARCH in "${ARCHS[@]}"
        do
            # Tag the image for GitHub Container Registry
            docker tag $IMAGE_NAME:$TAG-$ARCH $REPOSITORY_URI:$TAG-$ARCH
            # Push the image to GitHub Container Registry
            docker push $REPOSITORY_URI:$TAG-$ARCH
            # Create a manifest for the image
            docker manifest create $REPOSITORY_URI:$TAG $REPOSITORY_URI:$TAG-$ARCH --amend
            # Annotate the manifest with architecture information
            docker manifest annotate $REPOSITORY_URI:$TAG "$REPOSITORY_URI:$TAG-$ARCH" --os linux --arch $ARCH
        done

        # Push the manifest to GitHub Container Registry
        docker manifest push $REPOSITORY_URI:$TAG
    else
        # Tag the image for GitHub Container Registry
        docker tag $IMAGE_NAME:$TAG $REPOSITORY_URI:$TAG
        # Push the image to GitHub Container Registry
        docker push $REPOSITORY_URI:$TAG
    fi

    echo "Pushed $IMAGE_NAME:$TAG to $REPOSITORY_URI"
}

build_and_push_images "bedrock-proxy-api" "$TAG" "true" "../src/Dockerfile"
