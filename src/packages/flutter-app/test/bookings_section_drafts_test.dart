import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/accommodation.dart';
import 'package:travel_route_planner/models/trip.dart';
import 'package:travel_route_planner/models/trip_segment.dart';
import 'package:travel_route_planner/widgets/bookings_section.dart';
import 'package:travel_route_planner/widgets/status_pill.dart';

import 'support/l10n_test_app.dart';

Trip _trip() => Trip(
      id: 't1',
      title: 'Portugal',
      status: 'planned',
      createdAt: '2026-06-01',
      updatedAt: '2026-06-01',
    );

const _draftStay = Accommodation(
  id: 'a1',
  name: 'Stay in Lisbon',
  address: 'Lisbon',
  checkIn: '2026-09-01',
  checkOut: '2026-09-04',
  auto: true,
  autoKey: 'stay:lisbon',
);

const _confirmedStay = Accommodation(
  id: 'a2',
  name: 'Casa do Brian',
  provider: 'Airbnb',
  checkIn: '2026-09-04',
  checkOut: '2026-09-06',
);

const _draftLeg = TripSegment(
  id: 's1',
  mode: 'flight',
  origin: 'Lisbon',
  destination: 'Porto',
  departDate: '2026-09-04',
  auto: true,
  autoKey: 'transport:lisbon>>porto',
);

// ProviderScope is required, not incidental: confirmed booking rows render
// AddToCalendarButton, a ConsumerWidget. It only started being looked up once
// the button gained a Localizations dependency (which makes
// didChangeDependencies fire when the reorderable row is reparented), so the
// missing scope was latent breakage rather than a new requirement.
Widget _wrap(BookingsSection section) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        home: Scaffold(body: SingleChildScrollView(child: section)),
      ),
    );

BookingsSection _section({
  required List<Accommodation> stays,
  required List<TripSegment> segments,
  bool readOnly = false,
  void Function(Accommodation)? onConfirmStay,
  void Function(Accommodation)? onEditStay,
  void Function(Accommodation)? onDeleteStay,
  void Function(int, int)? onReorderStays,
  void Function(Accommodation, bool)? onStayBookedChanged,
  Widget? otherBookings,
  VoidCallback? onAddBooking,
}) =>
    BookingsSection(
      trip: _trip(),
      stays: stays,
      segments: segments,
      readOnly: readOnly,
      onAddStay: () {},
      onDeleteStay: onDeleteStay ?? (_) {},
      onEditStay: onEditStay ?? (_) {},
      onConfirmStay: onConfirmStay ?? (_) {},
      onAddSegment: () {},
      onDeleteSegment: (_) {},
      onEditSegment: (_) {},
      onConfirmSegment: (_) {},
      onReorderStays: onReorderStays,
      onStayBookedChanged: onStayBookedChanged,
      otherBookings: otherBookings,
      onAddBooking: onAddBooking,
    );

void main() {
  testWidgets('drafts render a Suggested pill and keep/edit/dismiss actions',
      (tester) async {
    Accommodation? kept, edited, dismissed;
    await tester.pumpWidget(_wrap(_section(
      stays: const [_draftStay, _confirmedStay],
      segments: const [_draftLeg],
      onConfirmStay: (a) => kept = a,
      onEditStay: (a) => edited = a,
      onDeleteStay: (a) => dismissed = a,
    )));

    // One pill per draft (stay + segment); the confirmed stay has none.
    expect(find.byType(StatusPill), findsNWidgets(2));
    expect(find.text('Suggested'), findsNWidgets(2));
    expect(find.text('Casa do Brian'), findsOneWidget);
    expect(find.text('Lisbon → Porto'), findsOneWidget);

    await tester.tap(find.byTooltip('Keep').first);
    expect(kept?.id, 'a1');
    await tester.tap(find.byTooltip('Edit').first);
    expect(edited?.id, 'a1');
    await tester.tap(find.byTooltip('Dismiss suggestion').first);
    expect(dismissed?.id, 'a1');
  });

  testWidgets('read-only mode hides drafts entirely', (tester) async {
    await tester.pumpWidget(_wrap(_section(
      stays: const [_draftStay, _confirmedStay],
      segments: const [_draftLeg],
      readOnly: true,
    )));

    expect(find.text('Suggested'), findsNothing);
    expect(find.text('Stay in Lisbon'), findsNothing);
    expect(find.text('Lisbon → Porto'), findsNothing);
    // Confirmed rows still render, without edit/delete affordances.
    expect(find.text('Casa do Brian'), findsOneWidget);
    expect(find.byTooltip('Remove stay'), findsNothing);
  });

  testWidgets('edit sheet prefills from the draft and pops a PATCH body',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  await showModalBottomSheet<Map<String, dynamic>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const AddStaySheet(initial: _draftStay),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit stay'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Stay in Lisbon'), findsOneWidget);
    expect(find.text('2026-09-01 → 2026-09-04'), findsOneWidget);
  });

  testWidgets('Booked checkbox: confirmed rows only, toggles, strikes title',
      (tester) async {
    Accommodation? toggled;
    bool? toggledTo;
    await tester.pumpWidget(_wrap(_section(
      stays: const [_draftStay, _confirmedStay],
      segments: const [],
      onStayBookedChanged: (a, v) {
        toggled = a;
        toggledTo = v;
      },
    )));

    // Only the confirmed stay has a checkbox — drafts keep keep/edit/dismiss.
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    expect(toggled?.id, 'a2');
    expect(toggledTo, isTrue);

    // A booked row renders muted + struck through.
    await tester.pumpWidget(_wrap(_section(
      stays: [_confirmedStay.copyWith(booked: true)],
      segments: const [],
    )));
    final title = tester.widget<Text>(find.text('Casa do Brian'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
    expect(
      tester.widget<Checkbox>(find.byType(Checkbox)).value,
      isTrue,
    );
  });

  testWidgets('read-only mode shows booked state but disables the checkbox',
      (tester) async {
    await tester.pumpWidget(_wrap(_section(
      stays: [_confirmedStay.copyWith(booked: true)],
      segments: const [],
      readOnly: true,
      onStayBookedChanged: (_, __) => fail('read-only checkbox toggled'),
    )));
    final box = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(box.value, isTrue);
    expect(box.onChanged, isNull);
  });

  testWidgets('drag handles render for editors but never in read-only mode',
      (tester) async {
    await tester.pumpWidget(_wrap(_section(
      stays: const [_draftStay, _confirmedStay],
      segments: const [],
      onReorderStays: (_, __) {},
    )));
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));

    await tester.pumpWidget(_wrap(_section(
      stays: const [_draftStay, _confirmedStay],
      segments: const [],
      readOnly: true,
      onReorderStays: (_, __) {},
    )));
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
  });

  testWidgets('sub-headers render only for non-empty groups', (tester) async {
    await tester.pumpWidget(_wrap(_section(
      stays: const [_confirmedStay],
      segments: const [],
    )));
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Stays'), findsOneWidget);
    expect(find.text('Transport'), findsNothing);
    expect(find.text('Other'), findsNothing);

    await tester.pumpWidget(_wrap(_section(
      stays: const [],
      segments: const [_draftLeg],
    )));
    expect(find.text('Stays'), findsNothing);
    expect(find.text('Transport'), findsOneWidget);
  });

  testWidgets('otherBookings slot renders under an Other sub-header',
      (tester) async {
    const slotKey = Key('other-slot');
    await tester.pumpWidget(_wrap(_section(
      stays: const [],
      segments: const [],
      otherBookings: const SizedBox(key: slotKey, height: 40),
    )));
    expect(find.text('Other'), findsOneWidget);
    expect(find.byKey(slotKey), findsOneWidget);
    // A non-null slot counts as content, so no empty hint.
    expect(find.textContaining('Nothing saved yet'), findsNothing);

    await tester.pumpWidget(_wrap(_section(
      stays: const [],
      segments: const [],
    )));
    expect(find.text('Other'), findsNothing);
    expect(find.textContaining('Nothing saved yet'), findsOneWidget);
  });

  testWidgets('Add booking footer: enabled, disabled offline, hidden read-only',
      (tester) async {
    var added = false;
    await tester.pumpWidget(_wrap(_section(
      stays: const [],
      segments: const [],
      onAddBooking: () => added = true,
    )));
    await tester.tap(find.text('Add booking'));
    expect(added, isTrue);

    // Null callback (offline) renders the footer disabled.
    await tester.pumpWidget(_wrap(_section(
      stays: const [],
      segments: const [],
    )));
    final button = tester.widget<TextButton>(
      find.ancestor(
          of: find.text('Add booking'), matching: find.bySubtype<TextButton>()),
    );
    expect(button.onPressed, isNull);

    await tester.pumpWidget(_wrap(_section(
      stays: const [],
      segments: const [],
      readOnly: true,
      onAddBooking: () {},
    )));
    expect(find.text('Add booking'), findsNothing);
  });
}
