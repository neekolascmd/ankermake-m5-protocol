# -*- mode: python ; coding: utf-8 -*-
#
# PyInstaller spec for the ankerctl server embedded in the macOS app.
#
# Unlike ankerctl.spec (a single-file console executable), this builds a
# one-folder distribution: it starts much faster because nothing has to be
# unpacked to a temporary directory on every launch, and it can be code
# signed as part of the app bundle. Build it with macos/build-app.sh.

import os

root = os.path.abspath(os.path.join(SPECPATH, '..'))


def src(path):
    return os.path.join(root, path)


a = Analysis(
    [src('ankerctl.py')],
    pathex=[root],
    binaries=[],
    datas=[(src(d), d) for d in ('static', 'ssl')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='ankerctl',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name='ankerctl',
)
