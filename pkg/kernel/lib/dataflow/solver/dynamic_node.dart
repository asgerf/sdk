import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/solver/solver.dart';

class DynamicNode extends WorkItem {
  DynamicNode _parent = null;
  int _rank = 0;

  DynamicNode get root {
    var parent = _parent;
    if (parent == null) return this;
    return _parent = parent.root;
  }

  static bool unify(DynamicNode first, DynamicNode second) {
    first = first.root;
    second = second.root;
    if (identical(first, second)) return false;
    if (first._rank < second._rank) {
      var tmp = first;
      first = second;
      second = tmp;
    } else if (first._rank == second._rank) {
      ++first._rank;
    }
    second._parent = first;
    first.dependencies = mergeLists(first.dependencies, second.dependencies);
    second.dependencies = null;
    first.isInWorklist = first.isInWorklist || second.isInWorklist;
    return true;
  }

  static List<Constraint> mergeLists(
      List<Constraint> first, List<Constraint> second) {
    if (first.length >= second.length) {
      first.addAll(second);
      return first;
    } else {
      second.addAll(first);
      return second;
    }
  }
}
