#!/bin/bash
# Generate Reserve DTF Token List
# Compatible with Uniswap Token List standard

set -e

OUTPUT_FILE="${1:-reserve-dtf-tokenlist.json}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Chains with DTF support
CHAINS=(1 8453 56)
CHAIN_NAMES=("Ethereum" "Base" "BSC")

echo "Fetching DTFs from Reserve API..."

# Fetch all DTFs
for i in "${!CHAINS[@]}"; do
    CHAIN_ID="${CHAINS[$i]}"
    CHAIN_NAME="${CHAIN_NAMES[$i]}"
    echo "  Fetching ${CHAIN_NAME} (${CHAIN_ID})..."

    RESPONSE=$(curl -s "https://api.reserve.org/discover/dtf?chainId=${CHAIN_ID}&limit=100")

    # Check if response is an array (valid) or object (error)
    TYPE=$(echo "$RESPONSE" | jq -r 'type')
    if [ "$TYPE" = "array" ]; then
        echo "$RESPONSE" > "${TEMP_DIR}/chain_${CHAIN_ID}.json"
        COUNT=$(echo "$RESPONSE" | jq 'length')
        echo "    Found ${COUNT} DTFs"
    else
        echo "    Skipping - API error"
        echo "[]" > "${TEMP_DIR}/chain_${CHAIN_ID}.json"
    fi
done

# Combine and transform
echo "Transforming to token list format..."

cat "${TEMP_DIR}"/chain_*.json | jq -s 'add | [.[] | {
    chainId: .chainId,
    address: .address,
    name: .name,
    symbol: .symbol,
    decimals: 18,
    logoURI: (.brand.logoURI // "https://reserve.org/assets/dtf-default.png"),
    _marketCap: .marketCap
}] | sort_by(._marketCap) | reverse | [.[] | del(._marketCap)]' > "${TEMP_DIR}/tokens.json"

TOKEN_COUNT=$(jq 'length' "${TEMP_DIR}/tokens.json")
echo "Total DTFs: ${TOKEN_COUNT}"

# Generate final token list
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
    --arg name "Reserve DTF Token List" \
    --arg timestamp "$TIMESTAMP" \
    --arg logoURI "https://reserve.org/assets/logo.png" \
    --slurpfile tokens "${TEMP_DIR}/tokens.json" \
    '{
        name: $name,
        timestamp: $timestamp,
        version: {
            major: 1,
            minor: 0,
            patch: 0
        },
        logoURI: $logoURI,
        keywords: ["reserve", "dtf", "index", "yield", "defi"],
        tokens: $tokens[0]
    }' > "$OUTPUT_FILE"

echo "Generated ${OUTPUT_FILE}"

# Validate against Uniswap schema
SCHEMA_URL="https://raw.githubusercontent.com/Uniswap/token-lists/main/src/tokenlist.schema.json"
SCHEMA_FILE="${TEMP_DIR}/tokenlist.schema.json"

echo "Validating against Uniswap token list schema..."
curl -s "$SCHEMA_URL" -o "$SCHEMA_FILE"

if npx ajv-cli validate -s "$SCHEMA_FILE" -d "$OUTPUT_FILE" --spec=draft7 --strict=false 2>&1 | grep -q "valid$"; then
    echo "Validation passed"
else
    echo "Validation failed:"
    npx ajv-cli validate -s "$SCHEMA_FILE" -d "$OUTPUT_FILE" --spec=draft7 --strict=false 2>&1
    exit 1
fi
