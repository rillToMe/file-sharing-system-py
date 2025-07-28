# =============================
# TransferPy.ps1 
# =============================

# === KONFIGURASI DASAR ===
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$servePath = "$scriptRoot\__TEMP__"
$uploadPath = "$scriptRoot\uploads"
$cacheDir = "$scriptRoot\cache"
$cacheFile = "$cacheDir\pw_cache.txt"
$flagForget = "$servePath\__FORGET_FLAG.txt"
$systemFolder = "$scriptRoot\System"
$logPath = "$scriptRoot\Logs"
$port = 8888

# === CEK PYTHON ===
$pythonExe = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonExe) {
    Write-Host "❌ Python tidak ditemukan. Pastikan sudah terinstall dan masuk PATH." -ForegroundColor Red
    exit
}
$pythonExe = $pythonExe.Source

# === CEK DEPENDENSI ===
$requirementsFile = "$scriptRoot\requirements.txt"
if (-not (Test-Path $requirementsFile)) {
    Write-Host "⚠️ File requirements.txt tidak ditemukan. Buat file ini dengan isi:" -ForegroundColor Yellow
    Write-Host "watchdog" -ForegroundColor Yellow
    Write-Host "qrcode" -ForegroundColor Yellow
    Write-Host "Lalu instal dengan: `pip install -r requirements.txt`" -ForegroundColor Yellow
} else {
    try {
        & $pythonExe -m pip install -r $requirementsFile -q
        Write-Host "✅ Dependensi terinstal dari requirements.txt." -ForegroundColor Green
    } catch {
        Write-Host "❌ Gagal instal dependensi. Pastikan pip terinstall dan coba: `pip install -r requirements.txt`" -ForegroundColor Red
    }


# === CEK IP ===
$ip = (Get-NetIPAddress -AddressFamily IPv4 `
    | Where-Object { $_.InterfaceAlias -like "Wi-Fi*" -and $_.IPAddress -like "10.*" } `
    | Select-Object -ExpandProperty IPAddress)

if (-not $ip) {
    Write-Host "❌ IP tidak ditemukan. Pastikan hotspot aktif." -ForegroundColor Red
    exit
}

# === CEK PASSWORD ===
if (Test-Path $cacheFile) {
    $pw = (Get-Content $cacheFile -Raw).Trim()  # Tambah Trim biar aman dari whitespace
    Write-Host "🔐 Password ditemukan di cache: $pw" -ForegroundColor Yellow
} else {
    $pw = Read-Host "🔐 Masukkan password akses"
    $pw = $pw.Trim()  # Trim input user
    if ([string]::IsNullOrWhiteSpace($pw)) {
        Write-Host "❌ Password tidak boleh kosong." -ForegroundColor Red
        exit
    }
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Set-Content $cacheFile $pw -Encoding UTF8
    Write-Host "✅ Password disimpan di: $cacheFile" -ForegroundColor Green
}

# === BERSIHKAN DAN BUAT ULANG FOLDER __TEMP__ ===
if (Test-Path $servePath) {
    try {
        Stop-Process -Name "python" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2  # Kasih waktu lebih buat pastiin proses mati
        Remove-Item -Recurse -Force $servePath -ErrorAction Stop
    } catch {
        Write-Host "⚠️ Gagal hapus folder, mencoba lagi..." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        try {
            Remove-Item -Recurse -Force $servePath -ErrorAction Stop
        } catch {
            Write-Host "❌ Gagal hapus folder __TEMP__. Tutup aplikasi lain yang mungkin mengunci folder." -ForegroundColor Red
            exit
        }
    }
}
New-Item -ItemType Directory -Path $servePath -Force | Out-Null

# === BUAT FOLDER UPLOADS DAN LOGS JIKA BELUM ADA ===
if (-not (Test-Path $uploadPath)) {
    New-Item -ItemType Directory -Path $uploadPath -Force | Out-Null
    Write-Host "📂 Folder uploads dibuat di: $uploadPath" -ForegroundColor Green
}
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    Write-Host "📂 Folder logs dibuat di: $logPath" -ForegroundColor Green
}

# === SALIN HTML/CSS/JS/SERVER KE __TEMP__ DAN LOGS ===
$files = @("index.html", "files.html", "forget.html", "style.css", "script.js", "server.py")
foreach ($f in $files) {
    $sourceFile = "$systemFolder\$f"
    if (-not (Test-Path $sourceFile)) {
        Write-Host "❌ File $f tidak ditemukan di folder System." -ForegroundColor Red
        exit
    }
    Copy-Item $sourceFile "$servePath\$f" -Force
    Copy-Item $sourceFile "$logPath\$f" -Force
}

# === MASUKKAN PASSWORD KE script.js ===
Write-Host "🔍 Mencoba update script.js di: $servePath\script.js" -ForegroundColor Cyan
$jsContent = Get-Content "$servePath\script.js" -Raw
$jsContent = $jsContent -replace "\{PASSWORD\}", $pw  # Gak perlu Regex::Escape, replacement itu literal
try {
    Set-Content "$servePath\script.js" $jsContent -Encoding UTF8 -ErrorAction Stop
    Write-Host "✅ script.js berhasil diupdate" -ForegroundColor Green
    # Debug: Cek apakah replacement beneran jalan
    $updatedJsContent = Get-Content "$servePath\script.js" -Raw
    if ($updatedJsContent -match "\{PASSWORD\}") {
        Write-Host "❌ {PASSWORD} masih ada di script.js, gagal replace!" -ForegroundColor Red
    } else {
        Write-Host "✅ {PASSWORD} berhasil diganti jadi $pw di script.js" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Gagal update script.js: $_" -ForegroundColor Red
    exit
}

# === BUAT LIST FILE DARI FOLDER UPLOADS DENGAN PREVIEW ===
function Update-FileList {
    $body = "<ul>"
    Get-ChildItem -Path $uploadPath | ForEach-Object {
        if ($_.PSIsContainer) {
            $body += "<li><a href='/download_folder/$($_.Name)' download>$($_.Name).zip</a> (Folder)</li>"
        } else {
            $ext = $_.Extension.ToLower()
            $fileUrl = "/uploads/$($_.Name)"
            Write-Host "Processing file: $($_.Name), full path: $uploadPath\$($_.Name), ext: $ext, url: $fileUrl" -ForegroundColor Cyan
            if ($ext -in @(".png", ".jpg", ".jpeg", ".gif")) {
                Write-Host "Adding image preview for $fileUrl" -ForegroundColor Green
                $body += "<li><img src='$fileUrl' class='preview' alt='$($_.Name)'><br><a href='$fileUrl' download>$($_.Name)</a> (Gambar)</li>"
            } elseif ($ext -in @(".mp4", ".webm", ".ogg")) {
                $videoType = "video/" + $ext.Replace(".", "")
                $body += "<li><video controls class='video-preview'><source src='$fileUrl' type='$videoType'>Browser kamu gak support video ini.</video><br><a href='$fileUrl' download>$($_.Name)</a> (Video)</li>"
            } else {
                $body += "<li><a href='$fileUrl' download>$($_.Name)</a></li>"
            }
        }
    }
    $body += "</ul>"
    $htmlFileList = Get-Content "$servePath\files.html" -Raw
    $htmlFileList = $htmlFileList -replace "\{FILELIST\}", $body
    Set-Content "$servePath\files.html" $htmlFileList -Encoding UTF8
}

# Panggil pertama kali
Update-FileList

# === QR CODE ===
$url = "http://$ip`:$port"
$qrTemp = "$env:TEMP\qr_temp.py"
$qrScript = @"
import qrcode
img = qrcode.make('$url')
print('🔗 Link: $url')
img.show()
"@
Set-Content -Path $qrTemp -Value $qrScript -Encoding UTF8
Start-Process $pythonExe -ArgumentList "`"$qrTemp`"" -NoNewWindow

# === START SERVER ===
$serverJob = Start-Job -ScriptBlock {
    param($servePath, $pythonExe)
    Set-Location -Path $servePath
    & $pythonExe server.py
} -ArgumentList $servePath, $pythonExe

# Cek apakah server job gagal
Start-Sleep -Seconds 2
if ($serverJob.State -eq "Failed") {
    Write-Host "❌ Gagal menjalankan server. Error: $($serverJob.ChildJobs[0].Error)" -ForegroundColor Red
    Stop-Job -Job $serverJob
    Remove-Job -Job $serverJob
    exit
}

Write-Host "`n🚀 Server berjalan di: http://${ip}:${port}" -ForegroundColor Green
Write-Host "🔗 Akses lokal juga: http://127.0.0.1:${port}" -ForegroundColor Green
Write-Host "📂 Taruh file untuk di-download di: $uploadPath" -ForegroundColor Green
Write-Host "📝 Jalankan manual: cd $logPath; python server.py untuk debug" -ForegroundColor Green
Write-Host "ℹ️ Ubah path custom di $uploadPath\config.txt jika perlu" -ForegroundColor Green
Write-Host "ℹ️ Instal dependensi: `pip install -r requirements.txt` jika belum" -ForegroundColor Green

# === MONITOR FOLDER UPLOADS ===
$watchJob = Start-Job -ScriptBlock {
    param($uploadPath, $servePath)
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $uploadPath
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::DirectoryName

    Register-ObjectEvent $watcher "Created" -Action {
        Write-Host "🔄 File baru terdeteksi: $Event.SourceEventArgs.FullPath" -ForegroundColor Cyan
        Update-FileList
        Write-Host "🔄 Daftar file diperbarui!" -ForegroundColor Cyan
    }
    Register-ObjectEvent $watcher "Deleted" -Action {
        Write-Host "🔄 File dihapus: $Event.SourceEventArgs.FullPath" -ForegroundColor Cyan
        Update-FileList
        Write-Host "🔄 Daftar file diperbarui!" -ForegroundColor Cyan
    }
    Register-ObjectEvent $watcher "Renamed" -Action {
        Write-Host "🔄 File diganti nama: $Event.SourceEventArgs.FullPath" -ForegroundColor Cyan
        Update-FileList
        Write-Host "🔄 Daftar file diperbarui!" -ForegroundColor Cyan
    }

    while ($true) { Start-Sleep -Seconds 1 }
} -ArgumentList $uploadPath, $servePath
# === MONITOR FOR RESET FLAG ===
Start-Job -ScriptBlock {
    param($flagPath, $cacheFile)
    while ($true) {
        Start-Sleep -Seconds 2
        if (Test-Path $flagPath) {
            Remove-Item $flagPath -Force -ErrorAction SilentlyContinue
            Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
            Write-Host "`n🔁 Password di-reset. Silakan restart skrip." -ForegroundColor Cyan
            break
        }
    }
} -ArgumentList $flagForget, $cacheFile | Out-Null

# === TUNGGU USER DAN TAMPILKAN MENU ===
do {
    $choice = Read-Host "`nTekan [ENTER] untuk hentikan server, atau ketik 'help' untuk lihat menu:"
    if ($choice -eq "help") {
        Write-Host "=== Menu ===" -ForegroundColor Cyan
        Write-Host "1. debug save - Simpan folder __TEMP__ untuk debug" -ForegroundColor Cyan
        Write-Host "2. restart server - Restart server tanpa hentikan skrip" -ForegroundColor Cyan
        Write-Host "3. clear cache - Hapus file cache password" -ForegroundColor Cyan
        Write-Host "Ketik nomor pilihan atau 'help' lagi untuk ulang, [ENTER] untuk keluar" -ForegroundColor Cyan
        $menuChoice = Read-Host "Pilih opsi (1-3):"
        switch ($menuChoice) {
            "1" {
                Write-Host "✅ Folder __TEMP__ disimpan untuk debug di: $servePath" -ForegroundColor Green
            }
            "2" {
                Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
                Remove-Job -Job $serverJob -ErrorAction SilentlyContinue
                Stop-Process -Name "python" -ErrorAction SilentlyContinue
                $serverJob = Start-Job -ScriptBlock {
                    param($servePath, $pythonExe)
                    Set-Location -Path $servePath
                    & $pythonExe server.py
                } -ArgumentList $servePath, $pythonExe
                Start-Sleep -Seconds 2
                if ($serverJob.State -eq "Running") {
                    Write-Host "✅ Server berhasil di-restart" -ForegroundColor Green
                } else {
                    Write-Host "❌ Gagal restart server" -ForegroundColor Red
                }
            }
            "3" {
                if (Test-Path $cacheFile) {
                    Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
                    Write-Host "✅ Cache password dihapus dari: $cacheFile" -ForegroundColor Green
                } else {
                    Write-Host "⚠️ Cache tidak ditemukan" -ForegroundColor Yellow
                }
                $pw = Read-Host "🔐 Masukkan password akses baru"
                $pw = $pw.Trim()
                if ([string]::IsNullOrWhiteSpace($pw)) {
                    Write-Host "❌ Password tidak boleh kosong." -ForegroundColor Red
                } else {
                    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                    Set-Content $cacheFile $pw -Encoding UTF8
                    Write-Host "✅ Password baru disimpan di: $cacheFile" -ForegroundColor Green
                    if (Test-Path $servePath) {
                        $jsContent = Get-Content "$servePath\script.js" -Raw -ErrorAction SilentlyContinue
                        if ($jsContent) {
                            $jsContent = $jsContent -replace "\{PASSWORD\}", $pw
                            Set-Content "$servePath\script.js" $jsContent -Encoding UTF8
                            Write-Host "✅ Password di-update di script.js" -ForegroundColor Green
                        } else {
                            Write-Host "⚠️ Gagal baca script.js, cek folder __TEMP__" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "⚠️ Folder __TEMP__ tidak ditemukan, coba restart skrip" -ForegroundColor Yellow
                    }
                }
            }
            default {
                Write-Host "⚠️ Pilihan tidak valid, coba lagi" -ForegroundColor Yellow
            }
        }
    }
} while ($choice -eq "help")

if ($choice -ne "help") {
    Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
    Remove-Job -Job $serverJob -ErrorAction SilentlyContinue
    Stop-Job -Job $watchJob -ErrorAction SilentlyContinue
    Remove-Job -Job $watchJob -ErrorAction SilentlyContinue
    Stop-Process -Name "python" -ErrorAction SilentlyContinue
    Remove-Item $servePath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $qrTemp -Force -ErrorAction SilentlyContinue
    Write-Host "`n✅ Server dimatikan & folder __TEMP__ dibersihkan." -ForegroundColor Green
    Write-Host "📂 Folder uploads ($uploadPath) tetap aman." -ForegroundColor Green
}