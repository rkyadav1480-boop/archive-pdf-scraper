import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';

// ══════════════════════════════════════════════════════════════
//   CONSTANTS
// ══════════════════════════════════════════════════════════════

const kArchiveSearch = 'https://archive.org/advancedsearch.php';
const kArchiveDownload = 'https://archive.org/download';
const kArchiveDetails = 'https://archive.org/details';
const kArchiveMeta = 'https://archive.org/metadata';
const kResultsPerPage = 20;

const kLanguages = {
  'Hindi': 'hin',
  'English': 'eng',
  'Urdu': 'urd',
  'Bengali': 'ben',
  'Tamil': 'tam',
  'Telugu': 'tel',
  'Marathi': 'mar',
  'Gujarati': 'guj',
  'Punjabi': 'pan',
  'Sanskrit': 'san',
};

const kCategories = [
  'novel', 'fiction', 'science', 'history', 'biography',
  'religion', 'poetry', 'philosophy', 'technology', 'children',
  'law', 'medicine', 'education', 'comics', 'magazine',
];

// ══════════════════════════════════════════════════════════════
//   MODELS
// ══════════════════════════════════════════════════════════════

class Book {
  final String identifier;
  final String title;
  final String creator;
  final String year;
  final int downloads;

  Book({
    required this.identifier,
    required this.title,
    required this.creator,
    required this.year,
    required this.downloads,
  });

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        identifier: j['identifier'] ?? '',
        title: (j['title'] ?? 'Unknown Title').toString(),
        creator: (j['creator'] ?? 'Unknown Author').toString(),
        year: (j['year'] ?? '?').toString(),
        downloads: int.tryParse(j['downloads']?.toString() ?? '0') ?? 0,
      );
}

class PdfFile {
  final String filename;
  final double sizeMb;
  final String url;

  PdfFile({required this.filename, required this.sizeMb, required this.url});
}

// ══════════════════════════════════════════════════════════════
//   MAIN
// ══════════════════════════════════════════════════════════════

void main() {
  runApp(const ArchiveApp());
}

class ArchiveApp extends StatelessWidget {
  const ArchiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Archive PDF Scraper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const SearchScreen(),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//   SEARCH SCREEN
// ══════════════════════════════════════════════════════════════

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _selectedLang = 'Hindi';
  String _selectedCat = 'novel';
  final _keywordCtrl = TextEditingController();
  bool _loading = false;
  List<Book> _results = [];
  int _page = 1;
  int _total = 0;
  String _error = '';

  // ── API ──────────────────────────────────────────────────────

  Future<void> _search({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = '';
      if (page == 1) _results = [];
    });

    final langCode = kLanguages[_selectedLang] ?? 'hin';
    final keyword = _keywordCtrl.text.trim();

    final parts = [
      'mediatype:texts',
      'format:pdf',
      'language:$langCode',
      'subject:"$_selectedCat"',
      if (keyword.isNotEmpty) keyword,
    ];

    final uri = Uri.parse(kArchiveSearch).replace(queryParameters: {
      'q': parts.join(' AND '),
      'fl[]': 'identifier,title,creator,year,downloads',
      'sort[]': 'downloads desc',
      'rows': '$kResultsPerPage',
      'page': '$page',
      'output': 'json',
    });

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body);
      final docs = (data['response']?['docs'] as List?) ?? [];
      final total = data['response']?['numFound'] ?? 0;

      setState(() {
        _results = docs.map((d) => Book.fromJson(d)).toList();
        _total = total;
        _page = page;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Search error: $e';
        _loading = false;
      });
    }
  }

  // ── UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Icon(Icons.auto_stories, color: Color(0xFFE8A838)),
            SizedBox(width: 10),
            Text(
              'Archive PDF Scraper',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xFFE8A838)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LinksLogScreen()),
            ),
            tooltip: 'Saved Links',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: Color(0xFFE8A838)),
            onPressed: _openDownloadsFolder,
            tooltip: 'Downloads',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersCard(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFE8A838)),
                  )
                : _error.isNotEmpty
                    ? _buildError()
                    : _results.isEmpty
                        ? _buildEmptyState()
                        : _buildResultsList(),
          ),
          if (_results.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildFiltersCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DropdownField<String>(
                  label: '🌐 Language',
                  value: _selectedLang,
                  items: kLanguages.keys.toList(),
                  onChanged: (v) => setState(() => _selectedLang = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DropdownField<String>(
                  label: '📂 Category',
                  value: _selectedCat,
                  items: kCategories,
                  onChanged: (v) => setState(() => _selectedCat = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '🔤 Keyword / Author / Title (optional)',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                    filled: true,
                    fillColor: const Color(0xFF2A2A3E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFFE8A838)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _loading ? null : () => _search(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8A838),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Search',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '📊 $_total results found  •  Page $_page',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      itemBuilder: (ctx, i) => _BookCard(
        book: _results[i],
        index: i + 1,
      ),
    );
  }

  Widget _buildPagination() {
    final hasNext = _results.length >= kResultsPerPage;
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed:
                _page > 1 ? () => _search(page: _page - 1) : null,
            icon: const Icon(Icons.arrow_back_ios, size: 14),
            label: const Text('Previous'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE8A838),
            ),
          ),
          Text(
            'Page $_page',
            style: const TextStyle(color: Colors.white70),
          ),
          TextButton.icon(
            onPressed: hasNext ? () => _search(page: _page + 1) : null,
            icon: const Icon(Icons.arrow_forward_ios, size: 14),
            label: const Text('Next'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE8A838),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red70)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off,
              color: Colors.white.withOpacity(0.3), size: 64),
          const SizedBox(height: 16),
          Text(
            'Koi result nahi.\nFilter badlo ya search karo.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Future<void> _openDownloadsFolder() async {
    final dir = await _getDownloadDir();
    if (await dir.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloads: ${dir.path}')),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════
//   BOOK CARD
// ══════════════════════════════════════════════════════════════

class _BookCard extends StatelessWidget {
  final Book book;
  final int index;

  const _BookCard({required this.book, required this.index});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E30),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.white.withOpacity(0.08),
          width: 0.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BookDetailScreen(book: book),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8A838).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Color(0xFFE8A838),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 12, color: Colors.white38),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            book.creator,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.calendar_today,
                            size: 12, color: Colors.white38),
                        const SizedBox(width: 4),
                        Text(
                          book.year,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.download, size: 12, color: Color(0xFF4CAF50)),
                        const SizedBox(width: 4),
                        Text(
                          '${book.downloads}',
                          style: const TextStyle(
                              color: Color(0xFF4CAF50), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//   BOOK DETAIL SCREEN
// ══════════════════════════════════════════════════════════════

class BookDetailScreen extends StatefulWidget {
  final Book book;

  const BookDetailScreen({super.key, required this.book});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  bool _loadingPdfs = true;
  List<PdfFile> _pdfs = [];
  String _error = '';
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _fetchPdfs();
  }

  Future<void> _fetchPdfs() async {
    try {
      final uri =
          Uri.parse('$kArchiveMeta/${widget.book.identifier}/files');
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      final data = jsonDecode(resp.body);
      final files = (data['result'] as List?) ?? [];

      final pdfs = files
          .where((f) =>
              (f['name'] as String? ?? '').toLowerCase().endsWith('.pdf'))
          .map((f) => PdfFile(
                filename: f['name'] ?? 'unknown.pdf',
                sizeMb: (int.tryParse(f['size']?.toString() ?? '0') ?? 0) /
                    (1024 * 1024),
                url:
                    '$kArchiveDownload/${widget.book.identifier}/${f['name']}',
              ))
          .toList();

      setState(() {
        _pdfs = pdfs;
        _loadingPdfs = false;
        if (pdfs.length == 1) _selected.add(0);
      });
    } catch (e) {
      setState(() {
        _error = 'PDF list load nahi hui: $e';
        _loadingPdfs = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          widget.book.title,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE8A838)),
      ),
      body: Column(
        children: [
          // Book info header
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E1E30),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFE8A838).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.menu_book,
                      color: Color(0xFFE8A838), size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.book.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 6),
                      Text('👤 ${widget.book.creator}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                      Text(
                          '📅 ${widget.book.year}   ⬇ ${widget.book.downloads} downloads',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // PDF list
          Expanded(
            child: _loadingPdfs
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFFE8A838)))
                : _error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error,
                              style: const TextStyle(color: Colors.red70)),
                        ),
                      )
                    : _pdfs.isEmpty
                        ? const Center(
                            child: Text('Koi PDF nahi mila.',
                                style: TextStyle(color: Colors.white54)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _pdfs.length,
                            itemBuilder: (ctx, i) => _PdfRow(
                              pdf: _pdfs[i],
                              index: i,
                              selected: _selected.contains(i),
                              onToggle: (v) => setState(() {
                                if (v) {
                                  _selected.add(i);
                                } else {
                                  _selected.remove(i);
                                }
                              }),
                            ),
                          ),
          ),

          // Action buttons
          if (!_loadingPdfs && _pdfs.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1A1A2E),
              child: Column(
                children: [
                  if (_pdfs.length > 1)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_selected.length} selected',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            if (_selected.length == _pdfs.length) {
                              _selected.clear();
                            } else {
                              _selected.addAll(
                                  List.generate(_pdfs.length, (i) => i));
                            }
                          }),
                          child: Text(
                            _selected.length == _pdfs.length
                                ? 'Deselect All'
                                : 'Select All',
                            style: const TextStyle(color: Color(0xFFE8A838)),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selected.isEmpty
                              ? null
                              : _saveLinksOnly,
                          icon: const Icon(Icons.link),
                          label: const Text('Save Links'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE8A838),
                            side: const BorderSide(color: Color(0xFFE8A838)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _selected.isEmpty
                              ? null
                              : _downloadSelected,
                          icon: const Icon(Icons.download),
                          label: const Text('Download'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE8A838),
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _downloadSelected() async {
    final selectedPdfs = _selected.map((i) => _pdfs[i]).toList();
    for (final pdf in selectedPdfs) {
      await _saveLink(pdf, downloaded: false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DownloadScreen(
            pdf: pdf,
            bookTitle: widget.book.title,
            identifier: widget.book.identifier,
          ),
        ),
      );
    }
  }

  Future<void> _saveLinksOnly() async {
    final selectedPdfs = _selected.map((i) => _pdfs[i]).toList();
    for (final pdf in selectedPdfs) {
      await _saveLink(pdf, downloaded: false);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selectedPdfs.length} link(s) saved!'),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
  }

  Future<void> _saveLink(PdfFile pdf, {required bool downloaded}) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('saved_links') ?? [];
    final entry = jsonEncode({
      'title': widget.book.title,
      'identifier': widget.book.identifier,
      'filename': pdf.filename,
      'size_mb': pdf.sizeMb.toStringAsFixed(2),
      'url': pdf.url,
      'archive_page': '$kArchiveDetails/${widget.book.identifier}',
      'status': downloaded ? 'DOWNLOADED' : 'LINK SAVED',
      'time': DateTime.now().toIso8601String(),
    });

    // Duplicate check
    final key = '${widget.book.identifier}/${pdf.filename}';
    if (!existing.any((e) {
      try {
        return jsonDecode(e)['identifier'] == widget.book.identifier &&
            jsonDecode(e)['filename'] == pdf.filename;
      } catch (_) {
        return false;
      }
    })) {
      existing.add(entry);
      await prefs.setStringList('saved_links', existing);
    }
  }
}

// ══════════════════════════════════════════════════════════════
//   PDF ROW WIDGET
// ══════════════════════════════════════════════════════════════

class _PdfRow extends StatelessWidget {
  final PdfFile pdf;
  final int index;
  final bool selected;
  final ValueChanged<bool> onToggle;

  const _PdfRow({
    required this.pdf,
    required this.index,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected
          ? const Color(0xFFE8A838).withOpacity(0.1)
          : const Color(0xFF1E1E30),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? const Color(0xFFE8A838).withOpacity(0.5)
              : Colors.white.withOpacity(0.05),
          width: selected ? 1 : 0.5,
        ),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: (v) => onToggle(v ?? false),
        activeColor: const Color(0xFFE8A838),
        checkColor: Colors.black,
        title: Text(
          pdf.filename,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${pdf.sizeMb.toStringAsFixed(2)} MB',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        secondary: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A3E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.picture_as_pdf,
              color: Color(0xFFE8A838), size: 18),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//   DOWNLOAD SCREEN
// ══════════════════════════════════════════════════════════════

class DownloadScreen extends StatefulWidget {
  final PdfFile pdf;
  final String bookTitle;
  final String identifier;

  const DownloadScreen({
    super.key,
    required this.pdf,
    required this.bookTitle,
    required this.identifier,
  });

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  double _progress = 0;
  double _downloadedMb = 0;
  double _totalMb = 0;
  String _status = 'Shuru ho raha hai...';
  bool _done = false;
  bool _failed = false;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    // Request storage permission
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }

    final dir = await _getDownloadDir();
    await dir.create(recursive: true);

    final safeName = widget.pdf.filename
        .replaceAll(RegExp(r'[\\/*?:"<>|]'), '_')
        .substring(0, widget.pdf.filename.length > 75 ? 75 : widget.pdf.filename.length);

    final dest = File('${dir.path}/$safeName');
    final tmp = File('${dir.path}/$safeName.tmp');

    // Resume check
    if (await dest.exists()) {
      final expectedSize = (widget.pdf.sizeMb * 1024 * 1024).toInt();
      if (dest.lengthSync() >= expectedSize * 0.95) {
        setState(() {
          _status = '⏭️ Pehle se download hai!';
          _progress = 1.0;
          _done = true;
          _savedPath = dest.path;
        });
        return;
      }
    }

    setState(() => _status = '📥 Downloading...');

    try {
      final request = http.Request('GET', Uri.parse(widget.pdf.url));
      final response = await request.send().timeout(const Duration(minutes: 10));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? (widget.pdf.sizeMb * 1024 * 1024).toInt();
      int done = 0;

      final sink = tmp.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        done += chunk.length;
        setState(() {
          _progress = total > 0 ? done / total : 0;
          _downloadedMb = done / (1024 * 1024);
          _totalMb = total / (1024 * 1024);
          _status = '📥 Downloading...';
        });
      }
      await sink.close();

      await tmp.rename(dest.path);

      // Save to links log
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('saved_links') ?? [];
      final entry = jsonEncode({
        'title': widget.bookTitle,
        'identifier': widget.identifier,
        'filename': widget.pdf.filename,
        'size_mb': widget.pdf.sizeMb.toStringAsFixed(2),
        'url': widget.pdf.url,
        'archive_page': '$kArchiveDetails/${widget.identifier}',
        'status': 'DOWNLOADED',
        'time': DateTime.now().toIso8601String(),
        'local_path': dest.path,
      });
      existing.add(entry);
      await prefs.setStringList('saved_links', existing);

      setState(() {
        _status = '✅ Download complete!';
        _done = true;
        _progress = 1.0;
        _savedPath = dest.path;
      });
    } catch (e) {
      if (await tmp.exists()) await tmp.delete();
      setState(() {
        _status = '❌ Download fail: $e';
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Downloading PDF',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Color(0xFFE8A838)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // File icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _done
                    ? const Color(0xFF4CAF50).withOpacity(0.15)
                    : _failed
                        ? Colors.red.withOpacity(0.15)
                        : const Color(0xFFE8A838).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _done
                    ? Icons.check_circle
                    : _failed
                        ? Icons.error
                        : Icons.download_rounded,
                color: _done
                    ? const Color(0xFF4CAF50)
                    : _failed
                        ? Colors.red
                        : const Color(0xFFE8A838),
                size: 44,
              ),
            ),
            const SizedBox(height: 24),

            // Book title
            Text(
              widget.bookTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              widget.pdf.filename,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 12,
                backgroundColor: const Color(0xFF2A2A3E),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _done
                      ? const Color(0xFF4CAF50)
                      : _failed
                          ? Colors.red
                          : const Color(0xFFE8A838),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Progress text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _status,
                  style: TextStyle(
                    color: _failed
                        ? Colors.red
                        : _done
                            ? const Color(0xFF4CAF50)
                            : Colors.white70,
                    fontSize: 13,
                  ),
                ),
                if (_totalMb > 0)
                  Text(
                    '${_downloadedMb.toStringAsFixed(1)} / ${_totalMb.toStringAsFixed(1)} MB',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),

            if (_progress > 0)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${(_progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: Color(0xFFE8A838), fontWeight: FontWeight.bold),
                ),
              ),

            const SizedBox(height: 40),

            // Action buttons after completion
            if (_done && _savedPath != null) ...[
              ElevatedButton.icon(
                onPressed: () => OpenFilex.open(_savedPath!),
                icon: const Icon(Icons.open_in_new),
                label: const Text('PDF Kholein'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.popUntil(
                    context, (route) => route.isFirst),
                icon: const Icon(Icons.search),
                label: const Text('Wapas Search Par'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE8A838),
                  side: const BorderSide(color: Color(0xFFE8A838)),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '📁 Saved: $_savedPath',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],

            if (_failed)
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _failed = false;
                    _progress = 0;
                    _status = 'Dobara try ho raha hai...';
                  });
                  _startDownload();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//   LINKS LOG SCREEN
// ══════════════════════════════════════════════════════════════

class LinksLogScreen extends StatefulWidget {
  const LinksLogScreen({super.key});

  @override
  State<LinksLogScreen> createState() => _LinksLogScreenState();
}

class _LinksLogScreenState extends State<LinksLogScreen> {
  List<Map<String, dynamic>> _links = [];

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('saved_links') ?? [];
    setState(() {
      _links = raw.map((e) {
        try {
          return Map<String, dynamic>.from(jsonDecode(e));
        } catch (_) {
          return <String, dynamic>{};
        }
      }).where((e) => e.isNotEmpty).toList().reversed.toList();
    });
  }

  Future<void> _clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_links');
    setState(() => _links = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Saved Links Log',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Color(0xFFE8A838)),
        actions: [
          if (_links.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E30),
                    title: const Text('Sab delete karein?',
                        style: TextStyle(color: Colors.white)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (ok == true) _clearAll();
              },
            ),
        ],
      ),
      body: _links.isEmpty
          ? const Center(
              child: Text('Koi saved link nahi hai.',
                  style: TextStyle(color: Colors.white54, fontSize: 16)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _links.length,
              itemBuilder: (ctx, i) {
                final link = _links[i];
                final isDownloaded =
                    link['status']?.toString().contains('DOWNLOADED') ?? false;
                return Card(
                  color: const Color(0xFF1E1E30),
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: isDownloaded
                            ? const Color(0xFF4CAF50).withOpacity(0.3)
                            : Colors.white.withOpacity(0.06)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isDownloaded
                                  ? Icons.check_circle
                                  : Icons.link,
                              color: isDownloaded
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFE8A838),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDownloaded
                                    ? const Color(0xFF4CAF50).withOpacity(0.15)
                                    : const Color(0xFFE8A838).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isDownloaded ? '✅ DOWNLOADED' : '🔗 LINK SAVED',
                                style: TextStyle(
                                  color: isDownloaded
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFE8A838),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          link['title'] ?? 'Unknown',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '📄 ${link['filename'] ?? ''}  •  💾 ${link['size_mb'] ?? '?'} MB',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '🕐 ${link['time']?.substring(0, 16).replaceAll('T', ' ') ?? ''}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//   HELPERS
// ══════════════════════════════════════════════════════════════

Future<Directory> _getDownloadDir() async {
  if (Platform.isAndroid) {
    return Directory('/storage/emulated/0/ArchivePDFs');
  }
  final base = await getApplicationDocumentsDirectory();
  return Directory('${base.path}/ArchivePDFs');
}

// ══════════════════════════════════════════════════════════════
//   DROPDOWN HELPER WIDGET
// ══════════════════════════════════════════════════════════════

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A3E),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: const Color(0xFF2A2A3E),
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            items: items
                .map((i) => DropdownMenuItem(
                      value: i,
                      child: Text(i.toString(),
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
