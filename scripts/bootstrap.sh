#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-madison-municipal-data}"
REGION="${REGION:-us-central1}"
STATE_BUCKET="stmsn-tfstate"

# The state bucket cannot be Terraform-managed (it holds the state), so it is
# created by hand exactly once and never imported.
gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="${PROJECT}" \
  --location="${REGION}" \
  --uniform-bucket-level-access \
  --public-access-prevention

# Versioning lets you recover a clobbered state file.
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning

echo "Created gs://${STATE_BUCKET} (versioned, unmanaged)."
echo "Next: write backend.tf, then run 'terraform init'."
