import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker/google_maps_place_picker.dart';
import 'package:google_maps_place_picker/providers/place_provider.dart';
import 'package:google_maps_place_picker/src/components/animated_pin.dart';
import 'package:google_maps_place_picker/src/components/floating_card.dart';
import 'package:google_maps_place_picker/src/place_picker.dart';
import 'package:google_maps_webservice/geocoding.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:provider/provider.dart';
import 'package:tuple/tuple.dart';

typedef SelectedPlaceWidgetBuilder = Widget Function(
  BuildContext context,
  PickResult selectedPlace,
  SearchingState state,
  bool isSearchBarFocused,
);

typedef PinBuilder = Widget Function(
  BuildContext context,
  PinState state,
);

class GoogleMapPlacePicker extends StatefulWidget {
  GoogleMapPlacePicker(
      {@required this.initialTarget,
      @required this.appBarKey,
      this.selectedPlaceWidgetBuilder,
      this.pinBuilder,
      this.onSearchFailed,
      this.onMoveStart,
      this.onMapCreated,
      this.debounceMilliseconds,
      this.enableMapTypeButton,
      this.enableMyLocationButton,
      this.onToggleMapType,
      this.onMyLocation,
      this.onPlacePicked,
      this.usePinPointingSearch,
      this.useMapSelectSearch,
      this.usePlaceDetailSearch,
      this.selectInitialPosition,
      this.language,
      this.forceSearchOnZoomChanged,
      this.geolocator,}
      );

  final LatLng initialTarget;
  final GlobalKey appBarKey;

  final SelectedPlaceWidgetBuilder selectedPlaceWidgetBuilder;
  final PinBuilder pinBuilder;

  final ValueChanged<String> onSearchFailed;
  final VoidCallback onMoveStart;
  final MapCreatedCallback onMapCreated;
  final VoidCallback onToggleMapType;
  final VoidCallback onMyLocation;
  final ValueChanged<PickResult> onPlacePicked;

  final int debounceMilliseconds;
  final bool enableMapTypeButton;
  final bool enableMyLocationButton;

  final bool usePinPointingSearch;
  final bool usePlaceDetailSearch;
  final bool useMapSelectSearch;

  final bool selectInitialPosition;

  final String language;

  final bool forceSearchOnZoomChanged;

  final Geolocator geolocator;

  @override
  State<StatefulWidget> createState() => _GoogleMapPlacePicker(
    initialTarget: this.initialTarget,
    appBarKey: this.appBarKey,
    selectedPlaceWidgetBuilder: this.selectedPlaceWidgetBuilder,
    pinBuilder: this.pinBuilder,
    onSearchFailed: this.onSearchFailed,
    onMoveStart: this.onMoveStart,
    onMapCreated: this.onMapCreated,
    debounceMilliseconds: this.debounceMilliseconds,
    enableMapTypeButton: this.enableMapTypeButton,
    enableMyLocationButton: this.enableMyLocationButton,
    onToggleMapType: this.onToggleMapType,
    onMyLocation: this.onMyLocation,
    onPlacePicked: this.onPlacePicked,
    usePinPointingSearch: this.usePinPointingSearch,
    useMapSelectSearch: this.useMapSelectSearch,
    usePlaceDetailSearch: this.usePlaceDetailSearch,
    selectInitialPosition: this.selectInitialPosition,
    language: this.language,
    forceSearchOnZoomChanged: this.forceSearchOnZoomChanged,
    geolocator: this.geolocator,
  );
}

class _GoogleMapPlacePicker extends State<GoogleMapPlacePicker> {
   _GoogleMapPlacePicker({
    @required this.initialTarget,
    @required this.appBarKey,
    this.selectedPlaceWidgetBuilder,
    this.pinBuilder,
    this.onSearchFailed,
    this.onMoveStart,
    this.onMapCreated,
    this.debounceMilliseconds,
    this.enableMapTypeButton,
    this.enableMyLocationButton,
    this.onToggleMapType,
    this.onMyLocation,
    this.onPlacePicked,
    this.usePinPointingSearch,
    this.useMapSelectSearch,
    this.usePlaceDetailSearch,
    this.selectInitialPosition,
    this.language,
    this.forceSearchOnZoomChanged,
    this.geolocator,
  });

  final LatLng initialTarget;
  final GlobalKey appBarKey;

  final SelectedPlaceWidgetBuilder selectedPlaceWidgetBuilder;
  final PinBuilder pinBuilder;

  final ValueChanged<String> onSearchFailed;
  final VoidCallback onMoveStart;
  final MapCreatedCallback onMapCreated;
  final VoidCallback onToggleMapType;
  final VoidCallback onMyLocation;
  final ValueChanged<PickResult> onPlacePicked;

  final int debounceMilliseconds;
  final bool enableMapTypeButton;
  final bool enableMyLocationButton;

  final bool usePinPointingSearch;
  final bool usePlaceDetailSearch;
  final bool useMapSelectSearch;

  final bool selectInitialPosition;

  final String language;

  final bool forceSearchOnZoomChanged;

  final Geolocator geolocator;

  Set<Marker> _markers = Set();

  BottomScreenState _bottomState = BottomScreenState.Nonexistent;

  _searchByCameraLocation(PlaceProvider provider) async {
    // We don't want to search location again if camera location is changed by zooming in/out.
    bool hasZoomChanged = provider.cameraPosition != null &&
        provider.prevCameraPosition != null &&
        provider.cameraPosition.zoom != provider.prevCameraPosition.zoom;
    if (forceSearchOnZoomChanged == false && hasZoomChanged) return;

    provider.placeSearchingState = SearchingState.Searching;

    final GeocodingResponse response =
        await provider.geocoding.searchByLocation(
      Location(provider.cameraPosition.target.latitude,
          provider.cameraPosition.target.longitude),
      language: language,
    );

    if (response.errorMessage?.isNotEmpty == true ||
        response.status == "REQUEST_DENIED") {
      print("Camera Location Search Error: " + response.errorMessage);
      if (onSearchFailed != null) {
        onSearchFailed(response.status);
      }
      provider.placeSearchingState = SearchingState.Idle;
      return;
    }

    if (usePlaceDetailSearch) {
      final PlacesDetailsResponse detailResponse =
          await provider.places.getDetailsByPlaceId(
        response.results[0].placeId,
        language: language,
      );

      if (detailResponse.errorMessage?.isNotEmpty == true ||
          detailResponse.status == "REQUEST_DENIED") {
        print("Fetching details by placeId Error: " +
            detailResponse.errorMessage);
        if (onSearchFailed != null) {
          onSearchFailed(detailResponse.status);
        }
        provider.placeSearchingState = SearchingState.Idle;
        return;
      }

      provider.selectedPlace =
          PickResult.fromPlaceDetailResult(detailResponse.result);
    } else {
      provider.selectedPlace =
          PickResult.fromGeocodingResult(response.results[0]);
    }

    provider.placeSearchingState = SearchingState.Idle;
  }


  _searchByMapSelection(PlaceProvider provider) async {
    provider.placeSearchingState = SearchingState.Searching;

    final GeocodingResponse response =
        await provider.geocoding.searchByLocation(
      Location(provider.markers.first.position.latitude,
          provider.markers.first.position.longitude),
      language: language,
    );

    if (response.errorMessage?.isNotEmpty == true ||
        response.status == "REQUEST_DENIED") {
      print("Map Selection Search Error: " + response.errorMessage);
      if (onSearchFailed != null) {
        onSearchFailed(response.status);
      }
      provider.placeSearchingState = SearchingState.Idle;
      return;
    }

    if (usePlaceDetailSearch) {
      final PlacesDetailsResponse detailResponse =
          await provider.places.getDetailsByPlaceId(
        response.results[0].placeId,
        language: language,
      );

      if (detailResponse.errorMessage?.isNotEmpty == true ||
          detailResponse.status == "REQUEST_DENIED") {
        print("Fetching details by placeId Error: " +
            detailResponse.errorMessage);
        if (onSearchFailed != null) {
          onSearchFailed(detailResponse.status);
        }
        provider.placeSearchingState = SearchingState.Idle;
        return;
      }

      provider.selectedPlace =
          PickResult.fromPlaceDetailResult(detailResponse.result);
    } else {
      provider.selectedPlace =
          PickResult.fromGeocodingResult(response.results[0]);
    }

    provider.placeSearchingState = SearchingState.Idle;
  }

  @override
  Widget build(BuildContext context) {
    var widgets = [
      _buildGoogleMap(context),
      //_buildFloatingCard(),
      _buildMapIcons(context),
    ];

    if (!useMapSelectSearch) {
      widgets.add(
        _buildPin()
      );
    }

    return Stack(
      children: widgets,
    );
  }

  Widget _buildGoogleMap(BuildContext context) {
    return Selector<PlaceProvider, MapType>(
        selector: (_, provider) => provider.mapType,
        builder: (_, data, __) {
          PlaceProvider provider = PlaceProvider.of(context, listen: false);
          CameraPosition initialCameraPosition =
              CameraPosition(target: initialTarget, zoom: 15);
          return GoogleMap(
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            initialCameraPosition: initialCameraPosition,
            mapType: data,
            myLocationEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              provider.mapController = controller;
              provider.setCameraPosition(null);
              provider.pinState = PinState.Idle;
              provider.markers = _markers;

              // When select initialPosition set to true.
              if (selectInitialPosition && !useMapSelectSearch) {
                provider.setCameraPosition(initialCameraPosition);
                _searchByCameraLocation(provider);
              } else if (useMapSelectSearch) {
                provider.bottomScreenState = BottomScreenState.Nonexistent;
              }
            },
            markers: _markers,
            onCameraIdle: () {
              if (provider.isAutoCompleteSearching) {
                provider.isAutoCompleteSearching = false;
                provider.pinState = PinState.Idle;
                return;
              }

              // Perform search only if the setting is to true.
              if (usePinPointingSearch && !useMapSelectSearch) {
                // Search current camera location only if camera has moved (dragged) before.
                if (provider.pinState == PinState.Dragging) {
                  // Cancel previous timer.
                  if (provider.debounceTimer?.isActive ?? false) {
                    provider.debounceTimer.cancel();
                  }
                  provider.debounceTimer =
                      Timer(Duration(milliseconds: debounceMilliseconds), () {
                    _searchByCameraLocation(provider);
                  });
                }
              }
              provider.pinState = PinState.Idle;
            },
            onCameraMoveStarted: () {
              provider.setPrevCameraPosition(provider.cameraPosition);

              // Cancel any other timer.
              provider.debounceTimer?.cancel();

              // Update state, dismiss keyboard and clear text.
              provider.pinState = PinState.Dragging;

              onMoveStart();
            },
            onCameraMove: (CameraPosition position) {
              provider.setCameraPosition(position);
            },
            onTap: (LatLng latlng) {
              if (!useMapSelectSearch) {
                return;
              }
              Marker marker = Marker(
                // This marker id can be anything that uniquely identifies each marker.
                  markerId: MarkerId((latlng.latitude + latlng.longitude).toString()),
                  position: latlng,
                  onTap: () {
                    showModalBottomSheet(
                        context: context,
                        enableDrag: true,
                        isDismissible: true,
                        builder: (BuildContext context) {
                          return ChangeNotifierProvider.value(
                            value: provider,
                            child: Container (
                              child: _buildBottomSheet(context, provider),
                            ),
                          );
                        }
                    );
                  }
              );

              setState(() {
                _markers.clear();
                _markers.add(marker);
              });

              Set<Marker> markers = {marker};
              provider.markers = markers;
              print(provider.markers.length);

              _searchByMapSelection(provider);

              showModalBottomSheet(
                  context: context,
                  enableDrag: true,
                  isDismissible: true,
                  builder: (BuildContext context) {
                    return ChangeNotifierProvider.value(
                        value: provider,
                        child: Container (
                          child: _buildBottomSheet(context, provider),
                        ),
                    );
                  }
              );
            },
          );
        });
  }

  Widget _buildPin() {
    return Center(
      child: Selector<PlaceProvider, PinState>(
        selector: (_, provider) => provider.pinState,
        builder: (context, state, __) {
          if (pinBuilder == null) {
            return _defaultPinBuilder(context, state);
          } else {
            return Builder(
                builder: (builderContext) => pinBuilder(builderContext, state));
          }
        },
      ),
    );
  }

  Widget _defaultPinBuilder(BuildContext context, PinState state) {
    if (state == PinState.Preparing) {
      return Container();
    } else if (state == PinState.Idle) {
      return Stack(
        children: <Widget>[
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.place, size: 36, color: Colors.red),
                SizedBox(height: 42),
              ],
            ),
          ),
          Center(
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
    } else {
      return Stack(
        children: <Widget>[
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AnimatedPin(
                    child: Icon(Icons.place, size: 36, color: Colors.red)),
                SizedBox(height: 42),
              ],
            ),
          ),
          Center(
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildBottomSheet(BuildContext context, PlaceProvider provider) {
    return Selector<PlaceProvider, Tuple3<PickResult, SearchingState, bool>>(
      selector: (_, provider) => Tuple3(provider.selectedPlace,
          provider.placeSearchingState, provider.isSearchBarFocused),
      builder: (context, data, __) {
        if ((data.item1 == null && data.item2 == SearchingState.Idle) ||
            data.item3 == true) {
          return Container();
        } else {
          if (selectedPlaceWidgetBuilder == null) {
            return _defaultNotCardBuilder(context, data.item1, data.item2);
          } else {
            return Builder(
                builder: (builderContext) => selectedPlaceWidgetBuilder(
                    builderContext, data.item1, data.item2, data.item3));
          }
        }
      },
    );

  }

  void _handleBottomSheet(BuildContext context, PickResult data, SearchingState state) {

  }

  Widget _buildFloatingCard() {
    return Selector<PlaceProvider, Tuple3<PickResult, SearchingState, bool>>(
      selector: (_, provider) => Tuple3(provider.selectedPlace,
          provider.placeSearchingState, provider.isSearchBarFocused),
      builder: (context, data, __) {
        if ((data.item1 == null && data.item2 == SearchingState.Idle) ||
            data.item3 == true) {
          return Container();
        } else {
          if (selectedPlaceWidgetBuilder == null) {
            return _defaultPlaceWidgetBuilder(context, data.item1, data.item2);
          } else {
            return Builder(
                builder: (builderContext) => selectedPlaceWidgetBuilder(
                    builderContext, data.item1, data.item2, data.item3));
          }
        }
      },
    );
  }

  Widget _defaultPlaceWidgetBuilder(
      BuildContext context, PickResult data, SearchingState state) {
    return FloatingCard(
      bottomPosition: MediaQuery.of(context).size.height * 0.05,
      leftPosition: MediaQuery.of(context).size.width * 0.025,
      rightPosition: MediaQuery.of(context).size.width * 0.025,
      width: MediaQuery.of(context).size.width * 0.9,
      borderRadius: BorderRadius.circular(12.0),
      elevation: 4.0,
      color: Theme.of(context).cardColor,
      child: state == SearchingState.Searching
          ? _buildLoadingIndicator()
          : _buildSelectionDetails(context, data),
    );
  }

  Widget _defaultNotCardBuilder(BuildContext context, PickResult data, SearchingState state) {
    return state == SearchingState.Searching
        ? _buildLoadingIndicator()
        : _buildSelectionDetails(context, data);
  }

  Widget _buildLoadingIndicator() {
    return Container(
      height: 48,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildSelectionDetails(BuildContext context, PickResult result) {
    var placeLocation;
    var placeName;
    var placeAdd;
    var placeCategory;

    if (result!= null) {
      placeLocation = result.geometry.location;
      placeName = result.name;
      placeAdd = result.formattedAddress;
      placeCategory = result.types[0]; //this is inaccurate
      print(placeName);
      print(placeAdd);
      print(placeCategory);
    } else {
      print("result is null");
    }

    //using initialTarget for userPosition to calculate distance
    //will not be adaptive to users moving while using app

    var body =
        result == null
        ? _buildLoadingIndicator()
        :
    FutureProvider (
        create: (context) => geolocator.distanceBetween(
            initialTarget.latitude, initialTarget.longitude,
            placeLocation.lat, placeLocation.lng),
        child: Container(
          height: 150,
          width: 300,
          child: Stack(
            children: <Widget>[
              //upper left information
              Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    width: 250,
                    child: Column (
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        (placeName == null)? Text ("null") : Text (
                          result.name,
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        (placeAdd == null)? Text ("null") : Text (
                          result.formattedAddress,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                          ),
                        )
                      ],
                    ),
                  )
              ),

              //upper right information
              Align(
                alignment: Alignment.topRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Consumer<double>
                      (builder: (context, meters, widget) {
                      return (meters != null)
                          ?Text(
                        '${(meters/1609.0).truncateToDouble()} miles',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      )
                          :Container();
                    },
                    ),

                    priceLevelToIcon(result.priceLevel), //MAKE THIS ALIGN PLS

                    Text(
                      "category",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        )
    );

    return Container(
      margin: EdgeInsets.all(10),
      child: Column(
        children: <Widget>[
          body, //THIS IS THE PLACE DETAILS
          SizedBox(height: 10),
          RaisedButton(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Text(
              "Select here",
              style: TextStyle(fontSize: 16),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4.0),
            ),
            onPressed: () {
              onPlacePicked(result);
            },
          ),
        ],
      ),
    );
  }

  Widget priceLevelToIcon(PriceLevel priceLevel) {
    double _size = 10;
    //initially price is null so three gray dollar signs
    var priceWidget = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Icon(
          Icons.attach_money,
          color: Colors.black54,
          size: _size,
        ),
        Icon(
          Icons.attach_money,
          color: Colors.black54,
          size: _size,
        ),
        Icon(
          Icons.attach_money,
          color: Colors.black54,
          size: _size,
        )
      ],
    );

    if (priceLevel == PriceLevel.free || priceLevel == PriceLevel.inexpensive) {
      priceWidget = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Icon(
            Icons.attach_money,
            color: Colors.black,
            size: _size,
          ),
          Icon(
            Icons.attach_money,
            color: Colors.black54,
            size: _size,
          ),
          Icon(
            Icons.attach_money,
            color: Colors.black54,
            size: _size,
          )
        ],
      );
    } else if (priceLevel == PriceLevel.moderate || priceLevel == PriceLevel.expensive) {
      priceWidget = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Icon(
            Icons.attach_money,
            color: Colors.black,
            size: _size,
          ),
          Icon(
            Icons.attach_money,
            color: Colors.black,
            size: _size,
          ),
          Icon(
            Icons.attach_money,
            color: Colors.black54,
            size: _size,
          )
        ],
      );
    } else if (priceLevel == PriceLevel.veryExpensive){
      priceWidget = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Icon(
            Icons.attach_money,
            color: Colors.black,
            size: _size,
          ),
          Icon(
            Icons.attach_money,
            color: Colors.black,
            size: _size,
          ),
          Icon(
            Icons.attach_money,
            color: Colors.black,
            size: _size,
          )
        ],
      );
    }

    return priceWidget;
  }

  Widget _buildMapIcons(BuildContext context) {
    final RenderBox appBarRenderBox =
        appBarKey.currentContext.findRenderObject();

    return Positioned(
      top: appBarRenderBox.size.height,
      right: 15,
      child: Column(
        children: <Widget>[
          enableMapTypeButton
              ? Container(
                  width: 35,
                  height: 35,
                  child: RawMaterialButton(
                    shape: CircleBorder(),
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black54
                        : Colors.white,
                    elevation: 8.0,
                    onPressed: onToggleMapType,
                    child: Icon(Icons.layers),
                  ),
                )
              : Container(),
          SizedBox(height: 10),
          enableMyLocationButton
              ? Container(
                  width: 35,
                  height: 35,
                  child: RawMaterialButton(
                    shape: CircleBorder(),
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black54
                        : Colors.white,
                    elevation: 8.0,
                    onPressed: onMyLocation,
                    child: Icon(Icons.my_location),
                  ),
                )
              : Container(),
        ],
      ),
    );
  }
}
