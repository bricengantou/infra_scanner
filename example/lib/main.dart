import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infra_scanner/infra_scanner.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF2563EB); // bleu moderne
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.light,
        fontFamily: 'Roboto',
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});
  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  StreamSubscription<BarcodeEvent>? _sub;
  BarcodeEvent? lastEvent;
  final List<String> _history = [];
  bool opened = false;
  bool continuous = false;
  ScanOutMode mode = ScanOutMode.broadcast;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      setState(() => busy = true);
      opened = await InfraScanner.instance.open();
      await InfraScanner.instance.setOutScanMode(mode);
      _sub = InfraScanner.instance.onScan.listen((e) {
        setState(() {
          lastEvent = e;
          _history.insert(0, e.code);
          if (_history.length > 10) _history.removeLast();
        });
      });
    } catch (e) {
      _toast('Erreur init : $e');
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    InfraScanner.instance.close();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _toggleOpen() async {
    try {
      setState(() => busy = true);
      if (opened) {
        await InfraScanner.instance.close();
      } else {
        opened = await InfraScanner.instance.open();
        await InfraScanner.instance.setOutScanMode(mode);
      }
      setState(() => opened = !opened ? opened : true);
      if (!opened) setState(() {});
    } catch (e) {
      _toast('Erreur: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _toggleContinuous() async {
    try {
      setState(() {
        continuous = !continuous;
        busy = true;
      });
      await InfraScanner.instance.setContinuous(on: continuous);
    } catch (e) {
      continuous = !continuous; // rollback
      _toast('Erreur: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _setMode(ScanOutMode m) async {
    try {
      setState(() => busy = true);
      await InfraScanner.instance.setOutScanMode(m);
      setState(() => mode = m);
    } catch (e) {
      _toast('Erreur: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _startScan() async {
    try {
      await InfraScanner.instance.start();
    } catch (e) {
      _toast('Start scan: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Infra Scanner'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'À propos',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Infra Scanner',
              applicationVersion: 'Demo UI',
              children: const [
                Text('Demo de scan matériel via plugin Flutter.'),
              ],
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.surface, cs.surfaceVariant.withOpacity(0.4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // STATUTS
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(
                        icon: opened ? Icons.link : Icons.link_off,
                        label: opened ? 'Connecté' : 'Fermé',
                        color: opened ? cs.primary : cs.outline,
                        onTap: _toggleOpen,
                      ),
                      _StatusChip(
                        icon: continuous ? Icons.bolt : Icons.bolt_outlined,
                        label: continuous ? 'Continu ON' : 'Continu OFF',
                        color: continuous ? cs.tertiary : cs.outline,
                        onTap: _toggleContinuous,
                      ),
                      _ModeDropdown(
                        mode: mode,
                        onChanged: (m) => _setMode(m),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // BOUTON SCAN ROND
                  Center(
                    child: _ScanCircleButton(
                      enabled: opened && !busy,
                      onTap: _startScan,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // DERNIER CODE
                  _LastCodeCard(
                    event: lastEvent,
                    onCopy: () async {
                      final txt = lastEvent?.code ?? '';
                      if (txt.isEmpty) return;
                      await Clipboard.setData(ClipboardData(text: txt));
                      _toast('Copié dans le presse-papiers');
                    },
                  ),

                  const SizedBox(height: 16),

                  // ACTIONS
                  _ActionsGrid(
                    onOpen: _toggleOpen,
                    onClose: () async {
                      try {
                        setState(() => busy = true);
                        await InfraScanner.instance.close();
                        setState(() => opened = false);
                      } catch (e) {
                        _toast('Erreur: $e');
                      } finally {
                        setState(() => busy = false);
                      }
                    },
                    onBroadcast: () => _setMode(ScanOutMode.broadcast),
                    onReset: () async {
                      try {
                        await InfraScanner.instance.reset();
                        _toast('Scanner réinitialisé');
                      } catch (e) {
                        _toast('Erreur reset: $e');
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // HISTORIQUE
                  if (_history.isNotEmpty) _HistoryList(history: _history),
                ],
              ),
            ),
          ),
          if (busy)
            const IgnorePointer(
              ignoring: true,
              child: Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(minHeight: 3),
              ),
            ),
        ],
      ),
    );
  }
}

/* -------------------------- Widgets décorés -------------------------- */

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: ShapeDecoration(
          color: color.withOpacity(0.10),
          shape: StadiumBorder(
            side: BorderSide(color: color.withOpacity(0.35)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeDropdown extends StatelessWidget {
  final ScanOutMode mode;
  final ValueChanged<ScanOutMode> onChanged;
  const _ModeDropdown({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = const [
      DropdownMenuItem(
        value: ScanOutMode.broadcast,
        child: Text('Mode: Broadcast'),
      ),
      DropdownMenuItem(
        value: ScanOutMode.editBox,
        child: Text('Mode: Edit box'),
      ),
      DropdownMenuItem(
        value: ScanOutMode.keyboard,
        child: Text('Mode: Clavier'),
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ScanOutMode>(
          value: mode,
          items: items,
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

class _ScanCircleButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _ScanCircleButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: enabled
                ? [cs.primaryContainer, cs.primary]
                : [cs.surfaceVariant, cs.outline],
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withOpacity(enabled ? 0.3 : 0.1),
              blurRadius: enabled ? 24 : 8,
              spreadRadius: enabled ? 4 : 1,
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.qr_code_scanner_rounded,
            size: 42,
            color: enabled ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LastCodeCard extends StatelessWidget {
  final BarcodeEvent? event;
  final VoidCallback onCopy;
  const _LastCodeCard({required this.event, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final code = event?.code ?? '';
    final type = event?.barcodeType ?? '';
    final aim = event?.aimId ?? '';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.confirmation_number, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: code.isEmpty
                    ? Text(
                        'Aucun scan pour le moment',
                        key: const ValueKey('empty'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      )
                    : Column(
                        key: const ValueKey('code'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            code,
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                              fontFamily: 'RobotoMono',
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (type.isNotEmpty)
                                _Pill(text: type, icon: Icons.category),
                              if (aim.isNotEmpty) const SizedBox(width: 6),
                              if (aim.isNotEmpty)
                                _Pill(text: aim, icon: Icons.abc),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
            IconButton(
              tooltip: 'Copier',
              onPressed: code.isEmpty ? null : onCopy,
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Pill({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: cs.secondaryContainer.withOpacity(0.6),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsGrid extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onBroadcast;
  final VoidCallback onReset;
  const _ActionsGrid({
    required this.onOpen,
    required this.onClose,
    required this.onBroadcast,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth > 520;
        final children = [
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.power_settings_new),
            label: const Text('Ouvrir'),
          ),
          FilledButton.tonalIcon(
            onPressed: onClose,
            icon: const Icon(Icons.power_off),
            label: const Text('Fermer'),
          ),
          OutlinedButton.icon(
            onPressed: onBroadcast,
            icon: const Icon(Icons.sensors),
            label: const Text('Broadcast'),
          ),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset'),
          ),
        ];

        if (isWide) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: children
                .map((w) => Expanded(
                    child: Padding(padding: const EdgeInsets.all(6), child: w)))
                .toList(),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: children
              .map((w) => SizedBox(width: double.infinity, child: w))
              .toList(),
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<String> history;
  const _HistoryList({required this.history});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historique (10 derniers)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: cs.outlineVariant),
              itemBuilder: (context, i) {
                final code = history[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: cs.primaryContainer,
                    child: Text('${i + 1}',
                        style: TextStyle(color: cs.primary, fontSize: 12)),
                  ),
                  title: Text(
                    code,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Copier',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: code)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
