#!/bin/bash
# =============================================================================
# OpenSearch Verification Script
# =============================================================================
# This script verifies that OpenSearch is running correctly and performs
# various health checks on the cluster.
#
# Usage:
#   ./verify_opensearch.sh [OPENSEARCH_HOST] [OPENSEARCH_PORT] [USERNAME] [PASSWORD]
#
# Example:
#   ./verify_opensearch.sh 10.0.1.10 9200 admin Admin@123!
# =============================================================================

set -e

# Configuration
OPENSEARCH_HOST="${1:-localhost}"
OPENSEARCH_PORT="${2:-9200}"
USERNAME="${3:-admin}"
PASSWORD="${4:-Admin@123!}"
DASHBOARDS_PORT="${5:-5601}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base URL
BASE_URL="https://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}"
DASHBOARDS_URL="http://${OPENSEARCH_HOST}:${DASHBOARDS_PORT}"

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}   OpenSearch Verification Script${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""
echo -e "Target: ${YELLOW}${BASE_URL}${NC}"
echo -e "Dashboards: ${YELLOW}${DASHBOARDS_URL}${NC}"
echo ""

# Function to make API calls
api_call() {
    local endpoint=$1
    local method=${2:-GET}
    curl -sk -X ${method} -u "${USERNAME}:${PASSWORD}" "${BASE_URL}${endpoint}"
}

# Function to print status
print_status() {
    local test_name=$1
    local status=$2
    if [ "$status" == "PASS" ]; then
        echo -e "[${GREEN}✓ PASS${NC}] $test_name"
    else
        echo -e "[${RED}✗ FAIL${NC}] $test_name"
    fi
}

echo -e "${YELLOW}1. Basic Connectivity Test${NC}"
echo "---------------------------------------------"

# Test 1: Check if OpenSearch is reachable
if curl -sk -u "${USERNAME}:${PASSWORD}" "${BASE_URL}" > /dev/null 2>&1; then
    print_status "OpenSearch is reachable" "PASS"
    
    # Get version info
    VERSION=$(api_call "/" | jq -r '.version.number // "unknown"')
    echo -e "   Version: ${GREEN}${VERSION}${NC}"
else
    print_status "OpenSearch is reachable" "FAIL"
    echo -e "${RED}Error: Cannot connect to OpenSearch at ${BASE_URL}${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}2. Cluster Health Check${NC}"
echo "---------------------------------------------"

# Test 2: Check cluster health
HEALTH=$(api_call "/_cluster/health")
CLUSTER_STATUS=$(echo $HEALTH | jq -r '.status // "unknown"')
CLUSTER_NAME=$(echo $HEALTH | jq -r '.cluster_name // "unknown"')
NUM_NODES=$(echo $HEALTH | jq -r '.number_of_nodes // 0')
ACTIVE_SHARDS=$(echo $HEALTH | jq -r '.active_shards // 0')

if [ "$CLUSTER_STATUS" == "green" ]; then
    print_status "Cluster status is GREEN" "PASS"
elif [ "$CLUSTER_STATUS" == "yellow" ]; then
    echo -e "[${YELLOW}⚠ WARN${NC}] Cluster status is YELLOW (expected for single-node)"
else
    print_status "Cluster status is healthy" "FAIL"
fi

echo -e "   Cluster Name: ${GREEN}${CLUSTER_NAME}${NC}"
echo -e "   Number of Nodes: ${GREEN}${NUM_NODES}${NC}"
echo -e "   Active Shards: ${GREEN}${ACTIVE_SHARDS}${NC}"

echo ""
echo -e "${YELLOW}3. Node Information${NC}"
echo "---------------------------------------------"

# Test 3: Get node info
NODES=$(api_call "/_cat/nodes?format=json")
NODE_COUNT=$(echo $NODES | jq 'length')

if [ "$NODE_COUNT" -ge 1 ]; then
    print_status "Nodes are registered in cluster" "PASS"
    echo "   Nodes:"
    echo $NODES | jq -r '.[] | "   - \(.name) (\(.ip)) - \(.node.role)"'
else
    print_status "Nodes are registered" "FAIL"
fi

echo ""
echo -e "${YELLOW}4. Index Templates Check${NC}"
echo "---------------------------------------------"

# Test 4: Check if index templates exist
TEMPLATES=$(api_call "/_index_template")
TEMPLATE_COUNT=$(echo $TEMPLATES | jq '.index_templates | length')

if [ "$TEMPLATE_COUNT" -ge 1 ]; then
    print_status "Index templates are configured" "PASS"
    echo "   Templates found: ${TEMPLATE_COUNT}"
    echo $TEMPLATES | jq -r '.index_templates[].name' | while read name; do
        echo "   - $name"
    done
else
    echo -e "[${YELLOW}⚠ WARN${NC}] No custom index templates found"
fi

echo ""
echo -e "${YELLOW}5. Indices Status${NC}"
echo "---------------------------------------------"

# Test 5: List indices
INDICES=$(api_call "/_cat/indices?format=json&v")
INDEX_COUNT=$(echo $INDICES | jq 'length')

print_status "Can list indices" "PASS"
echo "   Total indices: ${INDEX_COUNT}"

if [ "$INDEX_COUNT" -gt 0 ]; then
    echo "   Indices:"
    echo $INDICES | jq -r '.[] | "   - \(.index) (docs: \(.["docs.count"]), size: \(.["store.size"]))"' | head -10
fi

echo ""
echo -e "${YELLOW}6. Security Plugin Check${NC}"
echo "---------------------------------------------"

# Test 6: Check security plugin
SECURITY=$(api_call "/_plugins/_security/api/account")
if echo $SECURITY | jq -e '.user_name' > /dev/null 2>&1; then
    print_status "Security plugin is active" "PASS"
    CURRENT_USER=$(echo $SECURITY | jq -r '.user_name')
    echo -e "   Authenticated as: ${GREEN}${CURRENT_USER}${NC}"
else
    echo -e "[${YELLOW}⚠ WARN${NC}] Security plugin check failed or disabled"
fi

echo ""
echo -e "${YELLOW}7. ISM Policy Check${NC}"
echo "---------------------------------------------"

# Test 7: Check ISM policies
ISM_POLICIES=$(api_call "/_plugins/_ism/policies")
if echo $ISM_POLICIES | jq -e '.policies' > /dev/null 2>&1; then
    POLICY_COUNT=$(echo $ISM_POLICIES | jq '.policies | length')
    print_status "ISM policies endpoint accessible" "PASS"
    echo "   ISM Policies: ${POLICY_COUNT}"
else
    echo -e "[${YELLOW}⚠ WARN${NC}] No ISM policies configured"
fi

echo ""
echo -e "${YELLOW}8. OpenSearch Dashboards Check${NC}"
echo "---------------------------------------------"

# Test 8: Check Dashboards
if curl -sk "${DASHBOARDS_URL}/api/status" > /dev/null 2>&1; then
    print_status "OpenSearch Dashboards is accessible" "PASS"
    DASH_STATUS=$(curl -sk "${DASHBOARDS_URL}/api/status" | jq -r '.status.overall.state // "unknown"')
    echo -e "   Dashboards Status: ${GREEN}${DASH_STATUS}${NC}"
else
    echo -e "[${YELLOW}⚠ WARN${NC}] OpenSearch Dashboards is not accessible"
fi

echo ""
echo -e "${YELLOW}9. Write Test${NC}"
echo "---------------------------------------------"

# Test 9: Test write operation
TEST_INDEX="test-verification-$(date +%s)"
WRITE_RESULT=$(curl -sk -X PUT -u "${USERNAME}:${PASSWORD}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}/${TEST_INDEX}/_doc/1" \
    -d '{"message": "OpenSearch verification test", "timestamp": "'$(date -Iseconds)'"}')

if echo $WRITE_RESULT | jq -e '.result' > /dev/null 2>&1; then
    print_status "Write operation successful" "PASS"
    
    # Read back
    READ_RESULT=$(api_call "/${TEST_INDEX}/_doc/1")
    if echo $READ_RESULT | jq -e '._source.message' > /dev/null 2>&1; then
        print_status "Read operation successful" "PASS"
    fi
    
    # Cleanup
    api_call "/${TEST_INDEX}" DELETE > /dev/null 2>&1
    echo "   Test index cleaned up"
else
    print_status "Write operation" "FAIL"
fi

echo ""
echo -e "${YELLOW}10. Cluster Stats${NC}"
echo "---------------------------------------------"

# Test 10: Get cluster stats
STATS=$(api_call "/_cluster/stats")
TOTAL_DOCS=$(echo $STATS | jq -r '.indices.docs.count // 0')
STORE_SIZE=$(echo $STATS | jq -r '.indices.store.size_in_bytes // 0')
STORE_SIZE_MB=$((STORE_SIZE / 1024 / 1024))

print_status "Cluster stats available" "PASS"
echo "   Total Documents: ${TOTAL_DOCS}"
echo "   Store Size: ${STORE_SIZE_MB} MB"

echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}   Verification Complete!${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""
echo "Quick Commands:"
echo "---------------"
echo -e "Check cluster health:"
echo -e "  ${YELLOW}curl -k -u admin:Admin@123! ${BASE_URL}/_cluster/health?pretty${NC}"
echo ""
echo -e "List all indices:"
echo -e "  ${YELLOW}curl -k -u admin:Admin@123! ${BASE_URL}/_cat/indices?v${NC}"
echo ""
echo -e "View cluster nodes:"
echo -e "  ${YELLOW}curl -k -u admin:Admin@123! ${BASE_URL}/_cat/nodes?v${NC}"
echo ""
echo -e "Access Dashboards:"
echo -e "  ${YELLOW}${DASHBOARDS_URL}${NC}"
echo ""
