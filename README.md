# ProTanki update files

Upload this folder to a GitHub repo. The player launcher reads:

```text
https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/update_manifest.txt
```

## Update library.swf

1. Replace `files/local_client/library.swf`.
2. Run:

```powershell
powershell -ExecutionPolicy Bypass -File tools\Build-Manifest.ps1
```

3. Upload/commit both `files/local_client/library.swf` and `update_manifest.txt`.

The next time players open `ProTanki Launcher.exe`, it downloads the changed file.

Only upload files you have permission to distribute.
