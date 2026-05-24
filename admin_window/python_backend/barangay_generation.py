import sys
import os
import threading
import time
import logging
import traceback
import json
import uuid
import re  
from datetime import datetime

# ============================================================================
# LOGGING SETUP
# ============================================================================
def setup_logging():
    """Setup file logging for EXE debugging"""
    if getattr(sys, 'frozen', False):
        log_dir = os.path.expanduser('~/AppData/Local/BarangayApp/Logs')
        if not os.path.exists(log_dir):
            os.makedirs(log_dir)
        log_file = os.path.join(log_dir, 'barangay_debug.log')
    else:
        log_file = 'barangay_debug.log'
    
    logging.basicConfig(
        filename=log_file,
        level=logging.DEBUG,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    if not getattr(sys, 'frozen', False):
        console = logging.StreamHandler()
        console.setLevel(logging.INFO)
        logging.getLogger('').addHandler(console)

setup_logging()

class LogWriter:
    def __init__(self, logger_func):
        self.logger = logger_func
    def write(self, text):
        if text.strip():
            self.logger(text.strip())
    def flush(self):
        pass

if getattr(sys, 'frozen', False) and sys.platform == 'win32':
    sys.stdout = LogWriter(logging.info)
    sys.stderr = LogWriter(logging.error)

# ============================================================================
# IMPORTS
# ============================================================================
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename
from firebase_admin import db
import requests

from config import (
    FIREBASE_DATABASE_URL, 
    WORD_OUTPUT_FOLDER, 
    PDF_OUTPUT_FOLDER,
    initialize_all
)
from helpers import safe_get, get_business_data, get_full_name
from word_generator import (
    generate_business_clearance_word, 
    generate_document_word,
    generate_complaint_docx,
)
from pdf_generator import convert_to_pdf

# ============================================================================
# LOGO MANAGER
# ============================================================================
def get_cache_dir():
    if getattr(sys, 'frozen', False):
        base_dir = os.path.expanduser('~/AppData/Local/BarangayApp')
    else:
        base_dir = os.path.dirname(os.path.abspath(__file__))
    
    cache_dir = os.path.join(base_dir, 'logos_cache')
    if not os.path.exists(cache_dir):
        os.makedirs(cache_dir)
    return cache_dir

LOGO_CACHE_FOLDER = get_cache_dir()

def get_logo_paths():
    left_cache = os.path.join(LOGO_CACHE_FOLDER, 'logo_left.png')
    right_cache = os.path.join(LOGO_CACHE_FOLDER, 'logo_right.png')
    need_left = not os.path.exists(left_cache)
    need_right = not os.path.exists(right_cache)
    
    if need_left or need_right:
        try:
            logos_ref = db.reference('org_chart/logos')
            logos_data = logos_ref.get()
            if logos_data:
                if need_left and logos_data.get('left'):
                    _download_image(logos_data['left'], left_cache)
                if need_right and logos_data.get('right'):
                    _download_image(logos_data['right'], right_cache)
        except Exception as e:
            logging.warning(f"Could not fetch logos from Firebase: {e}")
    
    return {
        'left': left_cache if os.path.exists(left_cache) else None,
        'right': right_cache if os.path.exists(right_cache) else None
    }

def _download_image(url, save_path):
    try:
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            with open(save_path, 'wb') as f:
                f.write(response.content)
            logging.info(f"Downloaded logo: {os.path.basename(save_path)}")
            return True
    except Exception as e:
        logging.error(f"Failed to download logo: {e}")
    return False

# ============================================================================
# TEMPLATE MANAGER CONFIGURATION (FIXED FOR EXE / INNO SETUP)
# ============================================================================
def get_persistent_template_dir():
    """Ensure templates are stored in a persistent, read/write directory"""
    if getattr(sys, 'frozen', False):
        # If running as EXE, put templates in AppData so Windows allows writing
        base_dir = os.path.expanduser('~/AppData/Local/BarangayApp')
    else:
        base_dir = os.path.dirname(os.path.abspath(__file__))
    
    template_dir = os.path.join(base_dir, 'templates')
    if not os.path.exists(template_dir):
        os.makedirs(template_dir)
        logging.info(f"Created persistent template folder: {template_dir}")
        
    return template_dir

TEMPLATE_FOLDER = get_persistent_template_dir()
METADATA_FILE = os.path.join(TEMPLATE_FOLDER, 'templates_config.json')

def load_template_metadata():
    if not os.path.exists(METADATA_FILE):
        return {}
    try:
        with open(METADATA_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        logging.error(f"Failed to load templates config: {e}")
        return {}

def save_template_metadata(data):
    try:
        with open(METADATA_FILE, 'w') as f:
            json.dump(data, f, indent=4)
    except Exception as e:
        logging.error(f"Failed to save templates config: {e}")

# ============================================================================
# HELPER: SAFE FILENAME GENERATOR
# ============================================================================
def generate_safe_filename(doc_type, full_name=None):
    """
    Generates a guaranteed safe filename using UUID.
    Format: DocumentType_Timestamp_UUID.docx
    """
    safe_type = doc_type.replace(' ', '_').replace('-', '_') if doc_type else 'Document'
    safe_type = re.sub(r'[<>:\"/\\|?*]', '', safe_type)
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    short_uuid = str(uuid.uuid4().hex)[:8] 
    
    filename = f"{safe_type}_{timestamp}_{short_uuid}.docx"
    return filename

# ============================================================================
# FLASK SERVER
# ============================================================================
app = Flask(__name__)

@app.route('/generate_offline', methods=['POST'])
def handle_offline_generation():
    try:
        data = request.json
        logging.info(f"Received OFFLINE request: {data.get('documentType')}")
        
        os.makedirs(WORD_OUTPUT_FOLDER, exist_ok=True)
        os.makedirs(PDF_OUTPUT_FOLDER, exist_ok=True)

        doc_type = data.get('documentType', 'Barangay Clearance')
        full_name = data.get('fullName', 'User')
        
        filename = generate_safe_filename(doc_type)
        output_path = os.path.join(WORD_OUTPUT_FOLDER, filename)
        
        logging.info(f"Generating for: {full_name} -> {filename}")

        if 'business' in doc_type.lower():
            generate_business_clearance_word(data, output_path)
        else:
            generate_document_word(data, output_path)

        logging.info(f"Offline Document Generated: {output_path}")

        return jsonify({
            "status": "success", 
            "message": "Document generated successfully",
            "path": output_path,
            "original_name": full_name  
        }), 200

    except Exception as e:
        logging.error(f"Offline Generation Error: {str(e)}")
        logging.error(traceback.format_exc())
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/templates', methods=['GET'])
def get_templates():
    metadata = load_template_metadata()
    categorized = {}
    
    for t_id, t_data in metadata.items():
        cat = t_data.get('category', 'Uncategorized')
        if cat not in categorized:
            categorized[cat] = []
        
        t_data_with_id = t_data.copy()
        t_data_with_id['id'] = t_id
        categorized[cat].append(t_data_with_id)

    return jsonify(categorized)

@app.route('/api/upload_template', methods=['POST'])
def upload_template():
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400
        
    file = request.files['file']
    category = request.form.get('category')
    name = request.form.get('name')

    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    if file and file.filename.endswith('.docx'):
        filename = secure_filename(file.filename)
        unique_filename = f"{uuid.uuid4().hex[:8]}_{filename}"
        save_path = os.path.join(TEMPLATE_FOLDER, unique_filename)
        file.save(save_path)

        metadata = load_template_metadata()
        new_id = str(uuid.uuid4())
        
        is_first = True
        for t in metadata.values():
            if t.get('category') == category:
                is_first = False
                break

        metadata[new_id] = {
            "name": name,
            "filename": unique_filename,
            "category": category,
            "isActive": is_first
        }
        
        save_template_metadata(metadata)
        return jsonify({"message": "Upload successful", "id": new_id}), 200
    
    return jsonify({"error": "Invalid file type"}), 400

@app.route('/api/set_active_template', methods=['POST'])
def set_active_template():
    data = request.json
    target_id = data.get('template_id')
    category = data.get('category')

    metadata = load_template_metadata()

    for t_id, t_data in metadata.items():
        if t_data.get('category') == category:
            t_data['isActive'] = (t_id == target_id)
    
    save_template_metadata(metadata)
    return jsonify({"message": "Active template updated"}), 200

@app.route('/api/delete_template/<template_id>', methods=['DELETE'])
def delete_template(template_id):
    metadata = load_template_metadata()

    if template_id in metadata:
        filename = metadata[template_id]['filename']
        file_path = os.path.join(TEMPLATE_FOLDER, filename)

        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception as e:
                logging.error(f"Failed to delete file: {e}")
        
        del metadata[template_id]
        save_template_metadata(metadata)

        return jsonify({"message": "Deleted"}), 200

    return jsonify({"error": "Template not found"}), 404

def run_flask():
    import logging as flask_logging
    log = flask_logging.getLogger('werkzeug')
    log.setLevel(flask_logging.ERROR)
    
    logging.info("Offline Server running on http://127.0.0.1:5000")
    app.run(host='127.0.0.1', port=5000, debug=False, use_reloader=False)

# ============================================================================
# MONITORING FUNCTION
# ============================================================================
def monitor_and_generate():
    logging.info("Starting monitor_and_generate")
    print("=" * 80, flush=True)
    print("🔥 BARANGAY DOCUMENT AUTO-GENERATOR", flush=True)
    print("=" * 80, flush=True)
    print(f"📂 Word Output: {WORD_OUTPUT_FOLDER}", flush=True)
    print(f"📂 PDF Output:  {PDF_OUTPUT_FOLDER}", flush=True)
    print("=" * 80, flush=True)
    
    check_count = 0  
    start_time = datetime.now()
    consecutive_errors = 0
    
    while True:
        try:
            check_count += 1
            if check_count % 10 == 0:
                uptime = datetime.now() - start_time
                hours, remainder = divmod(int(uptime.total_seconds()), 3600)
                minutes, seconds = divmod(remainder, 60)
                print(f"💓 Heartbeat | Checks: {check_count} | Uptime: {hours:02d}:{minutes:02d}:{seconds:02d}", flush=True)

            try:
                all_requests_ref = db.reference('all_requests')
                all_requests = all_requests_ref.get()
                
                if all_requests:
                    for request_id, request_data in all_requests.items():
                        if not isinstance(request_data, dict): continue
                        
                        status = safe_get(request_data, 'status', '').lower()
                        doc_type = safe_get(request_data, 'documentType', '').lower()
                        
                        if 'appointment' in doc_type or 'complaint' in doc_type: continue
                        
                        if status == 'processing' and not request_data.get('documentWordPath'):
                            _process_standard_request(request_id, request_data)
                            
                consecutive_errors = 0
            except Exception as e:
                consecutive_errors += 1
                if consecutive_errors > 5: time.sleep(30)
                else: time.sleep(10)
                continue

            try:
                complaints_ref = db.reference('complaints')
                complaints = complaints_ref.get()
                if complaints:
                    for complaint_id, complaint_data in complaints.items():
                        if not isinstance(complaint_data, dict): continue
                        status = complaint_data.get('status', '').lower()
                        if status == 'processing' and complaint_data.get('generationStatus') != 'completed':
                            _process_complaint(complaint_id, complaint_data)
            except: pass

            time.sleep(3)
            
        except KeyboardInterrupt:
            break
        except Exception as e:
            logging.error(f"CRITICAL LOOP ERROR: {e}")
            time.sleep(15)

def _process_standard_request(request_id, request_data):
    try:
        doc_type = safe_get(request_data, 'documentType', '').lower()
        print(f"\n📝 PROCESSING: {doc_type}", flush=True)
        
        db.reference(f'all_requests/{request_id}').update({'generationStatus': 'generating'})
        
        full_name = get_full_name(request_data)
        
        original_doc_type = safe_get(request_data, 'documentType', 'Document')
        word_filename = generate_safe_filename(original_doc_type)
        pdf_filename = word_filename.replace('.docx', '.pdf')
        
        word_path = os.path.join(WORD_OUTPUT_FOLDER, word_filename)
        pdf_path = os.path.join(PDF_OUTPUT_FOLDER, pdf_filename)
        
        print(f"   📄 Word: {word_filename}", flush=True)
        
        if 'business' in doc_type:
            generate_business_clearance_word(request_data, word_path)
        else:
            generate_document_word(request_data, word_path)  
            
        convert_to_pdf(word_path, pdf_path)
        
        current_history = request_data.get('statusHistory', [])
        if isinstance(current_history, dict): current_history = list(current_history.values())
        if not isinstance(current_history, list): current_history = []
            
        current_history.append({
            "stage": "For Signing",
            "timestamp": datetime.now().isoformat(),
            "remarks": "Document generated automatically"
        })

        update_data = {
            'status': 'For Signing',
            'generationStatus': 'completed',
            'documentWordPath': word_path,
            'documentWordFilename': word_filename,
            'documentPdfPath': pdf_path,
            'documentPdfFilename': pdf_filename,
            'generatedAt': datetime.now().isoformat(),
            'fullName': full_name,
            'statusHistory': current_history
        }
        
        db.reference(f'all_requests/{request_id}').update(update_data)
        
        user_id = request_data.get('userId')
        if user_id and user_id != 'unknown':
            try:
                db.reference(f'users/{user_id}/requests/{request_id}').update(update_data)
            except: pass
            
        print(f"   ✅ Success!", flush=True)

    except Exception as e:
        print(f"   ❌ FAILED: {e}", flush=True)
        try:
            db.reference(f'all_requests/{request_id}').update({'generationStatus': 'failed', 'generationError': str(e)})
        except: pass

def _process_complaint(complaint_id, complaint_data):
    try:
        print(f"\n⚖️ PROCESSING COMPLAINT", flush=True)
        db.reference(f'complaints/{complaint_id}').update({'generationStatus': 'generating'})
        
        complaint_data['id'] = complaint_id
        actual_word_path, actual_filename = generate_complaint_docx(complaint_data, WORD_OUTPUT_FOLDER)
        
        pdf_filename = actual_filename.replace('.docx', '.pdf')
        pdf_path = os.path.join(PDF_OUTPUT_FOLDER, pdf_filename)
        
        convert_to_pdf(actual_word_path, pdf_path)

        update_data = {
            'generationStatus': 'completed',
            'generatedAt': datetime.now().isoformat(),
            'documentWordPath': actual_word_path,
            'documentWordFilename': actual_filename,
            'documentPdfPath': pdf_path,
            'documentPdfFilename': pdf_filename,
        }
        
        db.reference(f'complaints/{complaint_id}').update(update_data)
        print(f"   ✅ Success!", flush=True)

    except Exception as e:
        print(f"   ❌ FAILED: {e}", flush=True)
        try:
            db.reference(f'complaints/{complaint_id}').update({'generationStatus': 'failed', 'generationError': str(e)})
        except: pass

if __name__ == "__main__":
    try:
        logging.info("Starting Barangay App")
        
        firebase_initialized = False
        try:
            initialize_all()
            firebase_initialized = True
        except Exception as e:
            print("⚠️ Running in offline-only mode.", flush=True)

        flask_thread = threading.Thread(target=run_flask, daemon=True)
        flask_thread.start()
        
        if firebase_initialized:
            monitor_and_generate()
        else:
            print("🚀 Offline server active.", flush=True)
            while True: time.sleep(60)
                
    except Exception as e:
        logging.error(f"FATAL: {e}")
        input("Press Enter to exit...")