import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/features/theme_mode/views/theme_mode_bloc_utils.dart';
import 'package:Prism/theme/jam_icons_icons.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

List<Color> accentColors = [
  const Color(0xFFE57697),
  const Color(0xFFF44436),
  const Color(0xFFe91e63),
  const Color(0xFF9c27b0),
  const Color(0xFF673ab7),
  const Color(0xFF1976D2),
  const Color(0xFF03a9f4),
  const Color(0xFF00bcd4),
  const Color(0xFF009688),
  const Color(0xFF4caf50),
  const Color(0xFF8bc34a),
  const Color(0xFFcddc39),
  const Color(0xFFffc107),
  const Color(0xFFff9800),
  const Color(0xFFff5722),
  const Color(0xFF795548),
  const Color(0xFF9e9e9e),
  const Color(0xFF607d8b),
];

@RoutePage(name: 'ThemeViewRoute')
class ThemeView extends StatefulWidget {
  const ThemeView({super.key});

  @override
  State<ThemeView> createState() => _ThemeViewState();
}

class _ThemeViewState extends State<ThemeView> {
  late String _selectedMode;
  late String _selectedLightThemeId;
  late String _selectedDarkThemeId;
  late Color _selectedLightAccent;
  late Color _selectedDarkAccent;
  late bool _editingLight;

  @override
  void initState() {
    super.initState();
    _selectedLightThemeId = context.prismLightThemeId(listen: false);
    _selectedDarkThemeId = context.prismDarkThemeId(listen: false);
    _selectedLightAccent = Color(context.prismLightAccentValue(listen: false));
    _selectedDarkAccent = Color(context.prismDarkAccentValue(listen: false));
    _selectedMode = switch (context.prismThemeMode(listen: false)) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };
    _editingLight = context.prismModeStyleForWindow(listen: false) == 'Light';
  }

  ThemeData get _previewTheme {
    if (_editingLight) {
      return PrismThemeMapper.resolveLightTheme(
        themeId: _selectedLightThemeId,
        accentColorValue: _selectedLightAccent.toARGB32(),
      );
    }
    return PrismThemeMapper.resolveDarkTheme(
      themeId: _selectedDarkThemeId,
      accentColorValue: _selectedDarkAccent.toARGB32(),
    );
  }

  Color get _currentAccent => _editingLight ? _selectedLightAccent : _selectedDarkAccent;

  void _setMode(String mode) {
    context.setPrismThemeMode(mode);
    setState(() {
      _selectedMode = mode;
      if (mode == 'Light') {
        _editingLight = true;
      } else if (mode == 'Dark') {
        _editingLight = false;
      } else {
        _editingLight = context.prismModeStyleForWindow(listen: false) == 'Light';
      }
    });
  }

  void _setLightTheme(String themeId) {
    context.setPrismLightTheme(themeId);
    setState(() {
      _selectedLightThemeId = themeId;
      _editingLight = true;
    });
  }

  void _setDarkTheme(String themeId) {
    context.setPrismDarkTheme(themeId);
    setState(() {
      _selectedDarkThemeId = themeId;
      _editingLight = false;
    });
  }

  void _setAccent(Color color) {
    if (_editingLight) {
      context.setPrismLightAccent(color);
      setState(() => _selectedLightAccent = color);
    } else {
      context.setPrismDarkAccent(color);
      setState(() => _selectedDarkAccent = color);
    }
    final hex = color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
    analytics.track(AccentChangedEvent(color: hex));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).primaryColor,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(JamIcons.chevron_left),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Appearance', style: Theme.of(context).textTheme.headlineSmall),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _PreviewPanel(theme: _previewTheme, accent: _currentAccent, editingLight: _editingLight),
          const SizedBox(height: 20),
          _SectionTitle(title: 'Mode', trailing: _selectedMode),
          const SizedBox(height: 10),
          _ModeControl(selectedMode: _selectedMode, onChanged: _setMode),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Light Theme'),
          const SizedBox(height: 10),
          _ThemeStrip(
            themeIds: prismLightThemes.keys.toList(growable: false),
            selectedThemeId: _selectedLightThemeId,
            onSelected: _setLightTheme,
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Dark Theme'),
          const SizedBox(height: 10),
          _ThemeStrip(
            themeIds: prismDarkThemes.keys.toList(growable: false),
            selectedThemeId: _selectedDarkThemeId,
            onSelected: _setDarkTheme,
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: _editingLight ? 'Light Accent' : 'Dark Accent'),
          const SizedBox(height: 12),
          _AccentGrid(selected: _currentAccent, onSelected: _setAccent),
          const SizedBox(height: 20),
          Text(
            'Changes apply immediately.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.theme, required this.accent, required this.editingLight});

  final ThemeData theme;
  final Color accent;
  final bool editingLight;

  @override
  Widget build(BuildContext context) {
    final onPrimary = theme.colorScheme.secondary;
    return Container(
      height: 170,
      decoration: BoxDecoration(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onPrimary.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(editingLight ? 'Light preview' : 'Dark preview', style: theme.textTheme.titleMedium?.copyWith(color: onPrimary)),
              Container(width: 34, height: 34, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(child: _PreviewTile(color: accent, height: 64)),
              const SizedBox(width: 10),
              Expanded(child: _PreviewTile(color: onPrimary.withValues(alpha: 0.22), height: 64)),
              const SizedBox(width: 10),
              Expanded(child: _PreviewTile(color: onPrimary.withValues(alpha: 0.12), height: 64)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (trailing != null) Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ModeControl extends StatelessWidget {
  const _ModeControl({required this.selectedMode, required this.onChanged});

  final String selectedMode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'System', label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
        ButtonSegment(value: 'Light', label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
        ButtonSegment(value: 'Dark', label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
      ],
      selected: {selectedMode},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _ThemeStrip extends StatelessWidget {
  const _ThemeStrip({required this.themeIds, required this.selectedThemeId, required this.onSelected});

  final List<String> themeIds;
  final String selectedThemeId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: themeIds.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final id = themeIds[index];
          final selected = id == selectedThemeId;
          return ChoiceChip(
            label: Text(id.substring(2), maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: selected,
            onSelected: (_) => onSelected(id),
            avatar: selected ? const Icon(Icons.check, size: 16) : null,
          );
        },
      ),
    );
  }
}

class _AccentGrid extends StatelessWidget {
  const _AccentGrid({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final color in accentColors)
          _AccentDot(color: color, selected: color.toARGB32() == selected.toARGB32(), onTap: () => onSelected(color)),
      ],
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Theme.of(context).colorScheme.secondary : Colors.white54, width: selected ? 3 : 1),
        ),
        child: selected ? Icon(Icons.check, color: color.computeLuminance() > 0.55 ? Colors.black : Colors.white, size: 18) : null,
      ),
    );
  }
}
