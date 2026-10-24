import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/source.dart';
import '../providers/source_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/import_export_service.dart';
import '../widgets/category_badge.dart';
import '../widgets/font_size_controls.dart';
import 'source_feed_screen.dart';
import 'substack_login_screen.dart';

class SourcesTab extends StatelessWidget {
  const SourcesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SourceProvider>();
    final sources = provider.sources;
    final categories = provider.categories;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sources (${sources.length})'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.import_export),
            tooltip: 'Import / Export',
            onSelected: (value) => _handleMenuAction(context, value),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export_opml',
                child: ListTile(
                  leading: Icon(Icons.upload_file),
                  title: Text('Export OPML'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import_opml',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Import OPML'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'export_csv',
                child: ListTile(
                  leading: Icon(Icons.vpn_key),
                  title: Text('Export Substacks (CSV)'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import_csv',
                child: ListTile(
                  leading: Icon(Icons.vpn_key_outlined),
                  title: Text('Import Substacks (CSV)'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _FontSizeSection(),
          const Divider(height: 1),
          _CategoriesSection(categories: categories),
          const Divider(height: 1),
          ..._buildGroupedSources(context, sources, categories),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add source'),
      ),
    );
  }

  List<Widget> _buildGroupedSources(
      BuildContext context, List<Source> sources, List<String> categories) {
    if (sources.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              'No sources added yet.\nTap "Add source" to start.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];

    // Group sources by category
    for (final cat in categories) {
      final matching = sources
          .where((s) => s.category.trim().toLowerCase() == cat.toLowerCase())
          .toList();
      if (matching.isNotEmpty) {
        widgets.add(_CategoryGroupHeader(
          title: cat,
          count: matching.length,
          onManage: () => _showCategoryOptions(context, cat),
        ));
        for (final source in matching) {
          widgets.add(_SourceTile(source: source));
        }
      }
    }

    // Remaining / Uncategorized sources
    final catSet = categories.map((c) => c.toLowerCase()).toSet();
    final uncategorized = sources
        .where((s) =>
            s.category.trim().isEmpty ||
            s.category.toLowerCase() == 'custom' ||
            !catSet.contains(s.category.trim().toLowerCase()))
        .toList();

    if (uncategorized.isNotEmpty) {
      widgets.add(const _CategoryGroupHeader(
        title: 'Other',
        count: null,
      ));
      for (final source in uncategorized) {
        widgets.add(_SourceTile(source: source));
      }
    }

    return widgets;
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'export_opml':
        _exportOpml(context);
        break;
      case 'import_opml':
        _importOpml(context);
        break;
      case 'export_csv':
        _exportCsv(context);
        break;
      case 'import_csv':
        _importCsv(context);
        break;
    }
  }

  Future<void> _exportOpml(BuildContext context) async {
    final sources = context.read<SourceProvider>().sources;
    final service = ImportExportService();
    final opml = service.exportOpml(sources);

    final tempDir = await getTemporaryDirectory();
    final file = await service.writeToTempFile(
        opml, 'pluralis_sources.opml', tempDir.path);

    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _importOpml(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final service = ImportExportService();
      final sources = service.importOpml(content);

      if (!context.mounted) return;

      if (sources.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No sources found in OPML file')),
        );
        return;
      }

      await context.read<SourceProvider>().addSources(sources);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${sources.length} sources')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e')),
        );
      }
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final sources = context.read<SourceProvider>().sources;
    final service = ImportExportService();
    final csv = service.exportSubstackCsv(sources);

    final hasSubstacks =
        sources.any((s) => s.cookie != null && s.cookie!.isNotEmpty);
    if (!hasSubstacks) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No paid Substack sources with cookies to export')),
        );
      }
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final file = await service.writeToTempFile(
        csv, 'pluralis_substacks.csv', tempDir.path);

    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _importCsv(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final service = ImportExportService();
      final sources = service.importSubstackCsv(content);

      if (!context.mounted) return;

      if (sources.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Substack sources found in CSV')),
        );
        return;
      }

      await context.read<SourceProvider>().addSources(sources);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Imported ${sources.length} Substack sources with cookies')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e')),
        );
      }
    }
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.rss_feed),
                title: const Text('Add RSS source'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddRssSheet(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_open, color: Color(0xFFFF6719)),
                title: const Text('Add Substack (paid)'),
                subtitle: const Text('Requires sign-in for full articles'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddSubstackSheet(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Add category'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddCategorySheet(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddRssSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final rssCtrl = TextEditingController();
    final provider = context.read<SourceProvider>();
    final categories = provider.categories;
    String selectedCategory = categories.isNotEmpty ? categories.first : 'custom';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Add RSS source',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: rssCtrl,
                    decoration: const InputDecoration(
                      labelText: 'RSS URL',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCategory,
                          isDense: true,
                          isExpanded: true,
                          items: [
                            ...categories.map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                )),
                            const DropdownMenuItem(
                              value: 'custom',
                              child: Text('Uncategorized'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedCategory = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(88, 48),
                        ),
                        onPressed: () {
                          final name = nameCtrl.text.trim();
                          var rss = rssCtrl.text.trim();
                          if (name.isEmpty || rss.isEmpty) return;

                          if (rss.contains('substack.com') && !rss.endsWith('/feed')) {
                            rss = rss.endsWith('/') ? '${rss}feed' : '$rss/feed';
                          }

                          final id = name
                              .toLowerCase()
                              .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
                          final source = Source(
                            id: id,
                            name: name,
                            url: rss,
                            rss: rss,
                            category: selectedCategory,
                            lang: 'EN',
                            isDefault: false,
                          );
                          provider.addSource(source);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddSubstackSheet(BuildContext context) {
    final urlCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Add Substack publication',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Publication URL',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              const Text(
                'You will be asked to sign in to access paid content.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 48),
                    ),
                    onPressed: () async {
                      final url = urlCtrl.text.trim();
                      if (url.isEmpty) return;
                      Navigator.pop(ctx);

                      final cookie = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubstackLoginScreen(),
                        ),
                      );

                      if (cookie == null || !context.mounted) return;

                      final uri = Uri.tryParse(url);
                      final name = uri?.host
                              .replaceAll('.substack.com', '')
                              .replaceAll('www.', '') ??
                          url;
                      final id =
                          'substack_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
                      final rss = url.endsWith('/feed') ? url : '$url/feed';

                      final source = Source(
                        id: id,
                        name: name,
                        url: url,
                        rss: rss,
                        category: 'substack',
                        lang: 'EN',
                        tag: 'paid',
                        isDefault: false,
                        cookie: cookie,
                      );

                      if (context.mounted) {
                        context.read<SourceProvider>().addSource(source);
                      }
                    },
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCategorySheet(BuildContext context) {
    final nameCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'New category',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 48),
                    ),
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isNotEmpty) {
                        context.read<SourceProvider>().addCategory(name);
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryOptions(BuildContext context, String category) {
    final provider = context.read<SourceProvider>();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename category'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameCategorySheet(context, category);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete category',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.deleteCategory(category);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameCategorySheet(BuildContext context, String oldName) {
    final nameCtrl = TextEditingController(text: oldName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Rename category',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 48),
                    ),
                    onPressed: () {
                      final newName = nameCtrl.text.trim();
                      if (newName.isNotEmpty) {
                        context
                            .read<SourceProvider>()
                            .renameCategory(oldName, newName);
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoriesSection extends StatelessWidget {
  final List<String> categories;
  const _CategoriesSection({required this.categories});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Categories (${categories.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: Colors.black87,
                ),
              ),
              InkWell(
                onTap: () {
                  final state =
                      context.findAncestorWidgetOfExactType<SourcesTab>();
                  state?._showAddCategorySheet(context);
                },
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 4),
                      Text('Add category', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: categories.map((cat) {
                return InkWell(
                  onTap: () {
                    final state =
                        context.findAncestorWidgetOfExactType<SourcesTab>();
                    state?._showCategoryOptions(context, cat);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black54, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cat,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.more_vert, size: 14, color: Colors.black54),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryGroupHeader extends StatelessWidget {
  final String title;
  final int? count;
  final VoidCallback? onManage;

  const _CategoryGroupHeader({
    required this.title,
    this.count,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            count != null
                ? '${title.toUpperCase()} ($count)'
                : title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.black87,
            ),
          ),
          if (onManage != null)
            InkWell(
              onTap: onManage,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(Icons.more_horiz, size: 18, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final Source source;
  const _SourceTile({required this.source});

  void _showSourceOptions(BuildContext context) {
    final provider = context.read<SourceProvider>();
    final feedProvider = context.read<FeedProvider>();
    final hasCookie = source.cookie != null && source.cookie!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Change category'),
                subtitle: Text(
                  source.category.isNotEmpty && source.category != 'custom'
                      ? 'Current: ${source.category}'
                      : 'Current: None',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChangeCategorySheet(context, provider, feedProvider);
                },
              ),
              if (hasCookie) ...[
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Refresh cookie'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final cookie = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubstackLoginScreen(),
                      ),
                    );
                    if (cookie != null && context.mounted) {
                      provider.updateSourceCookie(source.id, cookie);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.key_off),
                  title: const Text('Clear cookie'),
                  onTap: () {
                    Navigator.pop(ctx);
                    provider.updateSourceCookie(source.id, null);
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete source',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, provider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangeCategorySheet(BuildContext context,
      SourceProvider sourceProvider, FeedProvider feedProvider) {
    final categories = sourceProvider.categories;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Select category for "${source.name}"',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              for (final cat in categories)
                ListTile(
                  title: Text(cat),
                  trailing: source.category.toLowerCase() == cat.toLowerCase()
                      ? const Icon(Icons.check, color: Colors.black)
                      : null,
                  onTap: () {
                    sourceProvider.updateSourceCategory(source.id, cat);
                    feedProvider.updateSourceCategory(source.id, cat);
                    Navigator.pop(ctx);
                  },
                ),
              ListTile(
                title: const Text('None (Uncategorized)'),
                trailing: (source.category.isEmpty || source.category == 'custom')
                    ? const Icon(Icons.check, color: Colors.black)
                    : null,
                onTap: () {
                  sourceProvider.updateSourceCategory(source.id, 'custom');
                  feedProvider.updateSourceCategory(source.id, 'custom');
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, SourceProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete source?'),
        content: Text('Remove "${source.name}" from your sources?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              provider.removeSource(source.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SourceProvider>();
    final feedActiveIds = context.watch<FeedProvider>().activeSourceIds;
    final isFeedActive = feedActiveIds.contains(source.id);
    final showInactive =
        source.active && feedActiveIds.isNotEmpty && !isFeedActive;
    final hasCookie = source.cookie != null && source.cookie!.isNotEmpty;

    return ListTile(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SourceFeedScreen(source: source),
        ),
      ),
      onLongPress: () => _showSourceOptions(context),
      title: Row(
        children: [
          Expanded(
            child: Text(
              source.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (hasCookie) ...[
            const SizedBox(width: 4),
            const Icon(Icons.vpn_key, size: 14, color: Color(0xFFFF6719)),
          ],
          const SizedBox(width: 6),
          CategoryBadge(category: source.category),
          const SizedBox(width: 4),
          if (showInactive)
            const _StatusChip(label: 'inactive', color: Colors.red)
          else if (source.active && feedActiveIds.isNotEmpty)
            const _StatusChip(label: 'active', color: Colors.green),
          const SizedBox(width: 4),
          _LangChip(lang: source.lang),
        ],
      ),
      trailing: Switch(
        value: source.active,
        onChanged: (_) => provider.toggleSource(source.id),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FontSizeSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return ListTile(
      title: const Text('Font size'),
      subtitle: Text(
        settings.fontSizeIsAuto
            ? 'Auto-calculated for this screen'
            : 'Set manually — long-press size to reset',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: const FontSizeControls(),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String lang;
  const _LangChip({required this.lang});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        lang,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}
