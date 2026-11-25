# Cartrest for Windows

Cartrest for Windows is a native WPF application built with C# and .NET 10. The x64 setup runs per user on Windows 11 and bundles the runtime. It creates a Start menu shortcut and registers Cartrest in **Settings → Apps → Installed apps**. Custom profiles live under `%LOCALAPPDATA%\Cartrest\Consoles`.

## Build and run

Use the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) on Windows. From the repository root, run the app or check geometry, print dimensions, and label composition.

```powershell
dotnet run --project windows/Cartrest.Windows
dotnet run --project windows/Cartrest.Checks -c Release -- .
```

## Build the installer

Install [NSIS](https://nsis.sourceforge.io/Download) and Python 3.11 or later. Give the packaging script the path to `makensis.exe` if it lives outside `PATH`.

```powershell
python windows/package.py --makensis "${env:ProgramFiles(x86)}\NSIS\makensis.exe"
```

The installer and its SHA-256 file go to `dist/windows/`. The self-contained publish stages the app, resource catalog, artwork examples, and dependency notices. The setup script records its staged files in the uninstaller, so unlinking the app preserves imported profiles and other user files. Run the installer checks on a clean Windows test account.

```powershell
./windows/test-install.ps1
```

## Source layout

| Path | Contents |
| --- | --- |
| `Cartrest.Windows/` | WPF window, native controls, cutting mat, and rotatable viewport |
| `Cartrest.Core/` | Profile decoding, mesh generation, A4 layout, and label rendering |
| `Cartrest.Checks/` | Scaling, STL topology, print dimensions, and label catalog checks |
| `installer/` | NSIS pages, icon, and installer artwork |

The Windows build reads [console JSON](../consoles/), [label assets](../design/labels/), and [artwork examples](../examples/) from the repository root. For a starter profile, see [Contributing](../CONTRIBUTING.md). The Windows and macOS binaries have separate source, build, and packaging paths.
