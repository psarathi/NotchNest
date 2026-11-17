import AppKit
import AVFoundation
import NotchNestCore
import SwiftUI

struct MirrorTabView: View {
    @Bindable var model: NotchNestModel
    @State private var showFramingGuides = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.035))

            switch model.cameraMirror.authState {
            case .authorized:
                ZStack {
                    CameraPreviewRepresentable(session: model.cameraMirror.session)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if showFramingGuides {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                            .padding(22)
                    }

                    VStack {
                        HStack {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(model.cameraMirror.isRunning ? Color.green : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text("Camera active only while Mirror is open")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.88))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())

                            Spacer()

                            Button {
                                showFramingGuides.toggle()
                            } label: {
                                Image(systemName: showFramingGuides ? "viewfinder" : "viewfinder.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(6)
                                    .background(.black.opacity(0.55), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Toggle framing guide")
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                .padding(6)

            case .notDetermined:
                VStack(spacing: 10) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.amberGlow)
                    Text("Check yourself quickly before a call")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Camera turns on only while viewing Mirror and stops the moment you leave or close.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Enable Camera") {
                        Task { await model.cameraMirror.requestAndStart() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.amberGlow, in: Capsule())
                    .buttonStyle(.plain)
                }

            case .denied:
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    Text("Camera permission is denied in System Settings → Privacy & Security → Camera.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.amberGlow)
                    .buttonStyle(.plain)
                }
                .padding()

            case .unavailable:
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("No camera device detected on this Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        nsView.applyMirroring()
    }
}

private final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirroring()
    }

    func applyMirroring() {
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
