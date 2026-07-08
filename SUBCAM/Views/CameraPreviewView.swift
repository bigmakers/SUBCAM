import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var videoRotationAngle: CGFloat = 90
    var onTapFocus: ((_ devicePoint: CGPoint, _ layerPoint: CGPoint) -> Void)? = nil
    var onPinchZoom: ((_ state: UIGestureRecognizer.State, _ scale: CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        context.coordinator.onTapFocus = onTapFocus
        context.coordinator.onPinchZoom = onPinchZoom

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.onTapFocus = onTapFocus
        context.coordinator.onPinchZoom = onPinchZoom

        // Sync preview orientation from CameraService's single source of truth
        if let connection = uiView.previewLayer.connection,
           connection.isVideoRotationAngleSupported(videoRotationAngle) {
            connection.videoRotationAngle = videoRotationAngle
        }
    }

    class Coordinator: NSObject {
        var onTapFocus: ((_ devicePoint: CGPoint, _ layerPoint: CGPoint) -> Void)?
        var onPinchZoom: ((_ state: UIGestureRecognizer.State, _ scale: CGFloat) -> Void)?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewUIView else { return }
            let layerPoint = gesture.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            onTapFocus?(devicePoint, layerPoint)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            onPinchZoom?(gesture.state, gesture.scale)
        }
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}
