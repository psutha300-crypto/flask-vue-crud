#!/usr/bin/env bash
set -euo pipefail

region="${1:?Usage: deploy.sh REGION ECR_REGISTRY IMAGE_TAG}"
registry="${2:?Missing ECR registry}"
tag="${3:?Missing image tag}"

[[ "$region" == "eu-west-2" ]] || exit 1
[[ "$registry" =~ ^[0-9]{12}\.dkr\.ecr\.eu-west-2\.amazonaws\.com$ ]] || exit 1
[[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || exit 1

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="$project_dir/docker-compose.prod.yml"

# Prevent overlapping deployments on this server.
exec 9>"$project_dir/.deployment.lock"
flock -n 9 || {
  echo "Another deployment is running."
  exit 1
}

# Keep registry credentials and candidate configuration temporary.
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export DOCKER_CONFIG="$work_dir/docker"
mkdir -p "$DOCKER_CONFIG"

unset ECR_REGISTRY IMAGE_TAG
printf 'ECR_REGISTRY=%s\nIMAGE_TAG=%s\n' \
  "$registry" "$tag" > "$work_dir/release.env"

compose=(
  docker compose
  --project-name assessment
  --env-file "$work_dir/release.env"
  -f "$compose_file"
)

"${compose[@]}" config --quiet

aws ecr get-login-password --region "$region" |
  docker login --username AWS --password-stdin "$registry"

# Download both images before replacing running containers.
"${compose[@]}" pull

if ! "${compose[@]}" up -d --force-recreate --wait --wait-timeout 180; then
  echo "Deployment failed. Container status and recent logs:"
  "${compose[@]}" ps --all || true
  "${compose[@]}" logs --tail 50 || true
  exit 1
fi

"${compose[@]}" ps
echo "Deployment completed: $tag"