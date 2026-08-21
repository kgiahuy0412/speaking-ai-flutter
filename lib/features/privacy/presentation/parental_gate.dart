import 'package:flutter/material.dart';

/// A lightweight parental gate for actions that leave the Kids experience or
/// delete account-like data. It does not replace verified parental consent.
Future<bool> showParentalGate(BuildContext context) async {
  final seed = DateTime.now().microsecondsSinceEpoch;
  final left = 12 + seed % 8;
  final right = 3 + (seed ~/ 11) % 6;
  final expected = left * right;
  final answerController = TextEditingController();
  String? error;

  final approved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Khu vực dành cho phụ huynh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Để tiếp tục tới liên kết bên ngoài hoặc thay đổi dữ liệu, hãy giải phép tính sau.',
            ),
            const SizedBox(height: 14),
            Text(
              '$left × $right = ?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: answerController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Kết quả',
                errorText: error,
              ),
              onSubmitted: (_) {
                if (int.tryParse(answerController.text.trim()) == expected) {
                  Navigator.of(dialogContext).pop(true);
                } else {
                  setDialogState(() => error = 'Kết quả chưa đúng.');
                }
              },
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (int.tryParse(answerController.text.trim()) == expected) {
                Navigator.of(dialogContext).pop(true);
              } else {
                setDialogState(() => error = 'Kết quả chưa đúng.');
              }
            },
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    ),
  );
  answerController.dispose();
  return approved ?? false;
}
