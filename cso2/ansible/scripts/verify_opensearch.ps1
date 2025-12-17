# OpenSearch Verification Script for Windows PowerShell
# =============================================================================
# This script verifies that OpenSearch is running correctly
#
# Usage:
#   .\verify_opensearch.ps1 -OpenSearchHost "10.0.1.10" -Port 9200
# =============================================================================

param(
    [string]$OpenSearchHost = "localhost",
    [int]$Port = 9200,
    [string]$Username = "admin",
    [string]$Password = "Admin@123!",
    [int]$DashboardsPort = 5601
)

# Disable SSL certificate validation for self-signed certs
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BaseUrl = "https://${OpenSearchHost}:${Port}"
$DashboardsUrl = "http://${OpenSearchHost}:${DashboardsPort}"
$Credentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))

function Invoke-OpenSearchAPI {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [string]$Body = $null
    )
    
    $headers = @{
        "Authorization" = "Basic $Credentials"
        "Content-Type" = "application/json"
    }
    
    try {
        if ($Body) {
            $response = Invoke-RestMethod -Uri "${BaseUrl}${Endpoint}" -Method $Method -Headers $headers -Body $Body
        } else {
            $response = Invoke-RestMethod -Uri "${BaseUrl}${Endpoint}" -Method $Method -Headers $headers
        }
        return $response
    } catch {
        return $null
    }
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed
    )
    
    if ($Passed) {
        Write-Host "[✓ PASS] $TestName" -ForegroundColor Green
    } else {
        Write-Host "[✗ FAIL] $TestName" -ForegroundColor Red
    }
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   OpenSearch Verification Script" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Dashboards: $DashboardsUrl" -ForegroundColor Yellow
Write-Host ""

# Test 1: Basic Connectivity
Write-Host "1. Basic Connectivity Test" -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$rootResponse = Invoke-OpenSearchAPI -Endpoint "/"
if ($rootResponse) {
    Write-TestResult -TestName "OpenSearch is reachable" -Passed $true
    Write-Host "   Version: $($rootResponse.version.number)" -ForegroundColor Green
} else {
    Write-TestResult -TestName "OpenSearch is reachable" -Passed $false
    Write-Host "Error: Cannot connect to OpenSearch" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 2: Cluster Health
Write-Host "2. Cluster Health Check" -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$health = Invoke-OpenSearchAPI -Endpoint "/_cluster/health"
if ($health) {
    $status = $health.status
    if ($status -eq "green") {
        Write-TestResult -TestName "Cluster status is GREEN" -Passed $true
    } elseif ($status -eq "yellow") {
        Write-Host "[⚠ WARN] Cluster status is YELLOW (expected for single-node)" -ForegroundColor Yellow
    } else {
        Write-TestResult -TestName "Cluster status is healthy" -Passed $false
    }
    Write-Host "   Cluster Name: $($health.cluster_name)" -ForegroundColor Green
    Write-Host "   Number of Nodes: $($health.number_of_nodes)" -ForegroundColor Green
    Write-Host "   Active Shards: $($health.active_shards)" -ForegroundColor Green
}

Write-Host ""

# Test 3: Node Information
Write-Host "3. Node Information" -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$nodes = Invoke-OpenSearchAPI -Endpoint "/_cat/nodes?format=json"
if ($nodes) {
    Write-TestResult -TestName "Nodes are registered in cluster" -Passed $true
    Write-Host "   Nodes:"
    foreach ($node in $nodes) {
        Write-Host "   - $($node.name) ($($node.ip))"
    }
}

Write-Host ""

# Test 4: Index Templates
Write-Host "4. Index Templates Check" -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$templates = Invoke-OpenSearchAPI -Endpoint "/_index_template"
if ($templates -and $templates.index_templates) {
    Write-TestResult -TestName "Index templates are configured" -Passed $true
    Write-Host "   Templates found: $($templates.index_templates.Count)"
    foreach ($template in $templates.index_templates) {
        Write-Host "   - $($template.name)"
    }
} else {
    Write-Host "[⚠ WARN] No custom index templates found" -ForegroundColor Yellow
}

Write-Host ""

# Test 5: Indices Status
Write-Host "5. Indices Status" -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$indices = Invoke-OpenSearchAPI -Endpoint "/_cat/indices?format=json"
if ($indices) {
    Write-TestResult -TestName "Can list indices" -Passed $true
    Write-Host "   Total indices: $($indices.Count)"
    if ($indices.Count -gt 0) {
        Write-Host "   Indices:"
        $indices | Select-Object -First 10 | ForEach-Object {
            Write-Host "   - $($_.index) (docs: $($_.'docs.count'), size: $($_.'store.size'))"
        }
    }
}

Write-Host ""

# Test 6: Security Plugin
Write-Host "6. Security Plugin Check" -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$security = Invoke-OpenSearchAPI -Endpoint "/_plugins/_security/api/account"
if ($security -and $security.user_name) {
    Write-TestResult -TestName "Security plugin is active" -Passed $true
    Write-Host "   Authenticated as: $($security.user_name)" -ForegroundColor Green
} else {
    Write-Host "[⚠ WARN] Security plugin check failed or disabled" -ForegroundColor Yellow
}

Write-Host ""

# Test 7: Write Test
Write-Host "7. Write Test" -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$testIndex = "test-verification-$(Get-Date -Format 'yyyyMMddHHmmss')"
$testDoc = @{
    message = "OpenSearch verification test"
    timestamp = (Get-Date -Format "o")
} | ConvertTo-Json

$writeResult = Invoke-OpenSearchAPI -Endpoint "/$testIndex/_doc/1" -Method "PUT" -Body $testDoc
if ($writeResult -and $writeResult.result) {
    Write-TestResult -TestName "Write operation successful" -Passed $true
    
    # Read back
    $readResult = Invoke-OpenSearchAPI -Endpoint "/$testIndex/_doc/1"
    if ($readResult -and $readResult._source) {
        Write-TestResult -TestName "Read operation successful" -Passed $true
    }
    
    # Cleanup
    Invoke-OpenSearchAPI -Endpoint "/$testIndex" -Method "DELETE" | Out-Null
    Write-Host "   Test index cleaned up"
} else {
    Write-TestResult -TestName "Write operation" -Passed $false
}

Write-Host ""

# Test 8: Cluster Stats
Write-Host "8. Cluster Stats" -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$stats = Invoke-OpenSearchAPI -Endpoint "/_cluster/stats"
if ($stats) {
    Write-TestResult -TestName "Cluster stats available" -Passed $true
    $storeSizeMB = [math]::Round($stats.indices.store.size_in_bytes / 1MB, 2)
    Write-Host "   Total Documents: $($stats.indices.docs.count)"
    Write-Host "   Store Size: $storeSizeMB MB"
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   Verification Complete!" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Quick Commands:" -ForegroundColor White
Write-Host "---------------"
Write-Host "Check cluster health:" -ForegroundColor White
Write-Host "  curl -k -u admin:Admin@123! $BaseUrl/_cluster/health?pretty" -ForegroundColor Yellow
Write-Host ""
Write-Host "List all indices:" -ForegroundColor White
Write-Host "  curl -k -u admin:Admin@123! $BaseUrl/_cat/indices?v" -ForegroundColor Yellow
Write-Host ""
Write-Host "Access Dashboards:" -ForegroundColor White
Write-Host "  $DashboardsUrl" -ForegroundColor Yellow
Write-Host ""
