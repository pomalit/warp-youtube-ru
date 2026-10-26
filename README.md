# warp-youtube-ru

Make YouTube think you are in Russia, so it shows **no ads** and an ad blocker isn't needed (and there's nothing to slow you down for using one). Only YouTube is affected; the rest of your browsing stays on your normal connection.

## How it works

- Google stopped selling ads in Russia in 2022, so YouTube serves no ads to Russian IPs.
- Cloudflare WARP is a free VPN. From Estonia it exits through Cloudflare's Tallinn servers. Most of those addresses look Estonian to Google, but some (roughly 1 in 10) look Russian.
- The script keeps reconnecting WARP until YouTube says `RU`, then stops. The address stays Russian as long as WARP stays connected.
- WARP runs in **proxy mode**: it only opens a local port (`127.0.0.1:40000`) and doesn't touch the rest of your traffic. A browser extension sends just the YouTube domains through that port.

Tested from Estonia in October 2026: on a WARP `RU` address, 5 of 5 popular videos had no ads scheduled; on the normal Estonian connection, every one had 2.

## Setup

### 1. Install Cloudflare WARP

**Windows**

```
winget install Cloudflare.Warp
```

**Linux (Debian / Ubuntu / Mint)**

```
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt-get update && sudo apt-get install cloudflare-warp
sudo systemctl enable --now warp-svc
```

**Linux (Fedora / RHEL)**

```
curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | sudo tee /etc/yum.repos.d/cloudflare-warp.repo
sudo dnf install cloudflare-warp
sudo systemctl enable --now warp-svc
```

**Linux (Arch)**: `cloudflare-warp-bin` from the AUR, then `sudo systemctl enable --now warp-svc`.

Don't press "Connect" in the WARP app before running the script, or it will route your whole computer through WARP. The script switches it to proxy mode first.

### 2. Run the script

Running it the first time registers a free WARP account, which means you accept [Cloudflare's WARP terms](https://www.cloudflare.com/application/terms/).

**Windows** (in PowerShell, from the repo folder):

```
powershell -ExecutionPolicy Bypass -File windows\warp-ru.ps1 -Install
```

**Linux**:

```
chmod +x linux/warp-ru.sh
./linux/warp-ru.sh --install
```

On Windows, `-Install` adds a scheduled task that checks at login, 30 seconds after the PC wakes up, and every 10 minutes. It reconnects WARP only when YouTube no longer sees `RU`, and each check is one small (~3 KB) request. On Linux, `--install` runs the script at every login. Both also run it once right away. Expect around 5 to 40 reconnects before it gets `RU`. Leave out the flag to run it just once.

| | Windows | Linux |
|---|---|---|
| Reconnect until RU | `warp-ru.ps1` | `warp-ru.sh` |
| Only show current country | `warp-ru.ps1 -Check` | `warp-ru.sh --check` |
| Keep it RU automatically | `warp-ru.ps1 -Install` (login, wake, every 10 min) | `warp-ru.sh --install` (login only) |
| Stop the automatic runs | `warp-ru.ps1 -Uninstall` | `warp-ru.sh --uninstall` |
| Log | `%LOCALAPPDATA%\warp-ru\warp-ru.log` (one line per check) | `journalctl --user -u warp-ru` |

Both accept `-MaxTries N` / `--max-tries N` (default 40).

If you move the repo folder after `-Install`, run `-Install` again so the task points to the new location. If you installed the first version (a shortcut in the Startup folder), run `-Install` again too: it replaces the shortcut with the scheduled task.

### 3. Send YouTube through WARP in your browser

Works in Chrome, Edge, Brave and Firefox.

1. Install **Proxy SwitchyOmega 3 (ZeroOmega)**: [Chrome Web Store](https://chromewebstore.google.com/detail/pfnededegaaopdmhkdmcofjmoldfiped) / Firefox Add-ons (search "ZeroOmega"). Its support link should point to `github.com/zero-peak/ZeroOmega`. The old plain "Proxy SwitchyOmega" no longer works in Chrome, and other look-alikes may be fake.
2. Right-click its icon → **Options** → **Import/Export** → **Restore from file** → pick `browser/zeroomega-youtube-ru.bak`.
3. Click the ZeroOmega icon and choose **youtube-ru**.

Open youtube.com: a small **RU** should appear next to the YouTube logo.

## Troubleshooting

- **Ads are back / no RU next to the logo**: WARP reconnected and got an Estonian address. That happens after sleep or a network change, and sometimes on its own when WARP's tunnel drops. With `-Install` on Windows it fixes itself within 10 minutes; otherwise run the script again.
- **WARP keeps coming back on**: with `-Install` on Windows, the check reconnects WARP if you turn it off. Run `-Uninstall` to stop that.
- **"No RU address after 40 tries"**: try again later, or with `-MaxTries 80`. If it never works anymore, Google has probably updated its location data and the trick is dead.
- **YouTube doesn't load at all**: WARP isn't connected. Run the script with `-Check` / `--check`, or switch ZeroOmega to `[Direct]` for a moment.
- **Only YouTube is proxied**: the rule list is `*.youtube.com`, `*.googlevideo.com`, `*.ytimg.com`, `*.ggpht.com`, `youtu.be`, `*.youtube-nocookie.com`, `*.youtubei.googleapis.com`. Everything else goes direct.

## Caveats

- This depends on how Google happens to geolocate some Cloudflare addresses. It can stop working at any time.
- YouTube will think you're in Russia: Trending, some recommendations and region-locked videos follow from that.
- Faking your location may go against YouTube's terms of service. Use at your own risk.

## Uninstall

1. `warp-ru.ps1 -Uninstall` / `warp-ru.sh --uninstall`
2. Remove ZeroOmega (or switch it to `[Direct]`).
3. Uninstall Cloudflare WARP (`winget uninstall Cloudflare.Warp`, or your Linux package manager).
