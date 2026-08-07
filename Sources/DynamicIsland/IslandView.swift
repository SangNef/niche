import SwiftUI

struct IslandView: View {
    let compactHeight: CGFloat
    let notchWidth: CGFloat
    @ObservedObject var hitTestModel: IslandHitTestModel
    @ObservedObject var nowPlaying: NowPlayingProvider
    @ObservedObject var volume: VolumeObserver
    @ObservedObject var brightness: BrightnessObserver
    @ObservedObject var bluetoothHeadphones: BluetoothHeadphoneObserver
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var settings: AppSettings

    @State private var isHovering = false
    @State private var hoverWorkItem: DispatchWorkItem?

    private enum Mode {
        case volume, brightness, bluetooth, updateAvailable, expanded, compactNowPlaying, compactIdle
    }

    private var mode: Mode {
        // Connecting headphones often also fires a system volume-property change
        // (output device switch), which would otherwise flash the volume HUD over
        // the more relevant "headphones connected" one — bluetooth wins.
        if bluetoothHeadphones.isVisible { return .bluetooth }
        if volume.isVisible { return .volume }
        if brightness.isVisible { return .brightness }
        if updateChecker.isVisible { return .updateAvailable }
        // Nothing playing: hovering just nudges the pill bigger (see scaleEffect
        // below) instead of expanding into an empty "no music" panel.
        if isHovering && nowPlaying.current != nil { return .expanded }
        if nowPlaying.isVisible { return .compactNowPlaying }
        return .compactIdle
    }

    /// True only while hovering the idle pill (nothing playing, no HUD/bluetooth/
    /// update override) — the one case that gets a subtle scale bump instead of expanding.
    private var isIdleHover: Bool { isHovering && mode == .compactIdle }

    private var compactSize: CGSize {
        CGSize(width: max(notchWidth + 60, 160), height: compactHeight)
    }
    /// Idle (nothing playing, not hovering): shrink back down to hug the physical
    /// notch instead of staying as wide as the now-playing pill.
    private var idleSize: CGSize {
        CGSize(width: notchWidth, height: compactHeight)
    }
    private var expandedSize: CGSize { CGSize(width: 330, height: 160) }
    private var hudSize: CGSize { CGSize(width: 220, height: 40) }
    private var bluetoothSize: CGSize { CGSize(width: 260, height: 46) }
    private var updateSize: CGSize { CGSize(width: 280, height: 46) }

    private var currentSize: CGSize {
        switch mode {
        case .volume, .brightness: hudSize
        case .bluetooth: bluetoothSize
        case .updateAvailable: updateSize
        case .expanded: expandedSize
        case .compactNowPlaying: compactSize
        case .compactIdle: idleSize
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
        case .updateAvailable: 22
        case .compactNowPlaying, .compactIdle: compactHeight / 2.8
        }
    }

    var body: some View {
        VStack {
            NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
                .fill(Color.black)
                .frame(width: currentSize.width, height: currentSize.height)
                .scaleEffect(isIdleHover ? 1.08 : 1.0)
                .overlay(content)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { publishFrame(proxy) }
                            .onChange(of: currentSize.width) { publishFrame(proxy) }
                    }
                )
                .onHover { hovering in
                    hoverWorkItem?.cancel()
                    if hovering {
                        // Small delay before expanding so a quick mouse pass-over the
                        // notch doesn't pop it open — only a deliberate, held hover does.
                        let workItem = DispatchWorkItem {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isHovering = true
                            }
                        }
                        hoverWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + settings.hoverExpandDelay, execute: workItem)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isHovering = false
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentSize.width)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: mode)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isIdleHover)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .volume:
            hudContent(iconName: volumeIconName, level: volume.isMuted ? 0 : volume.level, tint: Self.volumeTint)
        case .brightness:
            hudContent(iconName: brightnessIconName, level: brightness.level, tint: Self.brightnessTint)
        case .bluetooth:
            if let device = bluetoothHeadphones.connected { bluetoothContent(device) }
        case .updateAvailable:
            if let info = updateChecker.available { updateContent(info) }
        case .expanded:
            expandedContent
        case .compactNowPlaying:
            if let track = nowPlaying.current { compactNowPlayingContent(track) }
        case .compactIdle:
            EmptyView()
        }
    }

    private static let volumeTint = Color(red: 41.0 / 255, green: 255.0 / 255, blue: 198.0 / 255)
    private static let brightnessTint = Color(red: 1.0, green: 0.8, blue: 0.35)

    private func hudContent(iconName: String, level: Float, tint: Color) -> some View {
        HStack(spacing: 12) {
            // Fixed-width icon column: SF Symbols like speaker.slash.fill vs
            // speaker.wave.3.fill differ in glyph width, which was shifting the bar's
            // leading edge left/right as the icon swapped. Centering in a fixed frame
            // keeps the bar's start position stable.
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 20, alignment: .center)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.7), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(proxy.size.width * CGFloat(level), 5))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.2), value: level)
    }

    private func bluetoothContent(_ device: BluetoothHeadphoneInfo) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: bluetoothIconName(for: device.name))
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let battery = device.primaryBattery {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIconName(for: battery))
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

    private func updateContent(_ info: AppUpdateInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Self.volumeTint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Có bản cập nhật mới")
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Phiên bản \(info.version) — nhấn để tải")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { updateChecker.openReleasePage() }
    }

    /// Picks a model-accurate SF Symbol so the pill reads correctly for AirPods
    /// (regular/Pro/Max), Beats, or any other Bluetooth headset/headphones — the
    /// connect gate in BluetoothHeadphoneObserver already ensures this is always
    /// some kind of headset, never an unrelated accessory.
    private func bluetoothIconName(for deviceName: String) -> String {
        let name = deviceName.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods.gen3" }
        if name.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    private func batteryIconName(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private var volumeIconName: String {
        if volume.isMuted || volume.level <= 0.001 { return "speaker.slash.fill" }
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
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !track.isPlaying)) { timeline in
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
            .contentShape(Rectangle())
            .onTapGesture { openNowPlayingSource(track) }

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
                .font(.system(size: 22, weight: .semibold))
            }
            Button(action: MediaController.next) {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .font(.system(size: 16, weight: .medium))
    }

    private func compactNowPlayingContent(_ track: NowPlayingInfo) -> some View {
        HStack(spacing: 6) {
            artworkView(track.artwork, size: compactHeight - 12)
            Text(track.title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture { openNowPlayingSource(track) }
    }

    /// Brings the app that's actually playing (Music, Spotify, a browser tab, ...)
    /// to the foreground — matches tapping Control Center's Now Playing tile.
    private func openNowPlayingSource(_ track: NowPlayingInfo) {
        nowPlaying.openSource(for: track)
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
