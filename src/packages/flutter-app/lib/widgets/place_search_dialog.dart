import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                  widget.initialLocation == null ? 'Add Location' : 'Edit Location',
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
              title: const Text('Use Manual Coordinates'),
              subtitle: const Text('Enter latitude/longitude manually instead of searching places'),
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
                        decoration: const InputDecoration(
                          labelText: 'Location Name *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Location name is required';
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
                        decoration: const InputDecoration(
                          labelText: 'Category (optional)',
                          hintText: 'e.g., restaurant, museum, coffee_shop',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _visitDurationController,
                        decoration: const InputDecoration(
                          labelText: 'Visit Duration (minutes, optional)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            final duration = int.tryParse(value);
                            if (duration == null || duration <= 0) {
                              return 'Please enter a valid duration in minutes';
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
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                Navigator.of(context).pop(_buildLocation());
                              }
                            },
                            child: const Text('Save'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Search for a place',
            hintText: 'Type to search for restaurants, attractions, etc.',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
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
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _longitudeController,
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    border: OutlineInputBorder(),
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _latitudeController,
                decoration: const InputDecoration(
                  labelText: 'Latitude *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Latitude is required';
                  }
                  final lat = double.tryParse(value);
                  if (lat == null || lat < -90 || lat > 90) {
                    return 'Enter valid latitude (-90 to 90)';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _longitudeController,
                decoration: const InputDecoration(
                  labelText: 'Longitude *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Longitude is required';
                  }
                  final lng = double.tryParse(value);
                  if (lng == null || lng < -180 || lng > 180) {
                    return 'Enter valid longitude (-180 to 180)';
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
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No places found. Try a different search term.'),
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
            child: Text('Error: $error'),
          ),
        );
      },
    );
  }
}
