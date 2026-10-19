import 'package:flutter/material.dart';
import 'package:pre_ape/core/constants/app_colors.dart';

/// Conferma forte per "Elimina utente": il pulsante si abilita solo quando
/// l'email digitata coincide esattamente con quella dell'utente.
class DeleteUserDialog extends StatefulWidget {
  const DeleteUserDialog({super.key, required this.email});

  final String email;

  @override
  State<DeleteUserDialog> createState() => _DeleteUserDialogState();
}

class _DeleteUserDialogState extends State<DeleteUserDialog> {
  final _controller = TextEditingController();

  bool get _matches => _controller.text.trim() == widget.email;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Eliminare l\'utente?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'L\'account ${widget.email} verrà eliminato definitivamente '
            'insieme a tutti i suoi sopralluoghi, foto e documenti. '
            'L\'operazione non si può annullare.',
          ),
          const SizedBox(height: 16),
          const Text('Per confermare digita l\'email dell\'utente:'),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('delete_user_email'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(hintText: widget.email),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          key: const ValueKey('delete_user_confirm'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Elimina utente'),
        ),
      ],
    );
  }
}

/// true se l'amministratore ha confermato digitando l'email.
Future<bool> showDeleteUserDialog(BuildContext context, String email) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => DeleteUserDialog(email: email),
  );
  return ok == true;
}
