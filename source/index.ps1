$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

Function InitializeExecuter {
    $options = [pscustomobject]@{}
    $optionsPath = Join-Path -Path $PSScriptRoot -ChildPath '\option.executer.json'
    if ([System.IO.File]::Exists($optionsPath )) {  
        $options = (Get-Content $optionsPath | ConvertFrom-Json)
    }
    $options
}
Function InitializeSecrets([pscustomobject] $optionsExecuter) {
    if ($options.IsShowLogInitializeSecrets -eq $True) {
        Write-Host '=====InitializeSecrets====='
    }
    $secrets = [pscustomobject]@{}
    try {
        $GITHUB_secrets = $env:GITHUB_secrets | ConvertFrom-Json
        $GITHUB_secrets.PSObject.Properties | ForEach-Object {
            if ($_.Name -ne "github_token") {
                $converFromBase64 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_.Value))
                $secrets | Add-Member `
                    -NotePropertyName $_.Name `
                    -NotePropertyValue ($converFromBase64 | ConvertFrom-Json)   
            }  
            else {
                $secrets | Add-Member `
                    -NotePropertyName $_.Name `
                    -NotePropertyValue $_.Value 
            }
        }
    }
    catch {
        $secretsPath = Join-Path -Path $PSScriptRoot -ChildPath '.githubsecrets'
        if ([System.IO.Directory]::Exists($secretsPath )) {            
            $secretsPath = Join-Path -Path $secretsPath -ChildPath '*'
            $extension = ".githubsecrets.json"
            $table = get-childitem -Path ($secretsPath) -Include @('*' + $extension)
            foreach ($file in $table) {
                $secrets | Add-Member `
                    -NotePropertyName ($file.Name.Replace($extension, '')) `
                    -NotePropertyValue (Get-Content $file.Fullname | ConvertFrom-Json)
            }
        }
    }
    if ($options.IsShowLogInitializeSecrets -eq $True) {
        Write-Host ($secrets | ConvertTo-Json)
        Write-Host '=====END:InitializeSecrets='
    }
    $secrets
}
$options = InitializeExecuter
$secrets = InitializeSecrets -optionsExecuter $options
function GetLibraryFile ([string] $pathLibrary) {
    
    [System.IO.FileInfo]$infoFile = New-Object System.IO.FileInfo($pathLibrary);
    $o = [pscustomobject]@{}
    $o | Add-Member -NotePropertyName OriginalFilename -NotePropertyValue $infoFile.Name
    $o | Add-Member -NotePropertyName FileVersion -NotePropertyValue $infoFile.VersionInfo.FileVersion
    $o | Add-Member -NotePropertyName FileDescription -NotePropertyValue $infoFile.VersionInfo.FileDescription
    $o | Add-Member -NotePropertyName FileLength -NotePropertyValue $infoFile.Length
    $o | Add-Member -NotePropertyName IsExe -NotePropertyValue ($infoFile.Name -match '.exe$')

    # $o | Add-Member -NotePropertyName FileTime -NotePropertyValue ([pscustomobject]@{})
    # $o.FileTime | Add-Member -NotePropertyName CreationTime `
    #     -NotePropertyValue ($infoFile.CreationTime.ToString("yyyyMMdd HH:mm:ss"))
    # $o.FileTime | Add-Member -NotePropertyName LastWriteTime `
    #     -NotePropertyValue ($infoFile.LastWriteTime.ToString("yyyyMMdd HH:mm:ss"))
    # $o.FileTime | Add-Member -NotePropertyName LastAccessTime `
    #     -NotePropertyValue ($infoFile.LastAccessTime.ToString("yyyyMMdd HH:mm:ss"))
    
    $fileBytes = [System.IO.File]::ReadAllBytes($pathLibrary);
    $o | Add-Member -NotePropertyName FileHashMD5 `
        -NotePropertyValue ((Get-FileHash -InputStream  ([System.IO.MemoryStream]::New($fileBytes)) -Algorithm MD5).hash)
    $o | Add-Member -NotePropertyName FileHashSHA1 `
        -NotePropertyValue ((Get-FileHash -InputStream  ([System.IO.MemoryStream]::New($fileBytes)) -Algorithm SHA1).hash)
		
    try {
        $assembly = [System.Reflection.Assembly]::Load($fileBytes)
        $assemblyGetName = $assembly.GetName()
        $assemblyFullName = $assembly.FullName
        $o | Add-Member -NotePropertyName AssemblyFullName -NotePropertyValue $assemblyFullName
        $o | Add-Member -NotePropertyName AssemblyFullNameMD5 -NotePropertyValue `
        (Get-FileHash -Algorithm MD5 -InputStream ([System.IO.MemoryStream]::New([System.Text.Encoding]::ASCII.GetBytes($assemblyFullName)))).hash
        $o | Add-Member -NotePropertyName AssemblyFullNameSHA1 -NotePropertyValue `
        (Get-FileHash -Algorithm SHA1 -InputStream ([System.IO.MemoryStream]::New([System.Text.Encoding]::ASCII.GetBytes($assemblyFullName)))).hash
        
			
        $o | Add-Member -NotePropertyName AssemblyName -NotePropertyValue $assemblyGetName.Name
        $o | Add-Member -NotePropertyName AssemblyVersion -NotePropertyValue $assemblyGetName.Version.ToString()
        $o | Add-Member -NotePropertyName AssemblyProcessorArchitecture -NotePropertyValue $assemblyGetName.ProcessorArchitecture.ToString()
        $o | Add-Member -NotePropertyName AssemblyImageRuntimeVersion -NotePropertyValue $assembly.ImageRuntimeVersion
        $o | Add-Member -NotePropertyName ReferencedAssemblies -NotePropertyValue (New-Object System.Collections.Generic.List[string])
        Foreach ($asm in $assembly.GetReferencedAssemblies()) {
            $asmFullname = $asm.ToString().ToLower()
            $assemblySYSTEM = $asmFullname.StartsWith("mscorlib,".ToLower())
            $assemblySYSTEM = $assemblySYSTEM -or $asmFullname.StartsWith("WindowsBase,".ToLower())
            $assemblySYSTEM = $assemblySYSTEM -or $asmFullname.StartsWith("System,".ToLower())
            $assemblySYSTEM = $assemblySYSTEM -or $asmFullname.StartsWith("System.".ToLower())
            if ($assemblySYSTEM -eq $false) {
                $o.ReferencedAssemblies.Add($asm.FullName.ToString())
            }
        }
    }
    catch {
        $ignore = $_.ToString().Contains("Could not load file or assembly 'ChilkatDotNet4, Version=9.5.0.73, Culture=neutral")
        $ignore = $ignore -or $_.ToString().Contains("bytes loaded from Anonymously Hosted DynamicMethods Assembly")
        if ($ignore) { }
        else {
            Write-Host $o.OriginalFilename
            Write-Host $_
        }
    }
    return $o
}
function Format-Json([Parameter(Mandatory, ValueFromPipeline)][String]$json) {
    #https://github.com/PowerShell/PowerShell/issues/2736
    $indent = 0;
	($json -Split '\n' |
    % {
        if ($_ -match '[\}\]]') {
            # This line contains  ] or }, decrement the indentation level
            $indent--
        }
        $line = (' ' * $indent * 2) + $_.TrimStart().Replace(':  ', ': ')
        if ($_ -match '[\{\[]') {
            # This line contains [ or {, increment the indentation level
            $indent++
        }
        $line
    }) -Join "`n"
}

if ($options.IsLibrary -eq $True) {
    $deploy_libraries = (Join-Path -Path ([System.IO.Path]::GetDirectoryName($PSScriptRoot)) -ChildPath $options.Library.SourceDirectoryName)
    if ([System.IO.Directory]::Exists($deploy_libraries )) {
        $deploy_libraries = Join-Path -Path $deploy_libraries -ChildPath "*"
        $files = get-childitem -Path ($deploy_libraries) -Include $options.Library.SourceExtentsionFile
        foreach ($file in $files) {
            $checkFilename = ($options.Library.IsFileNames -eq $false) -or `
            (($options.Library.IsFileNames -eq $True) -and $options.Library.FileNames.Contains($file.Name))
            if ($checkFilename -eq $true) {
                $lib = GetLibraryFile -pathLibrary $file.FullName
                [System.IO.File]::WriteAllText($file.FullName + $options.Library.OutputExtentsionFile, `
                    ($lib | ConvertTo-Json | Format-Json), (New-Object System.Text.UTF8Encoding $false))
                Write-Host ($lib.OriginalFilename + $options.Library.OutputExtentsionFile, ";", $lib.AssemblyFullName)
            }
        }
    }
}
if ($options.IsGitCommitExecute) {
    if ($options.GitCommitExecute.ExcludeComputerNames.Contains($env:computername) -eq $false) {
        git --version
        git config user.name "bot-actions@github.com"
        git config user.email "bot-actions@github.com"
        $remoteUrl = ("https://x-access-token:" + $secrets.CONFIG.github_token + "@github.com/" + $options.GithubInfo.OwnerSplashRepository)
        git remote set-url origin $remoteUrl
        git config --global core.safecrlf false
        # git pull --tags origin main
        git add --all
        git commit -m "bot-actions@github.com"
        git push origin
    }
}