# templates.py - Document templates

from helpers import safe_get, get_full_name

DOCUMENT_TEMPLATES = {
    'barangay clearance': {
        'title': 'BARANGAY CLEARANCE',
        'content': lambda data: (
            f"     This is to certify that {get_full_name(data)}, legal age, "
            f"Filipino citizen, and bona fide resident of this Barangay is personally known to me "
            f"as a law-abiding citizen and has a good moral character.\n\n"
            f"     This CLEARANCE is issued by this office upon the request of the above-named person "
            f"for whatever purpose it may serve him/her best."
        ),
        'default_amount': 50.00
    },
    'barangay business clearance': {
        'title': 'BARANGAY BUSINESS CLEARANCE',
        'content': lambda data: (
            f"     This is to Certify that the Business or Trade Activity described below;"
        ),
        'default_amount': 200.00
    },
    'barangay certification': {
        'title': 'BARANGAY CERTIFICATION',
        'content': lambda data: (
            f"     This is to certify that {get_full_name(data)}, legal age, "
            f"Filipino citizen, and bona fide resident of this Barangay, is personally known to me "
            f"as a law-abiding citizen with a good moral character. Based on the record in this Barangay, "
            f"he/she is not involved in any unlawful activities.\n\n"
            f"     This CERTIFICATION is issued by this office upon the request of the above-named person "
            f"for whatever purpose it may serve him/her best."
        ),
        'default_amount': 50.00
    },
    'barangay indigent': {
        'title': 'CERTIFICATE OF INDIGENCY',
        'content': lambda data: (
            f"     This is to certify that {get_full_name(data)}, a resident of Barangay Pularaquen, "
            f"Taytay, Palawan, belongs to an indigent family in this barangay.\n\n"
            f"     This certification is issued for {safe_get(data, 'purpose', 'medical assistance')}."
        ),
        'default_amount': 0.00
    },
    'certification (late) registration': {
        'title': 'CERTIFICATION',
        'content': lambda data: '',  # Content handled specially in generators
        'default_amount': 50.00
    }
}