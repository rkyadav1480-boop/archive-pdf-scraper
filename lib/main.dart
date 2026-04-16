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
          Expan
