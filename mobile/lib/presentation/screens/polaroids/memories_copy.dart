abstract final class MemoriesCopy {
  static const String title = 'Our Scrapbook';
  static const String opening = 'Opening your scrapbook...';
  static const String snapMemory = 'Snap Memory';
  static const String wallError = 'We could not open your scrapbook just now. Please try again.';
  static const String emptyTitle = 'No Polaroids Yet';
  static const String createFirst = 'Create First Polaroid 💕';

  static String preserved(int count) => '$count ${count == 1 ? 'polaroid' : 'polaroids'} preserved';

  static String hidden(int count) =>
      '$count ${count == 1 ? 'polaroid' : 'polaroids'} could not be opened with your passphrase, so '
      '${count == 1 ? 'it is' : 'they are'} hidden for now.';

  static String emptyMessage(String partnerName) =>
      'Add your first photo together! It will be saved safely here and shared with $partnerName.';

  static const String developing = 'Developing... 💕';
  static const String noImage = 'No image';
  static const String locked = 'Our Space is locked.';
  static const String photoLocked = 'This photo could not be unlocked.';
  static const String specialMoment = 'A special moment';
  static const String photoAlt = 'Polaroid Memory';
  static const String deleteLabel = 'Delete memory';
  static const String deleteConfirm = 'Delete this precious memory? This cannot be undone.';
  static const String alreadyRemoved = 'That memory was already removed.';
  static const String deleteFailed = 'Delete failed.';
  static String deleteFailedWith(String message) => 'Delete failed: $message';

  static const String fullPolaroid = 'Full polaroid';

  static const String modalTitle = 'Add New Polaroid';
  static const String modalSubtitle = 'Kept just between you two';
  static const String captureOrChoose = 'Capture or choose a photo together';
  static const String camera = 'Camera';
  static const String gallery = 'Gallery';
  static const String changePhoto = 'Change Photo';
  static const String previewAlt = 'Preview';
  static const String captionLabel = 'Polaroid Caption';
  static const String captionHint = 'Write a sweet note or memory...';
  static const String dateLabel = 'Date Taken';
  static const String pinIt = 'Pin it up 💕';
  static const String developingPolaroid = 'Developing Polaroid...';
  static const String gettingReady = 'Getting it ready...';
  static const String tuckingAway = 'Tucking it away safely...';
  static const String savingScrapbook = 'Saving to your scrapbook...';
  static const String fillCaption = 'Please fill out this field.';
  static const String lockedTryAgain = 'Our Space is locked. Unlock it and try again.';
  static const String saveFailed = 'Could not save this memory. Please try again.';
  static String saveFailedWith(String message) => 'Could not save this memory: $message';
  static const String cameraFailed = 'We could not open your camera just now. Please try again.';
  static const String galleryFailed = 'We could not open your photos just now. Please try again.';

  static const int captionMaxLength = 280;
}
