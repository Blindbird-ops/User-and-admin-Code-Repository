# config.py
import sys
import io
import os
import firebase_admin
from firebase_admin import credentials, db
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from helpers import get_resource_path 

# ============================================================================
# WINDOWS CONSOLE FIX
# ============================================================================
if sys.platform == 'win32' and sys.stdout is not None:
    try:
        if hasattr(sys.stdout, 'buffer'):
            sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
        if hasattr(sys.stderr, 'buffer'):
            sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
    except Exception:
        pass

# ============================================================================
# PATHS CONFIGURATION
# ============================================================================

# User's Documents folder
DOCUMENTS_FOLDER = os.path.join(os.path.expanduser('~'), 'Documents')
WORD_OUTPUT_FOLDER = os.path.join(DOCUMENTS_FOLDER, "word_generator_documents")
PDF_OUTPUT_FOLDER = os.path.join(DOCUMENTS_FOLDER, "pdf_generator_documents")

# Internal Assets (bundled inside EXE)
LOGO_LEFT_PATH = get_resource_path(os.path.join("assets", "taytay_logo.png"))
LOGO_RIGHT_PATH = get_resource_path(os.path.join("assets", "pularaquen_logo.png"))
FONT_PATH = get_resource_path(os.path.join("fonts", "times.ttf"))

FIREBASE_DATABASE_URL = 'https://mabskie-47c24-default-rtdb.firebaseio.com'

def create_folders():
    """Create necessary output folders"""
    for folder in [WORD_OUTPUT_FOLDER, PDF_OUTPUT_FOLDER]:
        if not os.path.exists(folder):
            os.makedirs(folder)
            print(f"✅ Created folder: {folder}")

def initialize_firebase():
    """Initialize Firebase Admin SDK"""
    try:
        # Use get_resource_path to find the key inside the EXE
        key_path = get_resource_path('serviceAccountKey.json')
        cred = credentials.Certificate(key_path)
        
        firebase_admin.initialize_app(cred, {
            'databaseURL': FIREBASE_DATABASE_URL
        })
        print("✅ Firebase initialized successfully")
        return True
    except Exception as e:
        print(f"❌ Firebase initialization error: {e}")
        return False

def register_fonts():
    """Register fonts for PDF generation"""
    try:
        if os.path.exists(FONT_PATH):
            pdfmetrics.registerFont(TTFont('TimesNewRoman', FONT_PATH))
            print("✅ Font registered for PDF generation")
        else:
            print("⚠️  Font file not found, using default font")
    except Exception as e:
        print(f"⚠️  Font registration warning: {e}")

def initialize_all():
    """Initialize all configurations"""
    print(f"📂 Output location: {DOCUMENTS_FOLDER}")
    create_folders()
    if not initialize_firebase():
        # Don't exit hard here, let the offline mode in main script handle it
        pass 
    register_fonts()