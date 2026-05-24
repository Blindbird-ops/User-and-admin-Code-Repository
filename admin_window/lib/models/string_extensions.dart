extension StringCasingExtension on String {
  /// Converts a string to Title Case.
  /// Example: "john doe" becomes "John Doe".
  /// Handles multiple words and ensures consistent capitalization.
  String toTitleCase() {
    if (isEmpty) {
      return '';
    }
    // Split the string by spaces, capitalize each word, and then join them back.
    return split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}