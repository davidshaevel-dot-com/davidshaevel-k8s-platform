#!/usr/bin/env bash
# Delete Cloudflare DNS records for Teleport.
# Removes both:
#   ${TELEPORT_DOMAIN}   (proxy)
#   *.${TELEPORT_DOMAIN} (app subdomains)
# Requires: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID in .envrc

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-dns-delete"

DOMAIN="${TELEPORT_DOMAIN}"
WILDCARD_DOMAIN="*.${TELEPORT_DOMAIN}"
CF_API="https://api.cloudflare.com/client/v4"
ZONE_ID="${CLOUDFLARE_ZONE_ID:?Set CLOUDFLARE_ZONE_ID in .envrc or environment}"
API_TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN in .envrc or environment}"

# Look up existing records and store IDs for later deletion.
echo "Looking up DNS records for Teleport..."
RECORD_IDS=()
RECORD_NAMES=()
for name in "${DOMAIN}" "${WILDCARD_DOMAIN}"; do
    EXISTING=$(curl -s -X GET "${CF_API}/zones/${ZONE_ID}/dns_records?name=${name}&type=A" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json")

    RECORD_ID=$(echo "${EXISTING}" | jq -r '.result[0].id // empty')
    if [ -n "${RECORD_ID}" ]; then
        RECORD_IP=$(echo "${EXISTING}" | jq -r '.result[0].content')
        echo "  Found: ${name} -> ${RECORD_IP} (ID: ${RECORD_ID})"
        RECORD_IDS+=("${RECORD_ID}")
        RECORD_NAMES+=("${name}")
    fi
done

if [ ${#RECORD_IDS[@]} -eq 0 ]; then
    echo "No DNS records found for Teleport. Nothing to delete."
    exit 0
fi

echo ""
if [[ "${CI:-}" == "true" ]]; then
    echo "CI mode: skipping interactive confirmation."
else
    read -r -p "Type 'delete' to confirm deletion of ${#RECORD_IDS[@]} record(s): " confirm
    if [ "${confirm}" != "delete" ]; then
        echo "Confirmation failed. Aborting."
        exit 1
    fi
fi

# Delete records using stored IDs (no redundant lookups).
echo "Deleting DNS records..."
for i in "${!RECORD_IDS[@]}"; do
    record_id="${RECORD_IDS[$i]}"
    record_name="${RECORD_NAMES[$i]}"

    result=$(curl -s -X DELETE "${CF_API}/zones/${ZONE_ID}/dns_records/${record_id}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json")

    success=$(echo "${result}" | jq -r '.success')
    if [ "${success}" = "true" ]; then
        echo "  ${record_name}: deleted."
    else
        echo "  ${record_name}: error deleting:"
        echo "${result}" | jq '.errors'
        exit 1
    fi
done

echo ""
echo "All Teleport DNS records deleted."
