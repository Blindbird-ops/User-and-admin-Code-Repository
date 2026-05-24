// widget/side_menu.dart

import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart'; 
import 'package:admin_window/announcement/announcement_dialog.dart';
import 'package:admin_window/announcement/announcement_management_page.dart';
import 'package:admin_window/announcement/announcement_service.dart';
import 'package:admin_window/screens/admin_profile_page.dart'; 
import 'package:admin_window/screens/org_chart_page.dart'; 

class SideMenu extends StatelessWidget {
  final String token;
  final String userId; 
  final String adminFullName;
  final String? adminProfileImageUrl; 
  final VoidCallback? onProfileImageTap;
  final Function(int) onSelectItem;
  final int selectedIndex;
  final Future<void> Function() onLogout;
  final int pendingSubmissionsCount;

  // --- KEYS ---
  final GlobalKey keyProfile;
  final GlobalKey keyProfileBilling; 
  final GlobalKey keyManageAnnounce; 
  final GlobalKey keyPostAnnounce;
  final GlobalKey keyOrgChart;
  final GlobalKey keySideMap; // <--- Map key added
  final GlobalKey keySubRequests;
  final GlobalKey keyNonVerifUsers; 
  final GlobalKey keyVerifUsers;

  const SideMenu({
    super.key,
    required this.token,
    required this.adminFullName,
    required this.userId,
    this.adminProfileImageUrl,
    this.onProfileImageTap,
    required this.onSelectItem,
    required this.selectedIndex,
    required this.onLogout,
    required this.pendingSubmissionsCount,
    
    required this.keyProfile,
    required this.keyProfileBilling,
    required this.keyPostAnnounce,
    required this.keyManageAnnounce,
    required this.keyOrgChart,
    required this.keySideMap, // Ensure this is required
    required this.keySubRequests,
    required this.keyNonVerifUsers,
    required this.keyVerifUsers,
  });

  @override
  Widget build(BuildContext context) {
    double menuWidth = MediaQuery.of(context).size.width * 0.25;
    return Container(
      width: menuWidth,
      height: MediaQuery.of(context).size.height,
      color: const Color.fromARGB(255, 100, 158, 224),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            
            // --- 1. PROFILE IMAGE SECTION ---
            Center(
              child: Showcase(
                key: keyProfile,
                title: 'Your Profile',
                description: 'Click the camera icon to update your picture or name.',
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.white,
                        backgroundImage: (adminProfileImageUrl != null && adminProfileImageUrl!.isNotEmpty)
                            ? NetworkImage(adminProfileImageUrl!)
                            : null,
                        child: (adminProfileImageUrl == null || adminProfileImageUrl!.isEmpty)
                            ? const Icon(Icons.person, size: 40, color: Colors.blue)
                            : null,
                      ),
                      Positioned(
                        bottom: -4,
                        right: -4,
                        child: InkWell(
                          onTap: onProfileImageTap,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(adminFullName, 
              style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const Center(
              child: Text("Admin Officer", style: TextStyle(fontSize: 14, color: Colors.white70)),
            ),
            const SizedBox(height: 8),
            
            // --- UPDATE PROFILE BUTTON ---
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminProfilePage(
                        token: token,
                        userId: userId,
                      ),
                    ),
                  );
                },
                child: const Text("Update Profile"),
              ),
            ),

            // --- 2. PROFILE BILLING ---
            Showcase(
              key: keyProfileBilling,
              title: 'Profile Billing',
              description: 'View your billing history and payment records here.',
              child: ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.white),
                title: const Text("Profile Billing", style: TextStyle(color: Colors.white)),
                selected: selectedIndex == 5,
                onTap: () {
                  onSelectItem(5);
                },
              ),
            ),
            
            const Divider(color: Colors.white54),
            
            // --- 3. POST ANNOUNCEMENT ---
            Showcase(
              key: keyPostAnnounce,
              title: 'Announcements',
              description: 'Create and post new announcements for the barangay.',
              child: ListTile(
                leading: const Icon(Icons.announcement, color: Colors.white),
                title: const Text("Post Announcement", style: TextStyle(color: Colors.white)),
                selected: selectedIndex == 0,
                onTap: () {
                  onSelectItem(0);
                  showDialog(
                    context: context,
                    barrierDismissible: false, 
                    builder: (context) {
                      return AnnouncementDialog(
                        onPost: (title, message, when, where, imageUrl) async {
                          final announcementService = AnnouncementService(token: token);
                          bool success = await announcementService.postAnnouncement(
                            title: title,
                            message: message,
                            when: when,
                            where: where,
                            imageUrl: imageUrl,
                          );

                          if (context.mounted) {
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Announcement posted successfully")));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to post announcement")));
                            }
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),

            // --- 4. MANAGE ANNOUNCEMENTS ---
            Showcase(
              key: keyManageAnnounce,
              title: 'Manage Announcements',
              description: 'Edit or delete existing announcements.',
              child: ListTile(
                leading: const Icon(Icons.manage_accounts, color: Colors.white),
                title: const Text("Manage Announcements", style: TextStyle(color: Colors.white)),
                selected: selectedIndex == 1,
                onTap: () {
                  onSelectItem(1);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => AnnouncementManagementPage(token: token)));
                },
              ),
            ),

            // --- 5. ORG CHART BUTTON ---
            Showcase(
              key: keyOrgChart,
              title: 'Organization Chart',
              description: 'View and edit the Barangay Organizational Chart.',
              child: ListTile(
                leading: const Icon(Icons.account_tree_outlined, color: Colors.white),
                title: const Text("Organizational Chart", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => OrgChartPage(token: token))); 
                },
              ),
            ),

            // --- 5.5 BARANGAY MAP (MOVED HERE) ---
            Showcase(
              key: keySideMap,
              title: 'Barangay Map',
              description: 'View the interactive map of the barangay.',
              child: ListTile(
                leading: const Icon(Icons.map_outlined, color: Colors.white),
                title: const Text("Barangay Map", style: TextStyle(color: Colors.white)),
                onTap: () {
                  // Index 6 acts as a trigger to push the Map route
                  onSelectItem(6);
                },
              ),
            ),

            const Divider(color: Colors.white54),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text("USER MANAGEMENT", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            ),
            
            // --- 6. SUBMITTED REQUESTS ---
            Showcase(
              key: keySubRequests,
              title: 'Verification Requests',
              description: 'Review pending account verification requests from residents.',
              child: ListTile(
                leading: const Icon(Icons.rule_folder_outlined, color: Colors.white),
                title: const Text("Submitted Requests", style: TextStyle(color: Colors.white)),
                trailing: (pendingSubmissionsCount > 0)
                    ? Chip(
                        label: Text('$pendingSubmissionsCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.orange.shade800,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
                selected: selectedIndex == 4,
                onTap: () {
                  onSelectItem(4);
                },
              ),
            ),
            
            // --- 7. NON VERIFIED USERS ---
            Showcase(
              key: keyNonVerifUsers,
              title: 'Non-Verified Users',
              description: 'View list of users who have not submitted verification yet.',
              child: ListTile(
                leading: const Icon(Icons.person_off, color: Colors.white),
                title: const Text("Non Verified Users", style: TextStyle(color: Colors.white)),
                selected: selectedIndex == 2,
                onTap: () {
                  onSelectItem(2);
                },
              ),
            ),

            // --- 8. VERIFIED USERS ---
            Showcase(
              key: keyVerifUsers,
              title: 'User Database',
              description: 'View the master list of all verified residents.',
              child: ListTile(
                leading: const Icon(Icons.verified_user, color: Colors.white),
                title: const Text("Verified Users", style: TextStyle(color: Colors.white)),
                selected: selectedIndex == 3,
                onTap: () {
                  onSelectItem(3);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}