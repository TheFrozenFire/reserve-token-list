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
    tags: ["dtf"],
    extensions: {
        marketCap: .marketCap,
        fee: .fee,
        basketSize: (.basket | length)
    }
}]' > "${TEMP_DIR}/tokens.json"

TOKEN_COUNT=$(jq 'length' "${TEMP_DIR}/tokens.json")
echo "Total DTFs: ${TOKEN_COUNT}"

# Generate token map
jq 'map({("\(.chainId)_\(.address)"): .}) | add' "${TEMP_DIR}/tokens.json" > "${TEMP_DIR}/tokenMap.json"

# Generate final token list
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
    --arg name "Reserve DTF Token List" \
    --arg timestamp "$TIMESTAMP" \
    --arg logoURI "https://reserve.org/assets/logo.png" \
    --slurpfile tokens "${TEMP_DIR}/tokens.json" \
    --slurpfile tokenMap "${TEMP_DIR}/tokenMap.json" \
    '{
        name: $name,
        timestamp: $timestamp,
        logoURI: $logoURI,
        keywords: ["reserve", "dtf", "index", "yield", "defi"],
        tags: {
            dtf: {
                name: "DTF",
                description: "Decentralized Token Folio - tokenized index backed 1:1 by digital assets"
            }
        },
        version: {
            major: 1,
            minor: 0,
            patch: 0
        },
        tokens: $tokens[0],
        tokenMap: $tokenMap[0]
    }' > "$OUTPUT_FILE"

echo "Generated ${OUTPUT_FILE}"
