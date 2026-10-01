import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/shared/widgets/map_actions.dart';

final recentPlacesProvider = NotifierProvider<RecentPlaces, List<PlaceResult>>(
  RecentPlaces.new,
);

class RecentPlaces extends Notifier<List<PlaceResult>> {
  @override
  List<PlaceResult> build() => [];
  void add(PlaceResult place) {
    state = [
      place,
      ...state.where((item) => item.label != place.label),
    ].take(8).toList();
  }

  void clear() => state = [];
}

class PlaceSearchSheet extends ConsumerStatefulWidget {
  const PlaceSearchSheet({super.key, required this.start, this.onChooseOnMap});
  final bool start;
  final VoidCallback? onChooseOnMap;
  @override
  ConsumerState<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends ConsumerState<PlaceSearchSheet> {
  final _text = TextEditingController();
  List<PlaceResult> _places = [];
  String? _message;
  bool _busy = false;
  int _revision = 0;
  Timer? _debounce;
  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _pick(PlaceResult place) {
    ref.read(recentPlacesProvider.notifier).add(place);
    Navigator.pop(context, place);
  }

  Future<void> _search() async {
    final query = _text.text.trim();
    if (query.length < 3) {
      setState(() => _message = 'Enter at least 3 characters.');
      return;
    }
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    final revision = _revision;
    setState(() {
      _busy = true;
      _places = [];
      _message = null;
    });
    try {
      final api = ref.read(roadApiProvider);
      if (!api.configured) {
        throw StateError(
          'Live place search is unavailable. Connect to RoadGuard and try again.',
        );
      }
      final places = await api.searchPlaces(query);
      if (!mounted || revision != _revision) return;
      setState(() {
        _places = places;
        _message = places.isEmpty
            ? 'No places found. Add a city or choose on the map.'
            : null;
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(
          () => _message = error is StateError
              ? error.message.toString()
              : 'Live place search is unavailable. Retry or choose on the map.',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: MapSearchBar(
                  actionKey: const Key('place-query'),
                  onTap: () {},
                  controller: _text,
                  readOnly: false,
                  autofocus: true,
                  onChanged: (value) {
                    _debounce?.cancel();
                    _revision++;
                    setState(() {
                      _busy = false;
                      _places = [];
                      _message = null;
                    });
                    if (value.trim().length >= 3) {
                      _debounce = Timer(
                        const Duration(milliseconds: 450),
                        _search,
                      );
                    }
                  },
                  onSubmitted: (_) => _search(),
                ),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 18),
              children: [
                if (_text.text.trim().isEmpty &&
                    ref.watch(recentPlacesProvider).isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Recent',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF173441),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.read(recentPlacesProvider.notifier).clear(),
                          child: const Text('Clear recent'),
                        ),
                      ],
                    ),
                  ),
                  for (final place in ref.watch(recentPlacesProvider))
                    GestureDetector(
                      onTap: () => _pick(place),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFDDE5E8)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2F4),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.history_rounded,
                                color: Color(0xFF173441),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    place.label,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF173441),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      _message!,
                      style: const TextStyle(
                        color: Color(0xFF5E707A),
                        fontSize: 13,
                      ),
                    ),
                  ),
                for (final place in _places)
                  GestureDetector(
                    onTap: () => _pick(place),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFDDE5E8)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2F4),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _text.text.trim().isEmpty
                                  ? Icons.history_rounded
                                  : Icons.location_on_outlined,
                              color: const Color(0xFF173441),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  place.label,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF173441),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_places.isEmpty &&
                    _text.text.trim().isEmpty &&
                    ref.watch(recentPlacesProvider).isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 20, bottom: 16),
                    child: Text(
                      'Search for a real destination to see matching places.',
                      style: TextStyle(color: Color(0xFF5E707A), fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    final chooseOnMap = widget.onChooseOnMap;
                    Navigator.pop(context);
                    chooseOnMap?.call();
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Choose on map'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Search sends your query to Photon / OpenStreetMap. Avoid private information.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF5E707A)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
