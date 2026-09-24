/// 读取老版 Excel `.xls`（OLE2 复合文档 + BIFF8）中的单元格网格。
///
/// 为什么需要它：pub 上的 `excel` 包**只支持 .xlsx**，
/// 而国内高校教务导出的是老版 `.xls`（OLE2 格式），
/// 直接丢给 `Excel.decodeBytes` 会抛
/// `Excel format unsupported. Only .xlsx files are supported`。
///
/// 这里实现一个**只读**的最小解析器，覆盖教务课表会用到的东西：
/// - OLE2 容器：读 FAT / 目录 / 定位 `Workbook`（或 `Book`）流
/// - BIFF8 记录：`LABELSST`(文本单元格) / `NUMBER`、`RK`、`MULRK`(数值)
/// - `SST` 共享字符串表（含 CONTINUE 跨记录拼接）
///
/// 不支持的（教务课表不会用到）：公式求值、图表、格式、加密。
library;

import 'dart:typed_data';

/// 从 `.xls` 字节读出第一个工作表的网格。
///
/// 返回的网格已按 [maxRow]/[maxCol] 补齐为矩形；
/// 空单元格为 `''`。解析失败返回空网格（调用方据此给出提示）。
class XlsWorkbook {
  const XlsWorkbook({required this.grid, required this.sheetNames});

  /// 第一个非空工作表的网格。
  final List<List<String>> grid;

  /// 工作簿里所有工作表名（BOUNDSHEET 记录）。
  final List<String> sheetNames;

  bool get isEmpty => grid.isEmpty || grid.every((r) => r.every((c) => c.isEmpty));

  /// 解析入口。任何结构异常都返回空结果而不抛异常 ——
  /// 导入流程应给出友好提示，而不是崩溃。
  static XlsWorkbook parse(Uint8List bytes) {
    try {
      return _XlsReader(bytes).read();
    } catch (_) {
      return const XlsWorkbook(grid: [], sheetNames: []);
    }
  }
}

// ---------------------------------------------------------------------------
// OLE2 容器
// ---------------------------------------------------------------------------

class _OleHeader {
  int sectorSize = 512;
  int miniSectorSize = 64;
  int miniStreamCutoff = 4096;
  int dirStartSector = 0;
  int miniFatStartSector = 0;
  int miniFatSectorCount = 0;
  final List<int> fatSectors = [];
}

class _OleEntry {
  _OleEntry(this.name, this.type, this.startSector, this.size);
  final String name;
  final int type; // 1=storage 2=stream 5=root
  final int startSector;
  final int size;
}

/// 一个极简的 OLE2 读取器：只做到「取出某个流」。
class _Ole {
  _Ole(this.data);

  final Uint8List data;
  late final _OleHeader header = _readHeader();
  List<int>? _fat;
  List<_OleEntry>? _entries;

  static const _endOfChain = -2;
  static const _freeSector = -1;

  _OleHeader _readHeader() {
    if (data.length < 512) throw const FormatException('文件过小，不是 OLE2');
    // 校验 OLE2 魔数
    const magic = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    for (var i = 0; i < 8; i++) {
      if (data[i] != magic[i]) {
        throw const FormatException('不是 OLE2 复合文档（可能不是真正的 .xls）');
      }
    }
    final h = _OleHeader();
    h.sectorSize = 1 << _u16(30);
    h.miniSectorSize = 1 << _u16(32);
    h.dirStartSector = _i32(48);
    h.miniStreamCutoff = _i32(56);
    h.miniFatStartSector = _i32(60);
    h.miniFatSectorCount = _i32(64);
    for (var i = 0; i < 109; i++) {
      final v = _i32(76 + i * 4);
      if (v >= 0) h.fatSectors.add(v);
    }
    return h;
  }

  int _u16(int off) => data[off] | (data[off + 1] << 8);

  int _i32(int off) =>
      data[off] | (data[off + 1] << 8) | (data[off + 2] << 16) | (data[off + 3] << 24);

  int _sectorOffset(int sector) => 512 + sector * header.sectorSize;

  /// 读 FAT（扇区分配表）。
  List<int> get fat {
    if (_fat != null) return _fat!;
    final out = <int>[];
    for (final s in header.fatSectors) {
      final off = _sectorOffset(s);
      if (off + header.sectorSize > data.length) continue;
      for (var i = 0; i < header.sectorSize ~/ 4; i++) {
        out.add(_i32(off + i * 4));
      }
    }
    return _fat = out;
  }

  /// 沿 FAT 链读出一串扇区（用于主 FAT 链）。
  Uint8List _readChain(int startSector, int? limit) {
    final out = <int>[];
    var sector = startSector;
    var guard = 0;
    while (sector >= 0 && sector < fat.length && guard++ < 200000) {
      final off = _sectorOffset(sector);
      if (off + header.sectorSize > data.length) break;
      out.addAll(data.sublist(off, off + header.sectorSize));
      sector = fat[sector];
      if (limit != null && out.length >= limit) break;
    }
    final bytes = Uint8List.fromList(out);
    if (limit != null && bytes.length > limit) {
      return Uint8List.sublistView(bytes, 0, limit);
    }
    return bytes;
  }

  /// 目录条目。
  List<_OleEntry> get entries {
    if (_entries != null) return _entries!;
    final dirBytes = _readChain(header.dirStartSector, null);
    final out = <_OleEntry>[];
    for (var i = 0; i + 128 <= dirBytes.length; i += 128) {
      final nameLen = dirBytes[i + 64] | (dirBytes[i + 65] << 8);
      if (nameLen < 2 || nameLen > 64) continue;
      // 目录名是 UTF-16LE
      final chars = <int>[];
      for (var k = 0; k + 1 < nameLen - 2; k += 2) {
        chars.add(dirBytes[i + k] | (dirBytes[i + k + 1] << 8));
      }
      out.add(_OleEntry(
        String.fromCharCodes(chars),
        dirBytes[i + 66],
        _i32From(dirBytes, i + 116),
        _i32From(dirBytes, i + 120),
      ));
    }
    return _entries = out;
  }

  int _i32From(Uint8List b, int off) =>
      b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

  /// 取出一个流的内容（自动处理「小流走迷你 FAT」的情况）。
  Uint8List? openStream(String name) {
    final entry = entries.firstWhere(
      (e) => (e.name == name) && e.type == 2,
      orElse: () => _OleEntry('', 0, -1, 0),
    );
    if (entry.name.isEmpty) return null;

    if (entry.size < header.miniStreamCutoff) {
      final mini = _readMiniStream(entry);
      if (mini != null) return mini;
    }
    return _readChain(entry.startSector, entry.size);
  }

  /// 读「迷你流」（小于 4096 字节的流存在根条目的迷你流里）。
  Uint8List? _readMiniStream(_OleEntry entry) {
    final root = entries.firstWhere(
      (e) => e.type == 5,
      orElse: () => _OleEntry('', 0, -1, 0),
    );
    if (root.startSector < 0) return null;

    final miniStream = _readChain(root.startSector, root.size);
    final miniFat = _readChain(header.miniFatStartSector, null);

    final out = <int>[];
    var sector = entry.startSector;
    var guard = 0;
    while (sector >= 0 && sector * header.miniSectorSize < miniStream.length &&
        guard++ < 200000) {
      final off = sector * header.miniSectorSize;
      final end = (off + header.miniSectorSize).clamp(0, miniStream.length);
      out.addAll(miniStream.sublist(off, end));
      if (off + 4 > miniFat.length) break;
      final next = _i32From(miniFat, off ~/ header.miniSectorSize * 4);
      if (next == _endOfChain || next == _freeSector) break;
      sector = next;
    }
    if (out.isEmpty) return null;
    final bytes = Uint8List.fromList(out);
    return bytes.length > entry.size
        ? Uint8List.sublistView(bytes, 0, entry.size)
        : bytes;
  }
}

// ---------------------------------------------------------------------------
// BIFF8 记录解析
// ---------------------------------------------------------------------------

class _XlsReader {
  _XlsReader(this.rawBytes);

  final Uint8List rawBytes;

  XlsWorkbook read() {
    final ole = _Ole(rawBytes);
    // 老版本叫 Book，新版本叫 Workbook
    final stream = ole.openStream('Workbook') ?? ole.openStream('Book');
    if (stream == null || stream.isEmpty) {
      return const XlsWorkbook(grid: [], sheetNames: []);
    }
    final records = _collectRecords(stream);
    final sst = _readSst(records);
    final sheetNames = _readSheetNames(records);
    final grid = _buildGrid(records, sst);
    return XlsWorkbook(grid: grid, sheetNames: sheetNames);
  }

  /// 把整个流切分成 BIFF 记录列表。
  ///
  /// 每条记录：`[id(2), length(2), payload(length)]`。
  /// 连续的空记录（id=0,len=0）表示结束。
  List<_Record> _collectRecords(Uint8List s) {
    final out = <_Record>[];
    var p = 0;
    while (p + 4 <= s.length) {
      final id = s[p] | (s[p + 1] << 8);
      final len = s[p + 2] | (s[p + 3] << 8);
      if (id == 0 && len == 0) break;
      final body = (p + 4 + len <= s.length)
          ? Uint8List.sublistView(s, p + 4, p + 4 + len)
          : Uint8List.sublistView(s, p + 4, s.length);
      out.add(_Record(id, Uint8List.fromList(body)));
      p += 4 + len;
    }
    return out;
  }

  /// 工作表名（BOUNDSHEET）。
  List<String> _readSheetNames(List<_Record> records) {
    final out = <String>[];
    for (var i = 0; i < records.length; i++) {
      if (records[i].id != _recBoundsheet) continue;
      if (i + 1 >= records.length) break;
      final next = records[i + 1];
      if (next.id == _recSst || next.id == _recEof) continue;
      final name = _readUnicodeString(next.body, 0);
      if (name != null && name.value.isNotEmpty) out.add(name.value);
    }
    return out;
  }

  /// SST 共享字符串表。
  ///
  /// 注意：字符串可能跨 `CONTINUE` 记录，需要按 BIFF8 规则拼接
  /// （跨记录时首字节会重新给出「是否压缩」标志）。
  List<String> _readSst(List<_Record> records) {
    final out = <String>[];
    for (var i = 0; i < records.length; i++) {
      if (records[i].id != _recSst) continue;

      // 收集 SST 及其后续的 CONTINUE
      final chunks = <Uint8List>[records[i].body];
      for (var j = i + 1; j < records.length; j++) {
        if (records[j].id != _recContinue) break;
        chunks.add(records[j].body);
      }
      _parseSstChunks(chunks, out);
      break;
    }
    return out;
  }

  /// 解析 SST（含跨 CONTINUE 的字符串）。
  void _parseSstChunks(List<Uint8List> chunks, List<String> out) {
    if (chunks.isEmpty || chunks.first.length < 8) return;

    // 用「虚拟游标」跨块连续读取
    var chunkIndex = 0;
    var pos = 8; // 跳过 total / unique 计数

    int remaining() => chunks[chunkIndex].length - pos;

    bool ensure(int need) {
      // 若当前块剩余不足，且还有下一块，则跨块
      while (remaining() < need && chunkIndex + 1 < chunks.length) {
        chunkIndex++;
        pos = 0;
      }
      return remaining() >= need;
    }

    int readByte() => chunks[chunkIndex][pos++];

    while (true) {
      if (!ensure(3)) break;
      final charCount = chunks[chunkIndex][pos] |
          (chunks[chunkIndex][pos + 1] << 8);
      final flags = chunks[chunkIndex][pos + 2];
      pos += 3;
      var compressed = (flags & 0x01) == 0;
      var richRuns = 0;
      var extSize = 0;
      if ((flags & 0x08) != 0) {
        if (!ensure(2)) break;
        richRuns = chunks[chunkIndex][pos] |
            (chunks[chunkIndex][pos + 1] << 8);
        pos += 2;
      }
      if ((flags & 0x04) != 0) {
        if (!ensure(4)) break;
        extSize = chunks[chunkIndex][pos] |
            (chunks[chunkIndex][pos + 1] << 8) |
            (chunks[chunkIndex][pos + 2] << 16) |
            (chunks[chunkIndex][pos + 3] << 24);
        pos += 4;
      }

      final chars = <int>[];
      var need = charCount;
      while (need > 0) {
        if (remaining() == 0) {
          // 跨到下一块：首字节重新给压缩标志
          if (chunkIndex + 1 >= chunks.length) break;
          chunkIndex++;
          pos = 0;
          compressed = (readByte() & 0x01) == 0;
          continue;
        }
        if (compressed) {
          chars.add(readByte());
          need--;
        } else {
          if (remaining() < 2) {
            if (chunkIndex + 1 >= chunks.length) break;
            chunkIndex++;
            pos = 0;
            compressed = (readByte() & 0x01) == 0;
            continue;
          }
          chars.add(readByte() | (readByte() << 8));
          need--;
        }
      }
      // 跳过 rich text / 扩展
      var skip = richRuns * 4 + extSize;
      while (skip > 0) {
        if (remaining() == 0) {
          if (chunkIndex + 1 >= chunks.length) break;
          chunkIndex++;
          pos = 0;
          continue;
        }
        readByte();
        skip--;
      }
      out.add(String.fromCharCodes(chars));
    }
  }

  /// 用 LABELSST / NUMBER / RK / MULRK 组装网格。
  List<List<String>> _buildGrid(List<_Record> records, List<String> sst) {
    final cells = <int, Map<int, String>>{};
    var maxRow = -1;
    var maxCol = -1;

    void put(int row, int col, String value) {
      if (value.isEmpty) return;
      cells.putIfAbsent(row, () => {})[col] = value;
      if (row > maxRow) maxRow = row;
      if (col > maxCol) maxCol = col;
    }

    for (final rec in records) {
      final b = rec.body;
      switch (rec.id) {
        // LABELSST: row(2) col(2) xf(2) isst(4)
        case _recLabelSst:
          if (b.length < 10) break;
          final row = b[0] | (b[1] << 8);
          final col = b[2] | (b[3] << 8);
          final isst = b[6] | (b[7] << 8) | (b[8] << 16) | (b[9] << 24);
          if (isst >= 0 && isst < sst.length) put(row, col, sst[isst]);
        // NUMBER: row(2) col(2) xf(2) double(8)
        case _recNumber:
          if (b.length < 14) break;
          final row = b[0] | (b[1] << 8);
          final col = b[2] | (b[3] << 8);
          final value = _readDouble(b, 6);
          put(row, col, _formatNumber(value));
        // RK: row(2) col(2) xf(2) rk(4)
        case _recRk:
          if (b.length < 10) break;
          final row = b[0] | (b[1] << 8);
          final col = b[2] | (b[3] << 8);
          final rk = b[6] | (b[7] << 8) | (b[8] << 16) | (b[9] << 24);
          put(row, col, _formatNumber(_decodeRk(rk)));
        // MULRK: row(2) colFirst(2) [xf(2) rk(4)]* colLast(2)
        case _recMulRk:
          if (b.length < 6) break;
          final row = b[0] | (b[1] << 8);
          final colFirst = b[2] | (b[3] << 8);
          var p = 4;
          var col = colFirst;
          while (p + 6 <= b.length - 2) {
            final rk = b[p + 2] | (b[p + 3] << 8) | (b[p + 4] << 16) | (b[p + 5] << 24);
            put(row, col, _formatNumber(_decodeRk(rk)));
            col++;
            p += 6;
          }
      }
    }

    if (maxRow < 0) return const [];
    return List<List<String>>.generate(
      maxRow + 1,
      (r) => List<String>.generate(maxCol + 1, (c) => cells[r]?[c] ?? ''),
    );
  }

  double _readDouble(Uint8List b, int off) {
    final bytes = Uint8List(8);
    // BIFF 里是 little-endian 的 IEEE754
    for (var i = 0; i < 8; i++) {
      bytes[i] = b[off + i];
    }
    return ByteData.sublistView(bytes).getFloat64(0, Endian.little);
  }

  /// RK 是一种压缩过的数值编码。
  double _decodeRk(int rk) {
    final isDiv100 = (rk & 0x01) != 0;
    final isInt = (rk & 0x02) != 0;
    double value;
    if (isInt) {
      value = (rk >> 2).toSigned(30).toDouble();
    } else {
      final bits = (rk & 0xFFFFFFFC) << 32;
      final bd = ByteData(8)..setInt64(0, bits, Endian.little);
      value = bd.getFloat64(0, Endian.little);
    }
    return isDiv100 ? value / 100 : value;
  }

  String _formatNumber(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return v.toString();
  }

  /// 读 BIFF8 Unicode 字符串（BOUNDSHEET 用）。
  _UniStr? _readUnicodeString(Uint8List b, int offset) {
    if (offset + 3 > b.length) return null;
    final len = b[offset] | (b[offset + 1] << 8);
    final flags = b[offset + 2];
    var pos = offset + 3;
    final compressed = (flags & 0x01) == 0;
    final chars = <int>[];
    if (compressed) {
      if (pos + len > b.length) return null;
      for (var i = 0; i < len; i++) {
        chars.add(b[pos + i]);
      }
    } else {
      if (pos + len * 2 > b.length) return null;
      for (var i = 0; i < len; i++) {
        chars.add(b[pos + i * 2] | (b[pos + i * 2 + 1] << 8));
      }
    }
    return _UniStr(String.fromCharCodes(chars));
  }
}

class _UniStr {
  _UniStr(this.value);
  final String value;
}

class _Record {
  _Record(this.id, this.body);
  final int id;
  final Uint8List body;
}

// BIFF8 记录号
const _recNumber = 0x0203;
const _recLabelSst = 0x00FD;
const _recRk = 0x027E;
const _recMulRk = 0x00BD;
const _recSst = 0x00FC;
const _recContinue = 0x003C;
const _recBoundsheet = 0x0085;
const _recEof = 0x000A;
