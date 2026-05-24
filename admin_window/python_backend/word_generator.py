# word_generator.py - Template-based document generation

import sys
import os
import json
import re
import uuid
from datetime import datetime
from firebase_admin import db 
from docxtpl import DocxTemplate, RichText # <--- ADDED RichText HERE

from helpers import get_resource_path, get_ordinal_suffix, safe_get, get_business_data, get_full_name

# ============================================================================
# CONFIGURATION: PERSISTENT VS BUNDLED PATHS
# ============================================================================

def get_persistent_template_dir():
    """Matches the persistent directory set in barangay_generation.py"""
    if getattr(sys, 'frozen', False):
        base_dir = os.path.expanduser('~/AppData/Local/BarangayApp')
    else:
        base_dir = os.path.dirname(os.path.abspath(__file__))
    
    template_dir = os.path.join(base_dir, 'templates')
    if not os.path.exists(template_dir):
        os.makedirs(template_dir)
        
    return template_dir

# Where user uploads and the config are saved
PERSISTENT_TEMPLATE_FOLDER = get_persistent_template_dir()
CONFIG_FILE = os.path.join(PERSISTENT_TEMPLATE_FOLDER, 'templates_config.json')

# ============================================================================
# HELPER: GET ACTIVE TEMPLATE FILENAME
# ============================================================================
def get_template_path(category, default_filename):
    print(f"   🔍 Looking for template category: {category}", flush=True)
    
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                data = json.load(f)
            
            for t_id, t_data in data.items():
                if t_data.get('category', '').lower() == category.lower() and t_data.get('isActive') == True:
                    custom_path = os.path.join(PERSISTENT_TEMPLATE_FOLDER, t_data['filename'])
                    
                    if os.path.exists(custom_path):
                        print(f"   📂 Using Custom Template: {t_data['filename']}", flush=True)
                        return custom_path
                    else:
                        print(f"   ⚠️ Custom template marked active but file missing: {custom_path}", flush=True)
        except Exception as e:
            print(f"   ⚠️ Error reading template config: {e}", flush=True)

    default_path = get_resource_path(os.path.join('templates', default_filename))
    
    if not os.path.exists(default_path):
        print(f"   ❌ CRITICAL: Default bundled template not found: {default_path}", flush=True)
    else:
        print(f"   📂 Using Default Bundled Template: {default_filename}", flush=True)
        
    return default_path

# ============================================================================
# HELPER: FETCH NAMES FROM FIREBASE ORG CHART
# ============================================================================
def fetch_official_name(role_key):
    try:
        ref = db.reference(f'org_chart/{role_key}/name')
        name = ref.get()
        if name and isinstance(name, str) and name.strip() != "":
            return name.upper()
    except: pass
    
    if role_key == 'capt': return "HON. PUNONG BARANGAY"
    if role_key == 'sec': return "BARANGAY SECRETARY"
    return "_________________"

def get_current_date_dict():
    now = datetime.now()
    return {
        'day': str(now.day),
        'suffix': get_ordinal_suffix(now.day),
        'month': now.strftime("%B"),
        'year': str(now.year),
        'full_date': now.strftime("%B %d, %Y")
    }

# ============================================================================
# DOCUMENT GENERATORS
# ============================================================================

def generate_complaint_docx(complaint_data, output_folder):
    template_path = get_template_path("Complaint", "complaint_template.docx")
    doc = DocxTemplate(template_path)
    
    complainant = complaint_data.get('complainantName', '__________________')
    if not complainant or complainant == 'N/A':
        complainant = complaint_data.get('complainantEmail', '__________________')

    respondent = complaint_data.get('complaintAgainst', '__________________')
    subject = complaint_data.get('subject', '__________________')
    message = complaint_data.get('complaintDetails', complaint_data.get('message', '_________________________________________________'))

    try:
        ts_source = complaint_data.get('processDate') or complaint_data.get('date') or complaint_data.get('timestamp')
        if ts_source:
            if isinstance(ts_source, int):
                dt = datetime.fromtimestamp(ts_source / 1000)
            else:
                clean_str = str(ts_source).replace('Z', '')
                try: dt = datetime.fromisoformat(clean_str)
                except: dt = datetime.strptime(clean_str.split('T')[0], "%Y-%m-%d")
        else:
            dt = datetime.now()
    except:
        dt = datetime.now()

    context = {
        'complainant_name': complainant.upper(),
        'respondent_name': respondent.upper(),
        'subject': subject,
        'message': message,
        'day': dt.strftime("%d"),
        'month': dt.strftime("%B"),
        'year': dt.strftime("%Y"),
        'captain_name': fetch_official_name('capt')
    }

    doc.render(context)
    
    file_id = str(uuid.uuid4().hex)[:8]
    timestamp = int(datetime.now().timestamp())
    filename = f"complaint_{timestamp}_{file_id}.docx"
    save_path = os.path.join(output_folder, filename)
    
    doc.save(save_path)
    return save_path, filename

def generate_indigency_word(request_data, output_path):
    template_path = get_template_path("Certificate of Indigency", "indigency_template.docx")
    doc = DocxTemplate(template_path)
    
    date_info = get_current_date_dict()
    
    context = {
        'full_name': get_full_name(request_data).upper(),
        'day': date_info['day'],
        # 👇 FIX: Make the suffix small and raised!
        'suffix': RichText(date_info['suffix'], superscript=True), 
        'month': date_info['month'],
        'year': date_info['year'],
        'captain_name': fetch_official_name('capt')
    }
    
    doc.render(context)
    doc.save(output_path)
    print(f"   💾 Indigency Word saved", flush=True)

def generate_late_registration_word(request_data, output_path):
    template_path = get_template_path("Certificate of Late Registration", "late_registration_template.docx")
    doc = DocxTemplate(template_path)

    date_info = get_current_date_dict()
    father = safe_get(request_data, 'fatherName', '___________')
    if not father.upper().startswith("MR."): father = "MR. " + father

    context = {
        'control_number': safe_get(request_data, 'controlNumber', '___________'),
        'rbi_number': safe_get(request_data, 'rbiNumber', '___________'),
        'full_name': get_full_name(request_data).upper(),
        'birth_date': safe_get(request_data, 'birthDate', '___________').upper(),
        'place_of_birth': safe_get(request_data, 'placeOfBirth', '___________').upper(),
        'father_name': father.upper(),
        'mother_name': safe_get(request_data, 'motherName', '___________').upper(),
        'day': date_info['day'],
        'suffix': RichText(date_info['suffix'], superscript=True), # 👇 FIX
        'month': date_info['month'],
        'year': date_info['year'],
        'captain_name': fetch_official_name('capt'),
        'secretary_name': fetch_official_name('sec')
    }
    
    doc.render(context)
    doc.save(output_path)
    print(f"   💾 Late Registration Word saved", flush=True)

def generate_certification_word(request_data, output_path):
    template_path = get_template_path("Barangay Certification", "certification_template.docx")
    doc = DocxTemplate(template_path)
    
    date_info = get_current_date_dict()
    
    context = {
        'full_name': get_full_name(request_data).upper(),
        'day': date_info['day'],
        'suffix': RichText(date_info['suffix'], superscript=True), # 👇 FIX
        'month': date_info['month'],
        'year': date_info['year'],
        'captain_name': fetch_official_name('capt')
    }
    
    doc.render(context)
    doc.save(output_path)
    print(f"   💾 Certification Word saved", flush=True)

def generate_cohabitation_word(request_data, output_path):
    template_path = get_template_path("Certificate of Cohabitation", "cohabitation_template.docx")
    doc = DocxTemplate(template_path)
    
    date_info = get_current_date_dict()

    raw_name = get_full_name(request_data).upper()
    clean_requester_name = raw_name
    for t in ["MR. ", "MS. ", "MRS. "]:
        if clean_requester_name.startswith(t):
            clean_requester_name = clean_requester_name.replace(t, "", 1)
            break
            
    requester_bdate = safe_get(request_data, 'birthDate', '___________')
    if 'T' in requester_bdate:
        try:
            dt = datetime.fromisoformat(requester_bdate.replace('Z', ''))
            requester_bdate = dt.strftime("%B %d, %Y")
        except: pass

    cohab_details = safe_get(request_data, 'cohabitationDetails', {})
    address_obj = safe_get(cohab_details, 'cohabitationAddress', safe_get(request_data, 'businessAddress', {}))
    street = safe_get(address_obj, 'street', '')
    brgy = safe_get(address_obj, 'barangay', 'Pularaquen')
    muni = safe_get(address_obj, 'municipality', 'Taytay')
    prov = safe_get(address_obj, 'province', 'Palawan')
    full_address = f"{street}, Barangay {brgy}, {muni}, {prov}" if street else "Barangay Pularaquen, Taytay, Palawan"

    context = {
        'requester_name': clean_requester_name,
        'requester_bdate': requester_bdate,
        'partner_name': safe_get(cohab_details, 'partnerName', '___________').upper(),
        'partner_bdate': safe_get(cohab_details, 'partnerBirthDate', '___________'),
        'start_date': safe_get(cohab_details, 'cohabitationStartDate', '___________'),
        'address': full_address,
        'day': date_info['day'],
        'suffix': RichText(date_info['suffix'], superscript=True), # 👇 FIX
        'month': date_info['month'],
        'year': date_info['year'],
        'captain_name': fetch_official_name('capt')
    }

    doc.render(context)
    doc.save(output_path)
    print(f"   💾 Cohabitation Word saved", flush=True)

def generate_seaweeds_word(request_data, output_path):
    template_path = get_template_path("Seaweeds Certification", "seaweeds_template.docx")
    doc = DocxTemplate(template_path)
    
    date_info = get_current_date_dict()
    details = safe_get(request_data, 'seaweedsDetails', {})
    amount_figures = str(safe_get(details, 'amountFigures', '0.00'))
    if not amount_figures.startswith("₱") and not amount_figures.startswith("P"):
        amount_figures = f"₱{amount_figures}"

    context = {
        'seller_name': get_full_name(request_data).upper(),
        'buyer_name': safe_get(details, 'buyerName', '__________________').upper(),
        'quantity': safe_get(details, 'quantity', '__________________'),
        'amount_words': safe_get(details, 'amountWords', '__________________'),
        'amount_figures': amount_figures,
        'day': date_info['day'],
        'suffix': RichText(date_info['suffix'], superscript=True), # 👇 FIX
        'month': date_info['month'],
        'year': date_info['year'],
        'captain_name': fetch_official_name('capt')
    }

    doc.render(context)
    doc.save(output_path)
    print(f"   💾 Seaweeds Word saved", flush=True)

def generate_business_clearance_word(request_data, output_path):
    template_path = get_template_path("Business Clearance", "business_clearance_template.docx")
    doc = DocxTemplate(template_path)
    
    date_info = get_current_date_dict()
    business_name, business_address, operator_name, operator_address = get_business_data(request_data)
    
    if operator_name != '_________________________' and not operator_name.upper().startswith("MR."):
         operator_name = "MR. " + operator_name

    context = {
        'business_name': business_name.upper(),
        'business_address': business_address,
        'operator_name': operator_name.upper(),
        'operator_address': operator_address,
        'or_number': safe_get(request_data, 'orNumber', '___________'),
        'issued_at': safe_get(request_data, 'issuedAt', 'Bgy. Pularaquen'),
        'issued_on': datetime.now().strftime('%m-%d-%Y'),
        'amount_paid': f"{float(safe_get(request_data, 'amountPaid', 200.00)):.2f}",
        'day': date_info['day'],
        'suffix': RichText(date_info['suffix'], superscript=True), # 👇 FIX
        'month': date_info['month'],
        'year': date_info['year'],
        'captain_name': fetch_official_name('capt')
    }
    
    doc.render(context)
    doc.save(output_path)
    print(f"   💾 Business Clearance Word saved", flush=True)

def generate_document_word(request_data, output_path):
    """Main routing function for generic documents"""
    doc_type = safe_get(request_data, 'documentType', 'Barangay Clearance')
    doc_type_lower = doc_type.lower()
    
    if 'seaweeds' in doc_type_lower:
        return generate_seaweeds_word(request_data, output_path)
    elif 'cohabitation' in doc_type_lower:
        return generate_cohabitation_word(request_data, output_path)
    elif 'late' in doc_type_lower and 'registration' in doc_type_lower:
        return generate_late_registration_word(request_data, output_path)
    elif 'certification' in doc_type_lower and 'business' not in doc_type_lower and 'late' not in doc_type_lower:
        return generate_certification_word(request_data, output_path)
    elif 'indigent' in doc_type_lower:
        return generate_indigency_word(request_data, output_path)
    elif 'business' in doc_type_lower and 'clearance' in doc_type_lower:
         return generate_business_clearance_word(request_data, output_path)
    
    # DEFAULT / GENERIC CLEARANCE
    template_path = get_template_path("Barangay Clearance", "clearance_template.docx")
    doc = DocxTemplate(template_path)
    
    date_info = get_current_date_dict()
    
    context = {
        'doc_title': doc_type.upper(),
        'full_name': get_full_name(request_data).upper(),
        'day': date_info['day'],
        'suffix': RichText(date_info['suffix'], superscript=True), # 👇 FIX
        'month': date_info['month'],
        'year': date_info['year'],
        'captain_name': fetch_official_name('capt')
    }
    
    doc.render(context)
    doc.save(output_path)
    print(f"   💾 Generic Clearance Word saved", flush=True)