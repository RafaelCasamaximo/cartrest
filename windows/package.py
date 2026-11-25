#!/usr/bin/env python3
"""Publish a self-contained x64 build and package the staged files with NSIS."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from xml.etree import ElementTree


WINDOWS = Path(__file__).resolve().parent
PROJECT = WINDOWS / "Cartrest.Windows" / "Cartrest.Windows.csproj"
RID = "win-x64"


def copy_notices(destination):
    assets = json.loads((PROJECT.parent / "obj" / "project.assets.json").read_text(encoding="utf-8"))
    packages = [Path(folder) for folder in assets["packageFolders"]]
    dependencies = next(iter(assets["project"]["frameworks"].values()))["downloadDependencies"]
    versions = {
        entry["name"].lower(): entry["version"].strip("[]").split(",")[0]
        for entry in dependencies
    }
    for package in assets["libraries"]:
        name, version = package.lower().rsplit("/", 1)
        versions[name] = version

    notices = {
        ("microsoft.netcore.app.runtime.win-x64", "LICENSE.TXT"): "dotnet-license.txt",
        ("microsoft.netcore.app.runtime.win-x64", "THIRD-PARTY-NOTICES.TXT"): "dotnet-third-party-notices.txt",
        ("microsoft.windowsdesktop.app.runtime.win-x64", "LICENSE"): "dotnet-windowsdesktop-license.txt",
        ("skiasharp", "LICENSE.txt"): "skiasharp-license.txt",
    }
    destination.mkdir()
    for (package, filename), target in notices.items():
        found = next((root / package / versions[package] / filename for root in packages
                      if (root / package / versions[package] / filename).is_file()), None)
        if found is None:
            raise FileNotFoundError(f"Missing {filename} from {package}")
        shutil.copyfile(found, destination / target)


def installer_name():
    root = ElementTree.parse(WINDOWS / "Directory.Build.props")
    version = root.findtext("./PropertyGroup/Version")
    if not version:
        raise ValueError("The Windows build version is missing")
    return version, f"Cartrest-{version}-Windows-x64-Setup.exe"


def nsis_path(path):
    return str(path).replace("$", "$$").replace('"', '$\\"')


def uninstall_manifest(stage, destination):
    files = sorted(path for path in stage.rglob("*") if path.is_file())
    directories = sorted((path for path in stage.rglob("*") if path.is_dir()),
                         key=lambda path: (-len(path.parts), path.as_posix()))
    commands = [
        f'    Delete "$INSTDIR\\{nsis_path(path.relative_to(stage).as_posix().replace("/", chr(92)))}"\n'
        for path in files
    ]
    commands += [
        f'    RMDir "$INSTDIR\\{nsis_path(path.relative_to(stage).as_posix().replace("/", chr(92)))}"\n'
        for path in directories
    ]
    destination.write_text("".join(commands), encoding="utf-8-sig")
    return (sum(path.stat().st_size for path in files) + 1023) // 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dotnet", default="dotnet")
    parser.add_argument("--makensis", default="makensis")
    parser.add_argument("--out", type=Path, default=WINDOWS.parent / "dist" / "windows")
    args = parser.parse_args()

    version, name = installer_name()
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    setup = output / name
    with tempfile.TemporaryDirectory(prefix="cartrest-windows-") as temporary:
        scratch = Path(temporary)
        stage = scratch / "stage"
        subprocess.run([
            args.dotnet, "publish", str(PROJECT), "-c", "Release", "-r", RID,
            "--self-contained", "true", "-p:PublishSingleFile=true",
            "-p:IncludeNativeLibrariesForSelfExtract=true", "-p:EnableCompressionInSingleFile=true",
            "-p:DebugType=None", "-p:DebugSymbols=false", "-o", str(stage),
        ], check=True)
        for symbol in stage.rglob("*.pdb"):
            symbol.unlink()
        copy_notices(stage / "Notices")
        manifest = scratch / "uninstall.nsh"
        size = uninstall_manifest(stage, manifest)
        define = "/D" if sys.platform == "win32" else "-D"
        target = scratch / name
        subprocess.run([
            args.makensis,
            f"{define}VERSION={version}", f"{define}PAYLOAD={stage}", f"{define}SETUP={target}",
            f"{define}UNINSTALL_FILES={manifest}", f"{define}SIZE_KIB={size}", "Cartrest.nsi"
        ], cwd=WINDOWS / "installer", check=True)
        shutil.copyfile(target, setup)

    with setup.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    setup.with_suffix(".exe.sha256").write_text(f"{digest}  {name}\n", encoding="ascii")
    print(setup)


if __name__ == "__main__":
    main()
