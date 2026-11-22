import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/services/map_search_service.dart';

// Result returned by PlaceSearchSheet: either a picked place or "pick on map".
class PlaceSearchAction {
  const PlaceSearchAction.place(this.place) : pickOnMap = false;
  const PlaceSearchAction.pickOnMap() : place = null, pickOnMap = true;

  final PlaceResult? place;
  final bool pickOnMap;
}

// Google Maps-style search modal with debounced OSM place autocomplete.
class PlaceSearchSheet extends StatefulWidget {
  const PlaceSearchSheet({
    super.key,
    required this.searchService,
    this.nearPoint,
    this.initialQuery = '',
  });

  final MapSearchService searchService;
  final LatLng? nearPoint;
  final String initialQuery;

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  Timer? _debounce;
  int _requestId = 0;
  bool _isSearching = false;
  bool _hasSearched = false;
  List<PlaceResult> _results = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().length >= 2) {
      _runSearch(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      _requestId++;
      setState(() {
        _isSearching = false;
        _hasSearched = false;
        _results = const [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(trimmed);
    });
  }

  Future<void> _runSearch(String query) async {
    final currentId = ++_requestId;
    final places = await widget.searchService.searchPlaces(
      query,
      near: widget.nearPoint,
    );
    if (!mounted || currentId != _requestId) return;
    setState(() {
      _results = places;
      _isSearching = false;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onQueryChanged,
                  onSubmitted: (value) {
                    _debounce?.cancel();
                    if (value.trim().length >= 2) {
                      _runSearch(value.trim());
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search places, roads, landmarks…',
                    prefixIcon: const Icon(Icons.search),
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
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.push_pin_outlined, color: colors.primary),
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
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (_results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _hasSearched
                        ? 'No places found. Try a broader name or choose on the map.'
                        : 'Type at least 2 letters to search real places nearby.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = _results[index];
                      return ListTile(
                        leading: Icon(
                          Icons.location_on_outlined,
                          color: colors.primary,
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
                              ),
                        onTap: () =>
                            Navigator.of(context)
                                .pop(PlaceSearchAction.place(place)),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
