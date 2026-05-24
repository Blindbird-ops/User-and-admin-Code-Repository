const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// --- CONFIGURE GMAIL ---
// 1. Replace with your actual Gmail address
// 2. Replace with your 16-character App Password (no spaces)
const transporter = nodemailer.createTransport({
  host: "smtp.gmail.com",
  port: 465,
  secure: true, 
  auth: {
    user: "pularaquentaytaypalawan@gmail.com", // YOUR GMAIL ADDRESS
    pass: "kpyw ohes acjc wole",   // YOUR 16-DIGIT APP PASSWORD

  },
});

function generateOTP() {
  return Math.floor(10000000 + Math.random() * 90000000).toString();
}

exports.sendEmailOtp = functions.https.onCall(async (data, context) => {
  // Logic to find email whether it's wrapped or not
  const email = data.email || (data.data && data.data.email);
  const username = data.username || (data.data && data.data.username) || "User";

  // --- I REMOVED THE CONSOLE.LOG THAT WAS CRASHING YOUR APP ---

  if (!email) {
    // If we still can't find it, just throw error without printing data
    throw new functions.https.HttpsError("invalid-argument", "Email is required.");
  }

  const code = generateOTP();
  const expiresAt = Date.now() + 10 * 60 * 1000; 

  // Sanitize email for Realtime Database key
  const safeEmail = email.replace(/[.#$/[\]]/g, "_");
  
  await admin.database().ref(`email_verifications/${safeEmail}`).set({
    code: code,
    expiresAt: expiresAt
  });

  const mailOptions = {
    from: '"Barangay Service(Base) App" <pularaquentaytaypalawan@gmail.com>', // MUST MATCH THE USER ABOVE
    to: email,
    subject: "Your BaSe Verification Code",
    html: `
      <div style="font-family: Arial, sans-serif; padding: 20px;">
        <h2>BaSe Verification</h2>
        <p>Hello ${username},</p>
        <p>Your code is:</p>
        <h1 style="background: #eee; padding: 10px; display: inline-block;">${code}</h1>
        <p>Expires in 10 minutes.</p>
      </div>
    `,
  };

  try {
    await transporter.sendMail(mailOptions);
    return { success: true, message: "OTP sent" };
  } catch (error) {
    console.error("Gmail Error:", error);
    throw new functions.https.HttpsError("internal", "Email failed: " + error.message);
  }
});

exports.verifyEmailOtp = functions.https.onCall(async (data, context) => {
  const email = data.email || (data.data && data.data.email);
  const code = data.code || (data.data && data.data.code);
  const uid = data.uid || (data.data && data.data.uid);

  if (!email || !code) throw new functions.https.HttpsError("invalid-argument", "No code provided");

  const safeEmail = email.replace(/[.#$/[\]]/g, "_");
  const dbRef = admin.database().ref(`email_verifications/${safeEmail}`);
  
  const snapshot = await dbRef.once("value");
  const val = snapshot.val();

  if (!val) throw new functions.https.HttpsError("not-found", "No code found.");
  if (val.expiresAt < Date.now()) throw new functions.https.HttpsError("deadline-exceeded", "Expired.");
  if (val.code !== code) throw new functions.https.HttpsError("invalid-argument", "Wrong code.");

if (uid) {
  // 1. Verify in Authentication (Keep this!)
  // This puts the green checkmark next to their email in Firebase Auth tab
  await admin.auth().updateUser(uid, { emailVerified: true });

  // 2. Update Database
  // --- CHANGED ---
  // Instead of setting 'isVerified: true', we just mark 'emailVerified: true'
  // and leave 'isVerified' alone (it defaults to false from registration).
  await admin.database().ref(`users/${uid}`).update({ 
    emailVerified: true, // NEW FIELD
    // isVerified: true, <--- REMOVE THIS LINE
    verifiedAt: new Date().toISOString() // Optional: keep or remove
  });
}

  await dbRef.remove();
  return { success: true };
});

/**
 * 3. Reset Password with OTP
 */
exports.resetPasswordWithOtp = functions.https.onCall(async (data, context) => {
  const email = data.email || (data.data && data.data.email);
  const code = data.code || (data.data && data.data.code);
  const newPassword = data.newPassword || (data.data && data.data.newPassword);

  if (!email || !code || !newPassword) {
    throw new functions.https.HttpsError("invalid-argument", "Missing data.");
  }

  // 1. Check if the OTP is valid (Same logic as verify)
  const safeEmail = email.replace(/[.#$/[\]]/g, "_");
  const dbRef = admin.database().ref(`email_verifications/${safeEmail}`);
  const snapshot = await dbRef.once("value");
  const val = snapshot.val();

  if (!val) throw new functions.https.HttpsError("not-found", "No code found.");
  if (val.expiresAt < Date.now()) throw new functions.https.HttpsError("deadline-exceeded", "Code expired.");
  if (val.code !== code) throw new functions.https.HttpsError("invalid-argument", "Incorrect code.");

  // 2. Find the user by Email
  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (e) {
    throw new functions.https.HttpsError("not-found", "User not found.");
  }

  // 3. FORCE PASSWORD UPDATE
  await admin.auth().updateUser(userRecord.uid, {
    password: newPassword
  });

  // 4. Cleanup
  await dbRef.remove();

  return { success: true, message: "Password updated successfully" };
});

// 1. ADD THIS NEW FUNCTION
exports.validateOtp = functions.https.onCall(async (data, context) => {
  const email = data.email || (data.data && data.data.email);
  const code = data.code || (data.data && data.data.code);

  if (!email || !code) throw new functions.https.HttpsError("invalid-argument", "Missing data");

  const safeEmail = email.replace(/[.#$/[\]]/g, "_");
  const dbRef = admin.database().ref(`email_verifications/${safeEmail}`);
  const snapshot = await dbRef.once("value");
  const val = snapshot.val();

  if (!val) throw new functions.https.HttpsError("not-found", "No code found.");
  if (val.expiresAt < Date.now()) throw new functions.https.HttpsError("deadline-exceeded", "Code expired.");
  if (val.code !== code) throw new functions.https.HttpsError("invalid-argument", "Incorrect code.");

  // Returns success but DOES NOT delete the code yet (so Step 3 can use it)
  return { success: true };
});

/**
 * 4. Check if Phone Number Exists (For Login)
 */
exports.checkPhoneNumberExists = functions.https.onCall(async (data, context) => {
  // --- FIX: Check for wrapped data ---
  const phoneNumber = data.phoneNumber || (data.data && data.data.phoneNumber);
  console.log("Searching for phone number:", phoneNumber); 

  if (!phoneNumber) {
    throw new functions.https.HttpsError('invalid-argument', 'Phone number required');
  }

  try {
    // Check Firebase Auth for this number
    await admin.auth().getUserByPhoneNumber(phoneNumber);
    // If no error thrown, user exists!
    return { exists: true };
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      return { exists: false };
    }
    throw new functions.https.HttpsError('internal', 'Error checking user: ' + error.message);
  }
});