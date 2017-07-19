import UIKit
import AVFoundation
import Vision
import AudioToolbox

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    let numImages = 12
    let numSounds = 12
    let session = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer!
    let captureQueue = DispatchQueue(label: "captureQueue")
    var gradientLayer: CAGradientLayer!
    var visionRequests = [VNRequest]()
    var recognitionThreshold : Float = 0.25
    var audioPlayer:AVAudioPlayer!
    var imageLayer = CALayer()
    var timer: Timer?

    @IBOutlet weak var previewView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // get hold of the default video camera
        guard let camera = AVCaptureDevice.default(for: .video) else {
          fatalError("No video camera available")
        }
        do {
            // add the preview layer
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewView.layer.addSublayer(previewLayer)
            // add a slight gradient overlay so we can read the results easily
            gradientLayer = CAGradientLayer()
            gradientLayer.colors = [
                UIColor.init(red: 0, green: 0, blue: 0, alpha: 0.7).cgColor,
                UIColor.init(red: 0, green: 0, blue: 0, alpha: 0.0).cgColor,
            ]
            gradientLayer.locations = [0.0, 0.3]
            self.previewView.layer.addSublayer(gradientLayer)

            // create the capture input and the video output
            let cameraInput = try AVCaptureDeviceInput(device: camera)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            session.sessionPreset = .high

            // wire up the session
            session.addInput(cameraInput)
            session.addOutput(videoOutput)

            // make sure we are in portrait mode
            let conn = videoOutput.connection(with: .video)
            conn?.videoOrientation = .portrait

            // Start the session
            session.startRunning()

            // set up the vision model
            guard let resNet50Model = try? VNCoreMLModel(for: OpenNSFW().model) else {
                fatalError("Could not load model")
            }
            // set up the request using our vision model
            let classificationRequest = VNCoreMLRequest(model: resNet50Model, completionHandler: handleClassifications)
            classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOptionCenterCrop
            visionRequests = [classificationRequest]
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = self.previewView.bounds;
        gradientLayer.frame = self.previewView.bounds;

        imageLayer.frame = previewView.bounds
        imageLayer.contentsGravity = kCAGravityResizeAspectFill;
        imageLayer.isHidden = true
        previewView.layer.addSublayer(imageLayer)

        playSound()
        showImage()
    }
  
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
    
        connection.videoOrientation = .portrait
        var requestOptions:[VNImageOption: Any] = [:]
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
        }
    
        // for orientation see kCGImagePropertyOrientation
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: 1, options: requestOptions)
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
    }
    
    func handleClassifications(request: VNRequest, error: Error?) {
        if let theError = error {
            print("Error: \(theError.localizedDescription)")
            return
        }
        guard let observations = request.results else {
            print("No results")
            return
        }
        DispatchQueue.main.async {
            if observations.count > 0 {
                let observation = observations[0] as! VNClassificationObservation
                if observation.identifier == "NSFW" && observation.confidence > 0.75 && !self.audioPlayer.isPlaying {
                    self.showImage()
                    self.playSound()
                }
            }
        }
    }

    func playSound0() {
        let index = arc4random_uniform(UInt32(numSounds))
        var soundEffect: SystemSoundID = 0
        let path  = Bundle.main.path(forResource:"sound\(index)", ofType: "mp3")!
        let pathURL = NSURL(fileURLWithPath: path)
        AudioServicesCreateSystemSoundID(pathURL as CFURL, &soundEffect)
        AudioServicesPlaySystemSound(soundEffect)
    }

    func playSound() {
        let index = arc4random_uniform(UInt32(numSounds))
        let path  = Bundle.main.path(forResource:"sound\(index)", ofType: "mp3")!
        let url = NSURL(fileURLWithPath: path)
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url as URL)
            audioPlayer.play()
            timer = Timer.scheduledTimer(timeInterval: 0.5,
                                 target: self,
                                 selector: #selector(updateAudioProgressView),
                                 userInfo: nil,
                                 repeats: true)
        } catch {
            print("no")
        }
    }

    func showImage() {
        let index = arc4random_uniform(UInt32(numImages))
        guard let image = UIImage(named: "image\(index).jpg")?.cgImage else {
            print("no image")
            return
        }
        imageLayer.contents = image
        imageLayer.isHidden = false
    }

    func hideImage() {
        imageLayer.isHidden = true
    }

    @objc func updateAudioProgressView() {
        DispatchQueue.main.async { // 2
            if !self.audioPlayer.isPlaying {
                self.hideImage()
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }
}
