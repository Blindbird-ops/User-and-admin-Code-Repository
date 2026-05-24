// lib/widget/top_navigation_bar.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:showcaseview/showcaseview.dart'; 
class TopNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final GlobalKey tutorialKey; // Existing key for Notifications
  // --- NEW KEYS ADDED HERE ---
  final GlobalKey keySettings; 
  final List<GlobalKey> tabKeys; 
  // ---------------------------
  final List<Map<String, dynamic>> notificationHistory;
  final Function(int) onNotificationItemClick;
  final VoidCallback onClearNotifications;

  final VoidCallback onSettings;
  final VoidCallback onLogout;
  final List<Tab> tabs;
  final bool hasNewComplaints;
  final bool hasNewRequests;

  const TopNavigationBar({
    super.key,
    required this.hasNewRequests,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.tutorialKey,
    required this.notificationHistory,
    required this.onNotificationItemClick,
    required this.onClearNotifications,
    required this.onSettings,
    required this.onLogout,
    required this.tabs,
    required this.hasNewComplaints,
    
    // --- ADDED TO CONSTRUCTOR ---
    required this.keySettings,
    required this.tabKeys,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      color: const Color.fromARGB(255, 253, 253, 255),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // --- 1. NOTIFICATIONS SHOWCASE ---
          Showcase(
            key: tutorialKey,
            title: 'Notifications',
            description: 'Check here for new requests, complaints, and updates.',
            child: PopupMenuButton<int>(
              tooltip: 'Notifications',
              offset: const Offset(0, 50),
              icon: Stack(
                children: [
                  const Icon(Icons.notifications, color: Colors.black),
                  if (notificationHistory.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              itemBuilder: (context) {
                if (notificationHistory.isEmpty) {
                  return [
                    const PopupMenuItem(
                      enabled: false,
                      child: Text("No notifications"),
                    ),
                  ];
                }
                List<PopupMenuEntry<int>> items = [];
                // Header with Clear All
                items.add(
                  PopupMenuItem(
                    enabled: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Notifications", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onClearNotifications();
                          },
                          child: const Text("Clear All", style: TextStyle(fontSize: 12)),
                        )
                      ],
                    ),
                  ),
                );
                items.add(const PopupMenuDivider());
                // List Items
                for (int i = 0; i < notificationHistory.length; i++) {
                  final notif = notificationHistory[i];
                  final time = notif['timestamp'] as DateTime;
                  final timeString = DateFormat('h:mm a').format(time);

                  items.add(
                    PopupMenuItem(
                      value: i,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(notif['message'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text(timeString, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                }
                return items;
              },
              onSelected: (index) {
                final target = notificationHistory[index]['targetIndex'];
                onNotificationItemClick(target);
              },
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: tabs.asMap().entries.map((entry) {
                final int index = entry.key;
                final Tab tab = entry.value;
                final isSelected = selectedIndex == index;
                // Create the tab widget content
                Widget tabWidget = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: () => onTabSelected(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Text(
                              tab.text ?? '',
                              style: TextStyle(
                                fontSize: 16,
                                color: isSelected ? Colors.blue : Colors.black,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (index == 3 && hasNewRequests)
                              Positioned(
                                right: -12,
                                top: -4,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            if (index == 4 && hasNewComplaints)
                              Positioned(
                                right: -12,
                                top: -4,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 3,
                          width: 40,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                );
                // --- 2. WRAP TAB WITH SHOWCASE ---
                // We check if the index exists in our key list to avoid errors
                if (index < tabKeys.length) {
                  return Showcase(
                    key: tabKeys[index],
                    title: tab.text ?? 'Tab',
                    description: 'View ${tab.text} information here.',
                    child: tabWidget,
                  );
                } else {
                  return tabWidget;
                }
              }).toList(),
            ),
          ),
          // --- 3. WRAP SETTINGS WITH SHOWCASE ---
          Showcase(
            key: keySettings,
            title: 'Settings',
            description: 'Change theme, backup data, or reset tutorials here.',
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.black),
              onPressed: onSettings,
              tooltip: "Settings",
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: onLogout,
            tooltip: "Logout",
          ),
        ],
      ),
    );
  }
}