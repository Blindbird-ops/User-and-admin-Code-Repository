# helpers.py

import sys  # <--- THIS IS CRITICAL
import os   # <--- THIS IS CRITICAL
from firebase_admin import db

# ============================================================================
# PATH FIXER FOR EXE
# ============================================================================
def get_resource_path(relative_path):
    """ Get absolute path to resource, works for dev and for PyInstaller """
    try:
        # PyInstaller creates a temp folder and stores path in _MEIPASS
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")

    return os.path.join(base_path, relative_path)

# ============================================================================
# OTHER HELPERS
# ============================================================================

def get_ordinal_suffix(day):
    """Get ordinal suffix for day (1st, 2nd, 3rd, etc.)"""
    if day in [1, 21, 31]:
        return "st"
    elif day in [2, 22]:
        return "nd"
    elif day in [3, 23]:
        return "rd"
    else:
        return "th"

def safe_get(data, key, default=''):
    """Safely get value from dictionary with default"""
    value = data.get(key, default)
    if value is None or (isinstance(value, str) and not value.strip()):
        return default
    return value

def get_full_name(data):
    """Extract full name with fallback to user profile"""
    full_name = safe_get(data, 'fullName', '').strip()
    
    if full_name:
        return full_name
    
    # Fallback: Try to get from user profile using userId
    user_id = data.get('userId')
    if user_id:
        try:
            user_ref = db.reference(f'users/{user_id}')
            user_data = user_ref.get()
            
            if user_data and isinstance(user_data, dict):
                user_full_name = user_data.get('fullName', '').strip()
                if user_full_name:
                    return user_full_name
                
                title = user_data.get('title', '').strip()
                first = user_data.get('firstName', '').strip()
                middle = user_data.get('middleName', '').strip()
                last = user_data.get('lastName', '').strip()
                
                parts = [p for p in [title, first, middle, last] if p]
                if parts:
                    return ' '.join(parts)
        except Exception:
            pass
    
    return 'N/A'

def get_business_data(data):
    """Extract business data from nested structure"""
    business_details = data.get('businessDetails', {})
    
    business_name = business_details.get('businessName', safe_get(data, 'businessName', '_________________________'))
    operator_name = business_details.get('operator', safe_get(data, 'operatorName', '_________________________'))
    operator_address = business_details.get('operatorAddress', safe_get(data, 'operatorAddress', '_________________________'))
    
    business_address_obj = business_details.get('businessAddress', {})
    if business_address_obj and isinstance(business_address_obj, dict):
        street = business_address_obj.get('street', '')
        barangay = business_address_obj.get('barangay', '')
        municipality = business_address_obj.get('municipality', '')
        province = business_address_obj.get('province', '')
        address_parts = [part for part in [street, barangay, municipality, province] if part]
        business_address = ", ".join(address_parts) if address_parts else '_________________________'
    else:
        business_address = safe_get(data, 'businessAddress', '_________________________')
    
    return business_name, business_address, operator_name, operator_address