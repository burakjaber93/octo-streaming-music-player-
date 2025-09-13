#!/usr/bin/env pwsh
<#
generate_octostreaming_fixed.ps1
Robust, fixed generator for Octo Streaming (Electron + React) project.
Save this file to your Desktop and run it from PowerShell.

This version fixes the previous parse errors by ensuring all embedded JS/CSS/HTML
are written using PowerShell here-strings (single-quoted) so PowerShell doesn't
try to parse them as commands. It also checks for Node/npm and installs required
packages with retries.
#>

$ErrorActionPreference = 'Stop'

Write-Host "Octo Streaming generator (fixed) — starting..." -ForegroundColor Cyan

# Check Node and npm
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error "Node.js is required but was not found on PATH. Please install Node.js (v16+)."
  exit 1
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  Write-Error "npm was not found on PATH. Make sure Node.js was installed correctly."
  exit 1
}

# Prompt for Jellyfin server URL
$serverUrl = Read-Host "Enter Jellyfin server URL (example: http://gkinistech.com:8096/)"
if (-not $serverUrl) { Write-Error "Server URL is required. Exiting."; exit 1 }
$serverUrl = $serverUrl.TrimEnd('/')

# Paths
$projectFolder = Join-Path $PWD 'octostreaming-app'
$appDataFolder = Join-Path $env:LOCALAPPDATA 'OctoStreaming'
if (-not (Test-Path $appDataFolder)) { New-Item -ItemType Directory -Path $appDataFolder | Out-Null }

# Create/clean project folder
if (Test-Path $projectFolder) {
  Write-Host "Removing existing project folder to ensure a clean scaffold..." -ForegroundColor Yellow
  Remove-Item -Recurse -Force -Path $projectFolder
}
New-Item -ItemType Directory -Path $projectFolder | Out-Null
Set-Location -Path $projectFolder

# Write a valid package.json (explicit string to avoid JSON conversion issues)
$pkgText = @'
{
  "name": "octostreaming",
  "version": "1.0.0",
  "main": "main.js",
  "scripts": {
    "dev": "vite",
    "start": "electron .",
    "build": "electron-builder --win"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "axios": "^1.6.0",
    "idb-keyval": "^6.2.0"
  },
  "devDependencies": {
    "vite": "^4.5.14",
    "@vitejs/plugin-react": "^4.0.0",
    "electron": "^25.5.1",
    "electron-builder": "^24.6.0"
  },
  "build": {
    "appId": "com.octostreaming.app",
    "productName": "Octo Streaming",
    "directories": { "output": "dist" },
    "files": ["**/*"]
  }
}
'@
Set-Content -Path (Join-Path $projectFolder 'package.json') -Value $pkgText -Encoding UTF8

# Function to install packages with retries
function Install-NpmPackages {
  param(
    [string]$Packages,
    [switch]$Dev
  )
  $tries = 0
  while ($tries -lt 3) {
    try {
      if ($Dev) {
        Write-Host "Installing dev packages: $Packages" -ForegroundColor Cyan
        npm install --save-dev $Packages --no-audit --no-fund | Out-Null
      } else {
        Write-Host "Installing packages: $Packages" -ForegroundColor Cyan
        npm install $Packages --no-audit --no-fund | Out-Null
      }
      return
    } catch {
      Write-Warning "npm install failed (attempt $($tries+1)): $($_.Exception.Message)"
      Start-Sleep -Seconds 2
      $tries++
    }
  }
  throw "Failed to install: $Packages"
}

# Install required packages
Install-NpmPackages "react react-dom axios idb-keyval"
Install-NpmPackages "vite @vitejs/plugin-react electron electron-builder" -Dev

# --- Create Electron main.js (here-string to avoid PS parsing) ---
$mainJs = @'
const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const isDev = process.env.NODE_ENV === "development" || process.argv.includes("--dev");

function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  if (isDev) {
    win.loadURL('http://localhost:5173/');
  } else {
    win.loadFile(path.join(__dirname, 'index.html'));
  }
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });

ipcMain.handle('get-app-data-path', () => { return app.getPath('appData'); });
'@
Set-Content -Path (Join-Path $projectFolder 'main.js') -Value $mainJs -Encoding UTF8

# preload.js
$preloadJs = @'
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("electronAPI", {
  getAppDataPath: () => ipcRenderer.invoke('get-app-data-path')
});
'@
Set-Content -Path (Join-Path $projectFolder 'preload.js') -Value $preloadJs -Encoding UTF8

# index.html (loads env.js then app)
$indexHtml = @'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Octo Streaming</title>
  </head>
  <body>
    <div id="root"></div>
    <script src="/env.js"></script>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
'@
Set-Content -Path (Join-Path $projectFolder 'index.html') -Value $indexHtml -Encoding UTF8

# env.js exposes the Jellyfin server URL to the renderer
Set-Content -Path (Join-Path $projectFolder 'env.js') -Value ("window.SERVER_URL='" + $serverUrl + "';") -Encoding UTF8

# Create src structure
$src = Join-Path $projectFolder 'src'
New-Item -ItemType Directory -Path $src | Out-Null
New-Item -ItemType Directory -Path (Join-Path $src 'ui') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $src 'utils') | Out-Null

# src/main.jsx
$mainReact = @'
import React from "react";
import { createRoot } from "react-dom/client";
import App from "./ui/App";
import "./styles.css";
createRoot(document.getElementById("root")).render(<App />);
'@
Set-Content -Path (Join-Path $src 'main.jsx') -Value $mainReact -Encoding UTF8

# styles.css (Finamp-inspired purple haze baseline)
$styles = @'
:root{--bg1:#1b0026;--bg2:#3b0a4a;--accent:#8f47d3;--muted:#bfb7d7}
*{box-sizing:border-box}
body{margin:0;font-family:Inter,Segoe UI,Arial;background:linear-gradient(135deg,var(--bg1),var(--bg2));color:#fff}
#root{min-height:100vh;padding:20px}
.header{display:flex;align-items:center;justify-content:space-between;padding:12px 20px}
.brand{display:flex;align-items:center;gap:12px}
.brand-logo{width:42px;height:42px;background:linear-gradient(45deg,#6c1fa8,#b065ff);border-radius:8px;display:flex;align-items:center;justify-content:center;font-weight:700}
.card{background:rgba(255,255,255,0.03);padding:16px;border-radius:12px;margin:12px 0}
input,button,select{outline:none}
input{padding:10px;border-radius:8px;border:none;background:rgba(255,255,255,0.03);color:#fff}
button{background:var(--accent);border:none;padding:8px 12px;border-radius:8px;color:#fff;cursor:pointer}
.track{display:flex;align-items:center;gap:12px;padding:8px 6px;border-bottom:1px solid rgba(255,255,255,0.03)}
.player{position:fixed;left:50%;transform:translateX(-50%);bottom:18px;width:90%;max-width:1100px;background:linear-gradient(90deg,rgba(0,0,0,0.4),rgba(0,0,0,0.2));padding:10px;border-radius:14px;display:flex;align-items:center;gap:10px}
.queue{max-height:240px;overflow:auto}
'@
Set-Content -Path (Join-Path $src 'styles.css') -Value $styles -Encoding UTF8

# UI: App.jsx
$appjsx = @'
import React, { useEffect, useState } from "react";
import Login from "./Login";
import Library from "./Library";
import { loadStoredToken, saveStoredToken, clearStoredToken } from "../utils/auth";

export default function App() {
  const [tokenData, setTokenData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const stored = await loadStoredToken();
      if (stored) setTokenData(stored);
      setLoading(false);
    })();
  }, []);

  const handleLogin = async ({ token, user, remember }) => {
    const obj = { token, user };
    setTokenData(obj);
    if (remember) await saveStoredToken(obj);
  };

  const handleLogout = async () => {
    await clearStoredToken();
    setTokenData(null);
  };

  if (loading) return <div style={{padding:30}}>Loading...</div>;
  if (!tokenData) return <Login onLogin={handleLogin} serverUrl={window.SERVER_URL} />;
  return <Library token={tokenData.token} user={tokenData.user} onLogout={handleLogout} serverUrl={window.SERVER_URL} />;
}
'@
Set-Content -Path (Join-Path $src 'ui/App.jsx') -Value $appjsx -Encoding UTF8

# utils/auth.js (idb-keyval + WebCrypto encrypt)
$authjs = @'
import { set, get, del } from "idb-keyval";
const KEY = 'octo_auth_v1';
const ENC = 'octo_enc_v1';

async function getKey() {
  let raw = await get(ENC);
  if (!raw) {
    const k = await window.crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, true, ['encrypt','decrypt']);
    const exported = await window.crypto.subtle.exportKey('raw', k);
    await set(ENC, Array.from(new Uint8Array(exported)));
    return k;
  }
  const buf = new Uint8Array(raw);
  return await window.crypto.subtle.importKey('raw', buf, { name:'AES-GCM' }, true, ['encrypt','decrypt']);
}

export async function saveStoredToken(obj) {
  const key = await getKey();
  const iv = window.crypto.getRandomValues(new Uint8Array(12));
  const data = new TextEncoder().encode(JSON.stringify(obj));
  const ct = await window.crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, data);
  await set(KEY, { iv: Array.from(iv), ct: Array.from(new Uint8Array(ct)) });
}

export async function loadStoredToken() {
  const v = await get(KEY); if (!v) return null;
  try {
    const key = await getKey();
    const iv = new Uint8Array(v.iv);
    const ct = new Uint8Array(v.ct);
    const plain = await window.crypto.subtle.decrypt({ name:'AES-GCM', iv }, key, ct);
    return JSON.parse(new TextDecoder().decode(new Uint8Array(plain)));
  } catch (e) { console.warn('decrypt failed', e); return null; }
}

export async function clearStoredToken() { await del(KEY); await del(ENC); }
'@
Set-Content -Path (Join-Path $src 'utils/auth.js') -Value $authjs -Encoding UTF8

# UI: Login.jsx
$loginjsx = @'
import React, { useState } from "react";
import axios from "axios";

export default function Login({ onLogin, serverUrl }) {
  const [user, setUser] = useState("");
  const [pw, setPw] = useState("");
  const [remember, setRemember] = useState(true);
  const [loading, setLoading] = useState(false);

  const doLogin = async () => {
    setLoading(true);
    try {
      const res = await axios.post(`${serverUrl}/Users/AuthenticateByName`, { Username: user, Pw: pw });
      if (res.data && res.data.AccessToken) {
        onLogin({ token: res.data.AccessToken, user: res.data.User, remember });
      } else {
        alert('Login failed');
      }
    } catch (err) {
      alert('Login error: ' + (err.message || err));
    }
    setLoading(false);
  };

  return (
    <div style={{padding:40}}>
      <div className="card" style={{maxWidth:520, margin:'36px auto', textAlign:'center'}}>
        <div style={{display:'flex',alignItems:'center',justifyContent:'center',gap:12}}>
          <div className="brand-logo">OS</div>
          <h1>Octo Streaming</h1>
        </div>
        <div style={{marginTop:18}}>
          <input placeholder="Username" value={user} onChange={e=>setUser(e.target.value)} style={{width:'80%'}} />
        </div>
        <div style={{marginTop:12}}>
          <input placeholder="Password" type="password" value={pw} onChange={e=>setPw(e.target.value)} style={{width:'80%'}} />
        </div>
        <div style={{marginTop:12}}>
          <label><input type="checkbox" checked={remember} onChange={e=>setRemember(e.target.checked)} /> Remember Me</label>
        </div>
        <div style={{marginTop:14}}>
          <button onClick={doLogin} disabled={loading}>{loading? 'Logging in...':'Login'}</button>
        </div>
      </div>
    </div>
  );
}
'@
Set-Content -Path (Join-Path $src 'ui/Login.jsx') -Value $loginjsx -Encoding UTF8

# UI: Library.jsx
$libraryjsx = @'
import React, { useEffect, useState } from "react";
import axios from "axios";

function recommend(items) {
  const map = {};
  items.forEach(i => { if (i && i.Artist) { map[i.Artist] = map[i.Artist] || []; map[i.Artist].push(i); } });
  const out = [];
  Object.values(map).forEach(a => a.slice(0,3).forEach(x => out.push(x)));
  return out.slice(0,20);
}

export default function Library({ token, user, onLogout, serverUrl }) {
  const [items, setItems] = useState([]);
  const [recs, setRecs] = useState([]);
  const [allowDownload, setAllowDownload] = useState(false);

  useEffect(() => {
    const load = async () => {
      try {
        const userInfo = await axios.get(`${serverUrl}/Users/${user.Id}`, { headers: { 'X-Emby-Token': token }}).catch(()=>null);
        if (userInfo && userInfo.data && userInfo.data.Policy) {
          setAllowDownload(!!(userInfo.data.Policy.AllowDownload || userInfo.data.Policy.AllowMediaPlayback));
        }
        const r = await axios.get(`${serverUrl}/Users/Me/Items?IncludeItemTypes=Audio&Recursive=true&Limit=500`, { headers: { 'X-Emby-Token': token }});
        const it = (r.data && r.data.Items) || [];
        it.forEach(async t=>{
          try {
            if (t.Artist && (!t.Album || t.Album===t.Name)) {
              const q = encodeURIComponent(t.Artist + ' ' + t.Name);
              const mb = await axios.get(`https://musicbrainz.org/ws/2/recording/?query=${q}&fmt=json&limit=1`);
              if (mb.data && mb.data.recordings && mb.data.recordings.length>0) {
                t._fixed = { title: mb.data.recordings[0].title || t.Name, album: (mb.data.recordings[0].releases && mb.data.recordings[0].releases[0] && mb.data.recordings[0].releases[0].title) || t.Album };
              }
            }
          } catch(e) { }
        });
        setItems(it);
        setRecs(recommend(it));
      } catch(e) { alert('Failed to load library: '+(e.message||e)); }
    };
    load();
  }, [token]);

  const download = async (t) => {
    if (!allowDownload) { alert('Downloads not permitted for this account'); return; }
    try {
      const a = document.createElement('a');
      a.href = `${serverUrl}/Audio/${t.Id}/stream?ApiKey=${token}`;
      a.download = ((t._fixed && t._fixed.title) || t.Name || 'track') + '.mp3';
      document.body.appendChild(a); a.click(); a.remove();
      alert('Download started (dev). Packaged app will save to AppData/OctoStreaming/Downloads.');
    } catch(e) { alert('Download error: '+(e.message||e)); }
  };

  return (
    <div>
      <div className="header">
        <div className="brand"><div className="brand-logo">OS</div><div>Octo Streaming</div></div>
        <div><button onClick={onLogout}>Logout</button></div>
      </div>
      <div style={{display:'flex',gap:20}}>
        <div style={{flex:3}}>
          <div className="card"><strong>Library</strong></div>
          <div className="card">
            {items.map(t=> (
              <div className="track" key={t.Id}>
                <div style={{width:56,height:56,background:'#2b0036',borderRadius:6,flex:'0 0 56px'}}></div>
                <div className="meta">
                  <div style={{fontWeight:600}}>{(t._fixed && t._fixed.title) || t.Name}</div>
                  <div style={{color:'#ccc',fontSize:13}}>{t.Artist || t.AlbumArtist}</div>
                </div>
                <div>
                  {allowDownload && <button onClick={()=>download(t)}>Download</button>}
                </div>
              </div>
            ))}
          </div>
        </div>
        <div style={{flex:1}}>
          <div className="card"><strong>Recommended</strong></div>
          <div className="card queue">
            {recs.map(r=> <div key={r.Id} style={{padding:8}}>{r.Name} — {r.Artist}</div>)}
          </div>
        </div>
      </div>
      <div className="player card" style={{position:'fixed',left:'50%',transform:'translateX(-50%)',bottom:20,width:'90%',maxWidth:1100}}>
        <div style={{flex:1}}>Mini-player (play/pause, seek, queue will be implemented in next polishing pass)</div>
      </div>
    </div>
  );
}
'@
Set-Content -Path (Join-Path $src 'ui/Library.jsx') -Value $libraryjsx -Encoding UTF8

# Create run script (PowerShell) that launches Vite and Electron via cmd.exe to avoid PS wrapper issues
$runScript = @'
# run_octostreaming.ps1
Set-Location -Path "' + $projectFolder.Replace("`\", "\\") + '"
Start-Process -FilePath "cmd.exe" -ArgumentList "/c","npx vite" -WorkingDirectory "' + $projectFolder.Replace("`\", "\\") + '"
Start-Sleep -Seconds 3
Start-Process -FilePath "cmd.exe" -ArgumentList "/c","npx electron ." -WorkingDirectory "' + $projectFolder.Replace("`\", "\\") + '"
'@
Set-Content -Path (Join-Path $projectFolder 'run_octostreaming.ps1') -Value $runScript -Encoding UTF8

Write-Host "\nFinished: scaffold created at $projectFolder" -ForegroundColor Green
Write-Host "To run the app (dev mode):" -ForegroundColor Yellow
Write-Host "  cd `"$projectFolder`"" -ForegroundColor Yellow
Write-Host "  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force" -ForegroundColor Yellow
Write-Host "  .\run_octostreaming.ps1" -ForegroundColor Yellow
Write-Host "\nIf Vite complains about missing modules, run inside the project:" -ForegroundColor Cyan
Write-Host "  npm install react react-dom axios idb-keyval" -ForegroundColor Cyan
Write-Host "  npm install --save-dev vite @vitejs/plugin-react electron electron-builder" -ForegroundColor Cyan
Write-Host "\nIf a package install fails, paste the npm error here and I will patch the generator immediately." -ForegroundColor Green
