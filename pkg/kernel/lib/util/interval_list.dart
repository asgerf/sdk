library kernel.util.interval_list;

import 'dart:typed_data';

class IntervalListBuilder {
  final List<int> _events = <int>[];

  void addInterval(int start, int end) {
    // Add an event point for each interval end point, using the low bit to
    // distinguish opening from closing end points. Closing end points should
    // have the high bit to ensure they occur after an opening end point.
    _events.add(start << 1);
    _events.add((end << 1) + 1);
  }

  void addSingleton(int x) {
    addInterval(x, x + 1);
  }

  void addIntervalList(Uint32List intervals) {
    for (int i = 0; i < intervals.length; i += 2) {
      addInterval(intervals[i], intervals[i + 1]);
    }
  }

  /// Builds the union of all the intervals added to the build so far.
  ///
  /// This invalidates the interval list builder.
  ///
  /// If [requiredIntervalCount] is given, at least this number of intervals
  /// must overlap at a given point for that to be included in the set.
  /// If this is set to the number of intervals added, the result corresponds
  /// to the intersection of the intervals.
  Uint32List buildIntervalList([int requiredIntervalCount = 1]) {
    // Sort the event points and sweep left to right while tracking how many
    // intervals we are currently inside.  Record an interval end point when the
    // number of intervals drop below the required count increase to the
    // required count.
    // Event points are encoded so that an opening end point occur before a
    // closing end point at the same value.
    _events.sort();
    int insideCount = 0; // The number of intervals we are currently inside.
    int storeIndex = 0;
    for (int i = 0; i < _events.length; ++i) {
      int event = _events[i];
      if (event & 1 == 0) {
        // Start point
        ++insideCount;
        if (insideCount == requiredIntervalCount) {
          // Store the results temporarily back in the event array.
          _events[storeIndex++] = event >> 1;
        }
      } else {
        // End point
        if (insideCount == requiredIntervalCount) {
          _events[storeIndex++] = event >> 1;
        }
        --insideCount;
      }
    }
    // Copy the results over to a typed array of the correct length.
    var result = new Uint32List(storeIndex);
    for (int i = 0; i < storeIndex; ++i) {
      result[i] = _events[i];
    }
    return result;
  }
}

bool intervalListContains(Uint32List intervalList, int x) {
  int low = 0, high = intervalList.length - 1;
  if (high == -1 || x < intervalList[0] || intervalList[high] <= x) {
    return false;
  }
  // Find the lower bound of x in the list.
  // If the lower bound is at an even index, the lower bound is an opening point
  // of an interval that contains x, otherwise it is a closing point of an
  // interval below x and there is no interval containing x.
  while (low < high) {
    int mid = high - ((high - low) >> 1); // Get middle, rounding up.
    int pivot = intervalList[mid];
    if (pivot <= x) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low == high && (low & 1) == 0;
}

int intervalListSize(Uint32List intervalList) {
  int size = 0;
  for (int i = 0; i < intervalList.length; i += 2) {
    size += intervalList[i + 1] - intervalList[i];
  }
  return size;
}

bool listEquals(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (int i = 0; i < first.length; ++i) {
    if (first[i] != second[i]) {
      return false;
    }
  }
  return true;
}
