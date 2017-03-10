// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.util.writer;

import 'dart:convert';
import 'package:kernel/canonical_name.dart';
import 'buffered_sink.dart';

class Writer {
  final List<String> _stringTable = <String>[];
  final Map<String, int> _stringIndex = <String, int>{};
  final List<CanonicalName> _canonicalNames = <CanonicalName>[];
  final BufferedSink _sink;

  Writer(Sink<List<int>> sink) : _sink = new BufferedSink(sink);

  void writeByte(int byte) {
    _sink.addByte(byte);
  }

  void writeBytes(List<int> bytes) {
    _sink.addBytes(bytes);
  }

  void writeUInt(int value) {
    assert(value >= 0 && value >> 30 == 0);
    if (value < 0x80) {
      writeByte(value);
    } else if (value < 0x4000) {
      writeByte((value >> 8) | 0x80);
      writeByte(value & 0xFF);
    } else {
      writeByte((value >> 24) | 0xC0);
      writeByte((value >> 16) & 0xFF);
      writeByte((value >> 8) & 0xFF);
      writeByte(value & 0xFF);
    }
  }

  void writeString(String string) {
    writeUInt(_getStringIndex(string));
  }

  void writeCanonicalName(CanonicalName name) {
    assert(name != null);
    writeUInt(1 + _getCanonicalNameIndex(name));
  }

  void writeOptionalCanonicalName(CanonicalName name) {
    if (name == null) {
      writeByte(0);
    } else {
      writeUInt(1 + _getCanonicalNameIndex(name));
    }
  }

  void writeFixedUInt32(int value) {
    writeByte((value >> 24) & 0xFF);
    writeByte((value >> 16) & 0xFF);
    writeByte((value >> 8) & 0xFF);
    writeByte(value & 0xFF);
  }

  int _getStringIndex(String string) {
    int index = _stringIndex[string];
    if (index == null) {
      index = _stringTable.length;
      _stringIndex[string] = index;
      _stringTable.add(string);
    }
    return index;
  }

  int _getCanonicalNameIndex(CanonicalName name) {
    assert(name != null);
    if (name.index != -1) return name.index;
    if (name.parent != null) {
      _getCanonicalNameIndex(name.parent);
    }
    int index = name.index = _canonicalNames.length;
    _canonicalNames.add(name);
    return index;
  }

  void finish() {
    int canonicalNameTableOffset = _sink.numberOfBytesWritten;
    _writeCanonicalNameTable();
    int stringTableOffset = _sink.numberOfBytesWritten;
    _writeStringTable();
    writeFixedUInt32(canonicalNameTableOffset);
    writeFixedUInt32(stringTableOffset);
    _sink.flushAndDestroy();
  }

  void _writeStringTable() {
    writeUInt(_stringTable.length);
    for (var string in _stringTable) {
      var utf8 = UTF8.encode(string);
      writeUInt(utf8.length);
      writeBytes(utf8);
    }
  }

  void _writeCanonicalNameTable() {
    writeUInt(_canonicalNames.length);
    for (var canonicalName in _canonicalNames) {
      var parent = canonicalName.parent;
      if (parent == null) {
        writeByte(0);
      } else {
        writeUInt(parent.index + 1);
      }
      writeString(canonicalName.name);
    }
  }
}
