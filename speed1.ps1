param (
    [Parameter(Mandatory = $false, HelpMessage = "Path to save results (default: temp folder)")]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$ResultsPath = $env:TEMP
)

$BaseUrl = "https://www.speedtest.net/apps/cli"
$speedTestAppName = "ookla-speedtest-1.2.0-win64"


try {
    $downloadUrl = (Invoke-WebRequest $BaseUrl).Links | Where-Object { $_.href -like "*$speedTestAppName.zip*" } | Select-Object -First 1 -ExpandProperty href
    $ZipPath = Join-Path $ResultsPath ($downloadUrl.Split("/")[-1])
    $ExtractFolder = Join-Path $ResultsPath $speedTestAppName

	Write-Output "Downloading and extracting speedtest, to run on both adapters..."
    Invoke-WebRequest $downloadUrl -OutFile $ZipPath
    Expand-Archive $ZipPath $ExtractFolder -Force
}
catch {
    Write-Error "Failed to download or extract Speedtest CLI: $_"
    exit 1
}


function Run-SpeedTest {
    param([string]$AdapterName)

    Write-Output "Testing $AdapterName..."
    $SpeedTestExe = Join-Path $ExtractFolder "speedtest.exe"

    $adapter = Get-NetAdapter | Where-Object {$_.Name -eq $AdapterName }
    if($adapter) {
        $IP = ($adapter | Get-NetIPAddress -AddressFamily IPv4).IPAddress
    }

    if (-not $IP) {
        Write-Error "Interface '$AdapterName' not found or no IP address."
        return $null
    }

    try {
        $result = & $SpeedTestExe --ip $IP --accept-license --accept-gdpr 2>$null 
        $download = ([regex] "Download:\s+(\d+\.?\d+) Mbps").Match($result).Groups[1].Value
        $upload = ([regex] "Upload:\s+(\d+\.?\d+) Mbps").Match($result).Groups[1].Value

        return [PSCustomObject]@{
            Adapter = $AdapterName
            Download = [decimal]$download
            Upload = [decimal]$upload
        }
    }
    catch {
        Write-Warning "Speedtest failed for '$AdapterName': $_"
        return $null
    }
}

function Compare-ConnectionSpeeds {

    $EthernetName = (Get-NetAdapter | Where-Object { $_.Name -like "Ethernet" }).Name
    $WiFiName = (Get-NetAdapter | Where-Object { $_.Name -like "wifi" }).Name
    
    $EthernetResults = Run-SpeedTest -AdapterName $EthernetName
    $WiFiResults = Run-SpeedTest -AdapterName $WiFiName

    if ($EthernetResults -and $WiFiResults) {
        "Ethernet Results:"
        $EthernetResults | Format-Table
        "Wi-Fi Results:"
        $WiFiResults | Format-Table
    } else {
        Write-Error "Unable to obtain speed results for one or both interfaces."
    }
}
try {
   
    Compare-ConnectionSpeeds 
} catch {
    Write-Error "An error occurred: $_"
} finally {
    Remove-Item $ZipFilePath, $ExtractFolder -Recurse -Force -ErrorAction SilentlyContinue
}