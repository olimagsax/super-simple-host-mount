# Super Simple Host Mount

Super Simple Host Mount is a tiny macOS menu bar app that mounts SSH servers as Finder volumes (via sshfs on FUSE-T).
Click a server in the menu bar to connect or disconnect it; it appears in Finder under `~/mnt/<name>`.

## Requirements
- macOS, Xcode command line tools (`xcode-select --install`)
- FUSE-T and sshfs (run in Terminal.app, they need sudo):
  ```
  brew install --cask macos-fuse-t/homebrew-cask/fuse-t
  brew install --cask macos-fuse-t/homebrew-cask/fuse-t-sshfs
  ```

## Install
```
./build.sh
```
This builds `~/Applications/SSH Mounts.app` and creates `~/.config/ssh-mounts/servers.json`.

## Servers
Edit `~/.config/ssh-mounts/servers.json` (menu: Edit servers…, then Reload servers):
```json
[
  { "name": "my-vps", "host": "user@203.0.113.10", "path": "/var/www" }
]
```
`host` is anything ssh understands (an alias from `~/.ssh/config` or `user@host`); `path` is optional.

## Key login (one time)
The app can't answer prompts, so each server needs passwordless login. In the app, open a server's
submenu and click "Set up key login…", or by hand:
```
ssh-add --apple-use-keychain ~/.ssh/id_rsa      # store key passphrase in the Keychain
ssh-copy-id -i ~/.ssh/id_rsa.pub user@host      # install the key on the server
```

## Two networks, one name
To pick an address by network, use an ssh alias:
```
Host my-server
  AddKeysToAgent yes
  UseKeychain yes
Match host my-server exec "/usr/bin/nc -z -G 1 192.168.1.10 22 >/dev/null 2>&1"
  HostName 192.168.1.10
Match host my-server
  HostName my.public.host
```
Then use `"host": "my-server"` in `servers.json`.

## Notes
- sshfs mounts don't follow network changes: disconnect and reconnect.
- Nothing personal is stored in this repo; hosts live in your own `~/.ssh/config` and `servers.json`.

## License

Public domain ([Unlicense](LICENSE)): do whatever you want with it.
