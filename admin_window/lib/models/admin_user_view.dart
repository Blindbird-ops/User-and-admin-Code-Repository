// This model represents a user from an admin's point of view,
// combining their profile and submission status.
class AdminUserView {
  final String id;
  final String fullName;
  final String email;
  final bool isVerified;
  final String submissionStatus; // e.g., 'pending', 'approved', 'rejected', 'none'

  AdminUserView({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isVerified,
    required this.submissionStatus,
  });
}