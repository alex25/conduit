import 'package:conduit/src/http/serializable.dart';

/// An exception thrown when an ORM property validator is violated.
///
/// Behaves the same as [SerializableException].
class ValidationException extends SerializableException {
  ValidationException(List<String> errors) : super(errors);
}
