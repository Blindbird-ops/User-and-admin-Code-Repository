import os
import requests
from firebase_admin import db

LOGO_CACHE_FOLDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'logos_cache')

def ensure_logo_cache_folder():
    if not os.path.exists(LOGO_CACHE_FOLDER):
        os.makedirs(LOGO_CACHE_FOLDER)

def get_logo_paths():
    """
    Returns local paths to logos. 
    Downloads from Firebase if online, uses cache if offline.
    """
    ensure_logo_cache_folder()
    
    left_cache = os.path.join(LOGO_CACHE_FOLDER, 'logo_left.png')
    right_cache = os.path.join(LOGO_CACHE_FOLDER, 'logo_right.png')
    
    try:
        # Try to fetch fresh URLs from Firebase
        logos_ref = db.reference('org_chart/logos')
        logos_data = logos_ref.get()
        
        if logos_data:
            # Download left logo
            if logos_data.get('left'):
                _download_image(logos_data['left'], left_cache)
            
            # Download right logo
            if logos_data.get('right'):
                _download_image(logos_data['right'], right_cache)
                
    except Exception as e:
        print(f"⚠️ Could not fetch logos from Firebase (likely offline): {e}", flush=True)
        print("📂 Using cached logos if available...", flush=True)
    
    # Return paths (whether freshly downloaded or cached)
    return {
        'left': left_cache if os.path.exists(left_cache) else None,
        'right': right_cache if os.path.exists(right_cache) else None
    }

def _download_image(url, save_path):
    """Download image from URL to local path"""
    try:
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            with open(save_path, 'wb') as f:
                f.write(response.content)
            print(f"✅ Downloaded logo: {os.path.basename(save_path)}", flush=True)
            return True
    except Exception as e:
        print(f"❌ Failed to download logo: {e}", flush=True)
    return False