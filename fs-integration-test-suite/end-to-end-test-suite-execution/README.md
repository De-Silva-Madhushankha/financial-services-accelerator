# End-to-end test suite execution

This folder contains Linux (`.sh`) and Windows (`.ps1`) entry points for end-to-end test execution.

## Windows scripts

- `test.ps1` : Dynamic Client Registration flow (IS + Gateway test suites)
- `test_mcr.ps1` : Manual Client Registration flow (Gateway suites)

### Prerequisites

- Java and Maven installed and available on `PATH`
- PowerShell 5.1+ or PowerShell 7+
- `deployment.properties` file available in the input directory
- Firefox/geckodriver available under `fs-integration-test-suite/test-artifacts/selenium-libs`

### Usage

From `fs-integration-test-suite/end-to-end-test-suite-execution`:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\test.ps1 -InputDir . -OutputDir .\output
powershell.exe -ExecutionPolicy Bypass -File .\test_mcr.ps1 -InputDir . -OutputDir .\output
```

### Notes

- If `InstallGeckodriver=true` and `OperatingSystem`/`OSName` indicates Windows, the script downloads geckodriver for Windows.
- The scripts return non-zero when one or more Maven stages fail.
- `OperatingSystem` (new) and `OSName` (legacy) are both supported for OS detection.