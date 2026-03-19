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

Set-StrictMode -Version Latest

$script:MVNSTATE = 0

Function Get-Properties {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "[ERROR] deployment.properties not found: $FilePath"
    }

    $properties = @{}
    foreach ($line in Get-Content $FilePath) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }

        $index = $trimmed.IndexOf('=')
        if ($index -lt 0) {
            continue
        }

        $key = $trimmed.Substring(0, $index).Trim()
        $value = $trimmed.Substring($index + 1).Trim()
        $properties[$key] = $value
    }

    return $properties
}

Function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($Properties.ContainsKey($Key)) {
        return "$($Properties[$Key])"
    }

    return ""
}

Function Get-OsName {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Properties
    )

    $osName = Get-PropertyValue -Properties $Properties -Key "OSName"
    if ([string]::IsNullOrWhiteSpace($osName)) {
        $osName = Get-PropertyValue -Properties $Properties -Key "OperatingSystem"
    }

    return $osName.ToLowerInvariant()
}

Function Set-ConfigValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$CurrentValue,
        [Parameter(Mandatory = $true)]
        [string]$NewValue
    )

    $content = Get-Content $FilePath -Raw
    $updated = $content.Replace($CurrentValue, $NewValue)
    Set-Content -Path $FilePath -Value $updated
}

Function Invoke-Maven {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Push-Location $WorkingDirectory
    try {
        & mvn @Arguments
        if ($LASTEXITCODE -ne 0) {
            $script:MVNSTATE++
            Write-Output "[ERROR] Maven command failed in $WorkingDirectory"
        }
    }
    finally {
        Pop-Location
    }
}

Function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    if (-not (Test-Path $DirectoryPath)) {
        New-Item -Path $DirectoryPath -ItemType Directory -Force | Out-Null
    }
}

Function Copy-DirectoriesByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$DirectoryName,
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    Ensure-Directory -DirectoryPath $DestinationRoot

    $normalizedSourceRoot = (Resolve-Path $SourceRoot).Path.TrimEnd('\', '/')
    $folders = Get-ChildItem -Path $normalizedSourceRoot -Directory -Recurse -Filter $DirectoryName -ErrorAction SilentlyContinue
    foreach ($folder in $folders) {
        $relativePath = $folder.FullName.Substring($normalizedSourceRoot.Length).TrimStart('\', '/')
        $destinationPath = Join-Path $DestinationRoot $relativePath
        Ensure-Directory -DirectoryPath (Split-Path -Path $destinationPath -Parent)
        Copy-Item -Path $folder.FullName -Destination $destinationPath -Recurse -Force
    }
}

Function Resolve-WebDriverLocation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestArtifactsRoot,
        [Parameter(Mandatory = $true)]
        [string]$OperatingSystem
    )

    if ($OperatingSystem -match "mac") {
        return (Join-Path $TestArtifactsRoot "selenium-libs/mac/geckodriver")
    }

    if ($OperatingSystem -match "win") {
        return (Join-Path $TestArtifactsRoot "selenium-libs/windows/geckodriver.exe")
    }

    return (Join-Path $TestArtifactsRoot "selenium-libs/ubuntu/geckodriver")
}

Function Install-GeckoDriverIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,
        [Parameter(Mandatory = $true)]
        [string]$TestArtifactsRoot,
        [Parameter(Mandatory = $true)]
        [string]$OperatingSystem
    )

    $installFlag = Get-PropertyValue -Properties $Properties -Key "InstallGeckodriver"
    if ($installFlag -ne "true") {
        Write-Output "[INFO] Not required to install geckodriver"
        return
    }

    if ($OperatingSystem -match "win") {
        $windowsDriverDir = Join-Path $TestArtifactsRoot "selenium-libs/windows"
        Ensure-Directory -DirectoryPath $windowsDriverDir

        $zipPath = Join-Path $windowsDriverDir "geckodriver-v0.29.1-win64.zip"
        $extractPath = Join-Path $windowsDriverDir "geckodriver-extract"
        Invoke-WebRequest -Uri "https://github.com/mozilla/geckodriver/releases/download/v0.29.1/geckodriver-v0.29.1-win64.zip" -OutFile $zipPath
        if (Test-Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force
        }
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Copy-Item -Path (Join-Path $extractPath "geckodriver.exe") -Destination (Join-Path $windowsDriverDir "geckodriver.exe") -Force
        Remove-Item -Path $extractPath -Recurse -Force
        return
    }

    Write-Output "[INFO] Geckodriver auto-install is only implemented in Windows PowerShell scripts."
}

Function Initialize-TestConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,
        [Parameter(Mandatory = $true)]
        [string]$AcceleratorTestsHome,
        [Parameter(Mandatory = $true)]
        [string]$TestFrameworkHome,
        [Parameter(Mandatory = $true)]
        [string]$TestArtifactsRoot
    )

    $testConfigurationFile = Join-Path $TestFrameworkHome "src/main/resources/TestConfiguration.xml"
    $sampleConfigurationFile = Join-Path $TestFrameworkHome "src/main/resources/SampleTestConfiguration.xml"
    if (Test-Path $sampleConfigurationFile) {
        Copy-Item -Path $sampleConfigurationFile -Destination $testConfigurationFile -Force
    }
    elseif (-not (Test-Path $testConfigurationFile)) {
        throw "[ERROR] Neither SampleTestConfiguration.xml nor TestConfiguration.xml exists under $TestFrameworkHome/src/main/resources"
    }

    $isHost = (Get-PropertyValue -Properties $Properties -Key "IsHostname").ToLowerInvariant()
    $amHost = Get-PropertyValue -Properties $Properties -Key "ApimHostname"
    $operatingSystem = Get-OsName -Properties $Properties
    $webDriverLocation = Resolve-WebDriverLocation -TestArtifactsRoot $TestArtifactsRoot -OperatingSystem $operatingSystem

    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "Common.IS_Version" -NewValue "7.1.0"
    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "{AM_HOST}" -NewValue $amHost
    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "{IS_HOST}" -NewValue $isHost
    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "{TestSuiteDirectoryPath}" -NewValue $AcceleratorTestsHome
    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "Provisioning.Enabled" -NewValue "true"
    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "Provisioning.ProvisionFilePath" -NewValue "$AcceleratorTestsHome/accelerator-tests/preconfiguration.steps/src/test/resources/api-config-provisioning.yaml"
    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "BrowserAutomation.BrowserPreference" -NewValue "firefox"
    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "BrowserAutomation.HeadlessEnabled" -NewValue "true"
    Set-ConfigValue -FilePath $testConfigurationFile -CurrentValue "BrowserAutomation.WebDriverLocation" -NewValue $webDriverLocation

    Install-GeckoDriverIfNeeded -Properties $Properties -TestArtifactsRoot $TestArtifactsRoot -OperatingSystem $operatingSystem
}

Function Invoke-TestSuite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SuitePath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [string[]]$MavenArgs
    )

    Invoke-Maven -WorkingDirectory $SuitePath -Arguments $MavenArgs
    Ensure-Directory -DirectoryPath $OutputPath
    Copy-DirectoriesByName -SourceRoot $SuitePath -DirectoryName "surefire-reports" -DestinationRoot $OutputPath
}

Function Exit-WithMavenStatus {
    if ($script:MVNSTATE -gt 0) {
        Write-Output "[ERROR] One or more Maven stages failed."
        exit 1
    }

    Write-Output "[INFO] All Maven stages completed successfully."
    exit 0
}