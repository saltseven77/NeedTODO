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
  Timer? timer;
  String? ticket, error;
  bool busy = false, polling = false, authorized = false;
  DateTime? started;
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> begin() async {
    if (busy) return;
    timer?.cancel();
    setState(() {
      busy = true;
      error = null;
      authorized = false;
      ticket = null;
    });
    try {
      final flow = await widget.store.startRecovery();
      if (!mounted) return;
      setState(() {
        ticket = flow['ticket'];
        started = DateTime.now();
      });
      timer = Timer.periodic(const Duration(seconds: 3), (_) => poll());
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
      if (status['status'] == 'complete' && !authorized) {
        setState(() => authorized = true);
      }
      if (status['status'] == 'consumed') {
        timer?.cancel();
        Navigator.pop(context, status['username'] as String);
      }
    } catch (e) {
      if (mounted && ticket == activeTicket) {
        timer?.cancel();
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
                  authorized ? '请在浏览器中设置新密码，完成后返回登录。' : '使用此前绑定的 GitHub 验证身份。',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: busy || ticket != null ? null : begin,
                  child: Text(
                    ticket != null
                        ? (authorized ? '等待设置新密码' : '等待 GitHub 授权')
                        : '通过 GitHub 验证',
                  ),
                ),
                if (ticket != null)
                  TextButton(
                    onPressed: busy ? null : begin,
                    child: const Text('重新打开授权'),
                  ),
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
