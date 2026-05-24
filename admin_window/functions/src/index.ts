// 1. Force V1 import to fix "property ref does not exist" error
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

admin.initializeApp();

// =========================================================
// 1. ANNOUNCEMENT TRIGGER
// =========================================================
// =========================================================
// 1. ANNOUNCEMENT TRIGGER
// =========================================================
export const sendAnnouncementNotification = functions.database
  .ref("/announcements/{announcementId}")
  .onCreate(async (snapshot, context) => {
    const announcement = snapshot.val();
    
    if (!announcement || !announcement.title) return;

    // Create the message payload
    const payload: any = {
      notification: {
        title: `📢 ${announcement.title}`,
        body: announcement.message || "Check the app for details.",
      },
      // --- NEW: ANDROID SPECIFIC CONFIGURATION ---
      android: {
        notification: {
          sound: 'default', // Explicitly ask for sound
          channelId: 'announcements_channel', // Must match the key in your Flutter app
          priority: 'high',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK'
        }
      },
      // -------------------------------------------
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        id: context.params.announcementId,
        type: "announcement",
        when: announcement.when || "",
        where: announcement.where || "",
        imageUrl: announcement.imageUrl || ""
      },
      topic: "all_users",
    };

    try {
      const response = await admin.messaging().send(payload);
      console.log("Successfully sent announcement message:", response);
    } catch (error) {
      console.log("Error sending announcement message:", error);
    }
  });
// =========================================================
// 2. REQUEST STATUS TRIGGER
// =========================================================
// =========================================================
// 2. REQUEST STATUS TRIGGER (UPDATED)
// =========================================================
export const sendRequestStatusNotification = functions.database
  .ref("/users/{userId}/requests/{requestId}/status")
  .onUpdate(async (change, context) => {
    const newStatus = change.after.val();
    const userId = context.params.userId;

    // 1. FETCH PARENT DATA TO GET DOCUMENT TYPE
    // We go up one level to get the full request details
    const requestSnapshot = await change.after.ref.parent?.once("value");
    const requestData = requestSnapshot?.val();

    // Try to find the document name, default to "Document" if missing
    const docType = requestData?.documentType || requestData?.title || "Document";

    // 2. GET USER TOKEN
    const userTokenSnapshot = await admin.database().ref(`/users/${userId}/fcmToken`).once("value");
    const userToken = userTokenSnapshot.val();

    if (!userToken) {
        console.log("No FCM token found for user:", userId);
        return;
    }

    let emoji = "📄";
    const statusLower = String(newStatus).toLowerCase();
    if (statusLower.includes("approved") || statusLower.includes("ready")) emoji = "✅";
    if (statusLower.includes("rejected") || statusLower.includes("disapproved")) emoji = "❌";

    const payload: any = {
      notification: {
        // --- FIX: USE SPECIFIC DOCUMENT NAME ---
        title: `${emoji} Update: ${docType}`,
        body: `Your request is now: ${newStatus}`,
      },
      // --- FIX: ADD ANDROID CHANNEL CONFIG ---
      android: {
        notification: {
          sound: 'default',
          channelId: 'document_updates', // Matches Flutter NotificationService
          priority: 'high',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK'
        }
      },
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        navigate: "true",
        type: "document",
        requestId: context.params.requestId
      },
      token: userToken 
    };

    try {
      await admin.messaging().send(payload);
      console.log(`Sent update to user ${userId} regarding ${docType}`);
    } catch (error) {
      console.log("Error sending status update:", error);
    }
  });