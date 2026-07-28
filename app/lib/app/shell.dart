import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Persistent bottom navigation shell.
///
/// Follows GoGlyder's `MainScreen` pattern — one shell wrapping each page so
/// the bar never rebuilds or animates out between tabs — with two changes:
///
///  * An `IndexedStack` keeps every tab's state and scroll position alive.
///    Rebuilding a tab on each visit throws away scroll offset and re-fires
///    every network request, which is the most common way a tabbed app feels
///    cheap.
///  * Outline icons for inactive, filled for active. The weight change reads
///    faster than colour alone, and it still works for colour-blind users.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.tabs});

  final List<ShellTab> tabs;

  @override
  State<AppShell> createState() => _AppShellState();
}

class ShellTab {
  const ShellTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final WidgetBuilder builder;
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GGColors.bgDeep,
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: [
          for (final tab in widget.tabs) Builder(builder: tab.builder),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: _index,
        tabs: widget.tabs,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.tabs,
    required this.onTap,
  });

  final int index;
  final List<ShellTab> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: GGColors.surface2,
        border: Border(top: BorderSide(color: GGColors.hairline)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset, top: GGSpacing.s),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _NavItem(
                tab: tabs[i],
                selected: i == index,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final ShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? GGColors.volt : GGColors.textTertiary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GGRadius.m),
      splashColor: GGColors.volt.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GGSpacing.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A short indicator above the active icon. Cheaper to read at a
            // glance than colour alone, and it gives the bar a spine.
            AnimatedContainer(
              duration: GGDuration.fast,
              curve: Curves.easeOut,
              height: 3,
              width: selected ? 22 : 0,
              decoration: BoxDecoration(
                color: GGColors.volt,
                borderRadius: BorderRadius.circular(2),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: GGColors.volt.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(height: GGSpacing.s - 2),
            Icon(selected ? tab.activeIcon : tab.icon, size: 23, color: color),
            const SizedBox(height: 3),
            Text(
              tab.label,
              style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
