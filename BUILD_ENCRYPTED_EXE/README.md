# SingBoxTunGui

Windows GUI controller for sing-box TUN mode. The app downloads required binaries, generates a sing-box configuration, starts/stops the TUN process, and manages DNS settings for the TUN adapter.

## Repository Layout

- `extracted_source/SingBoxTunGui.ps1` - main WinForms PowerShell application.
- `assets/SingBoxTunGui.ico` - application icon used by both the UI and compiled EXE.
- `build_encrypted_exe.ps1` - creates the encrypted launcher executable in `dist/`.
- `BUILD_ENCRYPTED_EXE.md` - build notes.
- `THIRD_PARTY_NOTICES.md` - attribution for third-party assets.

## Build

Run from PowerShell:

```powershell
.\build_encrypted_exe.ps1
```

The build creates:

- `dist/SingBoxTunGui.exe`
- `dist/SingBoxTunGui.exe.sha256`
- `dist/SingBoxTunGui_CodeSigning.cer`

`dist/` is kept in the repository as the ready-to-publish distribution folder. `build_encrypted/` is also kept so the generated loader source, manifest, and build icon are available in GitHub.

## Notes

The application writes runtime files such as logs, `sing-box.json`, and downloaded binaries locally at runtime. These files are ignored by Git.
