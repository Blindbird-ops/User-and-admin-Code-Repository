import 'package:flutter/material.dart';

class DashboardView extends StatelessWidget {
  // User Stats
  final int totalUsers;
  final int verifiedUsers;
  final int nonVerifiedUsers;
  
  // Request Stats
  final int totalRequests;
  final int pendingRequests;
  final int processingRequests;
  final int forSigningRequests;
  final int readyRequests;
  final int releasedRequests;
  final int rejectedRequests;
  final VoidCallback? onPendingReviewsTap;
  final VoidCallback? onViewAllReviewsTap;
  // Complaint Stats
  final int totalComplaints;
  final int pendingComplaints;
  final int processingComplaints;
  final int resolvedComplaints;
  final int rejectedComplaintsDesc;

  // Verification Stats
  final int pendingVerifications;
  final int approvedVerifications;
  final int rejectedVerifications;

  // System Stats
  final int logCount;
  final bool isLoading;

  const DashboardView({
    super.key,
    required this.totalUsers,
    required this.verifiedUsers,
    required this.nonVerifiedUsers,
    this.onPendingReviewsTap,
    this.onViewAllReviewsTap,
    required this.totalRequests,
    required this.pendingRequests,
    required this.processingRequests,
    required this.forSigningRequests,
    required this.readyRequests,
    required this.releasedRequests,
    required this.rejectedRequests,

    required this.totalComplaints,
    required this.pendingComplaints,
    required this.processingComplaints,
    required this.resolvedComplaints,
    required this.rejectedComplaintsDesc,

    required this.pendingVerifications,
    required this.approvedVerifications,
    required this.rejectedVerifications,
    
    required this.logCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    if (isLoading) {
      return const _DashboardSkeleton();
    }

    if (totalUsers == 0 && totalRequests == 0 && totalComplaints == 0 && logCount == 0) {
      return _EmptyState(colorScheme: colorScheme);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive column calculation
        int crossAxisCount = _calculateColumns(constraints.maxWidth);
        
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Section with Key Metrics
                    _buildHeaderSection(context, colorScheme),
                    
                    const SizedBox(height: 32),
                    
                    // Quick Stats Row (High Priority Items)
                    if (pendingVerifications > 0 || pendingRequests > 0 || pendingComplaints > 0)
                      _buildAlertBanner(context, colorScheme, onPendingReviewsTap),
                    
                    const SizedBox(height: 24),
                    
                    // User Statistics Section
                    _buildSectionHeader(
                      context, 
                      "User Management", 
                      Icons.people_alt_outlined,
                      colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    _buildResponsiveGrid(
                      crossAxisCount: crossAxisCount,
                      children: [
                        _buildStatCard(
                          context: context,
                          title: 'Total Users',
                          value: totalUsers,
                          icon: Icons.people_alt_rounded,
                          color: colorScheme.primary,
                          subtitle: 'Registered accounts',
                          trend: verifiedUsers > 0 ? '${((verifiedUsers/totalUsers)*100).toStringAsFixed(1)}% verified' : null,
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'Verified Residents',
                          value: verifiedUsers,
                          icon: Icons.verified_user_rounded,
                          color: Colors.green,
                          subtitle: 'Active residents',
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'Non-Verified Users',
                          value: nonVerifiedUsers,
                          icon: Icons.person_outline_rounded,
                          color: Colors.orange,
                          subtitle: 'Awaiting approval',
                          isAlert: nonVerifiedUsers > 0,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Verification Section (Highlighted)
                    _buildSectionHeader(
                      context, 
                      "Verification Queue", 
                      Icons.fact_check_outlined,
                      Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    _buildResponsiveGrid(
                      crossAxisCount: crossAxisCount,
                      children: [
                        _buildStatCard(
                          context: context,
                          title: 'Pending Review',
                          value: pendingVerifications,
                          icon: Icons.hourglass_top_rounded,
                          color: Colors.orange,
                          subtitle: 'Needs admin action',
                          isAlert: pendingVerifications > 0,
                          badge: pendingVerifications > 0 ? 'Action Required' : null,
                          onTap: onPendingReviewsTap,
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'Approved Verifications',
                          value: approvedVerifications,
                          icon: Icons.check_circle_outline_rounded,
                          color: Colors.green,
                          subtitle: 'Successfully verified',
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'Rejected Verifications',
                          value: rejectedVerifications,
                          icon: Icons.cancel_outlined,
                          color: Colors.red.shade400,
                          subtitle: 'Needs revision',
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Document Requests Section with Pipeline Visualization
                    _buildSectionHeader(
                      context, 
                      "Document Requests", 
                      Icons.description_outlined,
                      colorScheme.secondary,
                    ),
                    const SizedBox(height: 16),
                    
                    // Request Pipeline Progress Indicator
                    _buildRequestPipeline(context, colorScheme),
                    const SizedBox(height: 16),
                    
                    _buildResponsiveGrid(
                      crossAxisCount: crossAxisCount,
                      children: [
                        _buildStatCard(
                          context: context,
                          title: 'Total Requests',
                          value: totalRequests,
                          icon: Icons.folder_copy_outlined,
                          color: colorScheme.secondary,
                          subtitle: 'All time requests',
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'New/Pending',
                          value: pendingRequests,
                          icon: Icons.mark_email_unread_outlined,
                          color: Colors.redAccent,
                          subtitle: 'Awaiting processing',
                          isAlert: pendingRequests > 5,
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'Processing',
                          value: processingRequests,
                          icon: Icons.sync_rounded,
                          color: Colors.indigo,
                          subtitle: 'In progress',
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'For Signing',
                          value: forSigningRequests,
                          icon: Icons.edit_note_rounded,
                          color: Colors.deepPurple,
                          subtitle: 'Awaiting signature',
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'Ready for Pickup',
                          value: readyRequests,
                          icon: Icons.inventory_2_outlined,
                          color: Colors.teal,
                          subtitle: 'Awaiting collection',
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'Released',
                          value: releasedRequests,
                          icon: Icons.check_circle_rounded,
                          color: Colors.green.shade700,
                          subtitle: 'Completed',
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Complaints Section
                    _buildSectionHeader(
                      context, 
                      "Complaints & Issues", 
                      Icons.support_agent_outlined,
                      Colors.deepPurple,
                    ),
                    const SizedBox(height: 16),
                    _buildResponsiveGrid(
                      crossAxisCount: crossAxisCount,
                      children: [
                        _buildStatCard(
                          context: context,
                          title: 'Total Issues',
                          value: totalComplaints,
                          icon: Icons.report_problem_outlined,
                          color: Colors.deepPurple,
                          subtitle: 'All complaints',
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'New Reports',
                          value: pendingComplaints,
                          icon: Icons.notification_important_outlined,
                          color: Colors.red,
                          subtitle: 'Awaiting review',
                          isAlert: pendingComplaints > 0,
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'In Progress',
                          value: processingComplaints,
                          icon: Icons.trending_up_rounded,
                          color: Colors.blue,
                          subtitle: 'Being handled',
                        ),
                        _buildStatCard(
                          context: context,
                          title: 'Resolved',
                          value: resolvedComplaints,
                          icon: Icons.task_alt_rounded,
                          color: Colors.green,
                          subtitle: 'Closed cases',
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // System Health Footer
                    _buildSystemHealthFooter(context, colorScheme),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  int _calculateColumns(double width) {
    if (width < 600) return 1; // Mobile
    if (width < 900) return 2; // Tablet
    if (width < 1200) return 3; // Small desktop
    return 4; // Large desktop
  }

  Widget _buildHeaderSection(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.teal.shade700,
            Colors.teal.shade300,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dashboard Overview',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Real-time system analytics and management',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimary.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.circle,
                      color: Color.fromARGB(255, 44, 250, 61),
                      size: 12,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'System Online',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildQuickStat(
                context,
                'Total Users',
                totalUsers.toString(),
                Icons.people,
              ),
              const SizedBox(width: 32),
              _buildQuickStat(
                context,
                'Pending Tasks',
                (pendingVerifications + pendingRequests + pendingComplaints).toString(),
                Icons.pending_actions,
              ),
              const SizedBox(width: 32),
              _buildQuickStat(
                context,
                'System Logs',
                logCount.toString(),
                Icons.article_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(BuildContext context, String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 32), // Made Icon larger
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36, // MASSIVELY INCREASED TOP STAT NUMBER (was 20)
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14, // Slightly increased label
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertBanner(BuildContext context, ColorScheme colorScheme, VoidCallback? onReviewTap) {
    final pendingTotal = pendingVerifications + pendingRequests + pendingComplaints;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You have $pendingTotal pending items requiring attention ($pendingVerifications verifications, $pendingRequests requests, $pendingComplaints complaints)',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onReviewTap,
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildRequestPipeline(BuildContext context, ColorScheme colorScheme) {
    final stages = [
      {'label': 'Pending', 'value': pendingRequests, 'color': Colors.redAccent},
      {'label': 'Processing', 'value': processingRequests, 'color': Colors.indigo},
      {'label': 'Signing', 'value': forSigningRequests, 'color': Colors.deepPurple},
      {'label': 'Ready', 'value': readyRequests, 'color': Colors.teal},
      {'label': 'Released', 'value': releasedRequests, 'color': Colors.green.shade700},
    ];

    final total = stages.fold<int>(0, (sum, stage) => sum + (stage['value'] as int));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Request Pipeline',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total > 0 ? (releasedRequests / total) : 0,
              backgroundColor: colorScheme.surfaceContainerHighest,
              minHeight: 8,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: stages.map((stage) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: stage['color'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${stage['label']}: ${stage['value']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveGrid({required int crossAxisCount, required List<Widget> children}) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.4, // Keep proportion nice for big numbers
      children: children,
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required String title,
    required int value,
    required IconData icon,
    required Color color,
    required String subtitle,
    String? trend,
    String? badge,
    bool isAlert = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Widget cardContent = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: isAlert 
          ? LinearGradient(
              colors: [
                color.withOpacity(0.05),
                Colors.transparent,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28), // Slightly bigger card icon
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible( // Flexible + FittedBox ensures it doesn't break UI if numbers get huge
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value.toString(),
                    style: TextStyle(
                      fontSize: 48, // MASSIVELY INCREASED GRID NUMBER (was headlineMedium)
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      height: 1.0, // Removes extra padding to stay neat
                      letterSpacing: -1.0, 
                    ),
                  ),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8), // Aligns nicely with the huge text
                  child: Text(
                    trend,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8), // A little extra breathing room
          Text(
            title,
            style: TextStyle(
              fontSize: 15, // Slightly bumped title
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Card(
      elevation: isAlert ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isAlert 
          ? BorderSide(color: color.withOpacity(0.5), width: 2)
          : BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: onTap != null
        ? InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: cardContent,
          )
        : cardContent,
    );
  }

  Widget _buildSystemHealthFooter(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.storage_outlined, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'System Health',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  '$logCount system logs recorded • Last updated just now',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

// Loading Skeleton Widget
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: List.generate(6, (index) => Container(
              width: 280,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
            )),
          ),
        ],
      ),
    );
  }
}

// Empty State Widget
class _EmptyState extends StatelessWidget {
  final ColorScheme colorScheme;

  const _EmptyState({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No Data Available',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dashboard statistics will appear here once data is available.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Data'),
          ),
        ],
      ),
    );
  }
}