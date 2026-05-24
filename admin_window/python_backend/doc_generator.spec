# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['barangay_generation.py'],
    pathex=[],
    binaries=[],
    # =========================================================
    # 1. CRITICAL FIX: Include Assets and JSON Key
    # =========================================================
    datas=[
        ('fonts', 'fonts'), 
        ('logos_cache', 'logos_cache'),
        ('assets', 'assets'),             # <--- ADD THIS
        ('serviceAccountKey.json', '.')   # <--- ADD THIS
    ],
    hiddenimports=[
        'certifi',
        'urllib3',
        'requests',
        'google.auth',
        'google.auth.transport.requests',
        'firebase_admin',
        'docx',          # <--- Added for safety
        'docx.template', # <--- Added for safety
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='doc_generator',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True, # <--- Keep TRUE for debugging, change to False only when perfect
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)