# PSScriptAnalyzerSettings.psd1
# PSScriptAnalyzer rule configuration for the Tools repo.
# Used by both the GitHub Actions lint workflow and VS Code + PowerShell extension
# for local development — ensures local and CI linting use identical rules.
#
# To use in VS Code: install the PowerShell extension — it picks this file up
# automatically when it exists in the workspace root.

@{
    ExcludeRules = @(
        # BOM is optional for UTF-8 and causes issues on Linux/macOS.
        # All toolkit scripts are UTF-8 without BOM by convention.
        'PSUseBOMForUnicodeEncodedFile',

        # Write-Host is used intentionally throughout for colored console output.
        'PSAvoidUsingWriteHost',

        # $CommonVersion and $SambaSharePath in common.ps1 are intentionally
        # exported via dot-sourcing for consumer scripts to read.
        # PSScriptAnalyzer cannot trace cross-script usage and flags them as unused.
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}
