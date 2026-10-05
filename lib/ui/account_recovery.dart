import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../store.dart';
import 'components.dart';

class AccountRecoveryPage extends StatefulWidget {
  final AppStore store;
  const AccountRecoveryPage({super.key, required this.store});
  @override
  State<AccountRecoveryPage> createState() => _AccountRecoveryPageState();
}

class _AccountRecoveryPageState extends State<AccountRecoveryPage> {
  final password = TextEditingController(),
      confirmation = TextEditingController();
  Timer? timer;
  String? ticket, username, error;
  bool busy = false, polling = false;
  DateTime? started;
  @override
  void dispose() {
    timer?.cancel();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> begin() async {
    timer?.cancel();
    final flow = await widget.store.startRecovery();
    if (!mounted) return;
    setState(() {
      ticket = flow['ticket'];
      started = DateTime.now();
    });
    timer = Timer.periodic(const Duration(seconds: 3), (_) => poll());
  }

  Future<void> poll() async {
    if (polling || !mounted || ticket == null) return;
    final activeTicket = ticket!;
    polling = true;
    try {
      if (DateTime.now().difference(started!) > const Duration(minutes: 10)) {
        throw Exception('授权已超时，请重试');
      }
      final status = await widget.store.recoveryStatus(activeTicket);
      if (!mounted || ticket != activeTicket) return;
      if (status['status'] == 'failed') {
        throw Exception('验证失败，请确认该 GitHub 已绑定泥土豆账号');
      }
      if (status['status'] == 'complete') {
        timer?.cancel();
        setState(() => username = status['username']);
      }
    } catch (e) {
      timer?.cancel();
      if (mounted && ticket == activeTicket) {
        setState(() {
          ticket = null;
          error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      polling = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(CupertinoIcons.back),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '找回账号',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
                ),
                const SizedBox(height: 12),
                Text(
                  username == null ? '使用此前绑定的 GitHub 验证身份。' : '账号 · $username',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 28),
                if (username != null) ...[
                  TextField(
                    controller: password,
                    obscureText: true,
                    maxLength: 128,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: '新密码（至少 8 位）',
                      counterText: '',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmation,
                    obscureText: true,
                    maxLength: 128,
                    decoration: const InputDecoration(
                      labelText: '确认新密码',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            if (password.text != confirmation.text) {
                              throw Exception('两次密码不一致');
                            }
                            final name = await widget.store.resetPassword(
                              ticket!,
                              password.text,
                            );
                            if (context.mounted) Navigator.pop(context, name);
                          }),
                    child: Text(busy ? '请稍候' : '更新密码'),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: busy || ticket != null ? null : () => run(begin),
                    child: Text(
                      ticket != null ? '等待 GitHub 授权' : '通过 GitHub 验证',
                    ),
                  ),
                  if (ticket != null)
                    TextButton(
                      onPressed: busy ? null : () => run(begin),
                      child: const Text('重新打开授权'),
                    ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
