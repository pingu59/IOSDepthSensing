/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's primary view controller that presents the camera interface.
*/

import UIKit
import AVFoundation
import Photos
import Dispatch

class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate, ItemSelectionViewControllerDelegate {
    
    private var spinner: UIActivityIndicatorView!
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }

    // MARK: View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable the UI. Enable the UI later, if and only if the session starts running.
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        photoButton.isEnabled = false
        livePhotoModeButton.isEnabled = false
        depthDataDeliveryButton.isEnabled = false
        portraitEffectsMatteDeliveryButton.isEnabled = false
        semanticSegmentationMatteDeliveryButton.isEnabled = false
        captureModeControl.isEnabled = false
        
        // Set up the video preview view.
        previewView.session = session
        /*
         Check the video authorization status. Video access is required and audio
         access is optional. If the user denies audio access, AVCam won't
         record audio during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.yellow
            self.previewView.addSubview(self.spinner)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    override var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        if let movieFileOutput = movieFileOutput {
            return !movieFileOutput.isRecording
        }
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    private var selectedSemanticSegmentationMatteTypes = [AVSemanticSegmentationMatte.MatteType]()
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private var setupResult: SessionSetupResult = .success
    
    @IBOutlet weak var view_multiplex: UIView!
    @IBOutlet weak var view_black: UIView!
    @IBOutlet weak var view_white: UIView!
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: PreviewView!
    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        /*
         Do not create an AVCaptureMovieFileOutput when setting up the session because
         Live Photo is not supported when AVCaptureMovieFileOutput is added to the session.
         */
        session.sessionPreset = .photo
        
        // Add video input.
        do {            
            // Choose the back dual camera, if available, otherwise default to a wide angle camera.
            
            guard let videoDevice = AVCaptureDevice.default(.builtInTrueDepthCamera,
                for: .video, position: .unspecified)
                else { fatalError("No true depth camera.") }
            do{
                try videoDevice.lockForConfiguration()
            }catch{
                print("Unable to lock the device config")
            }
            // Select a depth (not disparity) format that works with the active color format.
            let availableFormats = videoDevice.activeFormat.supportedDepthDataFormats

            let depthFormat = availableFormats.filter { format in
                let pixelFormatType =
                    CMFormatDescriptionGetMediaSubType(format.formatDescription)
//                print(pixelFormatType  == kCVPixelFormatType_DepthFloat16)
//                print(pixelFormatType  == kCVPixelFormatType_DepthFloat32) THIS ONE
//                print("========")
                return (pixelFormatType == kCVPixelFormatType_DepthFloat16 ||
                        pixelFormatType == kCVPixelFormatType_DepthFloat32)
            }.first

            // Set the capture device to use that depth format.
            videoDevice.activeDepthDataFormat = depthFormat
            videoDevice.unlockForConfiguration()
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    /*
                     Dispatch video streaming to the main queue because AVCaptureVideoPreviewLayer is the backing layer for PreviewView.
                     You can manipulate UIView only on the main thread.
                     Note: As an exception to the above rule, it's not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                     
                     Use the window scene's orientation as the initial video orientation. Subsequent orientation changes are
                     handled by CameraViewController.viewWillTransition(to:with:).
                     */
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add an audio input device.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
        
        // Add the photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = false //photoOutput.isLivePhotoCaptureSupported
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
            photoOutput.enabledSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            selectedSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            photoOutput.maxPhotoQualityPrioritization = .quality
            livePhotoMode = .off //photoOutput.isLivePhotoCaptureSupported ? .on : .off
            depthDataDeliveryMode = photoOutput.isDepthDataDeliverySupported ? .on : .off
            portraitEffectsMatteDeliveryMode = photoOutput.isPortraitEffectsMatteDeliverySupported ? .on : .off
            photoQualityPrioritizationMode = .quality
            
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton) {
        sessionQueue.async {
            /*
             The session might fail to start running, for example, if a phone or FaceTime call is still
             using audio or video. This failure is communicated by the session posting a
             runtime error notification. To avoid repeatedly failing to start the session,
             only try to restart the session in the error handler if you aren't
             trying to resume the session.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }
    
    private enum CaptureMode: Int {
        case photo = 0
        case movie = 1
    }
    
    @IBOutlet private weak var captureModeControl: UISegmentedControl!
    
    /// - Tag: EnableDisableModes
    @IBAction private func toggleCaptureMode(_ captureModeControl: UISegmentedControl) {
        captureModeControl.isEnabled = false
        
        if captureModeControl.selectedSegmentIndex == CaptureMode.photo.rawValue {
            recordButton.isEnabled = false
            
            sessionQueue.async {
                // Remove the AVCaptureMovieFileOutput from the session because it doesn't support capture of Live Photos.
                self.session.beginConfiguration()
                self.session.removeOutput(self.movieFileOutput!)
                self.session.sessionPreset = .photo
                
                DispatchQueue.main.async {
                    captureModeControl.isEnabled = true
                }
                
                self.movieFileOutput = nil
                
                //cannot work with bracket mode
//                if self.photoOutput.isLivePhotoCaptureSupported {
//                    self.photoOutput.isLivePhotoCaptureEnabled = true
//
//                    DispatchQueue.main.async {
//                        self.livePhotoModeButton.isEnabled = true
//                    }
//                }
                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = true
                    
                    DispatchQueue.main.async {
                        self.depthDataDeliveryButton.isEnabled = true
                    }
                }
                
                if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                    
                    DispatchQueue.main.async {
                        self.portraitEffectsMatteDeliveryButton.isEnabled = true
                    }
                }
                
                if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
					self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.selectedSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    
                    DispatchQueue.main.async {
                        self.semanticSegmentationMatteDeliveryButton.isEnabled = (self.depthDataDeliveryMode == .on) ? true : false
                    }
                }
                
                DispatchQueue.main.async {
                    self.livePhotoModeButton.isHidden = true //false
                    self.depthDataDeliveryButton.isHidden = false
                    self.portraitEffectsMatteDeliveryButton.isHidden = false
                    self.semanticSegmentationMatteDeliveryButton.isHidden = false
                }
                self.session.commitConfiguration()
            }
        } else if captureModeControl.selectedSegmentIndex == CaptureMode.movie.rawValue {
            livePhotoModeButton.isHidden = true
            depthDataDeliveryButton.isHidden = true
            portraitEffectsMatteDeliveryButton.isHidden = true
            semanticSegmentationMatteDeliveryButton.isHidden = true
            
            sessionQueue.async {
                let movieFileOutput = AVCaptureMovieFileOutput()
                
                if self.session.canAddOutput(movieFileOutput) {
                    self.session.beginConfiguration()
                    self.session.addOutput(movieFileOutput)
                    self.session.sessionPreset = .high
                    if let connection = movieFileOutput.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .off //.auto
                        }
                    }
                    self.session.commitConfiguration()
                    
                    DispatchQueue.main.async {
                        captureModeControl.isEnabled = true
                    }
                    
                    self.movieFileOutput = movieFileOutput
                    
                    DispatchQueue.main.async {
                        self.recordButton.isEnabled = true
                    }
                }
            }
        }
    }
    
    // MARK: Device Configuration
    
    @IBOutlet private weak var cameraButton: UIButton!
    
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
                                                                               mediaType: .video, position: .unspecified)
    
    /// - Tag: ChangeCamera
    @IBAction private func changeCamera(_ cameraButton: UIButton) {
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        photoButton.isEnabled = false
        livePhotoModeButton.isEnabled = false
        captureModeControl.isEnabled = false
        depthDataDeliveryButton.isEnabled = false
        portraitEffectsMatteDeliveryButton.isEnabled = false
        semanticSegmentationMatteDeliveryButton.isEnabled = false
        
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            
            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType
            
            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
                
            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInTrueDepthCamera
                
            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
            }
            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil
            
            // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, because AVCaptureSession doesn't support
                    // simultaneous use of the rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .off // .auto
                        }
                    }
                    
                    /*
                     Set Live Photo capture and depth data delivery if it's supported. When changing cameras, the
                     `livePhotoCaptureEnabled` and `depthDataDeliveryEnabled` properties of the AVCapturePhotoOutput
                     get set to false when a video device is disconnected from the session. After the new video device is
                     added to the session, re-enable them on the AVCapturePhotoOutput, if supported.
                     */
                    self.photoOutput.isLivePhotoCaptureEnabled = false //self.photoOutput.isLivePhotoCaptureSupported
                    self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliverySupported
                    self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.selectedSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                    
                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.recordButton.isEnabled = self.movieFileOutput != nil
                self.photoButton.isEnabled = true
                self.livePhotoModeButton.isEnabled = false//true
                self.captureModeControl.isEnabled = true
                self.depthDataDeliveryButton.isEnabled = self.photoOutput.isDepthDataDeliveryEnabled
                self.portraitEffectsMatteDeliveryButton.isEnabled = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
                self.semanticSegmentationMatteDeliveryButton.isEnabled = (self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty || self.depthDataDeliveryMode == .off) ? false : true
            }
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: Capturing Photos
    
    private let photoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    
    @IBOutlet private weak var photoButton: UIButton!
    
    /// - Tag: CapturePhoto
    private func capturePhoto_(_ photoButton: UIButton, im: Int, photoTakenSemaphore: DispatchSemaphore, fin: DispatchSemaphore,  change_alpha : Int? = nil) {
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. Do this to ensure that UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            
            // Get AVCaptureBracketedStillImageSettings for a set of exposure values.
            let exposureValues: [Float] = [-2, -1, 0, 1]
            let makeAutoExposureSettings = AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias:)
            let exposureSettings = exposureValues.map(makeAutoExposureSettings)
            assert(self.photoOutput.availablePhotoCodecTypes.contains(.hevc))
            let photoSettings = AVCapturePhotoBracketSettings(rawPixelFormatType: 0,
                processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc],
                bracketedSettings: exposureSettings)
            photoSettings.isLensStabilizationEnabled = false
//                self.photoOutput.isLensStabilizationDuringBracketedCaptureSupported
            
//            if self.videoDeviceInput.device.isFlashAvailable {
            photoSettings.flashMode = AVCaptureDevice.FlashMode.off
//            }
            
            photoSettings.isHighResolutionPhotoEnabled = true
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            // Live Photo capture is not supported when bracket enabled
//            if self.livePhotoMode == .on && self.photoOutput.isLivePhotoCaptureSupported {
//                let livePhotoMovieFileName = NSUUID().uuidString
//                let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
//                photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
//            }
            
            photoSettings.isDepthDataDeliveryEnabled = (self.depthDataDeliveryMode == .on
                && self.photoOutput.isDepthDataDeliveryEnabled)
            
            photoSettings.isPortraitEffectsMatteDeliveryEnabled = (self.portraitEffectsMatteDeliveryMode == .on
                && self.photoOutput.isPortraitEffectsMatteDeliveryEnabled)
            
            if photoSettings.isDepthDataDeliveryEnabled {
                if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                    photoSettings.enabledSemanticSegmentationMatteTypes = self.selectedSemanticSegmentationMatteTypes
                }
            }
            
            photoSettings.photoQualityPrioritization = self.photoQualityPrioritizationMode
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                
            }, livePhotoCaptureHandler: { capturing in
                self.sessionQueue.async {
                    if capturing {
                        self.inProgressLivePhotoCapturesCount += 1
                    } else {
                        self.inProgressLivePhotoCapturesCount -= 1
                    }
                    
                    let inProgressLivePhotoCapturesCount = self.inProgressLivePhotoCapturesCount
                    DispatchQueue.main.async {
                        if inProgressLivePhotoCapturesCount > 0 {
                            self.capturingLivePhotoLabel.isHidden = false
                        } else if inProgressLivePhotoCapturesCount == 0 {
                            self.capturingLivePhotoLabel.isHidden = true
                        } else {
                            print("Error: In progress Live Photo capture count is less than 0.")
                        }
                    }
                }
            }, completionHandler: { photoCaptureProcessor in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                DispatchQueue.main.async {
                    let illuminationMode = im
                    if illuminationMode == change_alpha{
                        fin.signal()
                    }
                }
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
                photoTakenSemaphore.signal()
            }, photoProcessingHandler: { animate in
                // Animates a spinner while photo is processing
                DispatchQueue.main.async {
                    if animate {
                        self.spinner.hidesWhenStopped = true
                        self.spinner.center = CGPoint(x: self.previewView.frame.size.width / 2.0, y: self.previewView.frame.size.height / 2.0)
                        self.spinner.startAnimating()
                    } else {
                        self.spinner.stopAnimating()
                    }
                }
            }
            )
            
            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
    
    func setIllumination(im: Int, illuminationSemaphore: DispatchSemaphore){
        DispatchQueue.main.async {
            let illuminationMode = im
            let screenSize: CGRect = UIScreen.main.bounds
            let screenWidth = screenSize.width
            let screenHeight = screenSize.height
            var white_w = screenWidth
            var white_h = screenHeight
            var black_w = screenWidth
            var black_h = screenHeight
            var white_x : CGFloat = 0
            var white_y : CGFloat = 0
            var black_x : CGFloat = 0
            var black_y : CGFloat = 0
            print(illuminationMode)
            switch illuminationMode
            {
            case 0 :
                black_x = screenWidth/2
                white_w = screenWidth/2
                black_w = screenWidth/2
            case 1 :
                white_x = screenWidth/2
                white_w = screenWidth/2
                black_w = screenWidth/2
            case 2 :
                black_y = screenHeight/2
                white_h = screenHeight/2
                black_h = screenHeight/2
            case 3:
                white_y = screenHeight/2
                white_h = screenHeight/2
                black_h = screenHeight/2
            case 4:
                white_h = screenWidth/3
                white_w = screenWidth/3
                white_x = screenWidth - white_h
            case 5:
                white_h = screenWidth/3
                white_w = screenWidth/3
                white_x = 0
                white_y = screenHeight/3
            case 6:
                white_h = screenWidth/3
                white_w = screenWidth/3
                white_x = screenWidth/3
                white_y = screenHeight -  screenWidth/3
            case 7:
                self.view_multiplex.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                self.view_multiplex.frame = CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight)
                let colors = [UIColor(red: 1, green: 0, blue: 1, alpha: 1).cgColor, UIColor(red: 0, green: 0, blue: 1, alpha: 1).cgColor, UIColor(red: 1, green: 0, blue: 0, alpha: 1).cgColor, UIColor(red: 0, green: 0, blue: 0, alpha: 1).cgColor]
                let positions = [[0, 0], [0, screenWidth/2], [screenHeight/2, 0], [screenHeight/2, screenWidth/2]]
                for i in 0...3{
                    let ca = CALayer()
                    ca.frame = CGRect(x: positions[i][1], y: positions[i][0], width: screenWidth/2, height: screenHeight/2)
                    ca.backgroundColor = colors[i]
                    self.view_multiplex.layer.addSublayer(ca)
                }
            case 8:
                self.view_multiplex.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                self.view_multiplex.frame = CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight)
                let colors = [UIColor(red: 0, green: 0, blue: 0, alpha: 1).cgColor, UIColor(red: 1, green: 0, blue: 0, alpha: 1).cgColor, UIColor(red: 0, green: 0, blue: 1, alpha: 1).cgColor, UIColor(red: 1, green: 0, blue: 1, alpha: 1).cgColor]
                let positions = [[0, 0], [0, screenWidth/2], [screenHeight/2, 0], [screenHeight/2, screenWidth/2]]
                for i in 0...3{
                    let ca = CALayer()
                    ca.frame = CGRect(x: positions[i][1], y: positions[i][0], width: screenWidth/2, height: screenHeight/2)
                    ca.backgroundColor = colors[i]
                    self.view_multiplex.layer.addSublayer(ca)
                }
            default:
                break
            }
            if illuminationMode == 7 || illuminationMode == 8{
                self.view_black.alpha = 0
                self.view_white.alpha = 0
                self.view_multiplex.alpha = 1
            }else{
                self.view_multiplex.alpha = 0
                self.view_black.frame = CGRect(x: black_x, y: black_y, width: black_w, height: black_h)
                self.view_white.frame = CGRect(x: white_x, y: white_y, width: white_w, height: white_h)
                self.view_black.alpha = 1
                self.view_white.alpha = 1
            }
            illuminationSemaphore.signal()
        }
    }
    
    @IBOutlet weak var autoIlluminationMode: UISegmentedControl!
    @IBAction private func capturePhoto(_ photoButton: UIButton) {
        let photoTakenSemaphore = DispatchSemaphore(value: 0)
        let illuminationSemaphore = DispatchSemaphore(value: 0)
        let fin = DispatchSemaphore(value: 0)
        switch self.autoIlluminationMode.selectedSegmentIndex
        {
        case 0 :
            DispatchQueue.global().async {
                for i in [-1, 0, 1, 2, 3, 7, 8, 10]{ //Hack. The first photo cannot guarantee to be correctly illuminated
                    // Flash the screen to signal that AVCam took a photo.
                    self.setIllumination(im: i, illuminationSemaphore: illuminationSemaphore)
                    illuminationSemaphore.wait()
                    DispatchQueue.main.async {
                        self.capturePhoto_(photoButton, im: i, photoTakenSemaphore: photoTakenSemaphore, fin: fin, change_alpha: 10)
                    }
                    photoTakenSemaphore.wait()
                    photoTakenSemaphore.wait()
                    photoTakenSemaphore.wait()
                    photoTakenSemaphore.wait()
                }
            }
        case 1:
            DispatchQueue.global().async {
                //Hack. The first photo cannot guarantee to be correctly illuminated
                for i in [-1, 4, 5, 6]{
                    self.setIllumination(im: i, illuminationSemaphore: illuminationSemaphore)
                    DispatchQueue.main.async {
                        illuminationSemaphore.wait()
                        self.capturePhoto_(photoButton, im: i, photoTakenSemaphore: photoTakenSemaphore, fin: fin, change_alpha: 6)
                    }
                    photoTakenSemaphore.wait()
                    photoTakenSemaphore.wait()
                    photoTakenSemaphore.wait()
                    photoTakenSemaphore.wait()
                }
            }

        default:
            break
        }
        DispatchQueue.global().async() {
            fin.wait()
            DispatchQueue.main.async {
                print("here")
                self.view_black.alpha = 0
                self.view_white.alpha = 0
                self.view_multiplex.alpha = 0
                self.view_multiplex.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            }
        }
    }
    
    private enum LivePhotoMode {
        case on
        case off
    }
    
    private enum DepthDataDeliveryMode {
        case on
        case off
    }
    
    private enum PortraitEffectsMatteDeliveryMode {
        case on
        case off
    }
    
    private var livePhotoMode: LivePhotoMode = .off
    
    @IBOutlet private weak var livePhotoModeButton: UIButton!
    
    @IBAction private func toggleLivePhotoMode(_ livePhotoModeButton: UIButton) {
        sessionQueue.async {
            self.livePhotoMode = (self.livePhotoMode == .on) ? .off : .on
            let livePhotoMode = self.livePhotoMode
            
            DispatchQueue.main.async {
                if livePhotoMode == .on {
                    self.livePhotoModeButton.setImage(#imageLiteral(resourceName: "LivePhotoON"), for: [])
                } else {
                    self.livePhotoModeButton.setImage(#imageLiteral(resourceName: "LivePhotoOFF"), for: [])
                }
            }
        }
    }
    
    private var depthDataDeliveryMode: DepthDataDeliveryMode = .off
    
    @IBOutlet private weak var depthDataDeliveryButton: UIButton!
    
    @IBAction func toggleDepthDataDeliveryMode(_ depthDataDeliveryButton: UIButton) {
        sessionQueue.async {
            self.depthDataDeliveryMode = (self.depthDataDeliveryMode == .on) ? .off : .on
            let depthDataDeliveryMode = self.depthDataDeliveryMode
            if depthDataDeliveryMode == .on {
                self.portraitEffectsMatteDeliveryMode = .on
            } else {
                self.portraitEffectsMatteDeliveryMode = .off
            }
            
            DispatchQueue.main.async {
                if depthDataDeliveryMode == .on {
                    self.depthDataDeliveryButton.setImage(#imageLiteral(resourceName: "DepthON"), for: [])
                    self.portraitEffectsMatteDeliveryButton.setImage(#imageLiteral(resourceName: "PortraitMatteON"), for: [])
                    self.semanticSegmentationMatteDeliveryButton.isEnabled = true
                } else {
                    self.depthDataDeliveryButton.setImage(#imageLiteral(resourceName: "DepthOFF"), for: [])
                    self.portraitEffectsMatteDeliveryButton.setImage(#imageLiteral(resourceName: "PortraitMatteOFF"), for: [])
                    self.semanticSegmentationMatteDeliveryButton.isEnabled = false
                }
            }
        }
    }
    
    private var portraitEffectsMatteDeliveryMode: PortraitEffectsMatteDeliveryMode = .off
    
    @IBOutlet private weak var portraitEffectsMatteDeliveryButton: UIButton!
    
    @IBAction func togglePortraitEffectsMatteDeliveryMode(_ portraitEffectsMatteDeliveryButton: UIButton) {
        sessionQueue.async {
            if self.portraitEffectsMatteDeliveryMode == .on {
                self.portraitEffectsMatteDeliveryMode = .off
            } else {
                self.portraitEffectsMatteDeliveryMode = (self.depthDataDeliveryMode == .off) ? .off : .on
            }
            let portraitEffectsMatteDeliveryMode = self.portraitEffectsMatteDeliveryMode
            
            DispatchQueue.main.async {
                if portraitEffectsMatteDeliveryMode == .on {
                    self.portraitEffectsMatteDeliveryButton.setImage(#imageLiteral(resourceName: "PortraitMatteON"), for: [])
                } else {
                    self.portraitEffectsMatteDeliveryButton.setImage(#imageLiteral(resourceName: "PortraitMatteOFF"), for: [])
                }
            }
        }
    }
    
    private var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .quality
    
    @IBOutlet weak var semanticSegmentationMatteDeliveryButton: UIButton!
    
    @IBAction func toggleSemanticSegmentationMatteDeliveryMode(_ semanticSegmentationMatteDeliveryButton: UIButton) {
        let itemSelectionViewController = ItemSelectionViewController(delegate: self,
                                                                      identifier: semanticSegmentationTypeItemSelectionIdentifier,
                                                                      allItems: photoOutput.availableSemanticSegmentationMatteTypes,
                                                                      selectedItems: selectedSemanticSegmentationMatteTypes,
                                                                      allowsMultipleSelection: true)
        
        presentItemSelectionViewController(itemSelectionViewController)
        
    }
    
    // MARK: ItemSelectionViewControllerDelegate
    
    let semanticSegmentationTypeItemSelectionIdentifier = "SemanticSegmentationTypes"
    
    private func presentItemSelectionViewController(_ itemSelectionViewController: ItemSelectionViewController) {
        let navigationController = UINavigationController(rootViewController: itemSelectionViewController)
        navigationController.navigationBar.barTintColor = .black
        navigationController.navigationBar.tintColor = view.tintColor
        present(navigationController, animated: true, completion: nil)
    }
    
    func itemSelectionViewController(_ itemSelectionViewController: ItemSelectionViewController,
                                     didFinishSelectingItems selectedItems: [AVSemanticSegmentationMatte.MatteType]) {
        let identifier = itemSelectionViewController.identifier
        
        if identifier == semanticSegmentationTypeItemSelectionIdentifier {
            sessionQueue.async {
                self.selectedSemanticSegmentationMatteTypes = selectedItems
            }
        }
    }
    
    private var inProgressLivePhotoCapturesCount = 0
    
    @IBOutlet var capturingLivePhotoLabel: UILabel!
    
    // MARK: Recording Movies
    
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    @IBOutlet private weak var recordButton: UIButton!
    
    @IBOutlet private weak var resumeButton: UIButton!
    
    @IBAction private func toggleMovieRecording(_ recordButton: UIButton) {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        
        /*
         Disable the Camera button until recording finishes, and disable
         the Record button until recording starts or finishes.
         
         See the AVCaptureFileOutputRecordingDelegate methods.
         */
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        captureModeControl.isEnabled = false
        
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before recording.
                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!
                
                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                
                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }
                
                // Start recording video to a temporary file.
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                movieFileOutput.stopRecording()
            }
        }
    }
    
    /// - Tag: DidStartRecording
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Enable the Record button to let the user stop recording.
        DispatchQueue.main.async {
            self.recordButton.isEnabled = true
            self.recordButton.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
        }
    }
    
    /// - Tag: DidFinishRecording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Note: Because we use a unique file path for each recording, a new recording won't overwrite a recording mid-save.
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success {
            // Check the authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                    }, completionHandler: { success, error in
                        if !success {
                            print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanup()
                    }
                    )
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        DispatchQueue.main.async {
            // Only enable the ability to change camera if the device has more than one camera.
            self.cameraButton.isEnabled = self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
            self.recordButton.isEnabled = true
            self.captureModeControl.isEnabled = true
            self.recordButton.setImage(#imageLiteral(resourceName: "CaptureVideo"), for: [])
        }
    }
    
    // MARK: KVO and Notifications
    
    private var keyValueObservations = [NSKeyValueObservation]()
    /// - Tag: ObserveInterruption
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
//            let isLivePhotoCaptureEnabled = false //self.photoOutput.isLivePhotoCaptureEnabled
            let isDepthDeliveryDataEnabled = self.photoOutput.isDepthDataDeliveryEnabled
            let isPortraitEffectsMatteEnabled = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
            let isSemanticSegmentationMatteEnabled = !self.photoOutput.enabledSemanticSegmentationMatteTypes.isEmpty
            
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.recordButton.isEnabled = isSessionRunning && self.movieFileOutput != nil
                self.photoButton.isEnabled = isSessionRunning
                self.captureModeControl.isEnabled = isSessionRunning
                self.livePhotoModeButton.isEnabled = false //isSessionRunning && isLivePhotoCaptureEnabled
                self.depthDataDeliveryButton.isEnabled = isSessionRunning && isDepthDeliveryDataEnabled
                self.portraitEffectsMatteDeliveryButton.isEnabled = isSessionRunning && isPortraitEffectsMatteEnabled
                self.semanticSegmentationMatteDeliveryButton.isEnabled = isSessionRunning && isSemanticSegmentationMatteEnabled
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subjectAreaDidChange),
                                               name: .AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    /// - Tag: HandleRuntimeError
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    /// - Tag: HandleSystemPressure
    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        /*
         The frame rates used here are only for demonstration purposes.
         Your frame rate throttling may be different depending on your app's camera configuration.
         */
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            if self.movieFileOutput == nil || self.movieFileOutput?.isRecording == false {
                do {
                    try self.videoDeviceInput.device.lockForConfiguration()
                    print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                    self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                    self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                    self.videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }
    
    /// - Tag: HandleInterruption
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios you want to enable the user to resume the session.
         For example, if music playback is initiated from Control Center while
         using AVCam, then the user can let AVCam resume
         the session running, which will stop music playback. Note that stopping
         music playback in Control Center will not automatically resume the session.
         Also note that it's not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            var showResumeButton = false
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                showResumeButton = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Fade-in a label to inform the user that the camera is unavailable.
                cameraUnavailableLabel.alpha = 0
                cameraUnavailableLabel.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1
                }
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                print("Session stopped running due to shutdown system pressure level.")
            }
            if showResumeButton {
                // Fade-in a button to enable the user to try to resume the session running.
                resumeButton.alpha = 0
                resumeButton.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1
                }
            }
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            })
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        
        return uniqueDevicePositions.count
    }
}
