# 🏛️ Barangay Document Request Efficiency for Mobile Application
Welcome to the official repository for the **BaSe Application**. 

This system is designed to modernize and digitalize local barangay services. Its main objective is to provide a faster, more efficient, and hassle-free way for residents to request important documents, and for barangay officials to process them.

The system is divided into two main applications, built using **Flutter**:

---

## 📱 1. Mabs(Mobile Application for Barangay Services)
**Folder:** `mabs`

Mabs is the dedicated mobile application for the **Residents**. 
Instead of waiting in long lines at the barangay hall, residents can use this app to:
* Register and manage their personal information.
* Request necessary barangay documents (e.g., Barangay Clearance, Certificate of Indigency, etc.) straight from their smartphones.
* Track the status of their requests.

👉 *To view the main Dart code for this app, navigate to: `mabs/lib/`*

---
mab
## 💻 2. Secretary & Admin Dashboard
**Folder:** `admin_window`

This is the dedicated application for the **Barangay Secretary and Administrators**. 
It serves as the central hub for managing the barangay's daily operations. Through this portal, the secretary can:
* View and verify resident information.
* Receive real-time notifications for new document requests.
* Approve, process, and manage requested documents quickly and efficiently.

👉 *To view the main Dart code for this app, navigate to: `admin_window/lib/`*

---

### 🛠️ Technology Stack
* **Frontend:** Flutter & Dart
* **Backend:** Firebase (Authentication, Database, Storage, function) & Python

> **Note for Code Reviewers:** If you scanned the QR code to view the source code, please click on either the `mabs` or `admin_window` folders above, and open the `lib` folder to see the core Flutter logic.
**Note:** The actual application name of both mobile and windows application is BaSe we use the folder name mabs for residents to easily identify that this is for mobile application so when we develop our application it is easy to differentiate the projects.
