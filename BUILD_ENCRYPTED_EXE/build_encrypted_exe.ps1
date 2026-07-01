Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $root "extracted_source\SingBoxTunGui.ps1"
$buildDir = Join-Path $root "build_encrypted"
$distDir = Join-Path $root "dist"
$loaderCs = Join-Path $buildDir "SingBoxTunGui.Loader.cs"
$exePath = Join-Path $distDir "SingBoxTunGui.exe"
$iconPath = Join-Path $buildDir "SingBoxTunGui.ico"
$manifestPath = Join-Path $buildDir "SingBoxTunGui.exe.manifest"
$certPath = Join-Path $distDir "SingBoxTunGui_CodeSigning.cer"
$hashPath = "$exePath.sha256"
$certSubject = "CN=SingBoxTunGui Local Code Signing"

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source script not found: $source"
}

New-Item -ItemType Directory -Force -Path $buildDir, $distDir | Out-Null

function New-SingBoxTunGuiIcon {
    param([Parameter(Mandatory=$true)][string]$Path)

    Add-Type -AssemblyName System.Drawing

    $bitmap = New-Object System.Drawing.Bitmap 64, 64
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle 0, 0, 64, 64),
        [System.Drawing.Color]::FromArgb(23, 98, 132),
        [System.Drawing.Color]::FromArgb(39, 176, 117),
        45
    )
    $graphics.FillEllipse($bgBrush, 4, 4, 56, 56)

    $whitePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 5
    $whitePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $whitePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawArc($whitePen, 17, 18, 30, 28, 205, 250)

    $dotBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $graphics.FillEllipse($dotBrush, 29, 29, 7, 7)

    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
    $stream = [System.IO.File]::Create($Path)
    try {
        $icon.Save($stream)
    } finally {
        $stream.Dispose()
        $icon.Dispose()
        $dotBrush.Dispose()
        $whitePen.Dispose()
        $bgBrush.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-OrCreate-CodeSigningCertificate {
    param([Parameter(Mandatory=$true)][string]$Subject)

    $now = Get-Date
    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
        Where-Object { $_.Subject -eq $Subject -and $_.NotAfter -gt $now.AddDays(30) -and $_.HasPrivateKey } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    if ($cert) {
        return $cert
    }

    $cert = New-SelfSignedCertificate `
        -Subject $Subject `
        -Type CodeSigningCert `
        -CertStoreLocation Cert:\CurrentUser\My `
        -KeyAlgorithm RSA `
        -KeyLength 3072 `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature `
        -NotAfter $now.AddYears(3)

    $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
    $publisherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "CurrentUser")
    try {
        $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $rootStore.Add($cert)
        $publisherStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $publisherStore.Add($cert)
    } finally {
        $rootStore.Close()
        $publisherStore.Close()
    }

    $cert
}

function Write-Sha256File {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$OutputPath
    )

    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $FilePath
    $fileName = Split-Path -Leaf $FilePath
    $line = "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $fileName
    [System.IO.File]::WriteAllText($OutputPath, $line + [Environment]::NewLine, [System.Text.Encoding]::ASCII)
}

New-SingBoxTunGuiIcon -Path $iconPath

$manifest = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="1.0.0.0" processorArchitecture="*" name="SingBoxTunGui" type="win32" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
"@
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.Encoding]::UTF8)

$script = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)
$script = $script -replace '\$scriptDir\s*=\s*Split-Path -Parent \$MyInvocation\.MyCommand\.Path', '$scriptDir  = if ($env:SINGBOXTUNGUI_APPDIR) { $env:SINGBOXTUNGUI_APPDIR } else { Split-Path -Parent $MyInvocation.MyCommand.Path }'
$script = $script -replace '\$scriptDir\s*=\s*\$PSScriptRoot', '$scriptDir  = if ($env:SINGBOXTUNGUI_APPDIR) { $env:SINGBOXTUNGUI_APPDIR } else { $PSScriptRoot }'

$plainBytes = [System.Text.Encoding]::UTF8.GetBytes($script)
$aes = [System.Security.Cryptography.Aes]::Create()
$aes.KeySize = 256
$aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
$aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
$aes.GenerateKey()
$aes.GenerateIV()

$encryptor = $aes.CreateEncryptor()
$cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
$encryptor.Dispose()

$keyB64 = [Convert]::ToBase64String($aes.Key)
$ivB64 = [Convert]::ToBase64String($aes.IV)
$payloadB64 = [Convert]::ToBase64String($cipherBytes)

function Convert-ToChunks {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [int]$Size = 100
    )

    $chunks = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Text.Length; $i += $Size) {
        $len = [Math]::Min($Size, $Text.Length - $i)
        $chunks.Add($Text.Substring($i, $len))
    }
    $chunks
}

$payloadChunks = (Convert-ToChunks -Text $payloadB64 -Size 100) | ForEach-Object { '            "' + $_ + '"' }
$payloadLines = [string]::Join("," + [Environment]::NewLine, $payloadChunks)

$sourceCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

internal static class Program
{
    private const string KeyBase64 = "$keyB64";
    private const string IvBase64 = "$ivB64";

    [STAThread]
    private static int Main()
    {
        try
        {
            string script = DecryptScript();
            string appDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");

            string tempDir = Path.Combine(Path.GetTempPath(), "SingBoxTunGui");
            Directory.CreateDirectory(tempDir);
            string tempScript = Path.Combine(tempDir, "SingBoxTunGui.runtime.ps1");
            File.WriteAllText(tempScript, script, new UTF8Encoding(false));

            ProcessStartInfo info = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File \"" + tempScript + "\"",
                UseShellExecute = false,
                RedirectStandardInput = false,
                RedirectStandardOutput = false,
                RedirectStandardError = false,
                CreateNoWindow = false,
                WorkingDirectory = appDir
            };
            info.EnvironmentVariables["SINGBOXTUNGUI_APPDIR"] = appDir;
            info.EnvironmentVariables["SINGBOXTUNGUI_EXE"] = Application.ExecutablePath;

            using (Process process = Process.Start(info))
            {
                if (process == null)
                {
                    throw new InvalidOperationException("Unable to start Windows PowerShell.");
                }

                process.WaitForExit();
                try { File.Delete(tempScript); } catch { }
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.ToString(), "SingBoxTunGui launcher error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string DecryptScript()
    {
        byte[] key = Convert.FromBase64String(KeyBase64);
        byte[] iv = Convert.FromBase64String(IvBase64);
        byte[] encrypted = Convert.FromBase64String(GetPayload());

        using (Aes aes = Aes.Create())
        {
            aes.Key = key;
            aes.IV = iv;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;

            using (ICryptoTransform decryptor = aes.CreateDecryptor())
            {
                byte[] plain = decryptor.TransformFinalBlock(encrypted, 0, encrypted.Length);
                return Encoding.UTF8.GetString(plain);
            }
        }
    }

    private static string GetPayload()
    {
        string[] chunks = new string[]
        {
$payloadLines
        };
        return string.Concat(chunks);
    }
}
"@

[System.IO.File]::WriteAllText($loaderCs, $sourceCode, [System.Text.Encoding]::UTF8)

$cscCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) {
    throw "csc.exe not found."
}

& $csc /nologo /optimize+ /target:winexe /platform:anycpu /win32icon:$iconPath /win32manifest:$manifestPath /out:$exePath /reference:System.Windows.Forms.dll $loaderCs
if ($LASTEXITCODE -ne 0) {
    throw "C# compilation failed with exit code $LASTEXITCODE."
}

$cert = Get-OrCreate-CodeSigningCertificate -Subject $certSubject
Export-Certificate -Cert $cert -FilePath $certPath -Force | Out-Null

$signature = Set-AuthenticodeSignature -FilePath $exePath -Certificate $cert -HashAlgorithm SHA256
if ($signature.Status -ne "Valid") {
    throw "Authenticode signature failed or is not valid. Status: $($signature.Status). Message: $($signature.StatusMessage)"
}

Write-Sha256File -FilePath $exePath -OutputPath $hashPath

Write-Host "Created encrypted executable:"
Write-Host $exePath
Write-Host "Created SHA256 file:"
Write-Host $hashPath
Write-Host "Created and exported code-signing certificate:"
Write-Host $certPath
Write-Host "Signature status:"
Write-Host $signature.Status
