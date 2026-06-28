#!/usr/bin/env bash
set -euo pipefail

PROJECT=${1:-ha-nginx}
ENV=${2:-dev}
REGION=${3:-ap-southeast-2}

deploy() {
  echo "Deploying $1..."
  aws cloudformation deploy \
    --region "$REGION" \
    --stack-name "$1" \
    --template-file "$2" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides ProjectName="$PROJECT" Environment="$ENV"
}

deploy "${PROJECT}-${ENV}-networking"  templates/01-networking.yaml
deploy "${PROJECT}-${ENV}-loadbalancer" templates/02-loadbalancer.yaml
deploy "${PROJECT}-${ENV}-compute"     templates/03-compute.yaml

ALB=$(aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "${PROJECT}-${ENV}-loadbalancer" \
  --query "Stacks[0].Outputs[?OutputKey=='ALBDnsName'].OutputValue" \
  --output text)

echo ""
echo "Done. Open: http://$ALB"
