import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class OptimizationParamsWidget extends StatelessWidget {
  final String? startTime;
  final String? startDate;
  final bool returnToStart;
  final Function(String?) onStartTimeChanged;
  final Function(String?) onStartDateChanged;
  final Function(bool) onReturnToStartChanged;

  const OptimizationParamsWidget({
    super.key,
    required this.startTime,
    required this.startDate,
    required this.returnToStart,
    required this.onStartTimeChanged,
    required this.onStartDateChanged,
    required this.onReturnToStartChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.optParamsTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Start Date and Time Row
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.optParamsStartDate,
                        prefixIcon: const Icon(Icons.calendar_today),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        startDate ?? l10n.optParamsSelectDate,
                        style: TextStyle(
                          color: startDate != null 
                              ? Theme.of(context).textTheme.bodyLarge?.color
                              : Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectTime(context),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.optParamsStartTime,
                        prefixIcon: const Icon(Icons.access_time),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        startTime != null
                            ? _formatTime(startTime!, context)
                            : l10n.optParamsSelectTime,
                        style: TextStyle(
                          color: startTime != null 
                              ? Theme.of(context).textTheme.bodyLarge?.color
                              : Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Return to Start Toggle
            Row(
              children: [
                const Icon(Icons.replay),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.optParamsReturnToStart,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Switch(
                  value: returnToStart,
                  onChanged: onReturnToStartChanged,
                ),
              ],
            ),
            
            // Clear buttons
            if (startDate != null || startTime != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (startDate != null)
                    TextButton.icon(
                      onPressed: () => onStartDateChanged(null),
                      icon: const Icon(Icons.clear, size: 16),
                      label: Text(l10n.optParamsClearDate),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (startDate != null && startTime != null)
                    const SizedBox(width: 8),
                  if (startTime != null)
                    TextButton.icon(
                      onPressed: () => onStartTimeChanged(null),
                      icon: const Icon(Icons.clear, size: 16),
                      label: Text(l10n.optParamsClearTime),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: startDate != null 
          ? DateTime.tryParse(startDate!) ?? DateTime.now()
          : DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null) {
      onStartDateChanged(picked.toIso8601String().split('T').first);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: startTime != null 
          ? _parseTime(startTime!)
          : TimeOfDay.now(),
    );
    
    if (picked != null) {
      final String formattedTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      onStartTimeChanged(formattedTime);
    }
  }

  TimeOfDay _parseTime(String timeString) {
    try {
      final parts = timeString.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (e) {
      return TimeOfDay.now();
    }
  }

  String _formatTime(String timeString, BuildContext context) {
    try {
      final time = _parseTime(timeString);
      return time.format(context);
    } catch (e) {
      return timeString;
    }
  }
}
