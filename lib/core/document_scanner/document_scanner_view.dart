import 'package:ekyc_id_flutter/core/document_scanner/document_scanner_values.dart';
import 'package:ekyc_id_flutter/core/models/frame_status.dart';
import 'package:ekyc_id_flutter/core/overlays/doc_minimal/doc_minimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_beep/flutter_beep.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

import 'document_scanner.dart';
import 'document_scanner_controller.dart';
import 'document_scanner_options.dart';
import 'document_scanner_result.dart';

class DocumentScannerView extends StatefulWidget {
  const DocumentScannerView({
    Key? key,
    required this.onDocumentScanned,
    this.documentTypes = const [DocumentScannerDocType.NATIONAL_ID],
    this.overlayMode = DocumentScannerViewOverlayMode.MINIMAL,
    this.options = const DocumentScannerOptions(preparingDuration: 1),
  }) : super(key: key);

  final DocumentScannerOptions options;
  final List<DocumentScannerDocType> documentTypes;
  final DocumentScannerViewOverlayMode overlayMode;
  final OnDocumentScannedCallback onDocumentScanned;

  @override
  State<DocumentScannerView> createState() => _DocumentScannerViewState();
}

class _DocumentScannerViewState extends State<DocumentScannerView> {
  AudioPlayer? player;
  bool isInitialized = false;
  bool shouldRenderCamera = false;
  bool showFlippingAnimation = false;
  bool allowFrameStatusUpdate = true;

  late DocumentScannerController controller;
  DocumentSide currentSide = DocumentSide.MAIN;
  FrameStatus frameStatus = FrameStatus.INITIALIZING;
  List<ObjectDetectionObjectGroup> mainWhiteList = [];
  List<ObjectDetectionObjectGroup> secondaryWhiteList = [];

  DocumentScannerResult? mainSide;
  DocumentScannerResult? secondarySide;

  void _buildWhiteList() {
    for (var doc in widget.documentTypes) {
      var mapping = DOC_TYPE_WHITE_LIST_MAPPING[doc]!;
      this.mainWhiteList.addAll(mapping[DocumentSide.MAIN]!);
      this.secondaryWhiteList.addAll(mapping[DocumentSide.MAIN]!);
    }
  }

  Future<void> onPlatformViewCreated(
    DocumentScannerController controller,
  ) async {
    this.controller = controller;
    await this.controller.start(
          onFrame: onFrame,
          options: widget.options,
          onDetection: onDetection,
          onInitialized: onInitialized,
        );
    await this.controller.setWhiteList(
          mainWhiteList.map((e) => e.toShortString()).toList(),
        );
  }

  @override
  void initState() {
    player = AudioPlayer();
    this._buildWhiteList();
    SystemChrome.setEnabledSystemUIOverlays([]);
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        shouldRenderCamera = true;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
    this.player?.dispose();
    this.controller.dispose();
    super.dispose();
  }

  Widget _buildOverlay() {
    if (widget.overlayMode == DocumentScannerViewOverlayMode.MINIMAL) {
      return DocMinimalOverlay(
        frameStatus: frameStatus,
        currentSide: currentSide,
        showFlippingAnimation: showFlippingAnimation,
      );
    }

    return DocMinimalOverlay(
      frameStatus: frameStatus,
      currentSide: currentSide,
      showFlippingAnimation: showFlippingAnimation,
    );
  }

  void onFrame(FrameStatus f) {
    if (this.mounted) {
      if (allowFrameStatusUpdate) {
        setState(() {
          frameStatus = f;
        });

        if ([
          FrameStatus.CANNOT_GRAB_FACE,
          FrameStatus.CANNOT_GRAB_DOCUMENT,
        ].contains(f)) {
          setState(() {
            allowFrameStatusUpdate = false;
          });

          Future.delayed(const Duration(seconds: 2), () {
            setState(() {
              allowFrameStatusUpdate = true;
            });
          });
        }
      }
    }
  }

  void onInitialized() {
    setState(() {
      isInitialized = true;
      frameStatus = FrameStatus.DOCUMENT_NOT_FOUND;
    });

    playInstruction();
    playBeep();
  }

  void onDetection(DocumentScannerResult result) async {
    try {
      playBeep();

      if (currentSide == DocumentSide.MAIN) {
        mainSide = result;

        if (DOCUMENTS_WITH_SECONDARY_SIDE.contains(result.documentType)) {
          setState(() {
            currentSide = DocumentSide.SECONDARY;
            showFlippingAnimation = true;
          });

          playInstruction();

          Future.delayed(const Duration(seconds: 4), () {
            setState(() {
              showFlippingAnimation = false;
            });
          });

          await this.controller.setWhiteList(
              secondaryWhiteList.map((e) => e.toShortString()).toList());
          throw Exception("next_image");
        }

        await widget
            .onDocumentScanned(
          mainSide: mainSide,
          secondarySide: secondarySide,
        )
            .then((value) async {
          await onBackFromResult(
            fullImage: result.fullImage,
            group: result.documentGroup.toString().toLowerCase(),
          );
        });
      } else {
        secondarySide = result;

        await widget
            .onDocumentScanned(
          mainSide: mainSide,
          secondarySide: secondarySide,
        )
            .then((value) async {
          await onBackFromResult(
            fullImage: mainSide!.fullImage,
            group: mainSide!.documentGroup.toString().toLowerCase(),
          );
        });
      }
    } catch (e) {
      this.controller.nextImage();
    }
  }

  Future<void> onBackFromResult({
    required List<int> fullImage,
    required String group,
  }) async {
    setState(() {
      mainSide = null;
      secondarySide = null;
      currentSide = DocumentSide.MAIN;
    });
    await this
        .controller
        .setWhiteList(mainWhiteList.map((e) => e.toShortString()).toList());
    this.controller.nextImage();
  }

  void playBeep() {
    FlutterBeep.beep();
    Vibration.hasVibrator().then((value) {
      if (value != null && value) {
        Vibration.vibrate();
      }
    });
  }

  void playInstruction() {
    try {
      player
          ?.setAsset(
              "packages/ekyc_id_flutter/assets/audios/scan_${currentSide == DocumentSide.MAIN ? "front" : "back"}_en.mp3")
          .then((value) {
        player?.play();
      });
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: shouldRenderCamera
              ? DocumentScanner(
                  onCreated: onPlatformViewCreated,
                )
              : Container(),
        ),
        Positioned.fill(child: _buildOverlay())
      ],
    );
  }
}