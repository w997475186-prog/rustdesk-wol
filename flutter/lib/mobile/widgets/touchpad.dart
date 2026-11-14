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
class TouchpadPanel extends StatefulWidget {
  final FFI ffi;

  const TouchpadPanel({Key? key, required this.ffi}) : super(key: key);

  @override
  State<TouchpadPanel> createState() => TouchpadPanelState();
}

class TouchpadPanelState extends State<TouchpadPanel> {
  static const double padSize = 168;
  static const double handleHeight = 26;
  static const double buttonHeight = 30;

  /// Finger travel to pointer travel. 1.0 would make the pointer as slow as
  /// the finger, which feels sluggish on a phone screen.
  static const double speed = 1.8;

  Offset? _position;
  final Map<int, Offset> _pointers = {};
  double _scrollAcc = 0;
  bool _moved = false;
  int _downAt = 0;

  InputModel get _input => widget.ffi.inputModel;

  Offset _clamp(Offset p, Size screen) {
    final maxX = screen.width - padSize;
    final maxY = screen.height - handleHeight - padSize - buttonHeight;
    return Offset(p.dx.clamp(0.0, maxX), p.dy.clamp(0.0, maxY));
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
    final ms = DateTime.now().millisecondsSinceEpoch - _downAt;
    // A short touch without movement is a left click at the current position.
    if (!_moved && ms < 350) {
      _click(MouseButtons.left);
    }
  }

  Widget _buildButton(IconData icon, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: buttonHeight,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    _position ??=
        _clamp(Offset(screen.width - padSize - 12, screen.height * 0.28), screen);
    final pos = _clamp(_position!, screen);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Column(
        children: [
          // Handle: drag to move the whole panel, tap does nothing.
          GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                _position = _clamp((_position ?? pos) + d.delta, screen);
              });
            },
            child: Container(
              width: padSize,
              height: handleHeight,
              decoration: const BoxDecoration(
                color: Color(0x33222222),
                borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: const Center(
                child: Icon(Icons.drag_indicator,
                    size: 16, color: Colors.white70),
              ),
            ),
          ),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: (e) => _pointers.remove(e.pointer),
            child: Container(
              width: padSize,
              height: padSize,
              decoration: BoxDecoration(
                color: const Color(0x22111111),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: const Center(
                child: Icon(Icons.mouse, size: 26, color: Color(0x44FFFFFF)),
              ),
            ),
          ),
          Container(
            width: padSize,
            decoration: const BoxDecoration(
              color: Color(0x33222222),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
            ),
            child: Row(
              children: [
                _buildButton(Icons.ads_click, () => _click(MouseButtons.left)),
                _buildButton(Icons.mouse, () => _click(MouseButtons.right)),
                _buildButton(Icons.keyboard_arrow_up, () {
                  unawaited(_input.scroll(1));
                }),
                _buildButton(Icons.keyboard_arrow_down, () {
                  unawaited(_input.scroll(-1));
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
