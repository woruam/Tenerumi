param([string]$KeytoolPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$keyDirectory = Join-Path $projectRoot 'android/keystore'
$storePath = Join-Path $keyDirectory 'osi-production.jks'
$certificatePath = Join-Path $keyDirectory 'osi-production.cer'
$propertiesPath = Join-Path $projectRoot 'android/key.properties'
if (Test-Path -LiteralPath $propertiesPath) {
    Write-Output 'Configurazione già presente: la chiave esistente viene conservata.'
    return
}
if (Test-Path -LiteralPath $storePath) {
    throw 'Keystore già presente senza configurazione: recuperare le credenziali originali. Non verrà sostituito.'
}
if (-not $KeytoolPath) {
    $keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
    if ($keytoolCommand) { $KeytoolPath = $keytoolCommand.Source }
    elseif ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin/keytool.exe'))) {
        $KeytoolPath = Join-Path $env:JAVA_HOME 'bin/keytool.exe'
    } else {
        $KeytoolPath = 'C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe'
    }
}
if (-not (Test-Path -LiteralPath $KeytoolPath)) {
    throw 'keytool non trovato. Installare un JDK o fornire -KeytoolPath con il percorso del programma.'
}
if ($env:OS -ne 'Windows_NT') { throw 'Usare questo script su Windows: applica i permessi privati tramite ACL.' }

New-Item -ItemType Directory -Path $keyDirectory -Force | Out-Null
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
function Set-PrivatePermissions([string]$path, [bool]$directory) {
    $permission = if ($directory) { '(OI)(CI)F' } else { 'F' }
    & icacls.exe $path /inheritance:r /grant:r "${identity}:$permission" '*S-1-5-18:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Impossibile proteggere i file di firma: operazione interrotta.' }
}
Set-PrivatePermissions $keyDirectory $true
function Invoke-PrivateKeytool([string[]]$toolArguments) {
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5 treats keytool's stderr diagnostics as errors,
        # even when key generation succeeds. Check the actual process exit code.
        $ErrorActionPreference = 'Continue'
        $capturedOutput = & $KeytoolPath @toolArguments 2>&1
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
}
$passwordBytes = New-Object byte[] 32
$random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $random.GetBytes($passwordBytes) } finally { $random.Dispose() }
$password = [Convert]::ToBase64String($passwordBytes)
$previousPassword = $env:OSIPP_KEYTOOL_PASSWORD
try {
    # The password is never included in process arguments or console output.
    $env:OSIPP_KEYTOOL_PASSWORD = $password
    $generationExit = Invoke-PrivateKeytool -toolArguments @('-genkeypair','-keystore',$storePath,'-storetype','JKS','-alias','osi','-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=OSI','-storepass:env','OSIPP_KEYTOOL_PASSWORD','-keypass:env','OSIPP_KEYTOOL_PASSWORD')
    if ($generationExit -ne 0) { throw 'Generazione del keystore non riuscita. Nessuna chiave esistente è stata sostituita.' }
    # Persist credentials before exporting the certificate, so an export failure
    # cannot leave a newly generated key without its password.
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $properties = "storeFile=../keystore/osi-production.jks`nstorePassword=$password`nkeyAlias=osi`nkeyPassword=$password`n"
    [System.IO.File]::WriteAllText($propertiesPath, '', $utf8)
    Set-PrivatePermissions $propertiesPath $false
    [System.IO.File]::WriteAllText($propertiesPath, $properties, $utf8)
    $exportExit = Invoke-PrivateKeytool -toolArguments @('-exportcert','-keystore',$storePath,'-alias','osi','-file',$certificatePath,'-storepass:env','OSIPP_KEYTOOL_PASSWORD')
    if ($exportExit -ne 0) { throw 'Chiave e password conservate; esportazione certificato fallita. Completare certSha256 prima della build.' }
    $fingerprint = (Get-FileHash -LiteralPath $certificatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::AppendAllText($propertiesPath, "certSha256=$fingerprint`n", $utf8)
    Write-Output 'Firma configurata. Conservare insieme android/keystore e android/key.properties in una copia sicura fuori dal repository.'
} finally {
    $env:OSIPP_KEYTOOL_PASSWORD = $previousPassword
    [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
    $password = $null
}
