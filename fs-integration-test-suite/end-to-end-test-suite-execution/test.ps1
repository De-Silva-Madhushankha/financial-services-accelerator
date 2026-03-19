 # Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 #
 # WSO2 LLC. licenses this file to you under the Apache License,
 # Version 2.0 (the "License"); you may not use this file except
 # in compliance with the License.
 # You may obtain a copy of the License at
 #
 #    http://www.apache.org/licenses/LICENSE-2.0
 #
 # Unless required by applicable law or agreed to in writing,
 # software distributed under the License is distributed on an
 # "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 # KIND, either express or implied. See the License for the
 # specific language governing permissions and limitations
 # under the License.

[CmdletBinding()]
param(
    [Alias('i')]
    [string]$InputDir,
    [Alias('o')]
    [string]$OutputDir,
    [Alias('m')]
    [string]$MavenOpts,
    [Alias('h')]
    [switch]$Help
)

if ($Help) {
    Write-Output "Usage: .\test.ps1 -InputDir <path> -OutputDir <path> [-MavenOpts <opts>]"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($InputDir) -or [string]::IsNullOrWhiteSpace($OutputDir)) {
    throw "[ERROR] InputDir and OutputDir are required."
}

. (Join-Path $PSScriptRoot "test.common.ps1")

if (-not [string]::IsNullOrWhiteSpace($MavenOpts)) {
    $env:MAVEN_OPTS = $MavenOpts
}

$env:DATA_BUCKET_LOCATION = $InputDir
$deploymentProperties = Join-Path $InputDir "deployment.properties"
Get-Content $deploymentProperties
$properties = Get-Properties -FilePath $deploymentProperties

$projectHome = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path
$acceleratorTestsHome = Join-Path $projectHome "fs-integration-test-suite"
$testFrameworkHome = Join-Path $acceleratorTestsHome "accelerator-test-framework"
$testArtifacts = Join-Path $acceleratorTestsHome "test-artifacts"
$gatewayIntegrationTestHome = Join-Path $acceleratorTestsHome "accelerator-tests/gateway-tests"
$isTestHome = Join-Path $acceleratorTestsHome "accelerator-tests/is-tests"

Write-Output "[INFO] Go to fs-integration-test-suite folder"
Initialize-TestConfiguration -Properties $properties -AcceleratorTestsHome $acceleratorTestsHome -TestFrameworkHome $testFrameworkHome -TestArtifactsRoot $testArtifacts

Invoke-Maven -WorkingDirectory $projectHome -Arguments @("clean", "install", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn")
Invoke-Maven -WorkingDirectory $acceleratorTestsHome -Arguments @("clean", "install", "-Dmaven.test.skip=true", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn")
Invoke-Maven -WorkingDirectory (Join-Path $acceleratorTestsHome "accelerator-tests/preconfiguration.steps") -Arguments @("clean", "install", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn")

Write-Output "[INFO] Executing IS tests"
$isSuites = @(
    "dcr",
    "token",
    "pre-configuration-step",
    "consent-management",
    "event-notification"
)

foreach ($suite in $isSuites) {
    $suitePath = Join-Path $isTestHome $suite
    $outputPath = Join-Path $OutputDir "scenarios/is-tests/$suite"
    Invoke-TestSuite -SuitePath $suitePath -OutputPath $outputPath -MavenArgs @("clean", "install", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn", "-fae", "-B", "-f", "pom.xml")
}

Write-Output "[INFO] End of IS tests"

Write-Output "[INFO] Executing Gateway tests"
Invoke-TestSuite -SuitePath (Join-Path $gatewayIntegrationTestHome "dcr") -OutputPath (Join-Path $OutputDir "scenarios/gateway-tests/dcr") -MavenArgs @("clean", "install", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn", "-fae", "-B", "-f", "pom.xml")

Write-Output "[INFO] Rebuild the Accelerator Framework to fetch configuration changes"
Invoke-Maven -WorkingDirectory $testFrameworkHome -Arguments @("clean", "install", "-Dmaven.test.skip=true", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn")

Invoke-TestSuite -SuitePath (Join-Path $gatewayIntegrationTestHome "accounts") -OutputPath (Join-Path $OutputDir "scenarios/gateway-tests/accounts") -MavenArgs @("clean", "install", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn", "-fae", "-B", "-f", "pom.xml")
Invoke-TestSuite -SuitePath (Join-Path $gatewayIntegrationTestHome "cof") -OutputPath (Join-Path $OutputDir "scenarios/gateway-tests/cof") -MavenArgs @("clean", "install", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn", "-fae", "-B", "-f", "pom.xml")
Invoke-TestSuite -SuitePath (Join-Path $gatewayIntegrationTestHome "payments") -OutputPath (Join-Path $OutputDir "scenarios/gateway-tests/payments") -MavenArgs @("clean", "install", "-DdcrEnabled=true", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn", "-fae", "-B", "-f", "pom.xml")
Invoke-TestSuite -SuitePath (Join-Path $gatewayIntegrationTestHome "schema.validation") -OutputPath (Join-Path $OutputDir "scenarios/gateway-tests/schema.validation") -MavenArgs @("clean", "install", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn", "-fae", "-B", "-f", "pom.xml")
$tokenSuitePath = Join-Path $gatewayIntegrationTestHome "token"
Invoke-TestSuite -SuitePath $tokenSuitePath -OutputPath (Join-Path $OutputDir "scenarios/gateway-tests/token") -MavenArgs @("clean", "install", "-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn", "-fae", "-B", "-f", "pom.xml")

Write-Output "[INFO] End of Gateway tests"
Copy-DirectoriesByName -SourceRoot $tokenSuitePath -DirectoryName "aggregate-surefire-report" -DestinationRoot (Join-Path $OutputDir "scenarios")

Exit-WithMavenStatus