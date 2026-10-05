import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../machine/machine_controller.dart';
import '../storage/settings.dart';
import '../theme.dart';
import 'hud.dart';

/// Talking to the Machine (or Samaritan), typed or out loud: answers appear
/// a word at a time and are spoken. After a spoken question it listens again
/// once it has answered, until nobody says anything. With [listen] it opens
/// talking and listening, the way Siri opens it. [onSimulate] runs when a
/// question asks what will happen.
Future<void> showTalk(
  BuildContext context,
  MachineController controller, {
  bool listen = false,
  VoidCallback? onSimulate,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, _, _) => _TalkView(controller: controller, listen: listen, onSimulate: onSimulate),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
}

class _Exchange {
  _Exchange(this.question, this.answer, this.at);

  final String question;
  final String answer;
  final Duration at;
}

class _TalkView extends StatefulWidget {
  const _TalkView({required this.controller, required this.listen, this.onSimulate});

  final MachineController controller;
  final bool listen;
  final VoidCallback? onSimulate;

  @override
  State<_TalkView> createState() => _TalkViewState();
}

class _TalkViewState extends State<_TalkView> with SingleTickerProviderStateMixin {
  static const _wordSeconds = 0.28;

  final _text = TextEditingController();
  final _focus = FocusNode();
  final _exchanges = <_Exchange>[];
  late final Ticker _ticker;
  late final StreamSubscription<SpeechEvent> _speech;
  Duration _now = Duration.zero;

  /// The microphone is on; [_heard] is what it made out so far.
  bool _listening = false;
  String _heard = '';

  /// Recent microphone levels, newest last.
  final _levels = List<double>.filled(40, 0);
  String? _problem;

  /// The last question was spoken: listen again after the answer.
  bool _conversation = false;
  bool _waitingForVoice = false;
  Timer? _relisten;

  MachineController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => setState(() => _now = elapsed))..start();
    _speech = _controller.speech.listen(_onSpeech);
    _focus.addListener(() {
      // Typing ends the spoken conversation.
      if (_focus.hasFocus) _endConversation();
    });
    if (widget.listen) {
      _conversation = true;
      // The Machine speaks first, as it does in the show.
      final samaritan = _controller.settings.mode == MachineMode.samaritan;
      if (_controller.speakLine(samaritan ? 'What are your commands?' : 'Can you hear me?')) {
        _waitingForVoice = true;
      } else {
        unawaited(_startListening());
      }
    }
  }

  @override
  void dispose() {
    _relisten?.cancel();
    unawaited(_speech.cancel());
    if (_listening) unawaited(_controller.stopListening());
    _ticker.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSpeech(SpeechEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'level' when _listening:
        _levels
          ..setRange(0, _levels.length - 1, _levels, 1)
          ..last = event.level;
      case 'partial' when _listening:
        setState(() => _heard = event.text);
      case 'final' when _listening:
        final question = (event.text.trim().isEmpty ? _heard : event.text).trim();
        setState(() {
          _listening = false;
          _heard = '';
        });
        if (question.isEmpty) {
          // Silence ends the conversation.
          _conversation = false;
        } else {
          _ask(question, spoken: true);
        }
      case 'spoken' when _waitingForVoice:
        _waitingForVoice = false;
        _relisten = Timer(const Duration(milliseconds: 300), _listenAgain);
    }
  }

  void _send() {
    final question = _text.text.trim();
    if (question.isEmpty) return;
    _text.clear();
    _ask(question, spoken: false);
    _focus.requestFocus();
  }

  void _ask(String question, {required bool spoken}) {
    final answer = _controller.ask(question);
    setState(() {
      _exchanges.add(_Exchange(question, answer.text, _now));
      if (_exchanges.length > 6) _exchanges.removeAt(0);
    });
    if (answer.simulate) {
      _endConversation();
      // Let the answer show, then hand over to the simulation.
      _relisten = Timer(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        Navigator.pop(context);
        widget.onSimulate?.call();
      });
      return;
    }
    // A number comes with a ring and spoken digits: not a time to listen.
    _conversation = spoken && !answer.issueNumber;
    if (!_conversation) return;
    if (_controller.settings.voice) {
      _waitingForVoice = true;
    } else {
      final words = answer.text.split(' ').length;
      _relisten = Timer(Duration(milliseconds: 600 + (words * _wordSeconds * 1000).round() + 400), _listenAgain);
    }
  }

  void _listenAgain() {
    if (mounted && _conversation && !_listening) unawaited(_startListening());
  }

  void _endConversation() {
    _conversation = false;
    _waitingForVoice = false;
    _relisten?.cancel();
    if (_listening) unawaited(_controller.stopListening());
  }

  Future<void> _startListening() async {
    _relisten?.cancel();
    _waitingForVoice = false;
    _focus.unfocus();
    setState(() {
      _listening = true;
      _heard = '';
      _problem = null;
      _levels.fillRange(0, _levels.length, 0);
    });
    final problem = await _controller.listen();
    if (!mounted || problem == null) return;
    setState(() {
      _listening = false;
      _conversation = false;
      _problem = problem == 'denied'
          ? 'MICROPHONE OR SPEECH ACCESS DENIED. ALLOW IT IN SETTINGS.'
          : 'SPEECH RECOGNITION UNAVAILABLE.';
    });
  }

  void _onMic() {
    if (_listening) {
      // Stop now and take what was heard.
      unawaited(_controller.stopListening());
    } else {
      _conversation = true;
      unawaited(_startListening());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _controller.settings.theme;
    final samaritan = theme.isSamaritan;
    final background = samaritan ? SamaritanColors.paper : Colors.black;
    final ink = samaritan ? SamaritanColors.ink : MachineColors.text;
    final dim = samaritan ? const Color(0x99111111) : MachineColors.dim;
    final seconds = _now.inMicroseconds / 1e6;
    return Material(
      color: background,
      child: SafeArea(
        child: Padding(
          // Stay above the keyboard.
          padding: EdgeInsets.fromLTRB(20, 12, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (samaritan) ...[const SamaritanTriangle(), const SizedBox(width: 10)],
                  Expanded(
                    child: Text(
                      samaritan ? 'SAMARITAN // QUERY' : 'THE MACHINE // QUERY',
                      style: theme.style(size: 13, color: theme.accent, spacing: theme.spacing * 2),
                    ),
                  ),
                  _LanguageSwitch(settings: _controller.settings, theme: theme, ink: ink, dim: dim),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: ink),
                  ),
                ],
              ),
              Expanded(
                child: _exchanges.isEmpty
                    ? Center(
                        child: Text(
                          _listening
                              ? (samaritan ? 'SPEAK.' : 'I CAN HEAR YOU.')
                              : (samaritan ? 'WHAT ARE YOUR COMMANDS?' : 'CAN YOU HEAR ME?'),
                          textAlign: TextAlign.center,
                          style: theme.style(size: 18, color: ink, spacing: theme.spacing * 2),
                        ),
                      )
                    : ListView(
                        reverse: true,
                        padding: const EdgeInsets.only(right: 8),
                        children: [
                          for (final exchange in _exchanges.reversed) _exchangeView(exchange, theme, ink, dim),
                        ],
                      ),
              ),
              if (_problem case final problem?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(problem, style: theme.style(size: 11, color: theme.alert, spacing: 1.2)),
                ),
              if (_listening)
                SizedBox(
                  height: 34,
                  child: CustomPaint(painter: _LevelMeter(List.of(_levels), color: theme.accent, samaritan: samaritan)),
                ),
              Row(
                children: [
                  Text('>', style: theme.style(size: 16, color: theme.accent)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _listening
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              '${_heard.isEmpty ? 'LISTENING' : _heard.toUpperCase()}${(seconds * 3).floor().isEven ? '_' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.style(size: 15, color: _heard.isEmpty ? dim : ink, spacing: 1.5),
                            ),
                          )
                        : TextField(
                            controller: _text,
                            focusNode: _focus,
                            textCapitalization: TextCapitalization.characters,
                            cursorColor: theme.accent,
                            style: theme.style(size: 15, color: ink, spacing: 1.5),
                            decoration: InputDecoration(
                              hintText: 'ASK SOMETHING',
                              hintStyle: theme.style(size: 15, color: dim, spacing: 1.5),
                              border: InputBorder.none,
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _send(),
                          ),
                  ),
                  if (!_listening && _text.text.trim().isNotEmpty)
                    IconButton(onPressed: _send, icon: Icon(Icons.send, color: theme.accent))
                  else
                    IconButton(
                      onPressed: _onMic,
                      tooltip: _listening ? 'STOP' : 'SPEAK',
                      icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_none, color: theme.accent, size: 28),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exchangeView(_Exchange exchange, ModeTheme theme, Color ink, Color dim) {
    final seconds = (_now - exchange.at).inMicroseconds / 1e6;
    // A pause while it "calculates", then one word at a time.
    final words = exchange.answer.split(' ');
    final shown = ((seconds - 0.6) / _wordSeconds).floor() + 1;
    final calculating = seconds < 0.6;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('> ${exchange.question.toUpperCase()}', style: theme.style(size: 12, color: dim, spacing: 1.5)),
          const SizedBox(height: 8),
          Text(
            calculating ? 'CALCULATING RESPONSE...' : words.take(shown.clamp(1, words.length)).join(' '),
            style: theme.style(
              size: calculating ? 12 : 19,
              color: calculating ? dim : ink,
              spacing: theme.isSamaritan ? 4 : 2.5,
              weight: theme.isSamaritan ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// TR / EN: the language spoken questions are recognised in.
class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({required this.settings, required this.theme, required this.ink, required this.dim});

  final MachineSettings settings;
  final ModeTheme theme;
  final Color ink;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Row(
        children: [
          for (final language in const ['tr', 'en'])
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => settings.talkLanguage = language,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                child: Text(
                  language.toUpperCase(),
                  style: theme.style(size: 12, color: settings.talkLanguage == language ? theme.accent : dim, spacing: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The microphone level over the last two seconds, as bars.
class _LevelMeter extends CustomPainter {
  const _LevelMeter(this.levels, {required this.color, required this.samaritan});

  final List<double> levels;
  final Color color;
  final bool samaritan;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / levels.length;
    final paint = Paint()..color = color;
    for (var i = 0; i < levels.length; i++) {
      final height = 2 + levels[i] * (size.height - 2);
      final x = i * step + step / 2;
      final age = (i + 1) / levels.length;
      paint.color = color.withValues(alpha: 0.25 + 0.75 * age);
      if (samaritan) {
        canvas.drawCircle(Offset(x, size.height / 2), 1 + levels[i] * size.height / 3, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset(x, size.height / 2), width: step * 0.45, height: height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LevelMeter old) => true;
}
