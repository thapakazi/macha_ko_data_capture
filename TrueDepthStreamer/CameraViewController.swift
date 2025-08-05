/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Contains view controller code for previewing live-captured content.
*/

import UIKit
import AVFoundation
import CoreVideo
import MobileCoreServices
import Accelerate
import Photos

@available(iOS 11.1, *)
class CameraViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate {
    
    // MARK: - Properties
    
    @IBOutlet weak private var resumeButton: UIButton!
    
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    
    @IBOutlet weak private var jetView: PreviewMetalView!
    
    @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    
    @IBOutlet weak private var mixFactorSlider: UISlider!
    
    @IBOutlet weak private var touchDepth: UILabel!
    
    @IBOutlet weak var autoPanningSwitch: UISwitch!
    
    @IBOutlet weak var captureButton: UIButton!
    
    @IBOutlet weak var shareButton: UIButton!
    
    private var isManualCaptureMode = true
    private var shouldCapture = false
    private var photoView: PhotoView?
    private var latestCalibrationJSON: String?
    private var latestCalibrationFileURL: URL?
    private var latestRawDepthFileURL: URL?
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .success
    
    private let session = AVCaptureSession()
    
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], autoreleaseFrequency: .workItem)
    private var videoDeviceInput: AVCaptureDeviceInput!
    
    private let dataOutputQueue = DispatchQueue(label: "video data queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    
    private let videoDepthMixer = VideoMixer()
    
    private let videoDepthConverter = DepthToJETConverter()
    
    private var renderingEnabled = true
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera],
                                                                               mediaType: .video,
                                                                               position: .front)
    
    private var statusBarOrientation: UIInterfaceOrientation = .portrait
    
    private var touchDetected = false
    
    private var touchCoordinates = CGPoint(x: 0, y: 0)
    
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    @IBOutlet weak private var cloudToJETSegCtrl: UISegmentedControl!
    
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    
    private var lastScale = Float(1.0)
    
    private var lastScaleDiff = Float(0.0)
    
    private var lastZoom = Float(0.0)
    
    private var lastXY = CGPoint(x: 0, y: 0)
    
    private var JETEnabled = false
    
    private var viewFrameSize = CGSize()
    
    private var autoPanningIndex = Int(0) // start with auto-panning on
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewFrameSize = self.view.frame.size
        
        // Initialize PhotoView on main thread
        photoView = PhotoView()
        
        let tapGestureJET = UITapGestureRecognizer(target: self, action: #selector(focusAndExposeTap))
        jetView.addGestureRecognizer(tapGestureJET)
        
        let pressGestureJET = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressJET))
        pressGestureJET.minimumPressDuration = 0.05
        pressGestureJET.cancelsTouchesInView = false
        jetView.addGestureRecognizer(pressGestureJET)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        cloudView.addGestureRecognizer(pinchGesture)
        
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.numberOfTouchesRequired = 1
        cloudView.addGestureRecognizer(doubleTapGesture)
        
        let rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        cloudView.addGestureRecognizer(rotateGesture)
        
        let panOneFingerGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanOneFinger))
        panOneFingerGesture.maximumNumberOfTouches = 1
        panOneFingerGesture.minimumNumberOfTouches = 1
        cloudView.addGestureRecognizer(panOneFingerGesture)
        
        cloudToJETSegCtrl.selectedSegmentIndex = 0
        
        JETEnabled = (cloudToJETSegCtrl.selectedSegmentIndex == 0)
        
        sessionQueue.sync {
            if JETEnabled {
                self.depthDataOutput.isFilteringEnabled = self.depthSmoothingSwitch.isOn
            } else {
                self.depthDataOutput.isFilteringEnabled = false
            }
            
            self.cloudView.isHidden = JETEnabled
            self.jetView.isHidden = !JETEnabled
        }
        
        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant video access
             We suspend the session queue to delay session setup until the access request has completed
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        statusBarOrientation = interfaceOrientation
        
        let initialThermalState = ProcessInfo.processInfo.thermalState
        if initialThermalState == .serious || initialThermalState == .critical {
            showThermalState(state: initialThermalState)
        }
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded
                self.addObservers()
                let videoOrientation = self.videoDataOutput.connection(with: .video)!.videoOrientation
                let videoDevicePosition = self.videoDeviceInput.device.position
                let rotation = PreviewMetalView.Rotation(with: interfaceOrientation,
                                                         videoOrientation: videoOrientation,
                                                         cameraPosition: videoDevicePosition)
                self.jetView.mirroring = (videoDevicePosition == .front)
                if let rotation = rotation {
                    self.jetView.rotation = rotation
                }
                self.dataOutputQueue.async {
                    self.renderingEnabled = true
                }
                
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("TrueDepthStreamer doesn't have permission to use the camera, please change privacy settings",
                                                    comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "TrueDepthStreamer", message: message, preferredStyle: .alert)
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
                    self.cameraUnavailableLabel.isHidden = false
                    self.cameraUnavailableLabel.alpha = 0.0
                    UIView.animate(withDuration: 0.25) {
                        self.cameraUnavailableLabel.alpha = 1.0
                    }
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        dataOutputQueue.async {
            self.renderingEnabled = false
        }
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    @objc
    func didEnterBackground(notification: NSNotification) {
        // Free up resources
        dataOutputQueue.async {
            self.renderingEnabled = false
            //            if let videoFilter = self.videoFilter {
            //                videoFilter.reset()
            //            }
            self.videoDepthMixer.reset()
            self.videoDepthConverter.reset()
            self.jetView.pixelBuffer = nil
            self.jetView.flushTextureCache()
        }
    }
    
    @objc
    func willEnterForground(notification: NSNotification) {
        dataOutputQueue.async {
            self.renderingEnabled = true
        }
    }
    
    // You can use this opportunity to take corrective action to help cool the system down.
    @objc
    func thermalStateChanged(notification: NSNotification) {
        if let processInfo = notification.object as? ProcessInfo {
            showThermalState(state: processInfo.thermalState)
        }
    }
    
    func showThermalState(state: ProcessInfo.ThermalState) {
        DispatchQueue.main.async {
            var thermalStateString = "UNKNOWN"
            if state == .nominal {
                thermalStateString = "NOMINAL"
            } else if state == .fair {
                thermalStateString = "FAIR"
            } else if state == .serious {
                thermalStateString = "SERIOUS"
            } else if state == .critical {
                thermalStateString = "CRITICAL"
            }
            
            let message = NSLocalizedString("Thermal state: \(thermalStateString)", comment: "Alert message when thermal state has changed")
            let alertController = UIAlertController(title: "TrueDepthStreamer", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(
            alongsideTransition: { _ in
                let interfaceOrientation = UIApplication.shared.statusBarOrientation
                self.statusBarOrientation = interfaceOrientation
                self.sessionQueue.async {
                    /*
                     The photo orientation is based on the interface orientation. You could also set the orientation of the photo connection based
                     on the device orientation by observing UIDeviceOrientationDidChangeNotification.
                     */
                    let videoOrientation = self.videoDataOutput.connection(with: .video)!.videoOrientation
                    if let rotation = PreviewMetalView.Rotation(with: interfaceOrientation, videoOrientation: videoOrientation,
                                                                cameraPosition: self.videoDeviceInput.device.position) {
                        self.jetView.rotation = rotation
                    }
                }
        }, completion: nil
        )
    }
    
    // MARK: - KVO and Notifications
    
    private var sessionRunningContext = 0
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification,	object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError),
                                               name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
        
        session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.new, context: &sessionRunningContext)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted),
                                               name: NSNotification.Name.AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded),
                                               name: NSNotification.Name.AVCaptureSessionInterruptionEnded,
                                               object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange),
                                               name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        session.removeObserver(self, forKeyPath: "running", context: &sessionRunningContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context != &sessionRunningContext {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    // MARK: - Session Management
    
    // Call this on the session queue
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
        
        guard let videoDevice = defaultVideoDevice else {
            print("Could not find any video device")
            setupResult = .configurationFailed
            return
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            return
        }
        
        session.beginConfiguration()
        
//        lxk: change video type
//        session.sessionPreset = AVCaptureSession.Preset.hd1920x1080
        session.sessionPreset = AVCaptureSession.Preset.vga640x480
        
        
        // Add a video input
        guard session.canAddInput(videoDeviceInput) else {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addInput(videoDeviceInput)
        
        // Add a video data output
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        } else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add a depth data output
        if session.canAddOutput(depthDataOutput) {
            session.addOutput(depthDataOutput)
            depthDataOutput.isFilteringEnabled = false
            if let connection = depthDataOutput.connection(with: .depthData) {
                connection.isEnabled = true
            } else {
                print("No AVCaptureConnection")
            }
        } else {
            print("Could not add depth data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Search for highest resolution with half-point depth values
        let depthFormats = videoDevice.activeFormat.supportedDepthDataFormats
        let filtered = depthFormats.filter({
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16
        })
        let selectedFormat = filtered.max(by: {
            first, second in CMVideoFormatDescriptionGetDimensions(first.formatDescription).width < CMVideoFormatDescriptionGetDimensions(second.formatDescription).width
        })
        
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.activeDepthDataFormat = selectedFormat
            videoDevice.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
        // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer!.setDelegate(self, queue: dataOutputQueue)
        session.commitConfiguration()
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let videoDevice = self.videoDeviceInput.device
            
            do {
                try videoDevice.lockForConfiguration()
                if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
                    videoDevice.focusPointOfInterest = devicePoint
                    videoDevice.focusMode = focusMode
                }
                
                if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                    videoDevice.exposurePointOfInterest = devicePoint
                    videoDevice.exposureMode = exposureMode
                }
                
                videoDevice.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                videoDevice.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    @IBAction private func changeMixFactor(_ sender: UISlider) {
        let mixFactor = sender.value
        
        dataOutputQueue.async {
            self.videoDepthMixer.mixFactor = mixFactor
        }
    }
    
    @IBAction private func changeDepthSmoothing(_ sender: UISwitch) {
        let smoothingEnabled = sender.isOn
        
        sessionQueue.async {
            self.depthDataOutput.isFilteringEnabled = smoothingEnabled
        }
    }
    
    @IBAction func changeCloudToJET(_ sender: UISegmentedControl) {
        JETEnabled = (sender.selectedSegmentIndex == 0)
        
        sessionQueue.sync {
            if JETEnabled {
                self.depthDataOutput.isFilteringEnabled = self.depthSmoothingSwitch.isOn
            } else {
                self.depthDataOutput.isFilteringEnabled = false
            }
            
            self.cloudView.isHidden = JETEnabled
            self.jetView.isHidden = !JETEnabled
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: jetView)
        guard let texturePoint = jetView.texturePointForView(point: location) else {
            return
        }
        
        let textureRect = CGRect(origin: texturePoint, size: .zero)
        let deviceRect = videoDataOutput.metadataOutputRectConverted(fromOutputRect: textureRect)
        focus(with: .autoFocus, exposureMode: .autoExpose, at: deviceRect.origin, monitorSubjectAreaChange: true)
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            if reason == .videoDeviceInUseByAnotherClient {
                // Simply fade-in a button to enable the user to try to resume the session running.
                resumeButton.isHidden = false
                resumeButton.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1.0
                }
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                cameraUnavailableLabel.isHidden = false
                cameraUnavailableLabel.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1.0
                }
            }
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            }
            )
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
    
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
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
    
    @IBAction private func resumeInterruptedSession(_ sender: UIButton) {
        sessionQueue.async {
            /*
             The session might fail to start running. A failure to start the session running will be communicated via
             a session runtime error notification. To avoid repeatedly failing to start the session
             running, we only try to restart the session running in the session runtime error handler
             if we aren't trying to resume the session running.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "TrueDepthStreamer", message: message, preferredStyle: .alert)
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
    
    // MARK: - Point cloud view gestures
    
    @IBAction private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.numberOfTouches != 2 {
            return
        }
        if gesture.state == .began {
            lastScale = 1
        } else if gesture.state == .changed {
            let scale = Float(gesture.scale)
            let diff: Float = scale - lastScale
            let factor: Float = 1e3
            if scale < lastScale {
                lastZoom = diff * factor
            } else {
                lastZoom = diff * factor
            }
            DispatchQueue.main.async {
                self.autoPanningSwitch.isOn = false
                self.autoPanningIndex = -1
            }
            cloudView.moveTowardCenter(lastZoom)
            lastScale = scale
        } else if gesture.state == .ended {
        } else {
        }
    }
    
    @IBAction private func handlePanOneFinger(gesture: UIPanGestureRecognizer) {
        if gesture.numberOfTouches != 1 {
            return
        }
        
        if gesture.state == .began {
            let pnt: CGPoint = gesture.translation(in: cloudView)
            lastXY = pnt
        } else if (.failed != gesture.state) && (.cancelled != gesture.state) {
            let pnt: CGPoint = gesture.translation(in: cloudView)
            DispatchQueue.main.async {
                self.autoPanningSwitch.isOn = false
                self.autoPanningIndex = -1
            }
            cloudView.yawAroundCenter(Float((pnt.x - lastXY.x) * 0.1))
            cloudView.pitchAroundCenter(Float((pnt.y - lastXY.y) * 0.1))
            lastXY = pnt
        }
    }
    
    @IBAction private func handleDoubleTap(gesture: UITapGestureRecognizer) {
        DispatchQueue.main.async {
            self.autoPanningSwitch.isOn = false
            self.autoPanningIndex = -1
        }
        cloudView.resetView()
    }
    
    @IBAction private func handleRotate(gesture: UIRotationGestureRecognizer) {
        if gesture.numberOfTouches != 2 {
            return
        }
        
        if gesture.state == .changed {
            let rot = Float(gesture.rotation)
            DispatchQueue.main.async {
                self.autoPanningSwitch.isOn = false
                self.autoPanningIndex = -1
            }
            cloudView.rollAroundCenter(rot * 60)
            gesture.rotation = 0
        }
    }
    
    // MARK: - JET view Depth label gesture
    
    @IBAction private func handleLongPressJET(gesture: UILongPressGestureRecognizer) {
        
        switch gesture.state {
        case .began:
            touchDetected = true
            let pnt: CGPoint = gesture.location(in: self.jetView)
            touchCoordinates = pnt
        case .changed:
            let pnt: CGPoint = gesture.location(in: self.jetView)
            touchCoordinates = pnt
        case .possible, .ended, .cancelled, .failed:
            touchDetected = false
            DispatchQueue.main.async {
                self.touchDepth.text = ""
            }
        @unknown default:
            print("Unknow gesture state.")
            touchDetected = false
        }
    }
    
    @IBAction func didAutoPanningChange(_ sender: Any) {
        if autoPanningSwitch.isOn {
            self.autoPanningIndex = 0
        } else {
            self.autoPanningIndex = -1
        }
    }
    
    @IBAction func captureButtonPressed(_ sender: UIButton) {
        print("Capture button pressed")
        shouldCapture = true
        
        // Animate button press
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                sender.transform = CGAffineTransform.identity
            }
        }
    }
    
    @IBAction func shareButtonPressed(_ sender: UIButton) {
        // Animate button press
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                sender.transform = CGAffineTransform.identity
            }
        }
        
        // Share the latest calibration data and depth map
        guard let jsonString = latestCalibrationJSON else {
            showAlert(title: "No Data", message: "Please capture some data first before sharing.")
            return
        }
        
        // Create a single combined data file for easier sharing
        let timestamp = Int(Date().timeIntervalSince1970)
        let combinedFileName = "depth_capture_data_\(timestamp).json"
        let tempDirectory = FileManager.default.temporaryDirectory
        let combinedFileURL = tempDirectory.appendingPathComponent(combinedFileName)
        
        // Build combined data dictionary
        var combinedData: [String: Any] = [
            "calibration": jsonString,
            "timestamp": timestamp,
            "app_version": "TrueDepthStreamer 1.0"
        ]
        
        // Add depth file information if available
        if let rawDepthFileURL = latestRawDepthFileURL {
            combinedData["depth_file"] = rawDepthFileURL.lastPathComponent
            combinedData["depth_file_path"] = rawDepthFileURL.path
            
            // Check if it's a TIFF file
            if rawDepthFileURL.pathExtension == "tiff" {
                combinedData["depth_format"] = "16-bit TIFF"
            }
            
            // Also check for companion metadata
            let baseName = rawDepthFileURL.deletingPathExtension().lastPathComponent
            let metadataFileName = "\(baseName)_metadata.json"
            let metadataURL = rawDepthFileURL.deletingLastPathComponent().appendingPathComponent(metadataFileName)
            
            if let metadataData = try? Data(contentsOf: metadataURL),
               let metadata = try? JSONSerialization.jsonObject(with: metadataData, options: []) {
                combinedData["depth_metadata"] = metadata
            }
        }
        
        // Save combined data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: combinedData, options: .prettyPrinted)
            try jsonData.write(to: combinedFileURL)
            
            // Share items
            var activityItems: [Any] = [
                "TrueDepth Camera Calibration Data\n\nTimestamp: \(timestamp)\n\nFiles included:\n- Calibration JSON\n- 16-bit Depth TIFF",
                combinedFileURL
            ]
            
            // Always include the depth TIFF file if available
            if let rawDepthFileURL = latestRawDepthFileURL {
                activityItems.append(rawDepthFileURL)
                print("Sharing TIFF file: \(rawDepthFileURL.lastPathComponent)")
            }
            
            presentShareSheet(activityItems: activityItems, sourceView: sender)
            
        } catch {
            showAlert(title: "Error", message: "Failed to prepare data for sharing: \(error.localizedDescription)")
        }
    }
    
    private func presentShareSheet(activityItems: [Any], sourceView: UIView) {
        // Create activity view controller
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // For iPad
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = sourceView
            popoverController.sourceRect = sourceView.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func saveRawDepthMap(_ depthPixelBuffer: CVPixelBuffer) -> URL? {
        // Create timestamp for filename
        let timestamp = Int(Date().timeIntervalSince1970)
        let tiffFileName = "raw_depth_map_\(timestamp).tiff"
        
        // Use temporary directory for better compatibility with sharing
        let tempDirectory = FileManager.default.temporaryDirectory
        let tiffFileURL = tempDirectory.appendingPathComponent(tiffFileName)
        
        // Lock the pixel buffer for reading
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly) }
        
        // Get buffer properties
        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)
        
        // Verify this is a 16-bit float format
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthPixelBuffer)
        guard pixelFormat == kCVPixelFormatType_DepthFloat16 else {
            print("Error: Unexpected pixel format. Expected DepthFloat16, got: \(pixelFormat)")
            return nil
        }
        
        // Get the raw data pointer
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer) else {
            print("Error: Could not get base address of pixel buffer")
            return nil
        }
        
        // Save both TIFF and binary formats
        
        // 1. First save as 16-bit grayscale TIFF (converted from float16)
        let tiffSaved = create16BitTIFF(from: depthPixelBuffer, fileURL: tiffFileURL)
        
        // 2. Also save raw binary data with metadata for exact precision
        let dataLength = height * bytesPerRow
        let data = Data(bytes: baseAddress, count: dataLength)
        
        let binaryFileName = "raw_depth_map_\(timestamp).depth"
        let binaryFileURL = tempDirectory.appendingPathComponent(binaryFileName)
        
        // Create metadata dictionary
        let metadata: [String: Any] = [
            "width": width,
            "height": height,
            "bytesPerRow": bytesPerRow,
            "pixelFormat": "DepthFloat16",
            "timestamp": timestamp,
            "tiffFile": tiffFileName
        ]
        
        // Save metadata as companion JSON file
        let metadataFileName = "raw_depth_map_\(timestamp)_metadata.json"
        let metadataFileURL = tempDirectory.appendingPathComponent(metadataFileName)
        
        do {
            // Save raw depth data
            try data.write(to: binaryFileURL)
            
            // Save metadata
            let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
            try metadataData.write(to: metadataFileURL)
            
            print("Raw depth map saved successfully:")
            print("  - TIFF file: \(tiffFileURL.path)")
            print("  - Binary data: \(binaryFileURL.path)")
            print("  - Metadata: \(metadataFileURL.path)")
            print("  - Dimensions: \(width)x\(height)")
            print("  - Bytes per row: \(bytesPerRow)")
            
            // Return the TIFF file URL as primary (more compatible)
            return tiffSaved ? tiffFileURL : binaryFileURL
        } catch {
            print("Error saving raw depth map: \(error)")
            
            // Fallback: Return TIFF if it was created
            return tiffSaved ? tiffFileURL : nil
        }
    }
    
    private func create16BitTIFF(from depthPixelBuffer: CVPixelBuffer, fileURL: URL) -> Bool {
        // Get buffer properties
        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer) else {
            return false
        }
        
        // Convert 16-bit float to 16-bit unsigned integer (scaled to use full range)
        let outputBytesPerRow = width * 2 // 2 bytes per pixel for 16-bit
        let outputData = NSMutableData(length: height * outputBytesPerRow)!
        let outputPtr = outputData.mutableBytes.assumingMemoryBound(to: UInt16.self)
        
        // Find min/max for scaling
        var minDepth: Float = Float.greatestFiniteMagnitude
        var maxDepth: Float = -Float.greatestFiniteMagnitude
        var validDepthCount = 0
        
        for y in 0..<height {
            let rowData = baseAddress.advanced(by: y * bytesPerRow)
            let float16Ptr = rowData.assumingMemoryBound(to: UInt16.self)
            
            for x in 0..<width {
                var f16Value = float16Ptr[x]
                var f32Value: Float = 0
                var src = vImage_Buffer(data: &f16Value, height: 1, width: 1, rowBytes: 2)
                var dst = vImage_Buffer(data: &f32Value, height: 1, width: 1, rowBytes: 4)
                vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
                
                // Check for valid depth values
                if !f32Value.isNaN && !f32Value.isInfinite && f32Value > 0 && f32Value < 10.0 {
                    minDepth = min(minDepth, f32Value)
                    maxDepth = max(maxDepth, f32Value)
                    validDepthCount += 1
                }
            }
        }
        
        // If no valid depths found, use default range
        if validDepthCount == 0 || minDepth >= maxDepth {
            print("Warning: No valid depth values found. Using default range 0.1-2.0 meters")
            minDepth = 0.1
            maxDepth = 2.0
        }
        
        print("Depth statistics: Min=\(minDepth)m, Max=\(maxDepth)m, Valid pixels=\(validDepthCount)")
        
        // Convert to 16-bit unsigned
        let range = maxDepth - minDepth
        
        // Handle edge case where all depths are the same
        if range <= 0 {
            print("Warning: Depth range is zero or negative. Using default values.")
            // Fill with middle gray value
            for i in 0..<(width * height) {
                outputPtr[i] = 32768
            }
        } else {
            for y in 0..<height {
                let rowData = baseAddress.advanced(by: y * bytesPerRow)
                let float16Ptr = rowData.assumingMemoryBound(to: UInt16.self)
                
                for x in 0..<width {
                    var f16Value = float16Ptr[x]
                    var f32Value: Float = 0
                    var src = vImage_Buffer(data: &f16Value, height: 1, width: 1, rowBytes: 2)
                    var dst = vImage_Buffer(data: &f32Value, height: 1, width: 1, rowBytes: 4)
                    vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
                    
                    // Handle invalid values
                    if f32Value.isNaN || f32Value.isInfinite || f32Value <= 0 {
                        // Use 0 for invalid depths (will appear black)
                        outputPtr[y * width + x] = 0
                    } else {
                        // Clamp value to valid range
                        let clampedValue = max(minDepth, min(maxDepth, f32Value))
                        let normalized = (clampedValue - minDepth) / range
                        
                        // Ensure normalized is in 0-1 range
                        let safeNormalized = max(0, min(1, normalized))
                        outputPtr[y * width + x] = UInt16(safeNormalized * 65535)
                    }
                }
            }
        }
        
        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let dataProvider = CGDataProvider(data: outputData) else {
            return false
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 16,
            bytesPerRow: outputBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return false
        }
        
        // Save as TIFF
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, kUTTypeTIFF, 1, nil) else {
            return false
        }
        
        // Add metadata
        let tiffProperties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFCompression: 1, // No compression
                kCGImagePropertyTIFFSoftware: "TrueDepthStreamer",
                kCGImagePropertyTIFFImageDescription: "16-bit depth map (scaled from float16). Min depth: \(minDepth)m, Max depth: \(maxDepth)m"
            ]
        ]
        
        CGImageDestinationAddImage(destination, cgImage, tiffProperties as CFDictionary)
        
        return CGImageDestinationFinalize(destination)
    }
    
    private func createGrayscaleTIFF(from depthPixelBuffer: CVPixelBuffer, fileURL: URL) -> URL? {
        // Get buffer properties
        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)
        
        // Create a simple grayscale image from depth data
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer) else {
            return nil
        }
        
        // Convert 16-bit float to 8-bit grayscale for compatibility
        var minDepth: Float = Float.greatestFiniteMagnitude
        var maxDepth: Float = -Float.greatestFiniteMagnitude
        
        // Find min/max depth values
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)
        for y in 0..<height {
            let rowData = baseAddress.advanced(by: y * bytesPerRow)
            let float16Ptr = rowData.assumingMemoryBound(to: UInt16.self)
            
            for x in 0..<width {
                var f16Value = float16Ptr[x]
                var f32Value: Float = 0
                var src = vImage_Buffer(data: &f16Value, height: 1, width: 1, rowBytes: 2)
                var dst = vImage_Buffer(data: &f32Value, height: 1, width: 1, rowBytes: 4)
                vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
                
                if f32Value > 0 && f32Value < Float.greatestFiniteMagnitude {
                    minDepth = min(minDepth, f32Value)
                    maxDepth = max(maxDepth, f32Value)
                }
            }
        }
        
        // Create 8-bit grayscale data
        let grayscaleData = NSMutableData(length: width * height)!
        let grayscalePtr = grayscaleData.mutableBytes.assumingMemoryBound(to: UInt8.self)
        
        // Convert depth to grayscale
        for y in 0..<height {
            let rowData = baseAddress.advanced(by: y * bytesPerRow)
            let float16Ptr = rowData.assumingMemoryBound(to: UInt16.self)
            
            for x in 0..<width {
                var f16Value = float16Ptr[x]
                var f32Value: Float = 0
                var src = vImage_Buffer(data: &f16Value, height: 1, width: 1, rowBytes: 2)
                var dst = vImage_Buffer(data: &f32Value, height: 1, width: 1, rowBytes: 4)
                vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
                
                // Normalize to 0-255
                let normalized = (f32Value - minDepth) / (maxDepth - minDepth)
                grayscalePtr[y * width + x] = UInt8(normalized * 255)
            }
        }
        
        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let dataProvider = CGDataProvider(data: grayscaleData) else {
            return nil
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        // Save as TIFF
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, kUTTypeTIFF, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        
        if CGImageDestinationFinalize(destination) {
            print("Grayscale depth map saved as TIFF: \(fileURL.path)")
            return fileURL
        }
        
        return nil
    }
    
    private func saveCalibrationData(calibrationData: AVCameraCalibrationData,
                                   intrinsicMatrix: simd_float3x3,
                                   fx: CGFloat, fy: CGFloat, cx: CGFloat, cy: CGFloat,
                                   refWidth: CGFloat, refHeight: CGFloat,
                                   videoWidth: Int, videoHeight: Int) {
        var calibrationDict: [String: Any] = [
            "intrinsicMatrix": [
                "fx": fx,
                "fy": fy,
                "cx": cx,
                "cy": cy,
                "fx_original": Float(intrinsicMatrix.columns.0.x),
                "fy_original": Float(intrinsicMatrix.columns.1.y),
                "cx_original": Float(intrinsicMatrix.columns.2.x),
                "cy_original": Float(intrinsicMatrix.columns.2.y)
            ],
            "referenceDimensions": [
                "width": refWidth,
                "height": refHeight
            ],
            "videoDimensions": [
                "width": videoWidth,
                "height": videoHeight
            ],
            "pixelSize": [
                "width_scale": CGFloat(videoWidth) / refWidth,
                "height_scale": CGFloat(videoHeight) / refHeight
            ],
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Add extrinsic matrix (simd_float4x3 - 4 columns, 3 rows)
        // Format: [R|t] where R is 3x3 rotation matrix and t is 3x1 translation vector
        let extrinsic = calibrationData.extrinsicMatrix
        
        // Access the matrix columns (4 simd_float3 columns)
        let col0 = extrinsic.columns.0  // simd_float3
        let col1 = extrinsic.columns.1  // simd_float3
        let col2 = extrinsic.columns.2  // simd_float3
        let col3 = extrinsic.columns.3  // simd_float3 (translation vector)
        
        calibrationDict["extrinsicMatrix"] = [
            "rotation_translation_matrix": [
                "column0": [Float(col0.x), Float(col0.y), Float(col0.z)],  // R column 1
                "column1": [Float(col1.x), Float(col1.y), Float(col1.z)],  // R column 2
                "column2": [Float(col2.x), Float(col2.y), Float(col2.z)],  // R column 3
                "column3": [Float(col3.x), Float(col3.y), Float(col3.z)]   // t translation (mm)
            ],
            "description": "4x3 matrix [R|t] where R is 3x3 rotation matrix and t is 3x1 translation vector in millimeters"
        ]
        
        // Add lens distortion coefficients
        calibrationDict["lensDistortionCenter"] = [
            "x": Double(calibrationData.lensDistortionCenter.x),
            "y": Double(calibrationData.lensDistortionCenter.y)
        ]
        
        // Add pixel size (convert to Double to ensure JSON serialization works)
        calibrationDict["pixelSize"] = Double(calibrationData.pixelSize)
        
        // Save calibration data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: calibrationDict, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8)
            print("Camera Calibration Data:")
            print(jsonString ?? "Failed to convert to string")
            
            // Store latest data for sharing
            self.latestCalibrationJSON = jsonString
            
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "calibration_\(timestamp).json"
            
            // Save to documents directory (app private)
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = documentsPath.appendingPathComponent(fileName)
                try jsonData.write(to: fileURL)
                print("Calibration data saved to Documents: \(fileURL.path)")
                self.latestCalibrationFileURL = fileURL
            }
            
            // Also save to Files app accessible directory
            let fileManager = FileManager.default
            if let sharedContainerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.truedepth.calibration") {
                // If you have an app group configured
                let sharedFileURL = sharedContainerURL.appendingPathComponent(fileName)
                try jsonData.write(to: sharedFileURL)
                print("Calibration data saved to shared container: \(sharedFileURL.path)")
            } else {
                // Fallback: Create a temporary file for sharing
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
                try jsonData.write(to: tempURL)
                print("Calibration data saved to temp directory for sharing: \(tempURL.path)")
                self.latestCalibrationFileURL = tempURL
            }
            
        } catch {
            print("Error serializing calibration data: \(error)")
        }
    }
    
    // MARK: - Video + Depth Frame Processing
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        if !renderingEnabled {
            return
        }
        
        // Read all outputs
        guard renderingEnabled,
            let syncedDepthData: AVCaptureSynchronizedDepthData =
            synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
            let syncedVideoData: AVCaptureSynchronizedSampleBufferData =
            synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else {
                // only work on synced pairs
                return
        }
        
        if syncedDepthData.depthDataWasDropped || syncedVideoData.sampleBufferWasDropped {
            return
        }
        
        let depthData = syncedDepthData.depthData
        let depthPixelBuffer = depthData.depthDataMap
        let sampleBuffer = syncedVideoData.sampleBuffer
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                return
        }
        
        
 
//       lxk: ----------------------  start read calibration info ------------------------------------///
        let calibration = depthData.cameraCalibrationData;
        let intrinsic = calibration!.intrinsicMatrix;
        
        let refWidth = calibration!.intrinsicMatrixReferenceDimensions.width;
        let refHeight = calibration!.intrinsicMatrixReferenceDimensions.height;
        
        let videoWidth = CVPixelBufferGetWidth(videoPixelBuffer);
        let videoHeight = CVPixelBufferGetHeight(videoPixelBuffer);
        let wScale = CGFloat(videoWidth) / refWidth;
        let hScale = CGFloat(videoHeight)  / refHeight;
        
        let fx_ori = intrinsic.columns.0.x;
        let fy_ori = intrinsic.columns.1.y;
        let cx_ori = intrinsic.columns.2.x;
        let cy_ori = intrinsic.columns.2.y;
        
        let fx = CGFloat(fx_ori) * wScale;
        let fy =  CGFloat(fy_ori) * hScale ;
        let cx =   CGFloat(cx_ori) * wScale;
        let cy =  CGFloat(cy_ori) * hScale;

//       lxk: ----------------------  end read calibration info ------------------------------------///
        
        
        // Only capture if manual capture mode is disabled or capture button was pressed
        if !isManualCaptureMode || shouldCapture {
            // First, ensure we have calibration data
            guard let calibration = calibration else {
                print("No calibration data available")
                shouldCapture = false
                return
            }
            
            if let UIImageVideoPixelBuffer = UIImage(pixelBuffer: videoPixelBuffer){
                // Convert depth buffer to image using the pre-initialized PhotoView
                if let UIImagedepthPixelBuffer = self.photoView?.depthBuffer(toImage: depthPixelBuffer){
                    print("Successfully converted depth buffer to JET image")
                    
                    // Save raw depth map as TIFF (preserves 16-bit float data)
                    let rawDepthURL = self.saveRawDepthMap(depthPixelBuffer)
                    if let rawDepthURL = rawDepthURL {
                        self.latestRawDepthFileURL = rawDepthURL
                        print("Raw depth map saved successfully")
                    }
                    
                    // Save calibration data
                    self.saveCalibrationData(calibrationData: calibration,
                                      intrinsicMatrix: intrinsic, 
                                      fx: fx, fy: fy, cx: cx, cy: cy,
                                      refWidth: refWidth, refHeight: refHeight,
                                      videoWidth: videoWidth, videoHeight: videoHeight)
                    
                    // Save images on main thread
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Save JET-colored depth image to photo album
                        UIImageWriteToSavedPhotosAlbum(UIImagedepthPixelBuffer, nil, nil, nil)
                        usleep(5000)  //5ms
                        
                        // Save color RGB image to photo album
                        UIImageWriteToSavedPhotosAlbum(UIImageVideoPixelBuffer, nil, nil, nil)
                        usleep(5000)  //5ms
                        
                        // Reset capture flag
                        self.shouldCapture = false
                        
                        // Provide haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        
                        print("Capture completed: RGB image, JET depth image, raw depth TIFF, and calibration data saved")
                    }
                }
            }
        }
        
        if JETEnabled {
            if !videoDepthConverter.isPrepared {
                /*
                 outputRetainedBufferCountHint is the number of pixel buffers we expect to hold on to from the renderer.
                 This value informs the renderer how to size its buffer pool and how many pixel buffers to preallocate. Allow 2 frames of latency
                 to cover the dispatch_async call.
                 */
                var depthFormatDescription: CMFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                             imageBuffer: depthPixelBuffer,
                                                             formatDescriptionOut: &depthFormatDescription)
                videoDepthConverter.prepare(with: depthFormatDescription!, outputRetainedBufferCountHint: 2)
            }
            
            guard let jetPixelBuffer = videoDepthConverter.render(pixelBuffer: depthPixelBuffer) else {
                print("Unable to process depth")
                return
            }
            
            if !videoDepthMixer.isPrepared {
                videoDepthMixer.prepare(with: formatDescription, outputRetainedBufferCountHint: 3)
            }
            
            // Mix the video buffer with the last depth data we received
            guard let mixedBuffer = videoDepthMixer.mix(videoPixelBuffer: videoPixelBuffer, depthPixelBuffer: jetPixelBuffer) else {
                print("Unable to combine video and depth")
                return
            }
            
            jetView.pixelBuffer = mixedBuffer
            
            updateDepthLabel(depthFrame: depthPixelBuffer, videoFrame: videoPixelBuffer)
        } else {
            // point cloud
            if self.autoPanningIndex >= 0 {
                
                // perform a circle movement
                let moves = 200
                
                let factor = 2.0 * .pi / Double(moves)
                
                let pitch = sin(Double(self.autoPanningIndex) * factor) * 2
                let yaw = cos(Double(self.autoPanningIndex) * factor) * 2
                self.autoPanningIndex = (self.autoPanningIndex + 1) % moves
                
                cloudView?.resetView()
                cloudView?.pitchAroundCenter(Float(pitch) * 10)
                cloudView?.yawAroundCenter(Float(yaw) * 10)
            }
            
            cloudView?.setDepthFrame(depthData, withTexture: videoPixelBuffer)
        }
    }
    
    func updateDepthLabel(depthFrame: CVPixelBuffer, videoFrame: CVPixelBuffer) {
        
        if touchDetected {
            guard let texturePoint = jetView.texturePointForView(point: self.touchCoordinates) else {
                DispatchQueue.main.async {
                    self.touchDepth.text = ""
                }
                return
            }
            
            // scale
            let scale = CGFloat(CVPixelBufferGetWidth(depthFrame)) / CGFloat(CVPixelBufferGetWidth(videoFrame))
            let depthPoint = CGPoint(x: CGFloat(CVPixelBufferGetWidth(depthFrame)) - 1.0 - texturePoint.x * scale, y: texturePoint.y * scale)
            
            assert(kCVPixelFormatType_DepthFloat16 == CVPixelBufferGetPixelFormatType(depthFrame))
            CVPixelBufferLockBaseAddress(depthFrame, .readOnly)
            let rowData = CVPixelBufferGetBaseAddress(depthFrame)! + Int(depthPoint.y) * CVPixelBufferGetBytesPerRow(depthFrame)
            // swift does not have an Float16 data type. Use UInt16 instead, and then translate
            var f16Pixel = rowData.assumingMemoryBound(to: UInt16.self)[Int(depthPoint.x)]
            CVPixelBufferUnlockBaseAddress(depthFrame, .readOnly)
            
            var f32Pixel = Float(0.0)
            var src = vImage_Buffer(data: &f16Pixel, height: 1, width: 1, rowBytes: 2)
            var dst = vImage_Buffer(data: &f32Pixel, height: 1, width: 1, rowBytes: 4)
            vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
            
            // Convert the depth frame format to cm
            let depthString = String(format: "%.2f cm", f32Pixel * 100)
            
            // Update the label
            DispatchQueue.main.async {
                self.touchDepth.textColor = UIColor.white
                self.touchDepth.text = depthString
                self.touchDepth.sizeToFit()
            }
        } else {
            DispatchQueue.main.async {
                self.touchDepth.text = ""
            }
        }
    }
    
}

extension AVCaptureVideoOrientation {
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

extension PreviewMetalView.Rotation {
    
    init?(with interfaceOrientation: UIInterfaceOrientation, videoOrientation: AVCaptureVideoOrientation, cameraPosition: AVCaptureDevice.Position) {
        /*
         Calculate the rotation between the videoOrientation and the interfaceOrientation.
         The direction of the rotation depends upon the camera position.
         */
        switch videoOrientation {
            
        case .portrait:
            switch interfaceOrientation {
            case .landscapeRight:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .landscapeLeft:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .portrait:
                self = .rotate0Degrees
                
            case .portraitUpsideDown:
                self = .rotate180Degrees
                
            default: return nil
            }
            
        case .portraitUpsideDown:
            switch interfaceOrientation {
            case .landscapeRight:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .landscapeLeft:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .portrait:
                self = .rotate180Degrees
                
            case .portraitUpsideDown:
                self = .rotate0Degrees
                
            default: return nil
            }
            
        case .landscapeRight:
            switch interfaceOrientation {
            case .landscapeRight:
                self = .rotate0Degrees
                
            case .landscapeLeft:
                self = .rotate180Degrees
                
            case .portrait:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .portraitUpsideDown:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            default: return nil
            }
            
        case .landscapeLeft:
            switch interfaceOrientation {
            case .landscapeLeft:
                self = .rotate0Degrees
                
            case .landscapeRight:
                self = .rotate180Degrees
                
            case .portrait:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .portraitUpsideDown:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            default: return nil
            }
        @unknown default:
            fatalError("Unknown orientation. Can't continue.")
        }
    }
}

