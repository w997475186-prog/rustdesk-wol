import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/input_model.dart';

/// One key on the on-screen panel.
///
/// [name] is what goes over the wire: either a `KEY_MAP` entry ("VK_ENTER")
/// or a single character ("a"), which the peer turns into a raw character key.
class _Key {
  final String label;
  final String name;
  final int flex;
  final String? mod; // sticky modifier this key toggles

  const _Key(this.label, {String? name, this.flex = 10, this.mod})
      : name = name ?? label;
}

/// Bottom keyboard panel, modelled on what UU shows on a phone: its own
/// surface instead of the system IME, so the remote view can make room for it
/// (the panel is laid out *next to* the canvas, never on top of it).
///
/// Tabs: 输入法 (hand the session to the phone IME), 快捷键 (one tap combos)
/// and 电脑键盘 (a compact QWERTY that types into the peer).
class MobileKeyPanel extends StatefulWidget {
  final InputModel input;
  final VoidCallback onOpenIme;
  final VoidCallback onClose;

  const MobileKeyPanel(
      {Key? key, required this.input, required this.onOpenIme, required this.onClose})
      : super(key: key);

  @override
  State<MobileKeyPanel> createState() => _MobileKeyPanelState();
}

class _MobileKeyPanelState extends State<MobileKeyPanel> {
  static const _tabs = ['输入法', '快捷键', '电脑键盘'];

  int _tab = 2;
  bool _ctrl = false;
  bool _alt = false;
  bool _shift = false;
  bool _win = false;

  void _clearArmed() {
    if (_ctrl || _alt || _shift || _win) {
      setState(() {
        _ctrl = false;
        _alt = false;
        _shift = false;
        _win = false;
      });
    }
  }

  /// Tap a key. Sticky modifiers (ctrl/alt/shift/win) apply to the next key and
  /// then clear, which is what people expect from a phone key panel.
  void _tap(String name,
      {bool? ctrl, bool? alt, bool? shift, bool? command}) {
    widget.input.inputKeyWith(name,
        ctrl: ctrl ?? _ctrl,
        alt: alt ?? _alt,
        shift: shift ?? _shift,
        command: command ?? _win);
    _clearArmed();
  }

  // ---------------------------------------------------------------- tabs

  Widget _tabBar() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: _tab == i ? MyTheme.accent : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(_tabs[i],
                      style: TextStyle(
                          fontSize: 15,
                          color: _tab == i ? MyTheme.accent : Colors.white70,
                          fontWeight: _tab == i
                              ? FontWeight.w600
                              : FontWeight.w400)),
                ),
              ),
            ),
          IconButton(
            iconSize: 20,
            color: Colors.white70,
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 输入法

  Widget _imeTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MyTheme.accent),
              onPressed: widget.onOpenIme,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('打开手机输入法'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '用手机自带的拼音/手写输入，适合打字。\n面板会收起，画面自动让出空间。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 快捷键

  static const _shortcuts = <_Key>[
    _Key('Ctrl+C', name: 'c'),
    _Key('Ctrl+V', name: 'v'),
    _Key('Ctrl+X', name: 'x'),
    _Key('Ctrl+Z', name: 'z'),
    _Key('Ctrl+A', name: 'a'),
    _Key('Ctrl+S', name: 's'),
    _Key('Ctrl+F', name: 'f'),
    _Key('Alt+Tab', name: 'VK_TAB'),
    _Key('Alt+F4', name: 'VK_F4'),
    _Key('Ctrl+Shift+Esc', name: 'VK_ESCAPE'),
    _Key('Win+D', name: 'd'),
    _Key('Win+E', name: 'e'),
    _Key('锁屏', name: 'LOCK_SCREEN'),
    _Key('Ctrl+Alt+Del', name: 'CTRL_ALT_DEL'),
    _Key('Esc', name: 'VK_ESCAPE'),
    _Key('Enter', name: 'VK_ENTER'),
    _Key('Tab', name: 'VK_TAB'),
    _Key('Backspace', name: 'VK_BACK'),
    _Key('Delete', name: 'VK_DELETE'),
    _Key('F5', name: 'VK_F5'),
    _Key('Home', name: 'VK_HOME'),
    _Key('End', name: 'VK_END'),
    _Key('PgUp', name: 'VK_PRIOR'),
    _Key('PgDn', name: 'VK_NEXT'),
    _Key('←', name: 'VK_LEFT'),
    _Key('↑', name: 'VK_UP'),
    _Key('↓', name: 'VK_DOWN'),
    _Key('→', name: 'VK_RIGHT'),
  ];

  /// Ctrl/Alt/Shift/Win for the combos above: they are one shot, so the label
  /// of the key tells the whole story.
  void _shortcut(_Key k) {
    final n = k.label;
    if (n.startsWith('Ctrl+Shift+')) {
      _tap(k.name, ctrl: true, shift: true);
    } else if (n.startsWith('Ctrl+Alt+')) {
      _tap(k.name, ctrl: true, alt: true);
    } else if (n.startsWith('Ctrl+')) {
      _tap(k.name, ctrl: true);
    } else if (n.startsWith('Alt+')) {
      _tap(k.name, alt: true);
    } else if (n.startsWith('Win+')) {
      _tap(k.name, command: true);
    } else {
      _tap(k.name);
    }
  }

  Widget _shortcutsTab() {
    return LayoutBuilder(builder: (context, c) {
      const gap = 8.0;
      final perRow = c.maxWidth > 640 ? 6 : (c.maxWidth > 460 ? 5 : 4);
      final w = (c.maxWidth - gap * (perRow + 1)) / perRow;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(gap),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final k in _shortcuts)
              SizedBox(
                width: w,
                height: 42,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: Color(0x33FFFFFF)),
                    backgroundColor: const Color(0x1AFFFFFF),
                  ),
                  onPressed: () => _shortcut(k),
                  child: FittedBox(
                    child: Text(k.label,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white)),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  // ---------------------------------------------------------- 电脑键盘

  Widget _keyboardTab() {
    final rows = <List<_Key>>[
      [
        const _Key('Esc', name: 'VK_ESCAPE', flex: 12),
        const _Key('1'), const _Key('2'), const _Key('3'), const _Key('4'),
        const _Key('5'), const _Key('6'), const _Key('7'), const _Key('8'),
        const _Key('9'), const _Key('0'), const _Key('-'), const _Key('='),
        const _Key('⌫', name: 'VK_BACK', flex: 14),
      ],
      [
        const _Key('Tab', name: 'VK_TAB', flex: 13),
        const _Key('q'), const _Key('w'), const _Key('e'), const _Key('r'),
        const _Key('t'), const _Key('y'), const _Key('u'), const _Key('i'),
        const _Key('o'), const _Key('p'), const _Key('['), const _Key(']'),
        const _Key('\\'),
      ],
      [
        const _Key('Caps', name: 'VK_CAPITAL', flex: 14),
        const _Key('a'), const _Key('s'), const _Key('d'), const _Key('f'),
        const _Key('g'), const _Key('h'), const _Key('j'), const _Key('k'),
        const _Key('l'), const _Key(';'), const _Key("'"),
        const _Key('⏎', name: 'VK_ENTER', flex: 14),
      ],
      [
        const _Key('Shift', name: 'VK_SHIFT', flex: 16, mod: 'shift'),
        const _Key('z'), const _Key('x'), const _Key('c'), const _Key('v'),
        const _Key('b'), const _Key('n'), const _Key('m'), const _Key(','),
        const _Key('.'), const _Key('/'),
        const _Key('↑', name: 'VK_UP', flex: 10),
      ],
      [
        const _Key('Ctrl', name: 'VK_CONTROL', flex: 12, mod: 'ctrl'),
        const _Key('⊞', name: 'Meta', flex: 10, mod: 'win'),
        const _Key('Alt', name: 'VK_MENU', flex: 10, mod: 'alt'),
        const _Key('空格', name: 'VK_SPACE', flex: 40),
        const _Key('←', name: 'VK_LEFT', flex: 10),
        const _Key('↓', name: 'VK_DOWN', flex: 10),
        const _Key('→', name: 'VK_RIGHT', flex: 10),
      ],
    ];

    return LayoutBuilder(builder: (context, c) {
      const gap = 4.0;
      final rowH = (c.maxHeight - gap * (rows.length + 1)) / rows.length;
      final fontSize = (rowH * 0.42).clamp(11.0, 18.0).toDouble();
      return Padding(
        padding: const EdgeInsets.all(gap),
        child: Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: SizedBox(
                  height: rowH,
                  child: Row(
                    children: [
                      for (final k in row)
                        Expanded(
                          flex: k.flex,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: _keyButton(
                                k, fontSize, _isArmed(k) ? MyTheme.accent : null),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  bool _isArmed(_Key k) {
    switch (k.mod) {
      case 'ctrl':
        return _ctrl;
      case 'alt':
        return _alt;
      case 'shift':
        return _shift;
      case 'win':
        return _win;
    }
    return false;
  }

  Widget _keyButton(_Key k, double fontSize, Color? active) {
    final armed = active != null;
    return InkWell(
      onTap: () {
        if (k.mod != null) {
          // Sticky modifier: highlight and wait for the next key.
          setState(() {
            switch (k.mod) {
              case 'ctrl':
                _ctrl = !_ctrl;
                break;
              case 'alt':
                _alt = !_alt;
                break;
              case 'shift':
                _shift = !_shift;
                break;
              case 'win':
                _win = !_win;
                break;
            }
          });
          return;
        }
        _tap(k.name);
      },
      child: Container(
        decoration: BoxDecoration(
          color: armed ? MyTheme.accent : const Color(0x22FFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(k.label,
                style: TextStyle(fontSize: fontSize, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF01B1B1B),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _tabBar(),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _imeTab(),
                  _shortcutsTab(),
                  _keyboardTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
