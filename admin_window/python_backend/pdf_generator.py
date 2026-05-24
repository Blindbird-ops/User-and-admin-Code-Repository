import os
import comtypes.client

# Word File Format Constant for PDF
wdFormatPDF = 17

def convert_to_pdf(input_docx_path, output_pdf_path):
    """
    Converts a DOCX file to PDF using Microsoft Word via COM.
    Ensures 100% layout fidelity between the Word doc and the PDF.
    """
    word_app = None
    doc = None
    
    try:
        # 1. Resolve absolute paths (COM requires absolute paths)
        input_abs_path = os.path.abspath(input_docx_path)
        output_abs_path = os.path.abspath(output_pdf_path)

        # 2. Check if source exists
        if not os.path.exists(input_abs_path):
            print(f"   ❌ Source file missing: {input_abs_path}", flush=True)
            return False

        print(f"   🔄 Converting to PDF...", flush=True)

        # 3. Initialize Word (Hidden)
        word_app = comtypes.client.CreateObject('Word.Application')
        word_app.Visible = False
        word_app.DisplayAlerts = False # Prevent popups

        # 4. Open Document
        doc = word_app.Documents.Open(input_abs_path)

        # 5. Save as PDF
        doc.SaveAs(output_abs_path, FileFormat=wdFormatPDF)
        
        print(f"   📄 PDF Saved: {os.path.basename(output_pdf_path)}", flush=True)
        return True

    except Exception as e:
        print(f"   ❌ PDF Conversion Failed: {e}", flush=True)
        return False

    finally:
        # 6. Cleanup
        if doc:
            try:
                doc.Close()
            except:
                pass
        
        if word_app:
            try:
                word_app.Quit()
            except:
                pass