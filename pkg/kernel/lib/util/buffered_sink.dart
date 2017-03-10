library kernel.util.buffered_sink;

import 'dart:typed_data';

/// Puts a buffer in front of a [Sink<List<int>>].
class BufferedSink {
  static const int SIZE = 100000;
  static const int SMALL = 10000;
  final Sink<List<int>> _sink;
  Uint8List _buffer = new Uint8List(SIZE);
  int length = 0;
  int _bytesFlushed = 0;

  BufferedSink(this._sink);

  int get numberOfBytesWritten => length + _bytesFlushed;
  int get numberOfBytesFlushed => _bytesFlushed;

  void addByte(int byte) {
    _buffer[length++] = byte;
    if (length == SIZE) {
      _sink.add(_buffer);
      _buffer = new Uint8List(SIZE);
      length = 0;
      _bytesFlushed += SIZE;
    }
  }

  void addBytes(List<int> bytes) {
    // Avoid copying a large buffer into the another large buffer. Also, if
    // the bytes buffer is too large to fit in our own buffer, just emit both.
    if (length + bytes.length < SIZE &&
        (bytes.length < SMALL || length < SMALL)) {
      if (length == 0) {
        _sink.add(bytes);
        _bytesFlushed += bytes.length;
      } else {
        _buffer.setRange(length, length + bytes.length, bytes);
        length += bytes.length;
      }
    } else if (bytes.length < SMALL) {
      // Flush as much as we can in the current buffer.
      _buffer.setRange(length, SIZE, bytes);
      _sink.add(_buffer);
      _bytesFlushed += _buffer.length;
      // Copy over the remainder into a new buffer. It is guaranteed to fit
      // because the input byte array is small.
      int alreadyEmitted = SIZE - length;
      int remainder = bytes.length - alreadyEmitted;
      _buffer = new Uint8List(SIZE);
      _buffer.setRange(0, remainder, bytes, alreadyEmitted);
      length = remainder;
    } else {
      _sink.add(_buffer.sublist(0, length));
      _sink.add(bytes);
      _buffer = new Uint8List(SIZE);
      length = 0;
      _bytesFlushed += length + bytes.length;
    }
  }

  void flush() {
    _sink.add(_buffer.sublist(0, length));
    _buffer = new Uint8List(SIZE);
    _bytesFlushed += length;
    length = 0;
  }

  void flushAndDestroy() {
    _sink.add(_buffer.sublist(0, length));
    _bytesFlushed += length;
    length = 0;
  }
}
