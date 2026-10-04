import AppKit
import SwiftUI

/// "Send over Wi-Fi": the QR code and address of the page the Android device downloads the batch
/// from, the time left, each file's downloads and which device made them, and what to try when
/// the phone can't connect. Closing the sheet stops the server and the link with it.
struct AndroidWiFiSendSheet: View {
    @StateObject var session: AndroidWiFiSession
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send over Wi-Fi")
                .font(.title3.weight(.semibold))
            if session.state == .noNetwork {
                noNetwork
            } else {
                address
                fileList
                help
            }
            footer
        }
        .padding(20)
        .frame(width: 620, height: 640)
        .task { await session.start() }
        .onDisappear { session.stop() }
    }

    // MARK: Address

    private var address: some View {
        HStack(alignment: .top, spacing: 18) {
            qrCode
            VStack(alignment: .leading, spacing: 10) {
                Text("Scan the code with your Android device's camera, or open the address in its browser. Both devices must be on the same network.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = session.url {
                    HStack(spacing: 6) {
                        Text(verbatim: url.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .borderlessOnGlassButtonStyle()
                        .help("Copy Address")
                    }
                }
                if session.addresses.count > 1 { networkPicker }
                status
            }
        }
    }

    @ViewBuilder
    private var qrCode: some View {
        let side: CGFloat = 196
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white)
            if let url = session.url, let image = AndroidWiFiQRCode.image(for: url.absoluteString) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .padding(8)
                    .accessibilityLabel(Text("QR code of the address"))
            } else if session.isActive {
                ProgressView()
            } else {
                Image(systemName: "qrcode").font(.system(size: 64)).foregroundStyle(.gray.opacity(0.4))
            }
        }
        .frame(width: side, height: side)
    }

    private var networkPicker: some View {
        Picker("Network", selection: Binding(get: { session.address }, set: { address in
            guard let address else { return }
            Task { await session.choose(address) }
        })) {
            ForEach(session.addresses) { address in
                Text(verbatim: "\(address.displayName ?? address.interface) – \(address.host)").tag(Optional(address))
            }
        }
        .frame(maxWidth: 320)
    }

    @ViewBuilder
    private var status: some View {
        switch session.state {
        case .starting:
            ProgressView().controlSize(.small)
        case .serving:
            let now = Date()
            Label {
                Text("Expires in \(Text(timerInterval: now...max(now, session.expiry), countsDown: true))")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }
            .foregroundStyle(.secondary)
        case .stopped(.expired):
            Label("The link expired. Send again to make a new one.", systemImage: "clock.badge.xmark")
                .foregroundStyle(.secondary)
        case .stopped:
            Label("Sending stopped.", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .noNetwork:
            EmptyView()
        }
    }

    // MARK: Files

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(session.files) { file in
                    fileRow(file, progress: session.progress[file.index] ?? .init())
                }
            }
            .padding(12)
        }
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous)) {
            $0.background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func fileRow(_ file: AndroidWiFiFile, progress: AndroidWiFiSession.Progress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(file.title).lineLimit(1)
                Spacer()
                Text(verbatim: "\(AndroidWiFiPage.label(file.kind)) · \(file.size.formatted(.byteCount(style: .file)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !progress.completedBy.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityLabel(Text("Downloaded"))
                }
            }
            if progress.isDownloading || (progress.position > 0 && progress.completedBy.isEmpty) {
                ProgressView(value: Double(progress.position), total: Double(max(file.size, 1)))
                Text("\(progress.position.formatted(.byteCount(style: .file))) of \(file.size.formatted(.byteCount(style: .file)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !progress.completedBy.isEmpty {
                Text("Downloaded by \(progress.completedBy.formatted(.list(type: .and)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Help

    private var help: some View {
        DisclosureGroup("Can't connect?") {
            VStack(alignment: .leading, spacing: 6) {
                Label("The first time a device connects, macOS may ask whether Open Wallpaper Engine may accept incoming network connections. Click Allow.", systemImage: "lock.shield")
                Label("Some networks (guest and public Wi-Fi, some mesh systems) keep devices from reaching each other. Use your home network, or turn off client isolation (\"AP isolation\") in the router's settings.", systemImage: "wifi.exclamationmark")
                Label("If downloads stop, keep this window open and tap Download again: it resumes.", systemImage: "arrow.clockwise")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        }
    }

    // MARK: No network

    private var noNetwork: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi.slash").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("This Mac isn't connected to a Wi-Fi or local network.")
                .font(.headline)
            Text("Connect it to the same network as your Android device and try again, or save the files to a folder and copy them to the device another way.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Try Again") { Task { await session.start() } }
                        .glassButtonStyle()
                    Button("Save to Folder…") { session.saveToFolder() }
                        .glassButtonStyle(.prominent)
                }
            }
            if let error = session.saveError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if case .stopped = session.state {
                Button("Send Again") { Task { await session.start() } }
                    .glassButtonStyle()
            }
            Spacer()
            Button(session.isActive ? LocalizedStringKey("Stop Sending") : LocalizedStringKey("Done")) { dismiss() }
                .glassButtonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
