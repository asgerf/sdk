library kernel.util.reader;

import 'dart:convert';
import 'package:kernel/canonical_name.dart';

class Reader {
  final List<int> bytes;
  List<String> _stringTable;
  List<CanonicalName> _canonicalNames;
  int index = 0;

  Reader(this.bytes, [CanonicalName root]) {
    root ??= new CanonicalName.root();
    _readFooter(root);
  }

  int readByte() {
    return bytes[index++];
  }

  int readUInt() {
    var byte = readByte();
    if (byte & 0x80 == 0) {
      // 0xxxxxxx
      return byte;
    } else if (byte & 0x40 == 0) {
      // 10xxxxxx
      return ((byte & 0x3F) << 8) | readByte();
    } else {
      // 11xxxxxx
      return ((byte & 0x3F) << 24) |
          (readByte() << 16) |
          (readByte() << 8) |
          readByte();
    }
  }

  String readString() {
    return _stringTable[readUInt()];
  }

  int _readFixedUInt32At(int position) {
    return (bytes[position] << 24) +
        (bytes[position + 1] << 16) +
        (bytes[position + 2] << 8) +
        bytes[position + 3];
  }

  void _readFooter(CanonicalName root) {
    int stringTableOffset = _readFixedUInt32At(bytes.length - 4);
    int canonicalNameTableOffset = _readFixedUInt32At(bytes.length - 8);
    _readStringTable(stringTableOffset);
    _readCanonicalNameTable(canonicalNameTableOffset, root);
  }

  void _readStringTable(int offset) {
    index = offset;
    int numberOfStrings = readUInt();
    _stringTable = new List<String>(numberOfStrings);
    for (int i = 0; i < numberOfStrings; ++i) {
      int length = readUInt();
      _stringTable[i] =
          const Utf8Decoder().convert(bytes, index, index + length);
      index += length;
    }
  }

  void _readCanonicalNameTable(int offset, CanonicalName root) {
    index = offset;
    int numberOfCanonicalNames = readUInt();
    _canonicalNames = new List<CanonicalName>(numberOfCanonicalNames);
    for (int i = 0; i < numberOfCanonicalNames; ++i) {
      int biasedParentIndex = readUInt();
      var name = readString();
      if (biasedParentIndex == 0) {
        _canonicalNames[i] = root;
      } else {
        var parent = _canonicalNames[biasedParentIndex - 1];
        _canonicalNames[i] = parent.getChild(name);
      }
    }
  }
}
