import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../models/location.dart';
import '../models/place_search_result.dart';
import '../providers/places_api_provider.dart';

class PlaceSearchDialog extends ConsumerStatefulWidget {
  final Location? initialLocation;

  const PlaceSearchDialog({
    Key? key,
    this.initialLocation,
  }) : super(key: key);

  @override
  ConsumerState<PlaceSearchDialog> createState() => _PlaceSearchDialogState();
}

class _PlaceSearchDialogState extends ConsumerState<PlaceSearchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _visitDurationController = TextEditingController();
  
  String? _selectedPlaceId;
  PlaceSearchResult? _selectedPlace;
  String _searchQuery = '';
  bool _useManualCoordinates = false;
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _nameController.text = widget.initialLocation!.name;
      _categoryController.text = widget.initialLocation!.category ?? '';
      _visitDurationController.text = 
          widget.initialLocation!.visitDurationMinutes?.toString() ?? '';
      _selectedPlaceId = widget.initialLocation!.placeId;
      
      if (widget.initialLocation!.latitude != null) {
        _latitudeController.text = widget.initialLocation!.latitude.toString();
      }
      if (widget.initialLocation!.longitude != null) {
        _longitudeController.text = widget.initialLocation!.longitude.toString();
      }
      
      // Check if we should use manual coordinates
      _useManualCoordinates = widget.initialLocation!.placeId == null &&
          widget.initialLocation!.latitude != null &&
          widget.initialLocation!.longitude != null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _visitDurationController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _onPlaceSelected(PlaceSearchResult place) {
    setState(() {
      _selectedPlace = place;
      _selectedPlaceId = place.placeId;
      _nameController.text = place.name;
      _latitudeController.text = place.latitude.toString();
      _longitudeController.text = place.longitude.toString();
      _searchQuery = '';
    });
  }

  Location _buildLocation() {
    return Location(
      id: widget.initialLocation?.id ?? 
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      placeId: _useManualCoordinates ? null : _selectedPlaceId,
      latitude: _latitudeController.text.isNotEmpty 
          ? double.tryParse(_latitudeController.text)
          : null,
      longitude: _longitudeController.text.isNotEmpty 
          ? double.tryParse(_longitudeController.text)
          : null,
      address: _selectedPlace?.address,
      category: _categoryController.text.trim().isNotEmpty 
          ? _categoryController.text.trim() 
          : null,
      visitDurationMinutes: _visitDurationController.text.isNotEmpty 
          ? int.tryParse(_visitDurationController.text)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.initialLocation == null
                      ? l10n.placeSearchAddTitle
                      : l10n.placeSearchEditTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Toggle between place search and manual coordinates
            SwitchListTile(
              title: Text(l10n.placeSearchManualCoords),
              subtitle: Text(l10n.placeSearchManualCoordsSubtitle),
              value: _useManualCoordinates,
              onChanged: (value) {
                setState(() {
                  _useManualCoordinates = value;
                  if (value) {
                    _selectedPlaceId = null;
                    _selectedPlace = null;
                  }
                });
              },
            ),
            
            const SizedBox(height: 16),
            
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Location Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l10n.placeSearchNameLabel,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.placeSearchNameRequired;
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Place Search or Manual Coordinates
                      if (!_useManualCoordinates) ...[
                        _buildPlaceSearchSection(),
                      ] else ...[
                        _buildManualCoordinatesSection(),
                      ],
                      
                      const SizedBox(height: 16),
                      
                      // Optional fields
                      TextFormField(
                        controller: _categoryController,
                        decoration: InputDecoration(
                          labelText: l10n.placeSearchCategoryLabel,
                          hintText: l10n.placeSearchCategoryHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _visitDurationController,
                        decoration: InputDecoration(
                          labelText: l10n.placeSearchVisitDurationLabel,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            final duration = int.tryParse(value);
                            if (duration == null || duration <= 0) {
                              return l10n.placeSearchDurationInvalid;
                            }
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l10n.commonCancel),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                Navigator.of(context).pop(_buildLocation());
                              }
                            },
                            child: Text(l10n.commonSave),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceSearchSection() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          decoration: InputDecoration(
            labelText: l10n.placeSearchSearchLabel,
            hintText: l10n.placeSearchSearchHint,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        
        const SizedBox(height: 8),
        
        if (_searchQuery.isNotEmpty) ...[
          _buildSearchResults(),
        ],
        
        if (_selectedPlace != null) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.place, color: Colors.green),
              title: Text(_selectedPlace!.name),
              subtitle: Text(_selectedPlace!.address),
              trailing: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    _selectedPlace = null;
                    _selectedPlaceId = null;
                    _latitudeController.clear();
                    _longitudeController.clear();
                  });
                },
              ),
            ),
          ),
        ],
        
        const SizedBox(height: 16),
        
        // Show coordinates if a place is selected
        if (_selectedPlace != null) ...[
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _latitudeController,
                  decoration: InputDecoration(
                    labelText: l10n.placeSearchLatitude,
                    border: const OutlineInputBorder(),
                  ),
                  readOnly: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _longitudeController,
                  decoration: InputDecoration(
                    labelText: l10n.placeSearchLongitude,
                    border: const OutlineInputBorder(),
                  ),
                  readOnly: true,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildManualCoordinatesSection() {
    final l10n = context.l10n;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _latitudeController,
                decoration: InputDecoration(
                  labelText: l10n.placeSearchLatitudeRequired,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.placeSearchLatitudeRequiredError;
                  }
                  final lat = double.tryParse(value);
                  if (lat == null || lat < -90 || lat > 90) {
                    return l10n.placeSearchLatitudeInvalid;
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _longitudeController,
                decoration: InputDecoration(
                  labelText: l10n.placeSearchLongitudeRequired,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.placeSearchLongitudeRequiredError;
                  }
                  final lng = double.tryParse(value);
                  if (lng == null || lng < -180 || lng > 180) {
                    return l10n.placeSearchLongitudeInvalid;
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    return Consumer(
      builder: (context, ref, child) {
        final searchResults = ref.watch(placeSearchProvider(_searchQuery));
        
        return searchResults.when(
          data: (results) {
            if (results.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(context.l10n.placeSearchNoResults),
              );
            }
            
            return Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final place = results[index] as PlaceSearchResult;
                  return ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(place.name),
                    subtitle: Text(place.address),
                    trailing: place.rating != null 
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                              Text(place.rating!.toStringAsFixed(1)),
                            ],
                          )
                        : null,
                    onTap: () => _onPlaceSelected(place),
                  );
                },
              ),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.l10n.placeSearchError('$error')),
          ),
        );
      },
    );
  }
}
