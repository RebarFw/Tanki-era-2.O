$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClientRoot = Join-Path $Root "local_client"
$CacheRoot = Join-Path $ClientRoot "cache"
$PidPath = Join-Path $Root "local_proxy.pid"
$LogPath = Join-Path $Root "local_proxy.log"
$Port = 8765

New-Item -ItemType Directory -Force -Path $ClientRoot | Out-Null
New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null

$Upstreams = @(
    "https://s.pro-tanki.com",
    "http://s.pro-tanki.com",
    "https://tankiresources.com",
    "http://tankiresources.com",
    "http://146.59.110.103",
    "http://194.67.196.216"
)

$LocalBase = "http://127.0.0.1:8765"
$HostStrings = @(
    "http://146.59.110.103",
    "http://194.67.196.216",
    "http://s.pro-tanki.com",
    "https://s.pro-tanki.com",
    "http://tankiresources.com",
    "https://tankiresources.com"
)

$CoreNames = @(
    "prelauncher.swf",
    "loader.swf",
    "library.swf",
    "config.xml"
)

$StrictLocalNames = @(
    "prelauncher.swf",
    "loader.swf",
    "library.swf",
    "config.xml",
    "hardware.swf",
    "localized.data_en"
)

function Write-ProxyLog {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Timestamp] $Message"
    Write-Host $Line
    Add-Content -Encoding UTF8 -Path $LogPath -Value $Line
}

function Expand-CwsToFws {
    param([byte[]]$Data)

    $Signature = [Text.Encoding]::ASCII.GetString($Data, 0, 3)

    if ($Signature -eq "FWS") {
        return $Data
    }

    if ($Signature -ne "CWS") {
        return $Data
    }

    if ($Data.Length -lt 15) {
        return $Data
    }

    # CWS uses a zlib wrapper: two-byte header, raw deflate data, four-byte Adler32.
    $CompressedLength = $Data.Length - 14
    $CompressedStream = New-Object IO.MemoryStream
    $CompressedStream.Write($Data, 10, $CompressedLength)
    $CompressedStream.Position = 0

    $Output = New-Object IO.MemoryStream
    $Deflate = New-Object IO.Compression.DeflateStream(
        $CompressedStream,
        [IO.Compression.CompressionMode]::Decompress
    )

    try {
        $Deflate.CopyTo($Output)
    }
    finally {
        $Deflate.Dispose()
        $CompressedStream.Dispose()
    }

    $Body = $Output.ToArray()
    $Output.Dispose()

    $Result = New-Object byte[] (8 + $Body.Length)
    $Result[0] = [byte][char]'F'
    $Result[1] = [byte][char]'W'
    $Result[2] = [byte][char]'S'
    $Result[3] = $Data[3]

    $LengthBytes = [BitConverter]::GetBytes($Result.Length)
    [Array]::Copy($LengthBytes, 0, $Result, 4, 4)
    [Array]::Copy($Body, 0, $Result, 8, $Body.Length)

    return $Result
}

function Convert-ToLocalSwf {
    param([byte[]]$Data)

    if ($Data.Length -lt 8) {
        return $Data
    }

    $Expanded = Expand-CwsToFws $Data
    $Signature = [Text.Encoding]::ASCII.GetString($Expanded, 0, 3)

    if ($Signature -notin @("FWS", "CWS")) {
        return $Data
    }

    $Latin1 = [Text.Encoding]::GetEncoding(28591)
    $Text = $Latin1.GetString($Expanded)
    $Changed = $false

    foreach ($HostString in $HostStrings) {
        $Replacement = $LocalBase + ("/" * ($HostString.Length - $LocalBase.Length))
        if ($Text.Contains($HostString)) {
            $Text = $Text.Replace($HostString, $Replacement)
            $Changed = $true
        }
    }

    if (!$Changed) {
        return $Expanded
    }

    $Patched = $Latin1.GetBytes($Text)

    if ($Patched.Length -ge 8) {
        $LengthBytes = [BitConverter]::GetBytes($Patched.Length)
        [Array]::Copy($LengthBytes, 0, $Patched, 4, 4)
    }

    return $Patched
}

function Get-ContentType {
    param([string]$Path)

    switch -Regex ($Path.ToLowerInvariant()) {
        "\.swf$"  { return "application/x-shockwave-flash" }
        "\.xml$"  { return "application/xml" }
        "\.json$" { return "application/json" }
        "\.png$"  { return "image/png" }
        "\.jpg$"  { return "image/jpeg" }
        "\.jpeg$" { return "image/jpeg" }
        "\.gif$"  { return "image/gif" }
        "\.mp3$"  { return "audio/mpeg" }
        default   { return "application/octet-stream" }
    }
}

function Send-Response {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$Status,
        [string]$Reason,
        [byte[]]$Body,
        [string]$ContentType,
        [bool]$SendBody
    )

    $Header =
        "HTTP/1.1 $Status $Reason`r`n" +
        "Content-Type: $ContentType`r`n" +
        "Content-Length: $($Body.Length)`r`n" +
        "Connection: close`r`n" +
        "Access-Control-Allow-Origin: *`r`n" +
        "Cache-Control: no-cache, no-store, must-revalidate`r`n`r`n"

    $HeaderBytes = [Text.Encoding]::ASCII.GetBytes($Header)
    $Stream.Write($HeaderBytes, 0, $HeaderBytes.Length)

    if ($SendBody -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
}

function Download-Upstream {
    param(
        [string]$CleanPath,
        [string]$Query
    )

    $LastError = $null

    foreach ($Base in $Upstreams) {
        $Url = $Base.TrimEnd("/") + $CleanPath
        if ($Query) {
            $Url += "?" + $Query
        }

        try {
            $Client = New-Object Net.WebClient
            $Client.Headers["User-Agent"] = "Mozilla/5.0 ProTanki-Local-Client"
            $Client.Headers["Cache-Control"] = "no-cache"

            $Bytes = $Client.DownloadData($Url)

            if ($Bytes.Length -gt 0) {
                return @{
                    Bytes = $Bytes
                    Url = $Url
                }
            }
        }
        catch {
            $LastError = $_.Exception.Message
        }
        finally {
            if ($Client) {
                $Client.Dispose()
            }
        }
    }

    throw "Every source failed for $CleanPath. Last error: $LastError"
}

$Listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)

try {
    $Listener.Start()
}
catch {
    Write-ProxyLog "Could not bind to port $Port. Another local server may already be running."
    exit 1
}

$PID | Set-Content -Encoding ASCII $PidPath
Write-ProxyLog "Local file server started at http://127.0.0.1:$Port"

try {
    while ($true) {
        $TcpClient = $Listener.AcceptTcpClient()
        $Reader = $null
        $Stream = $null

        try {
            $Stream = $TcpClient.GetStream()
            $Reader = New-Object IO.StreamReader(
                $Stream,
                [Text.Encoding]::ASCII,
                $false,
                8192,
                $true
            )

            $RequestLine = $Reader.ReadLine()
            if (!$RequestLine) {
                continue
            }

            while (($HeaderLine = $Reader.ReadLine()) -ne "") {
                if ($null -eq $HeaderLine) {
                    break
                }
            }

            $Parts = $RequestLine.Split(" ")
            if ($Parts.Count -lt 2) {
                continue
            }

            $Method = $Parts[0].ToUpperInvariant()
            $Target = $Parts[1]
            $SendBody = ($Method -ne "HEAD")

            if ($Method -notin @("GET", "HEAD")) {
                $ErrorBody = [Text.Encoding]::UTF8.GetBytes("Method not allowed")
                Send-Response $Stream 405 "Method Not Allowed" $ErrorBody "text/plain" $SendBody
                continue
            }

            $TargetParts = $Target.Split("?", 2)
            $RawPath = $TargetParts[0]
            $Query = ""
            if ($TargetParts.Count -gt 1) {
                $Query = $TargetParts[1]
            }

            # URLs were padded with extra "/" characters to preserve SWF string lengths.
            $CleanPath = "/" + $RawPath.TrimStart("/")
            $Relative = [Uri]::UnescapeDataString($CleanPath.TrimStart("/"))
            $Relative = $Relative.Replace("/", [IO.Path]::DirectorySeparatorChar)

            if (!$Relative -or $Relative.Contains("..")) {
                $ErrorBody = [Text.Encoding]::UTF8.GetBytes("Forbidden")
                Send-Response $Stream 403 "Forbidden" $ErrorBody "text/plain" $SendBody
                continue
            }

            if ($CleanPath -eq "/crossdomain.xml") {
                $Policy = '<?xml version="1.0"?><cross-domain-policy><allow-access-from domain="*" secure="false"/></cross-domain-policy>'
                $Body = [Text.Encoding]::UTF8.GetBytes($Policy)
                Send-Response $Stream 200 "OK" $Body "application/xml" $SendBody
                continue
            }

            $Leaf = [IO.Path]::GetFileName($Relative)
            $LeafLower = $Leaf.ToLowerInvariant()
            $IsCore = $CoreNames -contains $LeafLower
            $IsStrictLocal = $StrictLocalNames -contains $LeafLower

            if ($IsCore) {
                $LocalPath = Join-Path $ClientRoot $Leaf
            }
            else {
                $LocalPath = Join-Path $CacheRoot $Relative

                $RootOverridePath = Join-Path $ClientRoot $Leaf
                if ($IsStrictLocal -and (Test-Path $RootOverridePath -PathType Leaf)) {
                    $LocalPath = $RootOverridePath
                }
            }

            if (Test-Path $LocalPath -PathType Leaf) {
                $Body = [IO.File]::ReadAllBytes($LocalPath)
                $SourceLabel = "local"
            }
            else {
                if ($IsStrictLocal) {
                    $Message = "Strict local file missing: $LocalPath"
                    $ErrorBody = [Text.Encoding]::UTF8.GetBytes($Message)
                    Send-Response $Stream 404 "Not Found" $ErrorBody "text/plain" $SendBody
                    Write-ProxyLog "$Method $CleanPath -> MISSING LOCAL ($LocalPath)"
                    continue
                }

                $Result = Download-Upstream $CleanPath $Query
                $RawBody = [byte[]]$Result.Bytes
                $Body = $RawBody
                $SourceLabel = $Result.Url

                if ($Leaf.ToLowerInvariant().EndsWith(".swf")) {
                    $Body = Convert-ToLocalSwf $RawBody
                }

                $Directory = Split-Path -Parent $LocalPath
                New-Item -ItemType Directory -Force -Path $Directory | Out-Null

                if ($IsCore) {
                    if ($Leaf.ToLowerInvariant().EndsWith(".swf")) {
                        $OriginalPath = Join-Path $ClientRoot (
                            [IO.Path]::GetFileNameWithoutExtension($Leaf) + ".original.swf"
                        )
                    }
                    else {
                        $OriginalPath = Join-Path $ClientRoot "config.original.xml"
                    }

                    if (!(Test-Path $OriginalPath)) {
                        [IO.File]::WriteAllBytes($OriginalPath, $RawBody)
                    }
                }

                [IO.File]::WriteAllBytes($LocalPath, $Body)
            }

            $ContentType = Get-ContentType $CleanPath
            Send-Response $Stream 200 "OK" $Body $ContentType $SendBody
            Write-ProxyLog "$Method $CleanPath -> $SourceLabel ($($Body.Length) bytes)"
        }
        catch {
            $Message = $_.Exception.Message

            if ($Message -like "*forcibly closed by the remote host*" -or
                $Message -like "*Unable to write data to the transport connection*") {
                Write-ProxyLog "Client disconnected during request"
                continue
            }

            Write-ProxyLog "Request failed: $Message"

            try {
                $ErrorBody = [Text.Encoding]::UTF8.GetBytes($Message)
                Send-Response $Stream 502 "Bad Gateway" $ErrorBody "text/plain" $true
            }
            catch {}
        }
        finally {
            if ($Reader) {
                $Reader.Dispose()
            }

            if ($Stream) {
                $Stream.Dispose()
            }

            if ($TcpClient) {
                $TcpClient.Close()
            }
        }
    }
}
finally {
    $Listener.Stop()
    Remove-Item -Force -ErrorAction SilentlyContinue $PidPath
}
