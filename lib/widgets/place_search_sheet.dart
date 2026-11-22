import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/services/app_preferences.dart';
import 'package:ridesync/services/map_search_service.dart';

// Quick Google Maps-style rider category shortcuts shown on the map and search sheet.
class SearchCategory {
  const SearchCategory({
    required this.id,
    required this.label,
    required this.query,
    required this.icon,
  });

  final String id;
  final String label;
  final String query;
  final IconData icon;
}

const List<SearchCategory> kRiderSearchCategories = [
  SearchCategory(
    id: 'fuel',
    label: 'Fuel',
    query: 'fuel station',
    icon: Icons.local_gas_station_outlined,
  ),
  SearchCategory(
    id: 'cafe',
    label: 'Cafe',
    query: 'cafe',
    icon: Icons.local_cafe_outlined,
  ),
  SearchCategory(
    id: 'food',
    label: 'Food',
    query: 'restaurant',
    icon: Icons.restaurant_outlined,
  ),
  SearchCategory(
    id: 'mechanic',
    label: 'Mechanic',
    query: 'motorcycle repair',
    icon: Icons.build_outlined,
  ),
  SearchCategory(
    id: 'viewpoint',
    label: 'Viewpoints',
    query: 'viewpoint',
    icon: Icons.landscape_outlined,
  ),
  SearchCategory(
    id: 'hospital',
    label: 'Hospital',
    query: 'hospital',
    icon: Icons.local_hospital_outlined,
  ),
];

IconData iconForPlaceCategory(String? category) {
  return switch (category) {
    'fuel' => Icons.local_gas_station_outlined,
    'cafe' => Icons.local_cafe_outlined,
    'food' => Icons.restaurant_outlined,
    'mechanic' => Icons.build_outlined,
    'viewpoint' => Icons.landscape_outlined,
    'hospital' => Icons.local_hospital_outlined,
    _ => Icons.location_on_outlined,
  };
}

// Result returned by PlaceSearchSheet: either a picked place or "pick on map".
class PlaceSearchAction {
  const PlaceSearchAction.place(this.place) : pickOnMap = false;
  const PlaceSearchAction.pickOnMap() : place = null, pickOnMap = true;

  final PlaceResult? place;
  final bool pickOnMap;
}

// Google Maps-style search modal with category chips, recent searches,
// distance badges, Photon + Nominatim fallback, and clear offline error states.
class PlaceSearchSheet extends StatefulWidget {
  const PlaceSearchSheet({
    super.key,
    required this.searchService,
    this.nearPoint,
    this.initialQuery = '',
    this.initialCategory,
    this.preferences,
  });

  final MapSearchService searchService;
  final LatLng? nearPoint;
  final String initialQuery;
  final SearchCategory? initialCategory;
  final AppPreferences? preferences;

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  late final AppPreferences _prefs = widget.preferences ?? AppPreferences();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialCategory?.query ?? widget.initialQuery,
  );
  Timer? _debounce;
  int _requestId = 0;
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;
  String? _activeCategoryId;
  List<PlaceResult> _results = const [];
  List<PlaceResult> _recentPlaces = const [];

  @override
  void initState() {
    super.initState();
    _activeCategoryId = widget.initialCategory?.id;
    _loadRecents();
    final startQuery = _controller.text.trim();
    if (startQuery.length >= 2) {
      _runSearch(startQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final recents = await _prefs.loadRecentPlaces();
    if (!mounted) return;
    setState(() {
      _recentPlaces = recents;
    });
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (_activeCategoryId != null) {
      _activeCategoryId = null;
    }
    if (trimmed.length < 2) {
      _requestId++;
      setState(() {
        _isSearching = false;
        _hasSearched = false;
        _errorMessage = null;
        _results = const [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _runSearch(trimmed);
    });
  }

  void _onCategoryTapped(SearchCategory category) {
    _debounce?.cancel();
    _controller.text = category.query;
    _controller.selection = TextSelection.collapsed(
      offset: category.query.length,
    );
    setState(() {
      _activeCategoryId = category.id;
      _isSearching = true;
      _errorMessage = null;
    });
    _runSearch(category.query);
  }

  Future<void> _runSearch(String query) async {
    final currentId = ++_requestId;
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });
    final outcome = await widget.searchService.searchPlacesOutcome(
      query,
      near: widget.nearPoint,
    );
    if (!mounted || currentId != _requestId) return;
    setState(() {
      _results = outcome.results;
      _errorMessage = outcome.errorMessage;
      _isSearching = false;
      _hasSearched = true;
    });
  }

  Future<void> _selectPlace(PlaceResult place) async {
    await _prefs.saveRecentPlace(place);
    if (!mounted) return;
    Navigator.of(context).pop(PlaceSearchAction.place(place));
  }

  Future<void> _clearRecents() async {
    await _prefs.clearRecentPlaces();
    if (!mounted) return;
    setState(() {
      _recentPlaces = const [];
    });
  }

  Widget _buildPlaceTile(
    BuildContext context,
    PlaceResult place, {
    required bool isRecent,
  }) {
    final colors = Theme.of(context).colorScheme;
    final near = widget.nearPoint;
    final distanceLabel = near == null
        ? null
        : formatPlaceDistance(near, place.point);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: SizedBox(
        width: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isRecent
                    ? colors.surfaceContainerHighest
                    : colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRecent
                    ? Icons.history_rounded
                    : iconForPlaceCategory(place.category),
                size: 18,
                color: isRecent
                    ? colors.onSurfaceVariant
                    : colors.onPrimaryContainer,
              ),
            ),
            if (distanceLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                distanceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      title: Text(
        place.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: place.subtitle.isEmpty
          ? null
          : Text(
              place.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
      trailing: Icon(
        Icons.north_west_rounded,
        size: 16,
        color: colors.onSurfaceVariant,
      ),
      onTap: () => _selectPlace(place),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final showRecents =
        _controller.text.trim().length < 2 && _recentPlaces.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Google Maps-style pill search bar with back & clear controls.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: widget.initialCategory == null,
                  textInputAction: TextInputAction.search,
                  onChanged: _onQueryChanged,
                  onSubmitted: (value) {
                    _debounce?.cancel();
                    if (value.trim().length >= 2) {
                      _runSearch(value.trim());
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search here',
                    filled: true,
                    fillColor: colors.surfaceContainerHighest,
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _controller.clear();
                              _onQueryChanged('');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              // Quick rider category chips (Fuel, Cafe, Food, Mechanic, etc.).
              SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  scrollDirection: Axis.horizontal,
                  itemCount: kRiderSearchCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = kRiderSearchCategories[index];
                    final selected = _activeCategoryId == category.id;
                    return FilterChip(
                      selected: selected,
                      showCheckmark: false,
                      avatar: Icon(
                        category.icon,
                        size: 16,
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                      label: Text(category.label),
                      onSelected: (_) => _onCategoryTapped(category),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (_isSearching)
                const LinearProgressIndicator(minHeight: 2)
              else
                const Divider(height: 1),

              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 17,
                  backgroundColor: colors.secondaryContainer,
                  child: Icon(
                    Icons.push_pin_outlined,
                    size: 18,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                title: const Text(
                  'Choose on map',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Tap anywhere on the map to drop a pin'),
                onTap: () =>
                    Navigator.of(context)
                        .pop(const PlaceSearchAction.pickOnMap()),
              ),
              const Divider(height: 1),

              // Body: offline error, recent searches, live results, or hint.
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 36,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          final q = _controller.text.trim();
                          if (q.length >= 2) _runSearch(q);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (showRecents)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recent',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            TextButton(
                              onPressed: _clearRecents,
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _recentPlaces.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) => _buildPlaceTile(
                            context,
                            _recentPlaces[index],
                            isRecent: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_results.isNotEmpty)
                Expanded(
                  child: ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _buildPlaceTile(
                      context,
                      _results[index],
                      isRecent: false,
                    ),
                  ),
                )
              else if (!_isSearching)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _hasSearched
                        ? 'No places found. Try a broader name or choose on the map.'
                        : 'Search a place, pick a category above, or drop a pin on the map.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
