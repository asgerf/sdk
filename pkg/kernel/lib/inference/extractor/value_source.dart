import 'constraint_builder.dart';
import '../key.dart';
import '../value.dart';

abstract class ValueSource {
  void generateAssignmentTo(
      ConstraintBuilder builder, Key destination, int mask);

  void generateEscape(ConstraintBuilder builder);

  bool isBottom(int mask);

  Value get value;
}

class ValueSourceWithNullability extends ValueSource {
  final ValueSource base, nullability;

  ValueSourceWithNullability(this.base, this.nullability);

  void generateAssignmentTo(
      ConstraintBuilder builder, Key destination, int mask) {
    base.generateAssignmentTo(builder, destination, mask);
    nullability.generateAssignmentTo(builder, destination, Flags.null_);
  }

  void generateEscape(ConstraintBuilder builder) {
    base.generateEscape(builder);
  }

  bool isBottom(int mask) => base.isBottom(mask) && nullability.isBottom(mask);

  Value get value {
    var baseValue = base.value;
    var nullabilityValue = nullability.value;
    if (baseValue.canBeNull || !nullabilityValue.canBeNull) return baseValue;
    return new Value(baseValue.baseClass, baseValue.flags | Flags.null_);
  }
}
