/// Button layout and interaction, independent of the device manufacturer.
enum StylusProfile {
  automatic,
  singleButton,
  twoButtons;

  static const preferenceKey = 'stylusProfile';

  static StylusProfile fromPreference(String? value) => values.firstWhere(
    (profile) => profile.name == value,
    orElse: () => automatic,
  );

  bool get supportsSecondaryButton => this != singleButton;
  bool get usesTemporaryButton => this == singleButton;
}
