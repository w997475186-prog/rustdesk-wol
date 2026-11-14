import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';

/// A UU style touchpad for phones: a semi transparent panel you can drag
/// anywhere on the screen, and inside it one finger moves the remote pointer
/// *relatively*.
///
/// This is deliberately not `FloatingMouse`: that one drags a mouse icon
/// around and maps its position to an absolute coordinate, so small targets
/// are painful on a phone and the icon itself covers what you want to click.
/// Here the finger never maps to a position - it only produces deltas, exactly
/// like a laptop trackpad, so the pointer glides instead of jumping.
///
/// Layout, sized from the screen instead of a fixed square:
///
///     +--------------------------+----+
///     |          handle           |    |
///     +--------------------------+ /\ |
///     |                          |----|
///     |        pad (deltas)      | \/ |
///     |                          |    |
///     +-------------+------------+----+
///     |   left      |   right         |
///     +-------------+-----------------+
class TouchpadPanel extends StatefulWidget {
  final FFI ffi;

  /// Size of the canvas the panel lives in. Not MediaQuery: the canvas is
  /// shorter than the screen once the bottom toolbar is in, and clamping against
  /// the screen let the button row slide underneath it.
  final Size bounds;

  const TouchpadPanel({Key? key, required this.ffi, required this.bounds})
      : super(key: key);

  @override
  State<TouchpadPanel> createState() => TouchpadPanelState();
}

class TouchpadPanelState extends State<TouchpadPanel> {
  static const double handleHeight = 30;
  static const double buttonHeight = 56;
  static const double scrollWidth = 54;

  /// Finger travel to pointer travel. 1.0 would make the pointer as slow as
  /// the finger, which feels sluggish on a phone screen.
  static const double speed = 1.8;

  Offset? _position;
  final Map<int, Offset> _pointers = {};
  double _scrollAcc = 0;
  bool _moved = false;
  int _downAt = 0;
  int _lastClickAt = 0;
  Timer? _repeatTimer;

  InputModel get _input => widget.ffi.inputModel;

  /// The panel sizes itself from the screen: a fixed 168px square was far too
  /// small for the buttons and made the pad feel like a toy.
  ({double w, double h, double padH}) _metrics(Size screen) {
    final w = (screen.width * 0.55).clamp(280.0, 620.0).toDouble();
    final padH = (w * 0.58).clamp(150.0, screen.height * 0.5).toDouble();
    return (w: w, h: handleHeight + padH + buttonHeight, padH: padH);
  }

  Offset _clamp(Offset p, Size screen, double w, double h) {
    return Offset(p.dx.clamp(0.0, (screen.width - w).clamp(0.0, double.infinity)),
        p.dy.clamp(0.0, (screen.height - h).clamp(0.0, double.infinity)));
  }

  void _movePointer(Offset delta) {
    final dx = delta.dx * speed;
    final dy = delta.dy * speed;
    if (dx == 0 && dy == 0) {
      return;
    }
    unawaited(_input.sendMobileRelativeMouseMove(dx, dy));
    // The peer moves its own cursor but rarely reports the position back, so
    // keep the painted pointer in step ourselves.
    widget.ffi.cursorModel.nudgeLocal(dx, dy);
  }

  void _click(MouseButtons button) {
    unawaited(_input.sendMouse('down', button));
    unawaited(_input.sendMouse('up', button));
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _moved = false;
      _downAt = DateTime.now().millisecondsSinceEpoch;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) {
      return;
    }
    _pointers[e.pointer] = e.localPosition;
    if (e.delta.distance > 6) {
      _moved = true;
    }
    // Two fingers scroll. The accumulator keeps sub-pixel deltas instead of
    // dropping them, otherwise slow scrolling does nothing at all.
    if (_pointers.length >= 2) {
      _scrollAcc += e.delta.dy / 24.0;
      final steps = _scrollAcc.truncate();
      if (steps != 0) {
        _scrollAcc -= steps;
        unawaited(_input.scroll(steps));
      }
      return;
    }
    _movePointer(e.delta);
  }

  void _onUp(PointerUpEvent e) {
    final hadPointer = _pointers.remove(e.pointer) != null;
    if (!hadPointer || _pointers.isNotEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final ms = now - _downAt;
    // A short touch without movement is a left click at the current position;
    // two of them in quick succession become a double click.
    if (!_moved && ms < 350) {
      _click(MouseButtons.left);
      if (now - _lastClickAt < 320) {
        _click(MouseButtons.left);
      }
      _lastClickAt = now;
    }
  }

  /// Scroll buttons repeat while held, which is what a wheel does.
  void _startRepeat(int lines) {
    _stopRepeat();
    unawaited(_input.scroll(lines));
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      unawaited(_input.scroll(lines));
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  Widget _padButton(String label, VoidCallback onTap, {double fontSize = 16}) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: buttonHeight,
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: fontSize,
                    color: Colors.white,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  Widget _scrollButton(IconData icon, int lines) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _startRepeat(lines),
        onTapUp: (_) => _stopRepeat(),
        onTapCancel: _stopRepeat,
        child: Center(child: Icon(icon, size: 30, color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = widget.bounds;
    final m = _metrics(screen);
    _position ??= _clamp(
        Offset(screen.width - m.w - 12, screen.height * 0.24), screen, m.w, m.h);
    final pos = _clamp(_position!, screen, m.w, m.h);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: m.w,
          color: const Color(0x40101010),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle: drag to move the whole panel, tap does nothing.
              GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    _position = _clamp(
                        (_position ?? pos) + d.delta, screen, m.w, m.h);
                  });
                },
                child: Container(
                  height: handleHeight,
                  color: const Color(0x55222222),
                  child: const Center(
                    child: Icon(Icons.drag_indicator,
                        size: 20, color: Colors.white70),
                  ),
                ),
              ),
              Row(
                children: [
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onDown,
                    onPointerMove: _onMove,
                    onPointerUp: _onUp,
                    onPointerCancel: (e) => _pointers.remove(e.pointer),
                    child: Container(
                      width: m.w - scrollWidth,
                      height: m.padH,
                      decoration: BoxDecoration(
                        color: const Color(0x1AFFFFFF),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                      child: Center(
                        child: Icon(Icons.mouse,
                            size: 34, color: const Color(0x3DFFFFFF)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: scrollWidth,
                    height: m.padH,
                    child: Column(
                      children: [
                        _scrollButton(Icons.keyboard_arrow_up, 1),
                        Container(
                            height: 1, color: const Color(0x33FFFFFF)),
                        _scrollButton(Icons.keyboard_arrow_down, -1),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _padButton('左键', () => _click(MouseButtons.left)),
                  Container(width: 1, height: buttonHeight, color: const Color(0x33FFFFFF)),
                  _padButton('右键', () => _click(MouseButtons.right)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
