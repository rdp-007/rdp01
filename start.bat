name: WINDOWS LATEST RDP

on:
  workflow_dispatch:
    inputs:
      increment:
        type: string
        description: 'ngrok token'
        required: false
        default: ''

jobs:
  build:
    runs-on: windows-latest
    timeout-minutes: 9999

    steps:
      - name: 🔽 Checkout Repository
        uses: actions/actions/checkout@v4

      - name: 🔽 Download Ngrok
        run: |
          Invoke-WebRequest https://equinox.io -OutFile ngrok.zip

      - name: 📦 Extract Ngrok
        run: Expand-Archive ngrok.zip -DestinationPath .\ngrok_extracted

      - name: 🔐 Set Ngrok Authtoken
        shell: pwsh
        run: |
          $inputToken = '${{ github.event.inputs.increment }}'
          $envToken = $Env:NGROK_AUTH
          if ($inputToken) {
            $token = $inputToken
          } elseif ($envToken) {
            $token = $envToken
          } else {
            Write-Host "❌ No ngrok token provided! Please set NGROK_AUTH secret or provide it as input."
            exit 1
          }
          Write-Host "Using ngrok token: $($token.Substring(0,[Math]::Min(10,$token.Length)))***"
          
          $ngrokExe = (Get-ChildItem -Path .\ngrok_extracted -Filter ngrok.exe -Recurse | Select-Object -First 1).FullName
          & $ngrokExe config add-authtoken $token
        env:
          NGROK_AUTH: ${{ secrets.TAKEN }}

      - name: 🔧 Enable RDP & Configure Firewall
        run: |
          Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
          Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
          Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
          Copy-Item wallpaper.bat D:\a\wallpaper.bat -ErrorAction SilentlyContinue

      - name: 🚀 Start Ngrok Tunnel (Hidden Window)
        shell: pwsh
        run: |
          $ngrokExe = (Get-ChildItem -Path .\ngrok_extracted -Filter ngrok.exe -Recurse | Select-Object -First 1).FullName
          Start-Process -FilePath $ngrokExe -ArgumentList "tcp", "--region", "ap", "3389" -NoNewWindow

      - name: 🔎 Verify Ngrok process is running
        shell: pwsh
        run: |
          Start-Sleep -Seconds 3
          $proc = Get-Process -Name ngrok -ErrorAction SilentlyContinue
          if ($proc) {
            Write-Host "✅ Ngrok process is running (PID: $($proc.Id))"
          } else {
            Write-Host "❌ Ngrok process NOT found!"
            exit 1
          }

      - name: 🕐 Wait for Ngrok to Initialize
        shell: pwsh
        run: Start-Sleep -Seconds 20

      - name: ⚙️ Run Setup Script (start.bat) with NGROK URL + credentials
        shell: pwsh
        run: |
          $retries = 10
          $url = $null
          while ($retries -gt 0 -and -not $url) {
            try {
              $tunnels = Invoke-RestMethod -Uri 'http://localhost:4040/api/tunnels' -ErrorAction Stop
              if ($tunnels.tunnels.Count -gt 0) {
                $url = $tunnels.tunnels[0].public_url
              }
            } catch {}
            if (-not $url) { Start-Sleep -Seconds 3 }
            $retries--
          }

          if (-not $url) {
            Write-Host "❌ Could not fetch Ngrok URL. Check ngrok process and authtoken."
            exit 1
          }

          Write-Host "✅ Ngrok Public URL: $url"

          $escapedUrl = $url.Replace('"', '\"')
          $escapedUser = 'administrator'.Replace('"','\"')
          $escapedPass = 'OLDUSER#06'.Replace('"','\"')
          $osVersion = 'Latest'

          $cmd = ".\start.bat `"$escapedUrl`" `"$escapedUser`" `"$escapedPass`" `"$osVersion`""
          cmd.exe /c $cmd

      - name: 🌐 Debug Ngrok API response raw
        shell: pwsh
        run: curl.exe -s http://localhost:4040/api/tunnels | Write-Host

      - name: 🔁 Keep Runner Alive
        shell: pwsh
        run: .\loop.bat
