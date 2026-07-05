import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/gradient_app_bar.dart';
import '../models/airbnb_listing.dart';
import '../models/trip.dart';
import '../providers/airbnb_provider.dart';
import '../providers/accommodations_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/trips_provider.dart';
import 'trip_detail_screen.dart';

class AirbnbParserScreen extends ConsumerStatefulWidget {
  const AirbnbParserScreen({super.key});

  @override
  ConsumerState<AirbnbParserScreen> createState() => _AirbnbParserScreenState();
}

class _AirbnbParserScreenState extends ConsumerState<AirbnbParserScreen> {
  final _urlController = TextEditingController();
  final _pageController = PageController();
  int _currentPhotoIndex = 0;
  bool _descriptionExpanded = false;
  bool _amenitiesExpanded = false;

  @override
  void dispose() {
    _urlController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _parse() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    ref.read(airbnbParserProvider.notifier).parseListing(url);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(airbnbParserProvider);

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('Airbnb Parser'),
        actions: [
          if (state.listing != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Clear',
              onPressed: () {
                ref.read(airbnbParserProvider.notifier).reset();
                _urlController.clear();
                setState(() {
                  _currentPhotoIndex = 0;
                  _descriptionExpanded = false;
                  _amenitiesExpanded = false;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (state.isLoading) const LinearProgressIndicator(),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _UrlInputSection(
                      controller: _urlController,
                      isLoading: state.isLoading,
                      onParse: _parse,
                    ),
                  ),
                ),
                if (state.error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ErrorCard(
                        message: state.error!,
                        onDismiss: () =>
                            ref.read(airbnbParserProvider.notifier).clearError(),
                      ),
                    ),
                  ),
                if (state.isLoading && state.listing == null)
                  const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Loading listing...\nThis may take 15–30 seconds.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (state.listing != null) ..._buildResults(context, state.listing!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _attaching = false;

  /// Maps the parsed listing to the accommodations POST body and saves it to
  /// a trip the user picks. Reuses the existing trips list + add endpoint.
  Future<void> _attachToTrip(AirbnbListing listing) async {
    List<Trip> trips;
    try {
      trips = await ref.read(tripsApiServiceProvider).listTrips();
    } catch (e) {
      _snack('Could not load your trips: $e');
      return;
    }
    if (trips.isEmpty) {
      _snack('No trips yet — plan one first, then attach this stay.');
      return;
    }
    if (!mounted) return;
    final trip = await showModalBottomSheet<Trip>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Attach to which trip?',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final t in trips)
              ListTile(
                leading: const Icon(Icons.card_travel),
                title: Text(t.title),
                subtitle: t.cities != null && t.cities!.isNotEmpty
                    ? Text(t.cities!.join(' · '))
                    : null,
                onTap: () => Navigator.of(context).pop(t),
              ),
          ],
        ),
      ),
    );
    if (trip == null) return;

    setState(() => _attaching = true);
    try {
      final loc = listing.location;
      await ref.read(accommodationsApiServiceProvider).add(trip.id, {
        'name': listing.title.isNotEmpty ? listing.title : 'Airbnb stay',
        'provider': 'Airbnb',
        'url': listing.url,
        if (loc.city.isNotEmpty)
          'address': [loc.city, loc.state, loc.country]
              .where((s) => s.isNotEmpty)
              .join(', '),
        if (loc.latitude != 0 || loc.longitude != 0) ...{
          'latitude': loc.latitude,
          'longitude': loc.longitude,
        },
        if (listing.pricing.hasPricing)
          'price_note':
              '${listing.pricing.currency} ${listing.pricing.nightlyRate.toStringAsFixed(0)}/night',
      });
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stay attached'),
          content: Text('Added to "${trip.title}".'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay here')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('View trip')),
          ],
        ),
      );
      if (open == true && mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TripDetailScreen(tripId: trip.id)));
      }
    } catch (e) {
      _snack('Could not attach stay: $e');
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  List<Widget> _buildResults(BuildContext context, AirbnbListing listing) {
    return [
      if (listing.photos.isNotEmpty)
        SliverToBoxAdapter(child: _PhotoGallery(
          photos: listing.photos,
          controller: _pageController,
          currentIndex: _currentPhotoIndex,
          onPageChanged: (i) => setState(() => _currentPhotoIndex = i),
        )),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TitleSection(listing: listing),
              const SizedBox(height: 16),
              // Attach the parsed listing to a saved trip as a stay — the
              // bridge from "looked it up" to "it's part of my plan".
              if (ref.watch(authProvider).isSignedIn)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed:
                        _attaching ? null : () => _attachToTrip(listing),
                    icon: _attaching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.luggage_outlined, size: 18),
                    label: const Text('Attach to trip'),
                  ),
                ),
              const SizedBox(height: 16),
              _StatsRow(listing: listing),
              if (listing.host.name.isNotEmpty) ...[
                const SizedBox(height: 16),
                _HostTile(host: listing.host),
              ],
              if (listing.location.city.isNotEmpty) ...[
                const SizedBox(height: 8),
                _LocationTile(location: listing.location),
              ],
              if (listing.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                _DescriptionSection(
                  description: listing.description,
                  expanded: _descriptionExpanded,
                  onToggle: () =>
                      setState(() => _descriptionExpanded = !_descriptionExpanded),
                ),
              ],
              if (listing.pricing.hasPricing) ...[
                const SizedBox(height: 16),
                _PricingCard(pricing: listing.pricing),
              ],
              if (listing.amenities.isNotEmpty) ...[
                const SizedBox(height: 16),
                _AmenitiesSection(
                  amenities: listing.amenities,
                  expanded: _amenitiesExpanded,
                  onToggle: () =>
                      setState(() => _amenitiesExpanded = !_amenitiesExpanded),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ];
  }
}

// --- URL Input ---

class _UrlInputSection extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onParse;

  const _UrlInputSection({
    required this.controller,
    required this.isLoading,
    required this.onParse,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Airbnb listing URL',
            hintText: 'https://www.airbnb.com/rooms/...',
            prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (_) => isLoading ? null : onParse(),
          enabled: !isLoading,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: isLoading ? null : onParse,
          icon: const Icon(Icons.search),
          label: Text(isLoading ? 'Parsing...' : 'Parse Listing'),
        ),
      ],
    );
  }
}

// --- Error Card ---

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorCard({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: theme.colorScheme.onErrorContainer),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Photo Gallery ---

class _PhotoGallery extends StatelessWidget {
  final List<AirbnbPhoto> photos;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  const _PhotoGallery({
    required this.photos,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: controller,
                itemCount: photos.length,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  return Image.network(
                    photos[index].url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, _, __) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, size: 48),
                    ),
                  );
                },
              ),
              // Photo count badge
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${currentIndex + 1} / ${photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Dot indicator (capped at 20 for readability)
        if (photos.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                photos.length > 20 ? 20 : photos.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: index == currentIndex ? 10 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == currentIndex
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[400],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// --- Title + Rating ---

class _TitleSection extends StatelessWidget {
  final AirbnbListing listing;

  const _TitleSection({required this.listing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(listing.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        if (listing.rating > 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.star, size: 16, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                listing.rating.toStringAsFixed(2),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (listing.reviewCount > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '(${listing.reviewCount} reviews)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
        if (listing.propertyType.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            listing.propertyType,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

// --- Stats Row ---

class _StatsRow extends StatelessWidget {
  final AirbnbListing listing;

  const _StatsRow({required this.listing});

  @override
  Widget build(BuildContext context) {
    final stats = <_Stat>[];
    if (listing.maxGuests > 0) stats.add(_Stat(Icons.people_outline, '${listing.maxGuests} guests'));
    if (listing.bedrooms > 0) stats.add(_Stat(Icons.bed_outlined, '${listing.bedrooms} bed${listing.bedrooms == 1 ? '' : 's'}room${listing.bedrooms == 1 ? '' : 's'}'));
    if (listing.beds > 0) stats.add(_Stat(Icons.single_bed_outlined, '${listing.beds} bed${listing.beds == 1 ? '' : 's'}'));
    if (listing.bathrooms > 0) {
      final bathStr = listing.bathrooms == listing.bathrooms.truncateToDouble()
          ? listing.bathrooms.toInt().toString()
          : listing.bathrooms.toString();
      stats.add(_Stat(Icons.bathtub_outlined, '$bathStr bath${listing.bathrooms == 1 ? '' : 's'}'));
    }

    if (stats.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: stats.map((s) => _StatChip(stat: s)).toList(),
    );
  }
}

class _Stat {
  final IconData icon;
  final String label;
  const _Stat(this.icon, this.label);
}

class _StatChip extends StatelessWidget {
  final _Stat stat;
  const _StatChip({required this.stat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stat.icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(stat.label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// --- Host ---

class _HostTile extends StatelessWidget {
  final AirbnbHost host;
  const _HostTile({required this.host});

  @override
  Widget build(BuildContext context) {
    Widget avatar;
    if (host.avatar.isNotEmpty) {
      avatar = CircleAvatar(backgroundImage: NetworkImage(host.avatar), radius: 20);
    } else {
      avatar = const CircleAvatar(radius: 20, child: Icon(Icons.person));
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: avatar,
      title: Text('Hosted by ${host.name}'),
      dense: true,
    );
  }
}

// --- Location ---

class _LocationTile extends StatelessWidget {
  final AirbnbListingLocation location;
  const _LocationTile({required this.location});

  @override
  Widget build(BuildContext context) {
    final parts = [location.city, location.state, location.country]
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(Icons.location_on_outlined,
            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(parts.join(', '),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      ],
    );
  }
}

// --- Description ---

class _DescriptionSection extends StatelessWidget {
  final String description;
  final bool expanded;
  final VoidCallback onToggle;

  const _DescriptionSection({
    required this.description,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = description.length > 300;
    final shown = expanded || !short ? description : '${description.substring(0, 300)}...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('About this place', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(shown, style: theme.textTheme.bodyMedium),
        if (short) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onToggle,
            child: Text(
              expanded ? 'Show less' : 'Show more',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// --- Pricing ---

class _PricingCard extends StatelessWidget {
  final AirbnbPricing pricing;
  const _PricingCard({required this.pricing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = pricing.currency.isNotEmpty ? pricing.currency : 'USD';

    String fmt(double amount) => '$cur ${amount.toStringAsFixed(2)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Price breakdown', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (pricing.nightlyRate > 0) ...[
              _PriceLine(
                label: '${fmt(pricing.nightlyRate)} × ${pricing.nights} night${pricing.nights == 1 ? '' : 's'}',
                value: fmt(pricing.nightlyRate * pricing.nights),
              ),
            ],
            if (pricing.cleaningFee > 0)
              _PriceLine(label: 'Cleaning fee', value: fmt(pricing.cleaningFee)),
            if (pricing.serviceFee > 0)
              _PriceLine(label: 'Service fee', value: fmt(pricing.serviceFee)),
            const Divider(),
            _PriceLine(
              label: 'Total',
              value: fmt(pricing.total),
              bold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _PriceLine({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

// --- Amenities ---

class _AmenitiesSection extends StatelessWidget {
  final List<String> amenities;
  final bool expanded;
  final VoidCallback onToggle;

  const _AmenitiesSection({
    required this.amenities,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const cap = 12;
    final shown = expanded ? amenities : amenities.take(cap).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Amenities', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: shown.map((a) => Chip(label: Text(a, style: theme.textTheme.bodySmall))).toList(),
        ),
        if (amenities.length > cap) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onToggle,
            child: Text(
              expanded ? 'Show fewer' : 'Show all ${amenities.length} amenities',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
