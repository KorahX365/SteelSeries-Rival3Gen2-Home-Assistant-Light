# Server bridge GameSense <-> Home Assistant para SteelSeries Rival 3
$port = 5055

# 1. Comprobar si el SteelSeries Rival 3 Gen 2 está conectado físicamente
function Test-MouseConnected {
    $dev = Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE '%VID_1038&PID_1870%' AND Status = 'OK'" -ErrorAction SilentlyContinue | Select-Object -First 1
    return ($null -ne $dev)
}

# Al iniciar sesión con Windows, esperamos hasta 30s a que el ratón y los drivers estén listos
$count = 0
while (-not (Test-MouseConnected) -and $count -lt 6) {
    Start-Sleep -Seconds 5
    $count++
}

if (-not (Test-MouseConnected)) {
    Write-Host "SteelSeries Rival 3 no detectado. Saliendo..."
    exit 0
}

Write-Host "SteelSeries Rival 3 detectado OK." -ForegroundColor Green

# 2. Iniciar servidor HTTP
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:$port/")

try {
    $listener.Start()
    Write-Host "[OK] Servidor escuchando en http://*:$port/" -ForegroundColor Green
} catch {
    Write-Host "[AVISO] No se pudo vincular a http://*:$port/ comodín. Probando localhost..." -ForegroundColor Yellow
    $listener.Close()
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Prefixes.Add("http://127.0.0.1:$port/")
    $listener.Start()
}

function Get-GameSenseUrl {
    $corePropsPath = "$env:PROGRAMDATA\SteelSeries\SteelSeries Engine 3\coreProps.json"
    if (Test-Path $corePropsPath) {
        $props = Get-Content $corePropsPath -Raw | ConvertFrom-Json
        return "http://$($props.address)"
    }
    return $null
}

# Esperar a que SteelSeries Engine / GG esté levantado
$retries = 0
while (-not (Get-GameSenseUrl) -and $retries -lt 30) {
    Start-Sleep -Seconds 2
    $retries++
}

# 3. Registrar el juego y el evento GameSense
function Ensure-GameSenseRegistered {
    $url = Get-GameSenseUrl
    if (-not $url) { return }

    try {
        $meta = @{
            game = "HOMEASSISTANT"
            game_display_name = "Home Assistant"
            icon_color_id = 5
            deinitialize_timer_length_ms = 86400000
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "$url/game_metadata" -Method Post -Body $meta -ContentType "application/json" -TimeoutSec 2 | Out-Null

        $bind = @{
            game = "HOMEASSISTANT"
            event = "SET_COLOR"
            handlers = @(
                @{
                    "device-type" = "mouse"
                    "zone" = "logo"
                    "mode" = "context-color"
                    "context-frame-key" = "base_color"
                },
                @{
                    "device-type" = "mouse"
                    "zone" = "base"
                    "mode" = "context-color"
                    "context-frame-key" = "base_color"
                },
                @{
                    "device-type" = "rgb-3-zone"
                    "zone" = "one"
                    "mode" = "context-color"
                    "context-frame-key" = "base_color"
                },
                @{
                    "device-type" = "rgb-3-zone"
                    "zone" = "two"
                    "mode" = "context-color"
                    "context-frame-key" = "base_color"
                },
                @{
                    "device-type" = "rgb-3-zone"
                    "zone" = "three"
                    "mode" = "context-color"
                    "context-frame-key" = "base_color"
                }
            )
        } | ConvertTo-Json -Depth 5

        Invoke-RestMethod -Uri "$url/bind_game_event" -Method Post -Body $bind -ContentType "application/json" -TimeoutSec 2 | Out-Null
    } catch {}
}

Ensure-GameSenseRegistered

# Estado global sincronizado para el hilo
$sync = [hashtable]::Synchronized(@{
    r = 255
    g = 255
    b = 255
    active = $true
    running = $true
})

# 4. Hilo de Heartbeat en segundo plano (refresca cada 1.5s para evitar que vuelva a blanco)
$heartbeatScript = {
    param($state)
    while ($state.running) {
        Start-Sleep -Milliseconds 1500
        if ($state.active) {
            $corePropsPath = "$env:PROGRAMDATA\SteelSeries\SteelSeries Engine 3\coreProps.json"
            if (Test-Path $corePropsPath) {
                try {
                    $props = Get-Content $corePropsPath -Raw | ConvertFrom-Json
                    $url = "http://$($props.address)"

                    $hb = @{ game = "HOMEASSISTANT" } | ConvertTo-Json
                    Invoke-RestMethod -Uri "$url/game_heartbeat" -Method Post -Body $hb -ContentType "application/json" -TimeoutSec 1 | Out-Null

                    $eventData = @{
                        game = "HOMEASSISTANT"
                        event = "SET_COLOR"
                        data = @{
                            frame = @{
                                base_color = @{
                                    red = $state.r
                                    green = $state.g
                                    blue = $state.b
                                }
                            }
                        }
                    } | ConvertTo-Json -Depth 5

                    Invoke-RestMethod -Uri "$url/game_event" -Method Post -Body $eventData -ContentType "application/json" -TimeoutSec 1 | Out-Null
                } catch {}
            }
        }
    }
}

$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$powershell = [powershell]::Create()
$powershell.Runspace = $runspace
$powershell.AddScript($heartbeatScript).AddArgument($sync) | Out-Null
$asyncResult = $powershell.BeginInvoke()

# 5. Bucle del listener HTTP
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        if ($request.HttpMethod -eq "POST" -and $request.Url.LocalPath -eq "/set_color") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $bodyText = $reader.ReadToEnd()
            $reader.Close()

            $json = $bodyText | ConvertFrom-Json
            $r = [int]$json.r
            $g = [int]$json.g
            $b = [int]$json.b

            $sync.r = $r
            $sync.g = $g
            $sync.b = $b
            $sync.active = $true

            Write-Host "Home Assistant -> R:$r, G:$g, B:$b" -ForegroundColor Magenta

            $url = Get-GameSenseUrl
            if ($url) {
                $eventData = @{
                    game = "HOMEASSISTANT"
                    event = "SET_COLOR"
                    data = @{
                        frame = @{
                            base_color = @{
                                red = $r
                                green = $g
                                blue = $b
                            }
                        }
                    }
                } | ConvertTo-Json -Depth 5

                Invoke-RestMethod -Uri "$url/game_event" -Method Post -Body $eventData -ContentType "application/json" -TimeoutSec 2 | Out-Null
            }

            $respObj = @{ status = "ok"; r = $r; g = $g; b = $b } | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($respObj)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        } else {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("SteelSeries Rival 3 Home Assistant Bridge Running")
            $response.ContentType = "text/plain"
            $response.ContentLength64 = $msg.Length
            $response.OutputStream.Write($msg, 0, $msg.Length)
        }

        $response.OutputStream.Close()
    }
} finally {
    $sync.running = $false
    $listener.Stop()
    $runspace.Close()
}
