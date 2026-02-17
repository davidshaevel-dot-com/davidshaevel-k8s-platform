#!/usr/bin/env bash
# Create or update Cloudflare DNS records for Teleport.
# Creates two A records:
#   ${TELEPORT_DOMAIN}   -> Teleport LoadBalancer IP (proxy)
#   *.${TELEPORT_DOMAIN} -> Teleport LoadBalancer IP (app subdomains)
# Requires: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID in .envrc
# Reference: https://developers.cloudflare.com/api/resources/dns/subresources/records/

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-dns"

DOMAIN="${TELEPORT_DOMAIN}"
WILDCARD_DOMAIN="*.${TELEPORT_DOMAIN}"
CF_API="https://api.cloudflare.com/client/v4"
ZONE_ID="${CLOUDFLARE_ZONE_ID:?Set CLOUDFLARE_ZONE_ID in .envrc or environment}"
API_TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN in .envrc or environment}"
TELEPORT_NAMESPACE="teleport-cluster"

# Get Teleport LoadBalancer external IP.
echo "Getting Teleport LoadBalancer IP..."
EXTERNAL_IP=$(kubectl get svc teleport-cluster -n "${TELEPORT_NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

if [ -z "${EXTERNAL_IP}" ]; then
    echo "Error: Teleport LoadBalancer IP not found."
    echo "Ensure Teleport is installed and the LoadBalancer has an external IP."
    echo "Run: kubectl get svc -n ${TELEPORT_NAMESPACE}"
    exit 1
fi
echo "Teleport LoadBalancer IP: ${EXTERNAL_IP}"

# Create or update a single DNS A record.
# Usage: upsert_record <record_name>
upsert_record() {
    local record_name="${1}"

    echo ""
    echo "Checking for existing record: ${record_name}..."
    local existing
    existing=$(curl -s -X GET "${CF_API}/zones/${ZONE_ID}/dns_records?name=${record_name}&type=A" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json")

    local record_id
    record_id=$(echo "${existing}" | jq -r '.result[0].id // empty')

    local result
    if [ -n "${record_id}" ]; then
        echo "Existing record found (ID: ${record_id}). Updating..."
        result=$(curl -s -X PUT "${CF_API}/zones/${ZONE_ID}/dns_records/${record_id}" \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${record_name}\",\"content\":\"${EXTERNAL_IP}\",\"ttl\":1,\"proxied\":false}")
    else
        echo "No existing record. Creating..."
        result=$(curl -s -X POST "${CF_API}/zones/${ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${record_name}\",\"content\":\"${EXTERNAL_IP}\",\"ttl\":1,\"proxied\":false}")
    fi

    local success
    success=$(echo "${result}" | jq -r '.success')
    if [ "${success}" = "true" ]; then
        echo "  ${record_name} -> ${EXTERNAL_IP}"
    else
        echo "Error setting ${record_name}:"
        echo "${result}" | jq '.errors'
        exit 1
    fi
}

# Create both records.
upsert_record "${DOMAIN}"
upsert_record "${WILDCARD_DOMAIN}"

echo ""
echo "DNS records set (proxied: false, TTL: auto):"
echo "  ${DOMAIN}          -> ${EXTERNAL_IP}"
echo "  ${WILDCARD_DOMAIN} -> ${EXTERNAL_IP}"
