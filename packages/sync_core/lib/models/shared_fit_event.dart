import 'shared_fit_draft.dart';

enum SharedFitEventType { draft, error }

class SharedFitEvent {
  final SharedFitEventType type;
  final SharedFitDraft? draft;
  final String? message;

  const SharedFitEvent._({required this.type, this.draft, this.message});

  const SharedFitEvent.draft(SharedFitDraft draft)
    : this._(type: SharedFitEventType.draft, draft: draft);

  const SharedFitEvent.error(String message)
    : this._(type: SharedFitEventType.error, message: message);
}
