#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-madison-municipal-data}"
REGION="${REGION:-us-central1}"
OUT="imports.generated.tf"

: > "$OUT"
sanitize() { echo "$1" | tr -c 'a-zA-Z0-9_' '_'; }

# route-traffic-monitor owns its own Terraform, so its resources are excluded
# here to avoid double management. Adjust the pattern to match its actual names.
SKIP_RE="${SKIP_RE:-route-traffic|route_traffic|routes}"
skip() { echo "$1" | grep -Eqi "$SKIP_RE"; }

{
  echo "// Generated import blocks. Review, then:"
  echo "//   terraform plan -generate-config-out=generated.tf"
  echo "// Delete this file once generated.tf is cleaned and applied."
  echo
} >> "$OUT"

emit() {  # emit <resource_type> <local_name> <import_id>
  cat >> "$OUT" <<EOF
import {
  to = ${1}.${2}
  id = "${3}"
}
EOF
}

# Cloud Run v2 jobs
for j in $(gcloud run jobs list --project="$PROJECT" --region="$REGION" \
             --format="value(metadata.name)" 2>/dev/null); do
  skip "$j" && continue
  emit google_cloud_run_v2_job "$(sanitize "$j")" \
       "projects/${PROJECT}/locations/${REGION}/jobs/${j}"
done

# Cloud Scheduler jobs
for s in $(gcloud scheduler jobs list --project="$PROJECT" --location="$REGION" \
             --format="value(name)" 2>/dev/null); do
  short="${s##*/}"
  skip "$short" && continue
  emit google_cloud_scheduler_job "$(sanitize "$short")" \
       "projects/${PROJECT}/locations/${REGION}/jobs/${short}"
done

# Artifact Registry repositories
for r in $(gcloud artifacts repositories list --project="$PROJECT" \
             --location="$REGION" --format="value(name)" 2>/dev/null); do
  short="${r##*/}"
  emit google_artifact_registry_repository "$(sanitize "$short")" \
       "projects/${PROJECT}/locations/${REGION}/repositories/${short}"
done

# Cloud Workflows
for w in $(gcloud workflows list --project="$PROJECT" --location="$REGION" \
             --format="value(name)" 2>/dev/null); do
  short="${w##*/}"
  emit google_workflows_workflow "$(sanitize "$short")" \
       "projects/${PROJECT}/locations/${REGION}/workflows/${short}"
done

# Service accounts (skip Google-managed defaults)
for sa in $(gcloud iam service-accounts list --project="$PROJECT" \
              --format="value(email)"); do
  case "$sa" in
    *-compute@developer.gserviceaccount.com) continue;;
    *@cloudservices.gserviceaccount.com)     continue;;
    *@appspot.gserviceaccount.com)           continue;;
  esac
  skip "$sa" && continue
  emit google_service_account "$(sanitize "${sa%%@*}")" \
       "projects/${PROJECT}/serviceAccounts/${sa}"
done

echo "Wrote ${OUT}"
echo "Next: terraform plan -generate-config-out=generated.tf"
