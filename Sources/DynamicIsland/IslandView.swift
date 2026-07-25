import SwiftUI

struct IslandView: View {
    let compactHeight: CGFloat
    let notchWidth: CGFloat
    @ObservedObject var hitTestModel: IslandHitTestModel
    @ObservedObject var nowPlaying: NowPlayingProvider
    @ObservedObject var volume: VolumeObserver
    @ObservedObject var brightness: BrightnessObserver
    @ObservedObject var bluetoothHeadphones: BluetoothHeadphoneObserver

    @State private var isHovering = false

    private enum Mode { case volume, brightness, bluetooth, expanded, compactNowPlaying, compactIdle }

    private var mode: Mode {
        if volume.isVisible { return .volume }
        if brightness.isVisible { return .brightness }
        if bluetoothHeadphones.isVisible { return .bluetooth }
        if isHovering { return .expanded }
        if nowPlaying.current != nil { return .compactNowPlaying }
        return .compactIdle
    }

    private var compactSize: CGSize {
        CGSize(width: max(notchWidth + 60, 160), height: compactHeight)
    }
    private var expandedSize: CGSize { CGSize(width: 330, height: 160) }
    private var hudSize: CGSize { CGSize(width: 220, height: 40) }
    private var bluetoothSize: CGSize { CGSize(width: 260, height: 46) }

    private var currentSize: CGSize {
        switch mode {
        case .volume, .brightness: hudSize
        case .bluetooth: bluetoothSize
        case .expanded: expandedSize
        case .compactNowPlaying, .compactIdle: compactSize
        }
    }

    private var topCornerRadius: CGFloat {
        mode == .expanded ? 16 : compactHeight / 2.8
    }

    private var bottomCornerRadius: CGFloat {
        switch mode {
        case .expanded: 40
        case .volume, .brightness: 20
        case .bluetooth: 22
        case .compactNowPlaying, .compactIdle: compactHeight / 2.8
        }
    }

    var body: some View {
        VStack {
            NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
                .fill(Color.black)
                .frame(width: currentSize.width, height: currentSize.height)
                .overlay(content)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { publishFrame(proxy) }
                            .onChange(of: currentSize.width) { publishFrame(proxy) }
                    }
                )
                .onHover { hovering in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isHovering = hovering
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentSize.width)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: mode)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .volume:
            hudContent(iconName: volumeIconName, level: volume.level)
        case .brightness:
            hudContent(iconName: brightnessIconName, level: brightness.level)
        case .bluetooth:
            if let device = bluetoothHeadphones.connected { bluetoothContent(device) }
        case .expanded:
            expandedContent
        case .compactNowPlaying:
            if let track = nowPlaying.current { compactNowPlayingContent(track) }
        case .compactIdle:
            EmptyView()
        }
    }

    private func hudContent(iconName: String, level: Float) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(.white)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white)
                        .frame(width: proxy.size.width * CGFloat(level))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 16)
    }

    private func bluetoothContent(_ device: BluetoothHeadphoneInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "airpodspro")
                .font(.system(size: 18))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let battery = device.primaryBattery {
                    HStack(spacing: 4) {
                        Image(systemName: "battery.75")
                            .font(.system(size: 9))
                        Text("\(battery)%")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private var volumeIconName: String {
        if volume.level <= 0.001 { return "speaker.slash.fill" }
        if volume.level < 0.33 { return "speaker.wave.1.fill" }
        if volume.level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var brightnessIconName: String {
        brightness.level < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }

    @ViewBuilder
    private var expandedContent: some View {
        if let track = nowPlaying.current {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                nowPlayingExpandedBody(track, now: timeline.date)
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundColor(.white.opacity(0.5))
                Text("Không có nhạc đang phát")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
    }

    private func nowPlayingExpandedBody(_ track: NowPlayingInfo, now: Date) -> some View {
        let elapsed = track.liveElapsed(at: now)
        let remaining = max(track.duration - elapsed, 0)
        let progress = track.duration > 0 ? elapsed / track.duration : 0

        return VStack(spacing: 18) {
            HStack(spacing: 14) {
                artworkView(track.artwork, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(track.accentColor)
                    .symbolEffect(
                        .variableColor.iterative, options: .repeating, isActive: track.isPlaying)
            }

            VStack(spacing: 6) {
                progressBar(progress)
                HStack {
                    Text(formatTime(elapsed))
                    Spacer()
                    Text("-\(formatTime(remaining))")
                }
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            }

            HStack {
                mediaControls
                    .frame(maxWidth: .infinity)
                Image(systemName: "airplayaudio")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 20)
    }

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Color.white)
                    .frame(width: proxy.size.width * CGFloat(progress))
            }
        }
        .frame(height: 4)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var mediaControls: some View {
        HStack(spacing: 24) {
            Button(action: MediaController.previous) {
                Image(systemName: "backward.fill")
            }
            Button(action: MediaController.togglePlayPause) {
                Image(
                    systemName: nowPlaying.current?.isPlaying == true ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 17, weight: .semibold))
            }
            Button(action: MediaController.next) {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .font(.system(size: 14, weight: .medium))
    }

    private func compactNowPlayingContent(_ track: NowPlayingInfo) -> some View {
        HStack(spacing: 6) {
            artworkView(track.artwork, size: compactHeight - 12)
            if track.isPlaying {
                Text(track.title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func artworkView(_ image: NSImage?, size: CGFloat) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(Color.white.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45))
                        .foregroundColor(.white)
                )
        }
    }

    private func publishFrame(_ proxy: GeometryProxy) {
        hitTestModel.frameInWindow = proxy.frame(in: .global)
    }
}
